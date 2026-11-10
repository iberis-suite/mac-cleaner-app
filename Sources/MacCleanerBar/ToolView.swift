import AppKit
import SwiftUI

struct ToolItem: Identifiable, Hashable {
    let index: Int
    let kb: Double
    let label: String
    let path: String
    let type: String
    let state: String

    var id: String { "\(type)|\(index)|\(path)" }

    var key: String { type == "unity" ? "u\(index)" : "\(index)" }

    static func parseList(_ text: String) -> [ToolItem] {
        text.components(separatedBy: "\n").compactMap { line in
            let c = line.components(separatedBy: "\t")
            guard c.count >= 5, let i = Int(c[0]), let kb = Double(c[1]) else { return nil }
            return ToolItem(index: i, kb: kb, label: c[2], path: c[3], type: c[4], state: c.count > 5 ? c[5] : "")
        }
    }

    var shortPath: String {
        let home = NSHomeDirectory()
        return path.hasPrefix(home) ? "~" + path.dropFirst(home.count) : path
    }
}

enum ToolStage: Equatable {
    case idle
    case loading
    case previewing
    case preview
    case working
    case done
}

@MainActor
final class ToolModel: ObservableObject {
    let tool: String
    let cliPath: String?
    @Published var items: [ToolItem] = []
    @Published var skipped: [ToolItem] = []
    @Published var selected: Set<String> = []
    @Published var collapsed: Set<Int> = []
    @Published var minMB: String
    @Published var days = "90"
    @Published var dir = NSHomeDirectory()
    @Published var stage: ToolStage = .idle
    @Published var listing = false
    @Published var output = ""
    @Published var message: String?
    @Published var failed = false
    var onChange: (() -> Void)?
    private var run: CLIRun?
    private var generation = 0

    init(tool: String, cliPath: String?) {
        self.tool = tool
        self.cliPath = cliPath
        minMB = tool == "duplicates" ? "1" : "500"
    }

    var command: String { tool == "cachesAdv" ? "caches" : tool }

    var needsSudo: Bool { tool == "system" || tool == "startup" }

    var actionLabel: String {
        switch tool {
        case "startup": return L.t("disable")
        case "dev", "cachesAdv": return L.t("delete")
        case "system": return L.t("thin")
        default: return L.t("toTrash")
        }
    }

    var params: [String] {
        switch tool {
        case "large": return ["--min", Int(minMB).map(String.init) ?? "500"]
        case "downloads": return ["--days", Int(days).map(String.init) ?? "90"]
        case "duplicates": return ["--dir", dir, "--min", Int(minMB).map(String.init) ?? "1"]
        default: return []
        }
    }

    var selectArgs: [String] {
        if tool == "system" { return [] }
        let main = items.filter { $0.type != "unity" && selected.contains($0.key) }.map(\.index)
        var args = ["--select", Array(Set(main)).sorted().map(String.init).joined(separator: " ")]
        if tool == "dev" {
            let unity = items.filter { $0.type == "unity" && selected.contains($0.key) }.map(\.index)
            args += ["--select-unity", Array(Set(unity)).sorted().map(String.init).joined(separator: " ")]
        }
        return args
    }

    var selectedKB: Double {
        items.filter { $0.type != "keep" && selected.contains($0.key) }.reduce(0) { $0 + $1.kb }
    }

    var hasSelection: Bool { tool == "system" || !selected.isEmpty }

    var busy: Bool { listing || stage == .previewing || stage == .working }

    func load(keepOutput: Bool = false) {
        run?.cancel()
        generation += 1
        let gen = generation
        if !keepOutput {
            output = ""
            message = nil
            stage = .idle
        }
        failed = false
        guard let cli = cliPath else {
            message = L.t("missing") + " " + Model.installHint
            return
        }
        listing = true
        let args = tool == "system" ? ["system", "--dry-run"] : [command, "--list"] + params
        run = CLIRun.start(cli: cli, args: args) { [weak self] text, status in
            guard let self, self.generation == gen else { return }
            self.listing = false
            if self.tool == "system" {
                self.output = ToolModel.clean(text)
            } else {
                let all = ToolItem.parseList(text)
                self.items = all.filter { $0.index > 0 }
                self.skipped = all.filter { $0.index == 0 }
                let keys = Set(self.items.map(\.key))
                self.selected = self.selected.intersection(keys)
                if self.tool == "cachesAdv" && !keepOutput && self.selected.isEmpty {
                    self.selected = Set(self.items.filter {
                        $0.state != "excluded" && !["docker", "nodemod", "devsupport"].contains($0.type) && $0.kb > 0
                    }.map(\.key))
                }
            }
            if status != 0 {
                self.failed = true
                self.message = UninstallModel.summary(text, status: status)
            }
        }
    }


    nonisolated static func clean(_ text: String) -> String {
        text.components(separatedBy: "\n").filter { !$0.contains("?") || !$0.contains("›") }
            .joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
    }

    func toggle(_ item: ToolItem) {
        guard !busy, item.type != "keep" else { return }
        if selected.contains(item.key) { selected.remove(item.key) } else { selected.insert(item.key) }
        if stage == .preview || stage == .done { stage = .idle; output = "" }
    }

    func act() {
        guard let cli = cliPath, !busy, hasSelection else { return }
        switch stage {
        case .preview:
            if needsSudo && CLIRun.askpassPath == nil && !Demo.enabled {
                message = L.t("noAskpass")
                return
            }
            stage = .working
            message = nil
            run = CLIRun.start(cli: cli, args: [command, "--yes"] + selectArgs + params, askpass: needsSudo,
                               output: { [weak self] t in self?.output = ToolModel.clean(t) }) { [weak self] text, status in
                guard let self else { return }
                self.output = ToolModel.clean(text)
                self.stage = .done
                self.failed = status != 0
                self.message = status == 0 ? L.t("doneNote") : UninstallModel.summary(text, status: status)
                Hub.finished(self.tool, ok: status == 0)
                if self.tool != "system" { self.selected = [] }
                self.onChange?()
                if self.tool != "system" { self.load(keepOutput: true) }
            }
        default:
            if tool == "system" {
                stage = .preview
                message = L.t("sudoNote")
                return
            }
            stage = .previewing
            message = nil
            generation += 1
            let gen = generation
            run = CLIRun.start(cli: cli, args: [command, "--dry-run"] + selectArgs + params) { [weak self] text, status in
                guard let self, self.generation == gen else { return }
                self.output = ToolModel.clean(text)
                self.stage = status == 0 ? .preview : .idle
                self.failed = status != 0
                self.message = status == 0 ? L.t("previewNote") + (self.needsSudo ? " " + L.t("sudoNote") : "")
                    : UninstallModel.summary(text, status: status)
            }
        }
    }

    func cancelPreview() {
        guard stage == .preview || stage == .done else { return }
        stage = .idle
        message = nil
        if tool != "system" { output = "" }
    }

    func chooseFolder() {
        let p = NSOpenPanel()
        p.canChooseDirectories = true
        p.canChooseFiles = false
        p.allowsMultipleSelection = false
        p.directoryURL = URL(fileURLWithPath: dir)
        p.level = .modalPanel
        if p.runModal() == .OK, let url = p.url {
            dir = url.path
            load()
        }
    }

    func cancel() {
        guard stage != .working else { return }
        let wasBusy = listing || stage == .previewing
        generation += 1
        run?.cancel()
        run = nil
        listing = false
        if stage == .previewing {
            stage = .idle
            output = ""
        }
        if wasBusy {
            failed = false
            message = L.t("cancelled")
        }
    }

    func back() -> Bool {
        switch stage {
        case .working: return false
        case .previewing: cancel()
        case .preview, .done: cancelPreview()
        case .idle, .loading:
            guard listing else { return false }
            cancel()
        }
        return true
    }

    var backKey: String {
        switch stage {
        case .previewing: return "cancel"
        case .preview, .done: return "back"
        default: return listing ? "cancel" : "home"
        }
    }

    func appear() {
        if stage == .idle && !listing { load() }
    }

    func stop() {
        if stage != .working { cancel() }
    }
}

struct ToolView: View {
    @ObservedObject var model: ToolModel
    let home: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            ToolHeader(title: L.t(model.tool), backTitle: L.t(model.backKey), back: { if !model.back() { home() } }) {
                if model.listing && !model.items.isEmpty { ProgressView().controlSize(.small) }
            }
            header
            if model.tool == "system" {
                outputBox(maxHeight: .infinity)
            } else {
                list
                if !model.skipped.isEmpty { SkippedRow(items: model.skipped) }
                if !model.output.isEmpty || model.stage == .previewing || model.stage == .working {
                    DetailsBox(text: model.output, loading: model.stage == .previewing || model.stage == .working, height: 150)
                }
            }
            if let message = model.message {
                if model.failed {
                    ErrorNote(summary: message, detail: model.output)
                } else {
                    Text(message).font(.caption).foregroundStyle(.secondary).lineLimit(3)
                }
            }
            footer
        }
        .padding(20)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    @ViewBuilder
    private var header: some View {
        switch model.tool {
        case "large":
            paramRow(L.t("minSize"), text: $model.minMB)
        case "downloads":
            paramRow(L.t("olderThan"), text: $model.days)
        case "duplicates":
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 8) {
                    Image(systemName: "folder").foregroundStyle(Color.accentBlue)
                    Text((model.dir as NSString).abbreviatingWithTildeInPath)
                        .font(.system(size: 12)).lineLimit(1).truncationMode(.middle)
                    Spacer()
                    Button(L.t("choose")) { model.chooseFolder() }.disabled(model.busy)
                }
                .padding(8)
                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 9, style: .continuous))
                paramRow(L.t("minSize"), text: $model.minMB)
            }
        case "startup":
            note(L.t("startupNote"))
        default:
            EmptyView()
        }
    }

    private func note(_ text: String) -> some View {
        Text(text).font(.system(size: 11)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
    }

    private func paramRow(_ label: String, text: Binding<String>) -> some View {
        HStack(spacing: 8) {
            Text(label).font(.system(size: 12)).foregroundStyle(.secondary)
            TextField("", text: text)
                .textFieldStyle(.plain)
                .font(.system(size: 12).monospacedDigit())
                .frame(width: 70)
                .padding(6)
                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 7, style: .continuous))
                .onSubmit { model.load() }
            Spacer()
            Button(L.t("scan")) { model.load() }.disabled(model.busy)
        }
    }

    private var list: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 2) {
                if model.listing && model.items.isEmpty {
                    VStack(spacing: 8) {
                        ProgressView().controlSize(.small)
                        Text(L.t("analyzing")).font(.system(size: 12)).foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity).padding(.vertical, 40)
                } else if model.items.isEmpty {
                    if model.failed || model.message == L.t("cancelled") {
                        Color.clear.frame(height: 80)
                    } else {
                        EmptyNote(text: L.t(["startup": "emptyStartup", "dev": "emptyDev"][model.tool] ?? "nothingFound"))
                    }
                } else {
                    switch model.tool {
                    case "duplicates": duplicateGroups
                    case "startup": startupSections
                    case "dev": devSections
                    default:
                        let maxKB = model.items.map(\.kb).max() ?? 0
                        ForEach(model.items) { checkRow($0, maxKB: maxKB) }
                    }
                }
            }
            .padding(6)
        }
        .frame(maxHeight: .infinity)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private func sectionTitle(_ text: String) -> some View {
        Text(text).font(.system(size: 11, weight: .semibold)).foregroundStyle(.secondary)
            .padding(.top, 6).padding(.horizontal, 4)
    }

    private func checkbox(_ on: Bool, enabled: Bool = true) -> some View {
        Image(systemName: on ? "checkmark.square.fill" : "square")
            .font(.system(size: 14))
            .foregroundStyle(enabled ? (on ? Color.accentBlue : Color.secondary) : Color.secondary.opacity(0.4))
    }

    private func finderButton(_ path: String) -> some View {
        Button {
            guard !path.isEmpty else { return }
            NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: path)])
        } label: {
            Image(systemName: "magnifyingglass.circle").font(.system(size: 13)).foregroundStyle(Color.accentBlue)
        }
        .buttonStyle(.plain)
        .help(L.t("showInFinder"))
        .opacity(path.hasPrefix("/") ? 1 : 0)
        .disabled(!path.hasPrefix("/"))
    }

    private func sizeText(_ kb: Double) -> some View {
        Text(L.human(kb: kb)).font(.system(size: 11)).monospacedDigit().foregroundStyle(.secondary)
    }

    private func checkRow(_ item: ToolItem, maxKB: Double) -> some View {
        let on = model.selected.contains(item.key)
        return HStack(spacing: 8) {
            Button { model.toggle(item) } label: {
                HStack(spacing: 8) {
                    checkbox(on)
                    Image(systemName: ItemStyle.symbol(item))
                        .font(.system(size: 12))
                        .foregroundStyle(Color.accentBlue)
                        .frame(width: 22, height: 22)
                        .background(Color.primary.opacity(0.07), in: RoundedRectangle(cornerRadius: 6, style: .continuous))
                    VStack(alignment: .leading, spacing: 3) {
                        HStack(spacing: 6) {
                            Text(item.label).font(.system(size: 12)).lineLimit(1).truncationMode(.middle)
                            Spacer(minLength: 6)
                            sizeText(item.kb)
                        }
                        if item.path.hasPrefix("/") {
                            Text(item.shortPath).font(.system(size: 10)).foregroundStyle(.secondary)
                                .lineLimit(1).truncationMode(.middle)
                        }
                        SizeBar(fraction: maxKB > 0 ? item.kb / maxKB : 0)
                    }
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help(item.path.hasPrefix("/") ? item.path : item.label)
            finderButton(item.path)
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 4)
        .background(on ? Color.accentBlue.opacity(0.12) : Color.clear, in: RoundedRectangle(cornerRadius: 7, style: .continuous))
    }

    @ViewBuilder
    private var duplicateGroups: some View {
        let groups = Dictionary(grouping: model.items, by: \.index)
        ForEach(groups.keys.sorted(), id: \.self) { g in
            let files = groups[g] ?? []
            let on = model.selected.contains("\(g)")
            let open = !model.collapsed.contains(g)
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 8) {
                    Button {
                        if let first = files.first(where: { $0.type == "copy" }) { model.toggle(first) }
                    } label: { checkbox(on) }
                    .buttonStyle(.plain)
                    Button {
                        if open { model.collapsed.insert(g) } else { model.collapsed.remove(g) }
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: "chevron.right").font(.system(size: 9, weight: .semibold))
                                .rotationEffect(.degrees(open ? 90 : 0)).foregroundStyle(.tertiary)
                            Text(String(format: L.t("group"), g, files.count, L.human(kb: files.first?.kb ?? 0)))
                                .font(.system(size: 12, weight: .semibold))
                            Spacer()
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
                if open {
                    ForEach(files) { f in
                        HStack(spacing: 8) {
                            Image(systemName: f.type == "keep" ? "lock.fill" : (on ? "trash" : "doc"))
                                .font(.system(size: 11))
                                .foregroundStyle(f.type == "keep" ? Color.green : (on ? Color.red : Color.secondary))
                                .frame(width: 16)
                            Text(f.shortPath).font(.system(size: 11)).lineLimit(1).truncationMode(.middle)
                            if f.type == "keep" {
                                Text(L.t("kept")).font(.system(size: 10, weight: .semibold)).foregroundStyle(Color.green)
                            }
                            Spacer(minLength: 6)
                            finderButton(f.path)
                        }
                        .padding(.leading, 26)
                    }
                }
            }
            .padding(.horizontal, 6)
            .padding(.vertical, 4)
            .background(on ? Color.accentBlue.opacity(0.12) : Color.clear, in: RoundedRectangle(cornerRadius: 7, style: .continuous))
        }
    }

    @ViewBuilder
    private var startupSections: some View {
        let sections: [(String, [String])] = [("loginItems", ["login"]), ("agents", ["agent", "sysagent"]), ("daemons", ["daemon"])]
        ForEach(sections, id: \.0) { section in
            let rows = model.items.filter { section.1.contains($0.type) }
            if !rows.isEmpty {
                sectionTitle(L.t(section.0))
                ForEach(rows) { item in
                    HStack(spacing: 8) {
                        Toggle("", isOn: Binding(
                            get: { !model.selected.contains(item.key) },
                            set: { _ in model.toggle(item) }
                        ))
                        .toggleStyle(.switch)
                        .controlSize(.mini)
                        .labelsHidden()
                        .disabled(model.busy)
                        VStack(alignment: .leading, spacing: 1) {
                            Text(item.label).font(.system(size: 12)).lineLimit(1).truncationMode(.middle)
                                .strikethrough(model.selected.contains(item.key))
                            Text(item.path.hasPrefix("/") ? item.shortPath : L.t(item.type == "login" ? "loginItems" : "agents"))
                                .font(.system(size: 10)).foregroundStyle(.secondary).lineLimit(1).truncationMode(.middle)
                        }
                        Spacer(minLength: 6)
                        Circle().fill(item.state == "on" ? Color.green : Color.secondary.opacity(0.4)).frame(width: 7, height: 7)
                        Text(L.t(item.state == "on" ? "loaded" : "notLoaded")).font(.system(size: 10)).foregroundStyle(.secondary)
                        finderButton(item.path)
                    }
                    .padding(.horizontal, 6)
                    .padding(.vertical, 3)
                }
            }
        }
    }

    @ViewBuilder
    private var devSections: some View {
        let wt = model.items.filter { $0.type == "worktree" }
        let unity = model.items.filter { $0.type == "unity" }
        if !wt.isEmpty {
            sectionTitle(L.t("worktrees"))
            ForEach(wt) { checkRow($0, maxKB: wt.map(\.kb).max() ?? 0) }
        }
        if !unity.isEmpty {
            sectionTitle(L.t("unityLib"))
            note(L.t("unityWarn")).padding(.horizontal, 4).padding(.bottom, 2)
            ForEach(unity) { checkRow($0, maxKB: unity.map(\.kb).max() ?? 0) }
        }
    }

    private func outputBox(maxHeight: CGFloat) -> some View {
        ScrollViewReader { proxy in
            ScrollView([.horizontal, .vertical]) {
                VStack(alignment: .leading, spacing: 0) {
                    Text(model.output.isEmpty ? L.t(model.listing ? "running" : "noOutput") : model.output)
                        .font(.system(size: 10.5, design: .monospaced))
                        .fixedSize(horizontal: true, vertical: true)
                        .textSelection(.enabled)
                        .padding(8)
                    Color.clear.frame(height: 1).id("end")
                }
                .frame(maxWidth: .infinity, alignment: .topLeading)
            }
            .frame(maxHeight: maxHeight)
            .background(Color.black.opacity(0.25), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            .onChange(of: model.output) { _ in
                if model.tool != "system" { proxy.scrollTo("end", anchor: .bottom) }
            }
        }
    }

    private var footer: some View {
        Group {
            if model.stage == .working {
                RunningNote(text: L.t("keepRunning"))
            } else {
                HStack(spacing: 10) {
                    if model.tool != "system" {
                        Text(String(format: L.t("selection"), L.human(kb: model.selectedKB)))
                            .font(.system(size: 12, weight: .semibold)).monospacedDigit()
                    }
                    Spacer()
                    buttons
                }
            }
        }
        .frame(minHeight: 32)
    }

    @ViewBuilder
    private var buttons: some View {
        let ready = model.hasSelection && model.cliPath != nil && !(model.tool == "system" && model.output.isEmpty)
        switch model.stage {
        case .done:
            BlueButton(title: L.t("done")) { model.cancelPreview() }.keyboardShortcut(.defaultAction)
        case .preview:
            SecondaryButton(title: L.t("cancel")) { model.cancelPreview() }
            BlueButton(title: "\(L.t("confirm")) · \(model.actionLabel)", enabled: ready && !model.listing, destructive: true) {
                model.act()
            }
            .keyboardShortcut(.defaultAction)
        case .previewing:
            SecondaryButton(title: L.t("cancel")) { model.cancel() }
            BlueButton(title: L.t("preview"), busy: true) {}
        default:
            if model.listing { SecondaryButton(title: L.t("cancel")) { model.cancel() } }
            BlueButton(title: model.tool == "system" ? model.actionLabel + "…" : "\(L.t("preview")) · \(model.actionLabel)",
                       enabled: ready && !model.busy) { model.act() }
                .keyboardShortcut(.defaultAction)
        }
    }
}
