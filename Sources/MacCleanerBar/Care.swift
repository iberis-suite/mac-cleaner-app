import AppKit
import SwiftUI

@MainActor
final class CareModel: ObservableObject {
    let tool: String
    let cliPath: String?
    @Published var tasks: [ToolItem] = []
    @Published var selected: Set<Int> = []
    @Published var output = ""
    @Published var loading = false
    @Published var working = false
    @Published var finished = false
    @Published var message: String?
    @Published var failed = false
    @Published var confirming = false
    var onChange: (() -> Void)?
    private var run: CLIRun?
    private var generation = 0

    init(tool: String, cliPath: String?) {
        self.tool = tool
        self.cliPath = cliPath
    }

    var isMaintenance: Bool { tool == "maintenance" }

    var selectArg: String { selected.sorted().map(String.init).joined(separator: " ") }

    var canRun: Bool {
        cliPath != nil && !loading && !working && !finished && !output.isEmpty && !failed
            && (!isMaintenance || !selected.isEmpty)
    }

    func reload() {
        run?.cancel()
        generation += 1
        let gen = generation
        finished = false
        failed = false
        message = nil
        guard let cli = cliPath else {
            message = L.t("missing") + " " + Model.installHint
            failed = true
            return
        }
        if isMaintenance {
            loading = true
            run = CLIRun.start(cli: cli, args: ["maintenance", "--list"]) { [weak self] text, status in
                guard let self, self.generation == gen else { return }
                guard status == 0 else {
                    self.loading = false
                    self.failed = true
                    self.output = ToolModel.clean(text)
                    self.message = UninstallModel.summary(text, status: status)
                    return
                }
                self.tasks = ToolItem.parseList(text)
                self.selected = Set(self.tasks.filter { $0.index > 0 }.map(\.index))
                self.preview()
            }
        } else {
            preview()
        }
    }

    func toggle(_ t: ToolItem) {
        guard t.index > 0, !working else { return }
        if selected.contains(t.index) { selected.remove(t.index) } else { selected.insert(t.index) }
        finished = false
        message = nil
        preview()
    }

    func preview() {
        guard let cli = cliPath else { return }
        run?.cancel()
        generation += 1
        let gen = generation
        if isMaintenance && selected.isEmpty {
            loading = false
            output = ""
            return
        }
        loading = true
        failed = false
        let args = isMaintenance ? ["maintenance", "--dry-run", "--select", selectArg] : ["privacy", "--dry-run"]
        run = CLIRun.start(cli: cli, args: args) { [weak self] text, status in
            guard let self, self.generation == gen else { return }
            self.loading = false
            self.output = ToolModel.clean(text)
            if status != 0 {
                self.failed = true
                self.message = UninstallModel.summary(text, status: status)
            } else {
                self.message = L.t("previewNote") + (self.isMaintenance ? " " + L.t("maintSudo") : "")
            }
        }
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
        if isMaintenance { runMaintenance(cli: cli) } else { runPrivacy(cli: cli) }
    }

    private func runPrivacy(cli: String) {
        run = CLIRun.start(cli: cli, args: ["privacy", "--yes"],
                           output: { [weak self] t in self?.output = ToolModel.clean(t) }) { [weak self] text, status in
            guard let self else { return }
            self.output = ToolModel.clean(text)
            self.finish(ok: status == 0, error: String(format: L.t("exitCode"), status))
        }
    }

    private func runMaintenance(cli: String) {
        if Demo.enabled {
            run = CLIRun.start(cli: cli, args: ["maintenance", "--yes", "--select", selectArg],
                               output: { [weak self] t in self?.output = ToolModel.clean(t) }) { [weak self] text, status in
                guard let self else { return }
                self.output = ToolModel.clean(text)
                self.finish(ok: status == 0, error: L.t("maintFailed"))
            }
            return
        }
        let hist = Model.historyPath
        let fm = FileManager.default
        try? fm.createDirectory(atPath: (hist as NSString).deletingLastPathComponent, withIntermediateDirectories: true)
        if !fm.fileExists(atPath: hist) { fm.createFile(atPath: hist, contents: nil) }
        var env = [
            "HOME": NSHomeDirectory(), "MAC_CLEANER_USER": NSUserName(), "MAC_CLEANER_LANG": L.fr ? "fr" : "en",
            "NO_COLOR": "1", "TERM": "dumb", "LC_CTYPE": "en_US.UTF-8",
        ]
        if let x = ProcessInfo.processInfo.environment["XDG_STATE_HOME"] { env["XDG_STATE_HOME"] = x }
        let assigns = env.keys.sorted().map { "\($0)=\(CareModel.quote(env[$0] ?? ""))" }.joined(separator: " ")
        let shell = "\(assigns) /bin/zsh \(CareModel.quote(cli)) maintenance --yes --select \(CareModel.quote(selectArg)) 2>&1"
        let source = "do shell script \"\(CareModel.escape(shell))\" with administrator privileges"
        Thread.detachNewThread { [weak self] in
            var error: NSDictionary?
            let result = NSAppleScript(source: source)?.executeAndReturnError(&error)
            let text = (result?.stringValue ?? "").replacingOccurrences(of: "\r", with: "\n")
            let reason = error?[NSAppleScript.errorMessage] as? String ?? ""
            let ok = error == nil
            DispatchQueue.main.async {
                guard let self else { return }
                self.output = Model.stripANSI(ok ? text : reason.replacingOccurrences(of: "\r", with: "\n"))
                self.finish(ok: ok, error: L.t("maintFailed"))
            }
        }
    }

    private func finish(ok: Bool, error: String) {
        working = false
        finished = true
        failed = !ok
        message = ok ? L.t("done") : error
        Hub.finished(tool, ok: ok)
        onChange?()
    }

    func cancel() {
        guard loading, !working else { return }
        generation += 1
        run?.cancel()
        run = nil
        loading = false
        output = ""
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
        if !working && !loading && (output.isEmpty || finished) { reload() }
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
            if model.isMaintenance { taskList }
            outputBox
            if let m = model.message {
                if model.failed {
                    ErrorNote(summary: m, detail: model.output)
                } else {
                    Text(m).font(.caption).foregroundStyle(.secondary).lineLimit(3)
                }
            }
            Group {
                if model.working {
                    RunningNote(text: L.t("keepRunning"))
                } else {
                    HStack(spacing: 10) {
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

    private var taskList: some View {
        VStack(alignment: .leading, spacing: 2) {
            ForEach(model.tasks) { t in
                let on = model.selected.contains(t.index)
                let available = t.index > 0
                Button { model.toggle(t) } label: {
                    HStack(spacing: 8) {
                        Image(systemName: on ? "checkmark.square.fill" : "square")
                            .font(.system(size: 14))
                            .foregroundStyle(available ? (on ? Color.accentBlue : Color.secondary) : Color.secondary.opacity(0.4))
                        VStack(alignment: .leading, spacing: 2) {
                            HStack(spacing: 6) {
                                Text(t.label).font(.system(size: 12))
                                if t.state == "root" {
                                    Text(L.t("admin")).font(.system(size: 9.5, weight: .semibold)).foregroundStyle(.secondary)
                                        .padding(.horizontal, 5).padding(.vertical, 1)
                                        .background(Color.primary.opacity(0.08), in: Capsule())
                                }
                                if !available {
                                    Text(L.t("unavailable")).font(.system(size: 10)).foregroundStyle(.tertiary)
                                }
                            }
                            Text(t.path).font(.system(size: 9.5, design: .monospaced)).foregroundStyle(.secondary)
                                .lineLimit(1).truncationMode(.middle)
                        }
                        Spacer(minLength: 0)
                    }
                    .padding(.horizontal, 6)
                    .padding(.vertical, 5)
                    .background(on ? Color.accentBlue.opacity(0.12) : Color.clear, in: RoundedRectangle(cornerRadius: 7, style: .continuous))
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .disabled(!available || model.working)
                .help(t.path)
            }
        }
        .padding(6)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private var outputBox: some View {
        ScrollView([.horizontal, .vertical]) {
            Group {
                if model.output.isEmpty {
                    Text(model.loading || model.working ? L.t("running") : L.t("noOutput"))
                } else {
                    Text(model.output)
                }
            }
            .font(.system(size: 10.5, design: .monospaced))
            .fixedSize(horizontal: true, vertical: true)
            .textSelection(.enabled)
            .padding(8)
            .frame(maxWidth: .infinity, alignment: .topLeading)
        }
        .frame(maxHeight: .infinity)
        .background(Color.black.opacity(0.25), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(alignment: .topTrailing) {
            if model.loading { ProgressView().controlSize(.small).padding(8) }
        }
    }
}
