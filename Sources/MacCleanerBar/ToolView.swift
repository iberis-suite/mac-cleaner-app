import AppKit
import SwiftUI

struct ToolItem: Identifiable, Hashable {
    let index: Int
    let kb: Double
    let label: String
    let path: String
    let type: String
    let state: String

    var id: String { "\(type)|\(index)|\(path)|\(label)" }

    var key: String { type == "unity" ? "u\(index)" : "\(index)" }

    static func parse(_ line: String) -> ToolItem? {
        let c = line.components(separatedBy: "\t")
        guard c.count >= 5, let i = Int(c[0]), let kb = Double(c[1]) else { return nil }
        return ToolItem(index: i, kb: kb, label: c[2], path: c[3], type: c[4], state: c.count > 5 ? c[5] : "")
    }

    static func parseList(_ text: String) -> [ToolItem] {
        text.components(separatedBy: "\n").compactMap(parse)
    }

    static func machine(_ line: String) -> Bool {
        line.hasPrefix("STEP\t") || line.hasPrefix("RESULT\t") || parse(line) != nil
    }

    static func humanLines(_ text: String) -> String {
        text.components(separatedBy: "\n").filter { !machine($0) }.joined(separator: "\n")
    }

    static func results(_ text: String) -> [[String]] {
        text.components(separatedBy: "\n").filter { $0.hasPrefix("RESULT\t") }.map { Array($0.components(separatedBy: "\t").dropFirst()) }
    }

    var shortPath: String {
        let home = NSHomeDirectory()
        return path.hasPrefix(home) ? "~" + path.dropFirst(home.count) : path
    }
}

struct ToolResult: Equatable {
    let ok: Bool
    let title: String
    var detail = ""
    var raw = ""
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
    @Published var info: [ToolItem] = []
    @Published var selected: Set<String> = []
    @Published var collapsed: Set<Int> = []
    @Published var minMB: String
    @Published var days = "90"
    @Published var dir = NSHomeDirectory()
    @Published var stage: ToolStage = .idle
    @Published var listing = false
    @Published var step: String?
    @Published var steps: [String: String] = [:]
    @Published var output = ""
    @Published var message: String?
    @Published var failed = false
    @Published var result: ToolResult?
    var onChange: (() -> Void)?
    private var run: CLIRun?
    private var generation = 0
    private var followAll = false

    static let riskyCaches: Set<String> = ["docker", "nodemod", "devsupport"]

    static let historyAction: [String: String] = [
        "large": "m4", "downloads": "m6", "duplicates": "m8", "startup": "m7", "dev": "md", "cachesAdv": "m5", "system": "ms",
    ]

    init(tool: String, cliPath: String?) {
        self.tool = tool
        self.cliPath = cliPath
        minMB = tool == "duplicates" ? "1" : "500"
    }

    var command: String { tool == "cachesAdv" ? "caches" : tool }

    var needsSudo: Bool { tool == "system" || tool == "startup" }

    var sortsBySize: Bool { tool == "large" || tool == "downloads" }

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

    var chosen: [ToolItem] {
        items.filter { $0.type != "keep" && selected.contains($0.key) }
    }

    var selectedKB: Double { chosen.reduce(0) { $0 + $1.kb } }

    func eligible(_ item: ToolItem) -> Bool {
        item.type != "keep" && item.state != "excluded" && !(tool == "cachesAdv" && ToolModel.riskyCaches.contains(item.type))
    }

    var eligibleKeys: [String] {
        var seen = Set<String>()
        return items.filter { eligible($0) && seen.insert($0.key).inserted }.map(\.key)
    }

    var eligibleSelectedCount: Int { eligibleKeys.filter { selected.contains($0) }.count }

    var eligibleSelectedKB: Double {
        items.filter { eligible($0) && selected.contains($0.key) }.reduce(0) { $0 + $1.kb }
    }

    var canSelectAll: Bool { tool != "system" && stage != .working && stage != .previewing && !eligibleKeys.isEmpty }

    var hasSelection: Bool { tool == "system" ? !info.isEmpty : !selected.isEmpty }

    var busy: Bool { listing || stage == .previewing || stage == .working }

    var foundCount: Int {
        switch tool {
        case "duplicates": return Set(items.map(\.index)).count
        default: return items.count
        }
    }

    var foundKB: Double {
        tool == "duplicates" ? items.filter { $0.type == "copy" }.reduce(0) { $0 + $1.kb } : items.reduce(0) { $0 + $1.kb }
    }

    func load(keepResult: Bool = false) {
        run?.cancel()
        generation += 1
        let gen = generation
        if !keepResult {
            message = nil
            result = nil
            stage = .idle
        }
        output = ""
        failed = false
        step = nil
        let previous = Set(items.filter { selected.contains($0.key) }.map(\.path))
        followAll = tool == "cachesAdv" && !keepResult && selected.isEmpty
        items = []
        skipped = []
        info = []
        selected = []
        guard let cli = cliPath else {
            message = L.t("missing") + " " + Model.installHint
            failed = true
            return
        }
        listing = true
        run = CLIRun.start(cli: cli, args: [command, "--list"] + params, line: { [weak self] l in
            guard let self, self.generation == gen else { return }
            if l.hasPrefix("STEP\t") {
                self.step = String(l.dropFirst(5))
                return
            }
            guard let item = ToolItem.parse(l) else { return }
            self.add(item, previous: previous)
        }) { [weak self] text, status in
            guard let self, self.generation == gen else { return }
            self.listing = false
            self.step = nil
            self.output = text
            if status != 0 {
                self.failed = true
                self.message = UninstallModel.summary(ToolItem.humanLines(text), status: status)
            }
        }
    }

    private func add(_ item: ToolItem, previous: Set<String>) {
        if tool == "system" {
            info.append(item)
            return
        }
        guard item.index > 0 else {
            skipped.append(item)
            return
        }
        if sortsBySize {
            let i = items.firstIndex { $0.kb < item.kb } ?? items.count
            items.insert(item, at: i)
        } else {
            items.append(item)
        }
        if previous.contains(item.path) && item.type != "keep" { selected.insert(item.key) }
        if followAll && eligible(item) && !(tool == "cachesAdv" && item.kb <= 0) {
            selected.insert(item.key)
        }
    }

    func stopSearch() {
        guard listing else { return }
        generation += 1
        run?.cancel()
        run = nil
        listing = false
        step = nil
        failed = false
        message = L.t("searchStopped")
    }

    func toggle(_ item: ToolItem) {
        guard stage != .working, stage != .previewing, item.type != "keep" else { return }
        if selected.contains(item.key) {
            selected.remove(item.key)
            followAll = false
        } else {
            selected.insert(item.key)
        }
        if stage == .preview || stage == .done { resetStage() }
    }

    func selectAll(_ on: Bool) {
        guard tool != "system", stage != .working, stage != .previewing, !items.isEmpty else { return }
        followAll = on
        if on { selected.formUnion(eligibleKeys) } else { selected.removeAll() }
        if stage == .preview || stage == .done { resetStage() }
    }

    private func resetStage() {
        stage = .idle
        result = nil
        message = nil
    }

    func act() {
        guard let cli = cliPath, !busy, hasSelection else { return }
        switch stage {
        case .preview:
            if needsSudo && CLIRun.askpassPath == nil && !Demo.enabled {
                message = L.t("noAskpass")
                failed = true
                return
            }
            let picked = chosen
            let estimate = selectedKB
            let before = Model.historyLines().count
            stage = .working
            message = nil
            failed = false
            steps = tool == "system" ? ["thin": "waiting", "purge": "waiting"] : [:]
            run = CLIRun.start(cli: cli, args: [command, "--yes"] + selectArgs + params, askpass: needsSudo, line: { [weak self] l in
                guard let self, l.hasPrefix("STEP\t") else { return }
                let c = l.components(separatedBy: "\t")
                if c.count >= 3 { self.steps[c[1]] = c[2] }
            }) { [weak self] text, status in
                guard let self else { return }
                self.output = text
                self.finish(text: text, status: status, picked: picked, estimate: estimate, before: before)
            }
        default:
            if tool == "system" {
                stage = .preview
                message = nil
                return
            }
            stage = .previewing
            message = nil
            failed = false
            generation += 1
            let gen = generation
            run = CLIRun.start(cli: cli, args: [command, "--dry-run"] + selectArgs + params) { [weak self] text, status in
                guard let self, self.generation == gen else { return }
                self.output = text
                self.stage = status == 0 ? .preview : .idle
                self.failed = status != 0
                self.message = status == 0 ? nil : UninstallModel.summary(ToolItem.humanLines(text), status: status)
            }
        }
    }

    private func finish(text: String, status: Int32, picked: [ToolItem], estimate: Double, before: Int) {
        let ok = status == 0
        let logged = Model.historyLines().dropFirst(before).filter { $0.action == ToolModel.historyAction[tool] }
        let freed = logged.isEmpty ? (ok ? estimate : 0) : logged.reduce(0) { $0 + $1.kb }
        let n = picked.count
        let title: String
        switch tool {
        case "startup":
            title = String(format: L.t("disabledN"), n)
        case "system":
            if let r = ToolItem.results(text).first(where: { $0.first == "free" }), r.count >= 3,
               let a = Double(r[1]), let b = Double(r[2]) {
                title = String(format: L.t("freeFromTo"), L.human(kb: a), L.human(kb: b))
            } else {
                title = L.t("done")
            }
        default:
            title = String(format: L.t("freedItems"), L.human(kb: freed), n)
        }
        result = ok ? ToolResult(ok: true, title: title, detail: tool == "startup" ? L.t("startupNote") : "")
            : ToolResult(ok: false, title: UninstallModel.summary(ToolItem.humanLines(text), status: status), raw: ToolItem.humanLines(text))
        stage = .done
        failed = false
        message = nil
        Hub.finished(tool, ok: ok)
        onChange?()
        selected = []
        load(keepResult: true)
    }

    func cancelPreview() {
        guard stage == .preview || stage == .done else { return }
        resetStage()
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
        if listing {
            stopSearch()
            return
        }
        guard stage == .previewing else { return }
        generation += 1
        run?.cancel()
        run = nil
        stage = .idle
        failed = false
        message = L.t("cancelled")
    }

    func back() -> Bool {
        switch stage {
        case .working: return false
        case .previewing: cancel()
        case .preview, .done: cancelPreview()
        case .idle, .loading:
            guard listing else { return false }
            stopSearch()
        }
        return true
    }

    var backKey: String {
        switch stage {
        case .previewing: return "cancel"
        case .preview, .done: return "back"
        default: return "home"
        }
    }

    func appear() {
        if stage == .idle && !listing && items.isEmpty && info.isEmpty { load() }
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
                EmptyView()
            }
            header
            if model.tool == "system" {
                SystemInfoView(rows: model.info, loading: model.listing)
            } else {
                ScanStatus(listing: model.listing, step: model.step.map { L.t("step_" + $0) }, count: model.foundCount,
                           kb: model.tool == "startup" ? nil : model.foundKB, stop: { model.stopSearch() })
                list
                if !model.skipped.isEmpty { SkippedRow(items: model.skipped) }
            }
            stageCard
            if let message = model.message {
                if model.failed {
                    ErrorNote(summary: message, detail: ToolItem.humanLines(model.output))
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
    private var stageCard: some View {
        switch model.stage {
        case .preview:
            SummaryCard(symbol: model.tool == "system" ? "gearshape.2" : "eye",
                        title: model.tool == "system" ? L.t("systemAction") : String(format: L.t("previewCount"), model.chosen.count, L.human(kb: model.selectedKB)),
                        subtitle: (model.tool == "system" ? "" : L.t("previewNote")) + (model.needsSudo ? (model.tool == "system" ? "" : " ") + L.t("sudoNote") : ""))
        case .working:
            if model.tool == "system" {
                StepList(steps: [("thin", L.t("stepThin")), ("purge", L.t("stepPurge"))].map { ($0.1, model.steps[$0.0] ?? "waiting") })
            } else {
                SummaryCard(symbol: "hourglass", title: String(format: L.t("workingCount"), model.chosen.count, L.human(kb: model.selectedKB)),
                            subtitle: L.t("keepRunning"), busy: true)
            }
        case .done:
            if let r = model.result { ResultCard(result: r) }
        default:
            EmptyView()
        }
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
                    Image(systemName: "folder").foregroundStyle(Theme.accent)
                    Text((model.dir as NSString).abbreviatingWithTildeInPath)
                        .font(.system(size: 12)).lineLimit(1).truncationMode(.middle)
                    Spacer()
                    Button(L.t("choose")) { model.chooseFolder() }.disabled(model.busy)
                }
                .padding(8)
                .themeField()
                paramRow(L.t("minSize"), text: $model.minMB)
            }
        case "startup":
            note(L.t("startupNote"))
        case "system":
            note(L.t("systemNote"))
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
                .themeField(7)
                .onSubmit { model.load() }
            Spacer()
            Button(L.t("scan")) { model.load() }.disabled(model.busy)
        }
    }

    private var list: some View {
        VStack(spacing: 0) {
            if !model.items.isEmpty {
                SelectAllBar(count: model.eligibleSelectedCount, total: model.eligibleKeys.count,
                             kb: model.tool == "startup" ? nil : model.eligibleSelectedKB,
                             enabled: model.canSelectAll) { model.selectAll($0) }
                    .padding(.horizontal, 6)
                    .padding(.top, 6)
                Divider().overlay(Theme.divider).padding(.horizontal, 10)
            }
            listScroll
        }
        .frame(maxHeight: .infinity)
        .themeCard()
    }

    private var listScroll: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 2) {
                if model.listing && model.items.isEmpty {
                    VStack(spacing: 8) {
                        ProgressView().controlSize(.small)
                        Text(L.t("searching")).font(.system(size: 12)).foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity).padding(.vertical, 40)
                } else if model.items.isEmpty {
                    if model.failed || model.message != nil {
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
    }

    private func sectionTitle(_ text: String) -> some View {
        Text(text).font(.system(size: 11, weight: .semibold)).foregroundStyle(.secondary)
            .padding(.top, 6).padding(.horizontal, 4)
    }

    private func checkbox(_ on: Bool, enabled: Bool = true) -> some View {
        Image(systemName: on ? "checkmark.square.fill" : "square")
            .font(.system(size: 14))
            .foregroundStyle(enabled ? (on ? Theme.accent : Color.secondary) : Color.secondary.opacity(0.4))
    }

    private func finderButton(_ path: String) -> some View {
        Button {
            guard !path.isEmpty else { return }
            NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: path)])
        } label: {
            Image(systemName: "magnifyingglass.circle").font(.system(size: 13)).foregroundStyle(Theme.accent)
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
                    IconTile(symbol: ItemStyle.symbol(item), size: 24, font: 12)
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
        .background(on ? Theme.selection : Color.clear, in: RoundedRectangle(cornerRadius: 7, style: .continuous))
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
                                .foregroundStyle(f.type == "keep" ? Theme.good : (on ? Theme.bad : Color.secondary))
                                .frame(width: 16)
                            Text(f.shortPath).font(.system(size: 11)).lineLimit(1).truncationMode(.middle)
                            if f.type == "keep" {
                                Text(L.t("kept")).font(.system(size: 10, weight: .semibold)).foregroundStyle(Theme.good)
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
            .background(on ? Theme.selection : Color.clear, in: RoundedRectangle(cornerRadius: 7, style: .continuous))
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
                        .disabled(model.stage == .working || model.stage == .previewing)
                        VStack(alignment: .leading, spacing: 1) {
                            Text(item.label).font(.system(size: 12)).lineLimit(1).truncationMode(.middle)
                                .strikethrough(model.selected.contains(item.key))
                            Text(item.path.hasPrefix("/") ? item.shortPath : L.t(item.type == "login" ? "loginItems" : "agents"))
                                .font(.system(size: 10)).foregroundStyle(.secondary).lineLimit(1).truncationMode(.middle)
                        }
                        Spacer(minLength: 6)
                        Circle().fill(item.state == "on" ? Theme.good : Color.secondary.opacity(0.4)).frame(width: 7, height: 7)
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
        let ready = model.hasSelection && model.cliPath != nil
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
            BlueButton(title: model.tool == "system" ? model.actionLabel + "…" : "\(L.t("preview")) · \(model.actionLabel)",
                       enabled: ready && !model.busy) { model.act() }
                .keyboardShortcut(.defaultAction)
        }
    }
}

struct SystemInfoView: View {
    let rows: [ToolItem]
    let loading: Bool

    private func rows(_ type: String) -> [ToolItem] { rows.filter { $0.type == type } }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 10) {
                if rows.isEmpty && loading {
                    VStack(spacing: 8) {
                        ProgressView().controlSize(.small)
                        Text(L.t("readingSystem")).font(.system(size: 12)).foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity).padding(.vertical, 40)
                } else {
                    LazyVGrid(columns: [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)], spacing: 10) {
                        if let f = rows("free").first {
                            let avail = Double(f.path) ?? f.kb
                            StatCard(symbol: "internaldrive", title: L.t("freeSpace"), value: L.human(kb: f.kb),
                                     detail: String(format: L.t("purgeableLine"), L.human(kb: Double(f.state) ?? 0), L.human(kb: avail)))
                        }
                        if let s = rows("swap").first {
                            let total = Double(s.path) ?? 0
                            StatCard(symbol: "arrow.left.arrow.right", title: L.t("swap"), value: L.human(kb: s.kb),
                                     detail: String(format: L.t("ofTotal"), L.human(kb: total)),
                                     fraction: total > 0 ? s.kb / total : nil)
                        }
                        let snaps = rows("snapshot")
                        StatCard(symbol: "clock.arrow.circlepath", title: L.t("snapshots"), value: "\(snaps.count)",
                                 detail: snaps.isEmpty ? L.t("noSnapshots") : snaps.prefix(2).map { SystemInfoView.snapshotName($0.label) }.joined(separator: " · "))
                        if let c = rows("container").first {
                            let cap = Double(c.path) ?? 0
                            StatCard(symbol: "square.stack.3d.up", title: String(format: L.t("container"), c.label), value: L.human(kb: c.kb),
                                     detail: String(format: L.t("ofTotal"), L.human(kb: cap)) + " · " + String(format: L.t("unallocated"), L.human(kb: Double(c.state) ?? 0)),
                                     fraction: cap > 0 ? c.kb / cap : nil)
                        }
                    }
                    let vols = rows("volume").sorted { $0.kb > $1.kb }
                    if !vols.isEmpty {
                        VStack(alignment: .leading, spacing: 6) {
                            Text(L.t("volumes")).font(.system(size: 11, weight: .semibold)).foregroundStyle(.secondary)
                            let maxKB = vols.map(\.kb).max() ?? 0
                            ForEach(vols) { v in
                                VStack(alignment: .leading, spacing: 3) {
                                    HStack {
                                        Text(v.label).font(.system(size: 12))
                                        if v.path != "-" && v.path != v.label {
                                            Text(v.path).font(.system(size: 10)).foregroundStyle(.secondary)
                                        }
                                        Spacer()
                                        Text(L.human(kb: v.kb)).font(.system(size: 11)).monospacedDigit().foregroundStyle(.secondary)
                                    }
                                    SizeBar(fraction: maxKB > 0 ? v.kb / maxKB : 0)
                                }
                            }
                        }
                        .padding(12)
                        .themeCard()
                    }
                    Text(L.t("swapNote")).font(.system(size: 11)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .frame(maxHeight: .infinity)
    }

    static func snapshotName(_ s: String) -> String {
        let parts = s.components(separatedBy: ".")
        if s.hasPrefix("com.apple.TimeMachine."), parts.count > 3 { return parts[3] }
        if s.hasPrefix("com.apple.os.update") { return L.t("snapUpdate") }
        return parts.last ?? s
    }
}

struct SelectAllBar: View {
    let count: Int
    let total: Int
    var kb: Double?
    var enabled = true
    let set: (Bool) -> Void

    private var all: Bool { total > 0 && count >= total }

    private var symbol: String { count == 0 ? "square" : (all ? "checkmark.square.fill" : "minus.square.fill") }

    private var counter: String {
        let base = String(format: L.t("selectedOf"), count, total)
        return kb.map { base + " · " + L.human(kb: $0) } ?? base
    }

    var body: some View {
        HStack(spacing: 8) {
            Button { set(!all) } label: {
                HStack(spacing: 8) {
                    Image(systemName: symbol)
                        .font(.system(size: 14))
                        .foregroundStyle(enabled && count > 0 ? Theme.accent : Color.secondary)
                    Text(L.t(all ? "selectNone" : "selectAll")).font(.system(size: 12, weight: .medium))
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(!enabled)
            .help(all ? "\u{2318}\u{21E7}A" : "\u{2318}A")
            Spacer(minLength: 6)
            Text(counter).font(.system(size: 11)).monospacedDigit().foregroundStyle(.secondary).lineLimit(1)
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 5)
        .background {
            ZStack {
                Button("") { set(true) }.keyboardShortcut("a", modifiers: .command)
                Button("") { set(false) }.keyboardShortcut("a", modifiers: [.command, .shift])
            }
            .disabled(!enabled)
            .opacity(0)
            .allowsHitTesting(false)
            .accessibilityHidden(true)
        }
    }
}

struct StatCard: View {
    let symbol: String
    let title: String
    let value: String
    var detail = ""
    var fraction: Double?

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            IconTile(symbol: symbol, size: 32, font: 14)
            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(.system(size: 11)).foregroundStyle(.secondary).lineLimit(1)
                Text(value).font(.system(size: 18, weight: .semibold, design: .rounded)).monospacedDigit().lineLimit(1)
                if let fraction { SizeBar(fraction: fraction).padding(.vertical, 2) }
                if !detail.isEmpty {
                    Text(detail).font(.system(size: 10.5)).foregroundStyle(.secondary).lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .themeCard()
    }
}
