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
            run = CLIRun.start(cli: cli, args: ["maintenance", "--list"]) { [weak self] text, _ in
                guard let self, self.generation == gen else { return }
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
                self.message = String(format: L.t("exitCode"), status)
            } else {
                self.message = L.t("previewNote") + (self.isMaintenance ? " " + L.t("maintSudo") : "")
            }
        }
    }

    func act() {
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
        onChange?()
    }

    func stop() {
        if !working { run?.cancel() }
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
    let close: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(L.t(model.tool)).font(.system(size: 18, weight: .bold, design: .rounded))
            Text(L.t(model.isMaintenance ? "maintNote" : "privacyNote"))
                .font(.system(size: 11)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            if model.isMaintenance { taskList }
            outputBox
            if let m = model.message {
                Text(m).font(.caption).foregroundStyle(model.failed ? Color.red : Color.secondary).lineLimit(3)
            }
            HStack {
                Spacer()
                Button(L.t("close")) { close() }.keyboardShortcut(.cancelAction)
                Button { model.act() } label: {
                    Group {
                        if model.working { ProgressView().controlSize(.small) }
                        else { Text(L.t(model.isMaintenance ? "runTasks" : "clean")) }
                    }
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 7)
                    .background((model.isMaintenance ? Color.accentBlue : Color.red).opacity(model.canRun ? 1 : 0.4),
                                in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .disabled(!model.canRun)
            }
            .controlSize(.large)
        }
        .padding(18)
        .frame(width: 480, height: model.isMaintenance ? 600 : 560)
        .background(.ultraThinMaterial)
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

@MainActor
final class CareWindow: NSObject, NSWindowDelegate {
    private var panel: NSPanel?
    private var model: CareModel?
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
            if model?.working != true { model?.reload() }
            NSApp.activate(ignoringOtherApps: true)
            panel.makeKeyAndOrderFront(nil)
            return
        }
        let m = CareModel(tool: tool, cliPath: cliPath)
        m.onChange = onChange
        let h: CGFloat = tool == "maintenance" ? 600 : 560
        let p = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 480, height: h),
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
        p.contentView = NSHostingView(rootView: CareView(model: m) { [weak p] in p?.close() })
        p.center()
        panel = p
        model = m
        m.reload()
        NSApp.activate(ignoringOtherApps: true)
        p.makeKeyAndOrderFront(nil)
    }

    func windowWillClose(_ notification: Notification) {
        model?.stop()
    }
}
