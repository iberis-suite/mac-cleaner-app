import AppKit
import Foundation
import ServiceManagement

struct HistoryEntry: Identifiable {
    let id = UUID()
    let date: Date
    let label: String
    let kb: Double
    let action: String
}

enum Phase: Equatable {
    case idle
    case previewing(String)
    case previewReady(String)
    case cleaning(String)
    case cleaned(String)
}

final class CLIRun {
    private let process = Process()
    private var data = Data()

    static var askpassPath: String? {
        guard let p = Bundle.main.path(forResource: "askpass", ofType: nil),
              FileManager.default.isExecutableFile(atPath: p) else { return nil }
        return p
    }

    static func environment(askpass: Bool = false) -> [String: String] {
        var env = ProcessInfo.processInfo.environment
        env.removeValue(forKey: "SUDO_ASKPASS")
        if askpass, let p = askpassPath { env["SUDO_ASKPASS"] = p }
        env["NO_COLOR"] = "1"
        env["TERM"] = "dumb"
        env["MAC_CLEANER_LANG"] = L.fr ? "fr" : "en"
        if env["LANG"] == nil && env["LC_ALL"] == nil && env["LC_CTYPE"] == nil {
            env["LC_CTYPE"] = "en_US.UTF-8"
        }
        return env
    }

    @discardableResult
    static func start(cli: String, args: [String], askpass: Bool = false, output: ((String) -> Void)? = nil,
                      completion: @escaping (String, Int32) -> Void) -> CLIRun {
        let run = CLIRun()
        let p = run.process
        p.executableURL = URL(fileURLWithPath: "/bin/zsh")
        p.arguments = [cli] + args
        p.environment = environment(askpass: askpass)
        p.standardInput = FileHandle.nullDevice
        let pipe = Pipe()
        p.standardOutput = pipe
        p.standardError = pipe
        pipe.fileHandleForReading.readabilityHandler = { handle in
            let chunk = handle.availableData
            guard !chunk.isEmpty else { return }
            DispatchQueue.main.async {
                run.data.append(chunk)
                output?(Model.stripANSI(String(decoding: run.data, as: UTF8.self)))
            }
        }
        p.terminationHandler = { proc in
            let rest = pipe.fileHandleForReading.readDataToEndOfFile()
            pipe.fileHandleForReading.readabilityHandler = nil
            let status = proc.terminationStatus
            DispatchQueue.main.async {
                if !rest.isEmpty { run.data.append(rest) }
                let text = Model.stripANSI(String(decoding: run.data, as: UTF8.self))
                output?(text)
                completion(text, status)
            }
        }
        do {
            try p.run()
        } catch {
            DispatchQueue.main.async { completion(error.localizedDescription, 1) }
        }
        return run
    }

    func cancel() {
        if process.isRunning { process.terminate() }
    }
}

@MainActor
final class Model: ObservableObject {
    static let installHint = "brew install chaibialaa/tap/mac-cleaner"
    static let estimated = ["temp", "caches", "trash"]

    @Published var diskTotal: Int64 = 0
    @Published var diskFree: Int64 = 0
    @Published var memFreePct: Int = 100
    @Published var sensors = SensorReading()
    @Published var freedMonth: Double = 0
    @Published var phase: Phase = .idle
    @Published var output = ""
    @Published var exitStatus: Int32 = 0
    @Published var launchAtLogin = false
    @Published var estimates: [String: Double] = [:]
    @Published var estimating: Set<String> = []
    @Published var purging = false
    @Published var notice: String?
    @Published var alertsEnabled: Bool
    @Published var weeklyEnabled = false
    @Published var fullDiskAccess = true
    @Published var battery: BatteryInfo?
    @Published var topCPU: [AppUsage] = []
    @Published var topMemory: [AppUsage] = []
    @Published var activityExpanded: Bool
    @Published var thermalState = ProcessInfo.processInfo.thermalState

    let cliPath: String?
    weak var panelWindow: NSWindow?
    var hotStreak = 0
    var trashBytes: Int64?
    var trashCheckedAt: Date?
    var trashMeasuring = false
    private var timer: Timer?
    private var ticks = 0
    private var activityTimer: Timer?
    private let sampler = ProcSampler()
    private var current: CLIRun?
    private var lastEstimate: Date?
    private var thermalObserver: NSObjectProtocol?

    init() {
        let d = UserDefaults.standard
        d.register(defaults: ["alertsEnabled": true, "activityExpanded": false])
        alertsEnabled = d.bool(forKey: "alertsEnabled")
        activityExpanded = d.bool(forKey: "activityExpanded")
        cliPath = Model.findCLI()
        launchAtLogin = SMAppService.mainApp.status == .enabled
        weeklyEnabled = WeeklyJob.isInstalled
        battery = Battery.read()
        AlertCenter.shared.onOpen = { [weak self] in
            Task { @MainActor in StatusItemOpener.open(panel: self?.panelWindow) }
        }
        AlertCenter.shared.setUp(enabled: alertsEnabled)
        thermalObserver = NotificationCenter.default.addObserver(
            forName: ProcessInfo.thermalStateDidChangeNotification, object: nil, queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.thermalState = ProcessInfo.processInfo.thermalState }
        }
        refresh()
        let t = Timer(timeInterval: 60, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.tick() }
        }
        RunLoop.main.add(t, forMode: .common)
        timer = t
    }

    private func tick() {
        refresh()
        ticks += 1
        if ticks % 5 == 0 { checkAlerts() }
    }

    var busy: Bool {
        if purging { return true }
        switch phase {
        case .previewing, .cleaning: return true
        default: return false
        }
    }

    var diskUsedPct: Int {
        diskTotal > 0 ? Int((diskTotal - diskFree) * 100 / diskTotal) : 0
    }

    var memUsedPct: Int { max(0, min(100, 100 - memFreePct)) }

    nonisolated static func level(pct: Int) -> Int { pct >= 85 ? 2 : (pct >= 60 ? 1 : 0) }

    nonisolated static let appleSilicon: Bool = {
        var v: Int32 = 0
        var size = MemoryLayout<Int32>.size
        return sysctlbyname("hw.optional.arm64", &v, &size, nil, 0) == 0 && v == 1
    }()

    var temperatureLevel: Int? {
        sensors.temperature.map { ChipProfile.current.level($0) }
    }

    var heatLevel: Int {
        max(Heat.level(thermalState), temperatureLevel ?? 0)
    }

    var level: Int {
        max(Model.level(pct: diskUsedPct), Model.level(pct: memUsedPct), min(2, heatLevel))
    }

    nonisolated static func nsColor(level: Int) -> NSColor {
        [NSColor.systemGreen, .systemOrange, .systemRed][max(0, min(2, level))]
    }

    var freeLabel: String {
        let gb = Double(diskFree) / 1_000_000_000
        return String(format: "%.0f %@", gb, L.gb)
    }

    static let symbolName: String = {
        for name in ["broom", "broom.fill", "paintbrush.pointed.fill", "paintbrush.fill"]
        where NSImage(systemSymbolName: name, accessibilityDescription: nil) != nil {
            return name
        }
        return "sparkles"
    }()

    var statusIcon: NSImage {
        let config = NSImage.SymbolConfiguration(pointSize: 13, weight: .regular)
            .applying(NSImage.SymbolConfiguration(paletteColors: [Model.nsColor(level: level)]))
        let image = NSImage(systemSymbolName: Model.symbolName, accessibilityDescription: "Mac Cleaner")?
            .withSymbolConfiguration(config) ?? NSImage()
        image.isTemplate = false
        return image
    }

    func refresh() {
        readDisk()
        readHistory()
        launchAtLogin = SMAppService.mainApp.status == .enabled
        weeklyEnabled = WeeklyJob.isInstalled
        fullDiskAccess = DiskAccess.hasFullAccess()
        thermalState = ProcessInfo.processInfo.thermalState
        DispatchQueue.global(qos: .utility).async { [weak self] in
            let pct = Model.readMemFree()
            let s = Sensors.read()
            DispatchQueue.main.async {
                guard let self else { return }
                if let pct { self.memFreePct = pct }
                self.sensors = s
            }
        }
    }

    func panelOpened() {
        refresh()
        refreshEstimates(force: false)
        battery = Battery.read()
        startActivity()
    }

    var panelVisible: Bool { panelWindow?.isVisible == true }

    func setActivityExpanded(_ on: Bool) {
        activityExpanded = on
        UserDefaults.standard.set(on, forKey: "activityExpanded")
        if on { startActivity() } else { stopActivity() }
    }

    func startActivity() {
        guard activityExpanded, activityTimer == nil else { return }
        sampler.reset()
        sampleActivity()
        DispatchQueue.main.asyncAfter(deadline: .now() + 1) { [weak self] in self?.activityTick() }
        let t = Timer(timeInterval: 3, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.activityTick() }
        }
        RunLoop.main.add(t, forMode: .common)
        activityTimer = t
    }

    func stopActivity() {
        activityTimer?.invalidate()
        activityTimer = nil
    }

    private func activityTick() {
        guard activityExpanded, panelVisible else {
            stopActivity()
            return
        }
        sampleActivity()
    }

    private func sampleActivity() {
        let apps = NSWorkspace.shared.runningApplications.filter {
            $0.activationPolicy == .regular && !$0.isTerminated && $0.processIdentifier != getpid()
        }
        let refs = apps.compactMap { a in a.bundleURL.map { AppRef(pid: a.processIdentifier, bundlePath: $0.path) } }
        sampler.sample(refs) { [weak self] result in
            guard let self else { return }
            let usages = apps.compactMap { a -> AppUsage? in
                guard let r = result[a.processIdentifier] else { return nil }
                return AppUsage(pid: a.processIdentifier, name: a.localizedName ?? a.bundleURL?.lastPathComponent ?? "?",
                                icon: a.icon, cpu: r.cpu, memory: r.memory, canQuit: ProcSampler.canQuit(a))
            }
            if usages.contains(where: { $0.cpu != nil }) {
                self.topCPU = Array(usages.sorted { ($0.cpu ?? 0) > ($1.cpu ?? 0) }.prefix(3))
            }
            self.topMemory = Array(usages.sorted { $0.memory > $1.memory }.prefix(3))
            self.battery = Battery.read()
        }
    }

    func quitApp(_ usage: AppUsage) {
        guard usage.canQuit, let app = NSRunningApplication(processIdentifier: usage.pid) else { return }
        app.terminate()
    }

    func setAlerts(_ on: Bool) {
        alertsEnabled = on
        UserDefaults.standard.set(on, forKey: "alertsEnabled")
        if !on { hotStreak = 0 }
        AlertCenter.shared.setUp(enabled: on)
    }

    func setWeekly(_ on: Bool) {
        if on {
            if let cli = cliPath { WeeklyJob.enable(cli: cli, lang: L.fr ? "fr" : "en") }
        } else {
            WeeklyJob.disable()
        }
        weeklyEnabled = WeeklyJob.isInstalled
    }

    func openFullDiskAccess() {
        NSWorkspace.shared.open(DiskAccess.settingsURL)
    }

    func refreshEstimates(force: Bool) {
        guard let cli = cliPath, estimating.isEmpty else { return }
        if !force, let last = lastEstimate, Date().timeIntervalSince(last) < 600 { return }
        lastEstimate = Date()
        estimate(cli: cli, queue: Model.estimated)
    }

    private func estimate(cli: String, queue: [String]) {
        guard let cmd = queue.first else { return }
        estimating.insert(cmd)
        CLIRun.start(cli: cli, args: [cmd, "--dry-run"]) { [weak self] text, status in
            guard let self else { return }
            self.estimating.remove(cmd)
            if status == 0, let kb = Model.parseTotal(text) { self.estimates[cmd] = kb } else { self.estimates[cmd] = nil }
            self.estimate(cli: cli, queue: Array(queue.dropFirst()))
        }
    }

    nonisolated static func parseTotal(_ text: String) -> Double? {
        let pattern = "(?:Total|Taille de la corbeille|Trash size)\\s*:\\s*([0-9]+(?:[.,][0-9]+)?)\\s*(Go|GB|Mo|MB|Ko|KB)"
        guard let re = try? NSRegularExpression(pattern: pattern) else { return nil }
        let ns = text as NSString
        guard let m = re.matches(in: text, range: NSRange(location: 0, length: ns.length)).last else { return nil }
        let n = Double(ns.substring(with: m.range(at: 1)).replacingOccurrences(of: ",", with: ".")) ?? 0
        switch ns.substring(with: m.range(at: 2)) {
        case "Go", "GB": return n * 1_048_576
        case "Mo", "MB": return n * 1024
        default: return n
        }
    }

    private func readDisk() {
        let url = URL(fileURLWithPath: "/")
        let keys: Set<URLResourceKey> = [.volumeTotalCapacityKey, .volumeAvailableCapacityForImportantUsageKey]
        if let v = try? url.resourceValues(forKeys: keys),
           let total = v.volumeTotalCapacity,
           let free = v.volumeAvailableCapacityForImportantUsage {
            diskTotal = Int64(total)
            diskFree = free
            return
        }
        var s = statfs()
        if statfs("/System/Volumes/Data", &s) == 0 {
            diskTotal = Int64(s.f_blocks) * Int64(s.f_bsize)
            diskFree = Int64(s.f_bavail) * Int64(s.f_bsize)
        }
    }

    nonisolated static func readMemFree() -> Int? {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/memory_pressure")
        let pipe = Pipe()
        p.standardOutput = pipe
        p.standardError = FileHandle.nullDevice
        p.standardInput = FileHandle.nullDevice
        guard (try? p.run()) != nil else { return nil }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        p.waitUntilExit()
        let text = String(decoding: data, as: UTF8.self)
        for line in text.split(separator: "\n") where line.contains("free percentage") {
            let digits = line.split(separator: ":").last?.filter { $0.isNumber } ?? ""
            return Int(digits)
        }
        return nil
    }

    nonisolated static var historyPath: String {
        let base = ProcessInfo.processInfo.environment["XDG_STATE_HOME"]
            ?? (NSHomeDirectory() as NSString).appendingPathComponent(".local/state")
        return (base as NSString).appendingPathComponent("mac-cleaner/history.tsv")
    }

    private func readHistory() {
        guard let text = try? String(contentsOfFile: Model.historyPath, encoding: .utf8) else {
            freedMonth = 0
            return
        }
        let fmt = DateFormatter()
        fmt.locale = Locale(identifier: "en_US_POSIX")
        fmt.dateFormat = "yyyy-MM-dd HH:mm"
        let cal = Calendar.current
        let now = Date()
        var sum = 0.0
        for line in text.split(separator: "\n") {
            let cols = line.split(separator: "\t", omittingEmptySubsequences: false).map(String.init)
            guard cols.count >= 3, let date = fmt.date(from: cols[0]) else { continue }
            if cal.isDate(date, equalTo: now, toGranularity: .month) { sum += Double(cols[2]) ?? 0 }
        }
        freedMonth = sum
    }

    static func findCLI() -> String? {
        let fm = FileManager.default
        if let env = ProcessInfo.processInfo.environment["MAC_CLEANER_BIN"], fm.fileExists(atPath: env) {
            return env
        }
        for path in ["/opt/homebrew/bin/mac-cleaner", "/usr/local/bin/mac-cleaner"] where fm.fileExists(atPath: path) {
            return path
        }
        return nil
    }

    func preview(_ command: String) {
        guard !busy else { return }
        phase = .previewing(command)
        run([command, "--dry-run"]) { [weak self] in self?.phase = .previewReady(command) }
    }

    func clean() {
        guard case .previewReady(let command) = phase else { return }
        phase = .cleaning(command)
        run([command, "--yes"]) { [weak self] in
            guard let self else { return }
            self.phase = .cleaned(command)
            self.refresh()
            self.refreshEstimates(force: true)
        }
    }

    func dismiss() {
        guard !busy else { return }
        phase = .idle
        output = ""
    }

    private func run(_ args: [String], completion: @escaping () -> Void) {
        output = ""
        exitStatus = 0
        guard let cli = cliPath else {
            output = L.t("missing") + "\n" + Model.installHint
            exitStatus = 127
            completion()
            return
        }
        current = CLIRun.start(cli: cli, args: args, output: { [weak self] text in
            self?.output = text
        }, completion: { [weak self] text, status in
            guard let self else { return }
            self.output = text
            self.exitStatus = status
            self.current = nil
            completion()
        })
    }

    func freeRAM() {
        guard !busy else { return }
        purging = true
        notice = nil
        Thread.detachNewThread { [weak self] in
            let before = Model.readMemFree()
            var error: NSDictionary?
            let script = NSAppleScript(source: "do shell script \"/usr/sbin/purge\" with administrator privileges")
            script?.executeAndReturnError(&error)
            let after = Model.readMemFree()
            let ok = error == nil
            if ok, let before, let after { Model.appendHistory(action: "m1", kb: 0, note: "\(before)% → \(after)%") }
            DispatchQueue.main.async {
                guard let self else { return }
                self.purging = false
                if ok, let before, let after {
                    self.notice = String(format: L.t("ramDone"), before, after)
                    self.memFreePct = after
                } else if !ok {
                    self.notice = L.t("ramFailed")
                }
                self.refresh()
            }
        }
    }

    nonisolated static func appendHistory(action: String, kb: Int, note: String) {
        let fmt = DateFormatter()
        fmt.locale = Locale(identifier: "en_US_POSIX")
        fmt.dateFormat = "yyyy-MM-dd HH:mm"
        let line = "\(fmt.string(from: Date()))\t\(action)\t\(kb)\t\(note)\n"
        let path = historyPath
        try? FileManager.default.createDirectory(atPath: (path as NSString).deletingLastPathComponent,
                                                 withIntermediateDirectories: true)
        if let h = FileHandle(forWritingAtPath: path) {
            h.seekToEndOfFile()
            h.write(Data(line.utf8))
            try? h.close()
        } else {
            try? line.write(toFile: path, atomically: true, encoding: .utf8)
        }
    }

    nonisolated static func stripANSI(_ s: String) -> String {
        s.replacingOccurrences(of: "\u{1B}\\[[0-9;?]*[A-Za-z]", with: "", options: .regularExpression)
            .replacingOccurrences(of: "\r", with: "\n")
    }

    func setLaunchAtLogin(_ on: Bool) {
        do {
            if on { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
        } catch {}
        launchAtLogin = SMAppService.mainApp.status == .enabled
    }
}
