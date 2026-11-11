import AppKit
import SwiftUI

@MainActor
final class CareModel: ObservableObject {
    let tool: String
    let cliPath: String?
    @Published var tasks: [ToolItem] = []
    @Published var notes: [ToolItem] = []
    @Published var selected: Set<Int> = []
    @Published var states: [Int: String] = [:]
    @Published var output = ""
    @Published var loading = false
    @Published var working = false
    @Published var finished = false
    @Published var message: String?
    @Published var failed = false
    @Published var confirming = false
    @Published var result: ToolResult?
    var onChange: (() -> Void)?
    private var run: CLIRun?
    private var generation = 0
    private var poll: Timer?

    init(tool: String, cliPath: String?) {
        self.tool = tool
        self.cliPath = cliPath
    }

    var isMaintenance: Bool { tool == "maintenance" }

    var selectArg: String { selected.sorted().map(String.init).joined(separator: " ") }

    var selectedKB: Double { tasks.filter { selected.contains($0.index) }.reduce(0) { $0 + $1.kb } }

    var canRun: Bool {
        cliPath != nil && !loading && !working && !finished && !failed && !selected.isEmpty
    }

    func reload() {
        run?.cancel()
        generation += 1
        let gen = generation
        finished = false
        failed = false
        message = nil
        result = nil
        states = [:]
        tasks = []
        notes = []
        selected = []
        output = ""
        guard let cli = cliPath else {
            message = L.t("missing") + " " + Model.installHint
            failed = true
            return
        }
        loading = true
        run = CLIRun.start(cli: cli, args: [tool, "--list"], line: { [weak self] l in
            guard let self, self.generation == gen, let item = ToolItem.parse(l) else { return }
            if item.index > 0 {
                self.tasks.append(item)
                if self.isMaintenance || item.type != "cookies" { self.selected.insert(item.index) }
            } else if self.isMaintenance {
                self.tasks.append(item)
            } else {
                self.notes.append(item)
            }
        }) { [weak self] text, status in
            guard let self, self.generation == gen else { return }
            self.loading = false
            self.output = text
            if status != 0 {
                self.failed = true
                self.message = UninstallModel.summary(ToolItem.humanLines(text), status: status)
            }
        }
    }

    func toggle(_ t: ToolItem) {
        guard t.index > 0, !working, !finished else { return }
        if selected.contains(t.index) { selected.remove(t.index) } else { selected.insert(t.index) }
    }

    func ask() {
        guard canRun else { return }
        if isMaintenance { act() } else { confirming = true }
    }

    func act() {
        confirming = false
        guard canRun, let cli = cliPath else { return }
        working = true
        message = nil
        result = nil
        states = Dictionary(uniqueKeysWithValues: selected.map { ($0, "waiting") })
        if isMaintenance { runMaintenance(cli: cli) } else { runPrivacy(cli: cli) }
    }

    private func apply(_ line: String) {
        guard line.hasPrefix("STEP\t") else { return }
        let c = line.components(separatedBy: "\t")
        guard c.count >= 3 else { return }
        if let i = Int(c[1]) {
            states[i] = c[2]
        } else if let t = tasks.first(where: { $0.type == c[1] }) {
            states[t.index] = c[2]
        }
    }

    private func runPrivacy(cli: String) {
        let estimate = selectedKB
        let count = selected.count
        run = CLIRun.start(cli: cli, args: ["privacy", "--yes", "--select", selectArg], line: { [weak self] l in
            self?.apply(l)
        }) { [weak self] text, status in
            guard let self else { return }
            self.output = text
            var kb = estimate
            var n = count
            if let r = ToolItem.results(text).first, r.count >= 2, let k = Double(r[0]), let c = Int(r[1]) {
                kb = k
                n = c
            }
            self.finish(ok: status == 0, title: String(format: L.t("erasedItems"), L.human(kb: kb), n),
                        error: UninstallModel.summary(ToolItem.humanLines(text), status: status))
        }
    }

    private func runMaintenance(cli: String) {
        if Demo.enabled {
            run = CLIRun.start(cli: cli, args: ["maintenance", "--yes", "--select", selectArg], line: { [weak self] l in
                self?.apply(l)
            }) { [weak self] text, status in
                guard let self else { return }
                self.output = text
                self.finishMaintenance(ok: status == 0)
            }
            return
        }
        let hist = Model.historyPath
        let fm = FileManager.default
        try? fm.createDirectory(atPath: (hist as NSString).deletingLastPathComponent, withIntermediateDirectories: true)
        if !fm.fileExists(atPath: hist) { fm.createFile(atPath: hist, contents: nil) }
        let log = (NSTemporaryDirectory() as NSString).appendingPathComponent("mac-cleaner-maintenance-\(UUID().uuidString).log")
        fm.createFile(atPath: log, contents: nil)
        var env = [
            "HOME": NSHomeDirectory(), "MAC_CLEANER_USER": NSUserName(), "MAC_CLEANER_LANG": L.fr ? "fr" : "en",
            "NO_COLOR": "1", "TERM": "dumb", "LC_CTYPE": "en_US.UTF-8", "MAC_CLEANER_MACHINE": "1",
        ]
        if let x = ProcessInfo.processInfo.environment["XDG_STATE_HOME"] { env["XDG_STATE_HOME"] = x }
        let assigns = env.keys.sorted().map { "\($0)=\(CareModel.quote(env[$0] ?? ""))" }.joined(separator: " ")
        let shell = "\(assigns) /bin/zsh \(CareModel.quote(cli)) maintenance --yes --select \(CareModel.quote(selectArg)) >> \(CareModel.quote(log)) 2>&1"
        let source = "do shell script \"\(CareModel.escape(shell))\" with administrator privileges"
        let t = Timer(timeInterval: 0.5, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.readLog(log) }
        }
        RunLoop.main.add(t, forMode: .common)
        poll = t
        Thread.detachNewThread { [weak self] in
            var error: NSDictionary?
            NSAppleScript(source: source)?.executeAndReturnError(&error)
            let reason = error?[NSAppleScript.errorMessage] as? String ?? ""
            let ok = error == nil
            DispatchQueue.main.async {
                guard let self else { return }
                self.poll?.invalidate()
                self.poll = nil
                self.readLog(log)
                try? FileManager.default.removeItem(atPath: log)
                if !ok && self.output.isEmpty { self.output = reason }
                self.finishMaintenance(ok: ok && !self.states.values.contains("failed"))
            }
        }
    }

    private func readLog(_ path: String) {
        guard let text = try? String(contentsOfFile: path, encoding: .utf8) else { return }
        output = Model.stripANSI(text)
        output.components(separatedBy: "\n").forEach(apply)
    }

    private func finishMaintenance(ok: Bool) {
        for (k, v) in states where v == "waiting" || v == "running" { states[k] = ok ? "done" : "skipped" }
        let n = states.values.filter { $0 == "done" }.count
        finish(ok: ok, title: String(format: L.t("tasksDone"), n), error: L.t("maintFailed"))
    }

    private func finish(ok: Bool, title: String, error: String) {
        working = false
        finished = true
        result = ok ? ToolResult(ok: true, title: title, detail: isMaintenance ? L.t("maintAfter") : "")
            : ToolResult(ok: false, title: error, raw: ToolItem.humanLines(output))
        Hub.finished(tool, ok: ok)
        onChange?()
    }

    func cancel() {
        guard loading, !working else { return }
        generation += 1
        run?.cancel()
        run = nil
        loading = false
        failed = false
        message = L.t("cancelled")
    }

    func back() -> Bool {
        if working { return false }
        if loading {
            cancel()
            return true
        }
        if finished {
            reload()
            return true
        }
        return false
    }

    var backKey: String {
        if working { return "home" }
        if loading { return "cancel" }
        return finished ? "back" : "home"
    }

    func appear() {
        if !working && !loading && (tasks.isEmpty || finished) { reload() }
    }

    func stop() {
        if !working { cancel() }
    }

    nonisolated static func quote(_ s: String) -> String {
        "'" + s.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }

    nonisolated static func escape(_ s: String) -> String {
        s.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"")
    }
}

struct CareView: View {
    @ObservedObject var model: CareModel
    let home: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            ToolHeader(title: L.t(model.tool), backTitle: L.t(model.backKey), back: { if !model.back() { home() } }) {
                EmptyView()
            }
            Text(L.t(model.isMaintenance ? "maintNote" : "privacyNote"))
                .font(.system(size: 11)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            if !model.isMaintenance {
                ScanStatus(listing: model.loading, count: model.tasks.count, kb: model.tasks.reduce(0) { $0 + $1.kb }) { model.cancel() }
            }
            list
            if let r = model.result { ResultCard(result: r) }
            if let m = model.message {
                if model.failed {
                    ErrorNote(summary: m, detail: ToolItem.humanLines(model.output))
                } else {
                    Text(m).font(.caption).foregroundStyle(.secondary).lineLimit(3)
                }
            }
            Group {
                if model.working {
                    RunningNote(text: L.t(model.isMaintenance ? "maintSudo" : "keepRunning"))
                } else {
                    HStack(spacing: 10) {
                        if !model.isMaintenance {
                            Text(String(format: L.t("selection"), L.human(kb: model.selectedKB)))
                                .font(.system(size: 12, weight: .semibold)).monospacedDigit()
                        }
                        Spacer()
                        if model.finished {
                            BlueButton(title: L.t("done")) { _ = model.back() }.keyboardShortcut(.defaultAction)
                        } else {
                            if model.loading { SecondaryButton(title: L.t("cancel")) { model.cancel() } }
                            BlueButton(title: L.t(model.isMaintenance ? "runTasks" : "clean") + (model.isMaintenance ? "" : "…"),
                                       enabled: model.canRun, destructive: !model.isMaintenance) { model.ask() }
                                .keyboardShortcut(.defaultAction)
                        }
                    }
                }
            }
            .frame(minHeight: 32)
        }
        .padding(20)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .alert(L.t("privacyAsk"), isPresented: $model.confirming) {
            Button(L.t("clean"), role: .destructive) { model.act() }
            Button(L.t("cancel"), role: .cancel) {}
        } message: {
            Text(L.t("privacyInfo"))
        }
    }

    @ViewBuilder
    private var list: some View {
        if model.isMaintenance {
            listContent.themeCard()
        } else {
            ScrollView { listContent }
                .frame(maxHeight: .infinity)
                .themeCard()
        }
    }

    private var listContent: some View {
            VStack(alignment: .leading, spacing: 2) {
                if model.tasks.isEmpty && model.loading {
                    VStack(spacing: 8) {
                        ProgressView().controlSize(.small)
                        Text(L.t("searching")).font(.system(size: 12)).foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity).padding(.vertical, 30)
                } else if model.tasks.isEmpty && !model.failed && model.message == nil {
                    EmptyNote(text: L.t(model.isMaintenance ? "nothing" : "noBrowser"))
                } else if model.isMaintenance {
                    ForEach(model.tasks) { taskRow($0) }
                } else {
                    privacyRows
                }
                ForEach(model.notes) { n in
                    HStack(spacing: 8) {
                        Image(systemName: n.type == "running" ? "lock" : "lock.shield").font(.system(size: 11)).foregroundStyle(.secondary)
                            .frame(width: 18)
                        Text(String(format: L.t(n.type == "running" ? "browserOpen" : "browserNoAccess"), n.label))
                            .font(.system(size: 11)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(.horizontal, 6).padding(.vertical, 4)
                }
            }
            .padding(6)
    }

    private func checkbox(_ on: Bool, available: Bool) -> some View {
        Image(systemName: on ? "checkmark.square.fill" : "square")
            .font(.system(size: 14))
            .foregroundStyle(available ? (on ? Theme.accent : Color.secondary) : Color.secondary.opacity(0.4))
    }

    private static let taskIcons = ["dns": "network", "spotlight": "magnifyingglass", "launch": "square.grid.2x2", "periodic": "calendar"]

    private func taskRow(_ t: ToolItem) -> some View {
        let on = model.selected.contains(t.index)
        let available = t.index > 0
        let state = model.states[t.index]
        return Button { model.toggle(t) } label: {
            HStack(spacing: 10) {
                checkbox(on, available: available)
                IconTile(symbol: CareView.taskIcons[t.type] ?? "wrench.and.screwdriver", size: 28, font: 13)
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text(t.label).font(.system(size: 12.5, weight: .medium))
                        if t.state == "root" {
                            Text(L.t("admin")).font(.system(size: 9.5, weight: .semibold)).foregroundStyle(.secondary)
                                .padding(.horizontal, 5).padding(.vertical, 1)
                                .background(Theme.tile, in: Capsule())
                        }
                    }
                    Text(available ? L.t("mt_" + t.type) : L.t("unavailable"))
                        .font(.system(size: 10.5)).foregroundStyle(.secondary).lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                    if state == "failed" {
                        Text(L.t("stepFailed")).font(.system(size: 10.5)).foregroundStyle(Theme.bad)
                    }
                }
                Spacer(minLength: 6)
                if let state { stateBadge(state) }
            }
            .padding(.horizontal, 6)
            .padding(.vertical, 6)
            .background(on && state == nil ? Theme.selection : Color.clear, in: RoundedRectangle(cornerRadius: 7, style: .continuous))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!available)
        .help(t.path)
    }

    private func stateBadge(_ state: String) -> some View {
        HStack(spacing: 4) {
            switch state {
            case "running": ProgressView().controlSize(.mini)
            case "done": Image(systemName: "checkmark.circle.fill").foregroundStyle(Theme.good)
            case "failed": Image(systemName: "xmark.circle.fill").foregroundStyle(Theme.bad)
            case "skipped": Image(systemName: "minus.circle").foregroundStyle(.secondary)
            default: Image(systemName: "circle").foregroundStyle(.tertiary)
            }
            Text(L.t("state_" + state)).font(.system(size: 10.5, weight: .medium)).foregroundStyle(.secondary)
        }
        .font(.system(size: 12))
    }

    private static func split(_ label: String) -> (String, String) {
        let parts = label.components(separatedBy: " · ")
        guard parts.count > 1 else { return (label, label) }
        return (parts.dropLast().joined(separator: " · "), parts.last ?? label)
    }

    @ViewBuilder
    private var privacyRows: some View {
        let groups = model.tasks.reduce(into: [(String, [ToolItem])]()) { acc, t in
            let w = CareView.split(t.label).0
            if let i = acc.firstIndex(where: { $0.0 == w }) { acc[i].1.append(t) } else { acc.append((w, [t])) }
        }
        let maxKB = model.tasks.map(\.kb).max() ?? 0
        ForEach(groups, id: \.0) { g in
            Text(g.0).font(.system(size: 11, weight: .semibold)).foregroundStyle(.secondary)
                .padding(.top, 6).padding(.horizontal, 4)
            ForEach(g.1) { t in
                let on = model.selected.contains(t.index)
                let state = model.states[t.index]
                Button { model.toggle(t) } label: {
                    HStack(spacing: 8) {
                        checkbox(on, available: true)
                        IconTile(symbol: ["history": "clock", "cookies": "person.badge.key", "cache": "square.stack.3d.up"][t.type] ?? "doc",
                                 size: 24, font: 12)
                        VStack(alignment: .leading, spacing: 3) {
                            HStack(spacing: 6) {
                                Text(CareView.split(t.label).1).font(.system(size: 12))
                                if t.type == "cookies" {
                                    Text(L.t("cookiesWarn")).font(.system(size: 10)).foregroundStyle(Theme.warn)
                                }
                                Spacer(minLength: 6)
                                if let state { stateBadge(state) }
                                Text(L.human(kb: t.kb)).font(.system(size: 11)).monospacedDigit().foregroundStyle(.secondary)
                            }
                            SizeBar(fraction: maxKB > 0 ? t.kb / maxKB : 0)
                        }
                    }
                    .padding(.horizontal, 6)
                    .padding(.vertical, 4)
                    .background(on && state == nil ? Theme.selection : Color.clear, in: RoundedRectangle(cornerRadius: 7, style: .continuous))
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help(t.path)
            }
        }
    }
}
