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
                self.message = UninstallModel.lastMeaningfulLine(text)
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
            if needsSudo && CLIRun.askpassPath == nil {
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
                self.message = status == 0 ? L.t("doneNote") : String(format: L.t("exitCode"), status)
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
            run = CLIRun.start(cli: cli, args: [command, "--dry-run"] + selectArgs + params) { [weak self] text, status in
                guard let self else { return }
                self.output = ToolModel.clean(text)
                self.stage = status == 0 ? .preview : .idle
                self.failed = status != 0
                self.message = status == 0 ? L.t("previewNote") + (self.needsSudo ? " " + L.t("sudoNote") : "")
                    : String(format: L.t("exitCode"), status)
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

    func stop() {
        run?.cancel()
        listing = false
    }
}

struct ToolView: View {
    @ObservedObject var model: ToolModel
    let close: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(L.t(model.tool)).font(.system(size: 18, weight: .bold, design: .rounded))
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
                Text(message).font(.caption).foregroundStyle(model.failed ? Color.red : Color.secondary).lineLimit(3)
            }
            footer
        }
        .padding(18)
        .frame(width: 480, height: 620)
        .background(.ultraThinMaterial)
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
        case "dev":
            note(L.t("unityWarn"))
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
                    HStack { Spacer(); ProgressView().controlSize(.small); Spacer() }.padding(.vertical, 30)
                } else if model.items.isEmpty {
                    Text(L.t("nothing")).font(.callout).foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity).padding(.vertical, 30)
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
        .overlay(alignment: .topTrailing) {
            if model.listing && !model.items.isEmpty { ProgressView().controlSize(.small).padding(8) }
        }
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
            ForEach(unity) { checkRow($0, maxKB: unity.map(\.kb).max() ?? 0) }
        }
    }

    private func outputBox(maxHeight: CGFloat) -> some View {
        ScrollViewReader { proxy in
            ScrollView([.horizontal, .vertical]) {
                VStack(alignment: .leading, spacing: 0) {
                    Text(model.output.isEmpty ? L.t("running") : model.output)
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
        HStack {
            if model.tool != "system" {
                Text(String(format: L.t("selection"), L.human(kb: model.selectedKB)))
                    .font(.system(size: 12, weight: .semibold)).monospacedDigit()
            }
            Spacer()
            if model.stage == .preview {
                Button(L.t("cancel")) { model.cancelPreview() }
            } else {
                Button(L.t("close")) { close() }.keyboardShortcut(.cancelAction)
            }
            let disabled = model.busy || !model.hasSelection || model.cliPath == nil
                || (model.tool == "system" && model.output.isEmpty)
            Button(role: .destructive) { model.act() } label: {
                Group {
                    if model.stage == .previewing || model.stage == .working {
                        ProgressView().controlSize(.small)
                    } else {
                        Text(model.stage == .preview ? "\(L.t("confirm")) · \(model.actionLabel)" : model.actionLabel)
                    }
                }
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.white)
                .padding(.horizontal, 14)
                .padding(.vertical, 7)
                .background(Color.red.opacity(disabled ? 0.4 : 1), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(disabled)
        }
        .controlSize(.large)
    }
}

@MainActor
final class ToolWindow: NSObject, NSWindowDelegate {
    private var panel: NSPanel?
    private var model: ToolModel?
    private let tool: String
    private let cliPath: String?
    private let onChange: () -> Void

    init(tool: String, cliPath: String?, onChange: @escaping () -> Void) {
        self.tool = tool
        self.cliPath = cliPath
        self.onChange = onChange
    }

    func show() {
        if let panel {
            if model?.busy != true { model?.load() }
            NSApp.activate(ignoringOtherApps: true)
            panel.makeKeyAndOrderFront(nil)
            return
        }
        let m = ToolModel(tool: tool, cliPath: cliPath)
        m.onChange = onChange
        let p = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 480, height: 620),
                        styleMask: [.titled, .closable, .fullSizeContentView],
                        backing: .buffered, defer: false)
        p.titlebarAppearsTransparent = true
        p.titleVisibility = .hidden
        p.isMovableByWindowBackground = true
        p.isFloatingPanel = true
        p.level = .floating
        p.hidesOnDeactivate = false
        p.isReleasedWhenClosed = false
        p.delegate = self
        p.contentView = NSHostingView(rootView: ToolView(model: m) { [weak p] in p?.close() })
        p.center()
        panel = p
        model = m
        m.load()
        NSApp.activate(ignoringOtherApps: true)
        p.makeKeyAndOrderFront(nil)
    }

    func windowWillClose(_ notification: Notification) {
        guard let model else { return }
        if model.stage != .working { model.stop() }
    }
}
