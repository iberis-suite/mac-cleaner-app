import AppKit
import Foundation
import ServiceManagement

struct HistoryEntry: Identifiable, Equatable {
    let id = UUID()
    let date: Date
    let action: String
    let kb: Double
    let note: String

    static let tools: [String: String] = [
        "m1": "ram", "m2": "trash", "m3": "uninstall", "m4": "large", "m5": "caches", "m6": "downloads",
        "m7": "startup", "m8": "duplicates", "m9": "auto", "mt": "temp", "md": "dev", "ms": "system",
        "m14": "maintenance", "m15": "privacy",
    ]

    var title: String { HistoryEntry.tools[action].map { L.t($0) } ?? action }

    var symbol: String {
        guard let t = HistoryEntry.tools[action] else { return "sparkles" }
        if t == "ram" { return "memorychip" }
        return ["caches", "temp", "trash", "auto"].contains(t) ? ItemStyle.command(t) : Catalog.icon(t)
    }
}

struct CleanResult: Equatable {
    let ok: Bool
    let freedKB: Double
    let sections: [String]
    let message: String
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
    private var pending = Data()
    private var demoFinish: ((String, Int32) -> Void)?

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
        env["MAC_CLEANER_MACHINE"] = "1"
        env["MAC_CLEANER_LANG"] = L.fr ? "fr" : "en"
        if env["LANG"] == nil && env["LC_ALL"] == nil && env["LC_CTYPE"] == nil {
            env["LC_CTYPE"] = "en_US.UTF-8"
        }
        return env
    }

    @discardableResult
    static func start(cli: String, args: [String], askpass: Bool = false, output: ((String) -> Void)? = nil,
                      line: ((String) -> Void)? = nil, completion: @escaping (String, Int32) -> Void) -> CLIRun {
        let run = CLIRun()
        if Demo.enabled {
            run.demoFinish = completion
            let (text, status) = Demo.respond(args)
            let lines = text.components(separatedBy: "\n")
            let step = args.contains("--yes") ? 0.5 : 0.18
            for (i, l) in lines.enumerated() {
                DispatchQueue.main.asyncAfter(deadline: .now() + step * Double(i + 1)) {
                    guard run.demoFinish != nil else { return }
                    line?(l)
                    output?(lines.prefix(i + 1).joined(separator: "\n"))
                }
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + step * Double(lines.count + 1)) {
                guard let finish = run.demoFinish else { return }
                run.demoFinish = nil
                finish(text, status)
            }
            return run
        }
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
                run.feed(chunk, line: line)
                output?(Model.stripANSI(String(decoding: run.data, as: UTF8.self)))
            }
        }
        p.terminationHandler = { proc in
            let rest = pipe.fileHandleForReading.readDataToEndOfFile()
            pipe.fileHandleForReading.readabilityHandler = nil
            let status = proc.terminationStatus
            DispatchQueue.main.async {
                if !rest.isEmpty {
                    run.data.append(rest)
                    run.feed(rest, line: line)
                }
                run.flush(line: line)
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

    private func feed(_ chunk: Data, line: ((String) -> Void)?) {
        guard let line else { return }
        pending.append(chunk)
        while let nl = pending.firstIndex(of: 0x0A) {
            let bytes = pending[pending.startIndex..<nl]
            pending.removeSubrange(pending.startIndex...nl)
            line(Model.stripANSI(String(decoding: bytes, as: UTF8.self)))
        }
    }

    private func flush(line: ((String) -> Void)?) {
        guard let line, !pending.isEmpty else { return }
        line(Model.stripANSI(String(decoding: pending, as: UTF8.self)))
        pending.removeAll()
    }

    func cancel() {
        if let finish = demoFinish {
            demoFinish = nil
            DispatchQueue.main.async { finish("", 15) }
            return
        }
        if process.isRunning { process.terminate() }
    }
}

@MainActor
final class Model: ObservableObject {
    static let installHint = "brew install iberis-suite/tap/mac-cleaner"
    static let estimated = ["temp", "caches"]

    @Published var diskTotal: Int64 = 0
    @Published var diskFree: Int64 = 0
    @Published var memFreePct: Int = 100
    @Published var sensors = SensorReading()
    @Published var freedMonth: Double = 0
    @Published var phase: Phase = .idle
    @Published var output = ""
    @Published var exitStatus: Int32 = 0
    @Published var sheetItems: [ToolItem] = []
    @Published var sheetSelected: Set<Int> = []
    @Published var sheetError: String?
    @Published var result: CleanResult?
    @Published var launchAtLogin = false
    @Published var estimates: [String: Double] = [:]
    @Published var estimating: Set<String> = []
    @Published var trashUnreadable = false
    private(set) var estimatedAt: [String: Date] = [:]
    @Published var purging = false
    @Published var notice: String?
    @Published var alertsEnabled: Bool
    @Published var weeklyEnabled = false
    @Published var fullDiskAccess = true
    @Published var accessRequested = UserDefaults.standard.bool(forKey: "fdaRequested")
    @Published var history: [HistoryEntry] = []
    @Published var freedTotal: Double = 0
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
    private var runToken = 0
    private var previewGeneration = 0
    private var panelObserver: NSObjectProtocol?
    private var lastEstimate: Date?
    private var trashWatch: DispatchSourceFileSystemObject?
    private var trashDebounce: DispatchWorkItem?
    private var trashPending = false
    private var thermalObserver: NSObjectProtocol?
    private var activeObserver: NSObjectProtocol?

    init() {
        let d = UserDefaults.standard
        d.register(defaults: ["alertsEnabled": true, "activityExpanded": false])
        alertsEnabled = d.bool(forKey: "alertsEnabled")
        activityExpanded = d.bool(forKey: "activityExpanded")
        cliPath = Model.findCLI()
        launchAtLogin = SMAppService.mainApp.status == .enabled
        weeklyEnabled = WeeklyJob.isInstalled
        battery = Demo.enabled ? nil : Battery.read()
        AlertCenter.shared.onOpen = { [weak self] in
            Task { @MainActor in StatusItemOpener.open(panel: self?.panelWindow) }
        }
        AlertCenter.shared.onOpenTool = { [weak self] tool in
            Task { @MainActor in if let self { Windows.open(tool, model: self) } }
        }
        AlertCenter.shared.setUp(enabled: alertsEnabled)
        thermalObserver = NotificationCenter.default.addObserver(
            forName: ProcessInfo.thermalStateDidChangeNotification, object: nil, queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.thermalState = ProcessInfo.processInfo.thermalState }
        }
        activeObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didBecomeActiveNotification, object: nil, queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.checkAccess() }
        }
        refresh()
        measureTrash()
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
        Theme.levelNS[max(0, min(2, level))]
    }

    var freeLabel: String {
        let gb = Double(diskFree) / 1_000_000_000
        return "\(L.num(gb, 0)) \(L.gb)"
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
        if Demo.enabled {
            Demo.fill(self)
            return
        }
        readDisk()
        readHistory()
        launchAtLogin = SMAppService.mainApp.status == .enabled
        weeklyEnabled = WeeklyJob.isInstalled
        checkAccess()
        watchTrash()
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
        measureTrash()
        if !Demo.enabled { battery = Battery.read() }
        startActivity()
        NetworkMonitor.shared.retain("panel")
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
        if Demo.enabled {
            topCPU = Demo.usages(byCPU: true)
            topMemory = Demo.usages(byCPU: false)
            return
        }
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
        guard !Demo.enabled, usage.canQuit, let app = NSRunningApplication(processIdentifier: usage.pid) else { return }
        app.terminate()
    }

    func setAlerts(_ on: Bool) {
        alertsEnabled = on
        UserDefaults.standard.set(on, forKey: "alertsEnabled")
        if !on { hotStreak = 0 }
        AlertCenter.shared.setUp(enabled: on)
    }

    func setWeekly(_ on: Bool) {
        if Demo.enabled {
            weeklyEnabled = on
            return
        }
        if on {
            if let cli = cliPath { WeeklyJob.enable(cli: cli, lang: L.fr ? "fr" : "en") }
        } else {
            WeeklyJob.disable()
        }
        weeklyEnabled = WeeklyJob.isInstalled
    }

    func openFullDiskAccess() {
        accessRequested = true
        UserDefaults.standard.set(true, forKey: "fdaRequested")
        NSWorkspace.shared.open(DiskAccess.settingsURL)
    }

    func checkAccess() {
        guard !Demo.enabled else { return }
        fullDiskAccess = DiskAccess.hasFullAccess()
        if fullDiskAccess && accessRequested {
            accessRequested = false
            UserDefaults.standard.set(false, forKey: "fdaRequested")
        }
    }

    func relaunch() {
        guard !Demo.enabled else { return }
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/open")
        p.arguments = ["-n", Bundle.main.bundlePath]
        guard (try? p.run()) != nil else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { NSApp.terminate(nil) }
    }

    var weeklyNext: Date? {
        guard weeklyEnabled else { return nil }
        var c = DateComponents()
        c.weekday = 2
        c.hour = 10
        c.minute = 0
        return Calendar.current.nextDate(after: Date(), matching: c, matchingPolicy: .nextTime)
    }

    var weeklyLast: Date? {
        guard !Demo.enabled else { return weeklyEnabled ? Calendar.current.date(byAdding: .day, value: -3, to: Date()) : nil }
        return (try? FileManager.default.attributesOfItem(atPath: WeeklyJob.logPath))?[.modificationDate] as? Date
    }

    func openPanelPreview(_ command: String) {
        preview(command)
        StatusItemOpener.open(panel: panelWindow)
    }

    func refreshEstimates(force: Bool) {
        guard !Snapshots.active else { return }
        if force { measureTrash() }
        guard let cli = cliPath, estimating.isDisjoint(with: Model.estimated) else { return }
        if !force, let last = lastEstimate, Date().timeIntervalSince(last) < 600 { return }
        lastEstimate = Date()
        estimate(cli: cli, queue: Model.estimated)
    }

    private func estimate(cli: String, queue: [String]) {
        guard let cmd = queue.first else { return }
        estimating.insert(cmd)
        CLIRun.start(cli: cli, args: [cmd, "--list"]) { [weak self] text, status in
            guard let self else { return }
            self.estimating.remove(cmd)
            if status == 0 {
                let items = ToolItem.parseList(text)
                self.estimates[cmd] = Model.defaultSelection(items).reduce(0) { $0 + $1.kb }
            } else {
                self.estimates[cmd] = nil
            }
            self.estimatedAt[cmd] = Date()
            self.estimate(cli: cli, queue: Array(queue.dropFirst()))
        }
    }

    nonisolated static let trashURL: URL = {
        if let dir = ProcessInfo.processInfo.environment["MAC_CLEANER_TRASH_DIR"], !dir.isEmpty {
            return URL(fileURLWithPath: dir)
        }
        return URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent(".Trash")
    }()

    func measureTrash() {
        guard !Demo.enabled else { return }
        if trashMeasuring {
            trashPending = true
            return
        }
        trashMeasuring = true
        estimating.insert("trash")
        let url = Model.trashURL
        let cli = cliPath
        DispatchQueue.global(qos: .utility).async { [weak self] in
            let readable = (try? FileManager.default.contentsOfDirectory(atPath: url.path)) != nil
            let local = readable && cli == nil ? DiskAccess.trashSize(at: url) : nil
            DispatchQueue.main.async {
                guard let self else { return }
                guard readable else { return self.finishTrash(kb: nil, unreadable: true) }
                guard let cli else { return self.finishTrash(kb: local.map { Double($0) / 1024 }, unreadable: false) }
                CLIRun.start(cli: cli, args: ["trash", "--list"]) { [weak self] text, status in
                    guard let self else { return }
                    let kb = status == 0 ? Model.defaultSelection(ToolItem.parseList(text)).reduce(0) { $0 + $1.kb } : nil
                    self.finishTrash(kb: kb, unreadable: false)
                }
            }
        }
    }

    private func finishTrash(kb: Double?, unreadable: Bool) {
        trashMeasuring = false
        estimating.remove("trash")
        trashUnreadable = unreadable
        estimates["trash"] = kb
        estimatedAt["trash"] = Date()
        trashCheckedAt = Date()
        trashBytes = kb.map { Int64($0 * 1024) }
        alertTrash(trashBytes)
        if trashPending {
            trashPending = false
            measureTrash()
        }
    }

    private func watchTrash() {
        guard trashWatch == nil, !Demo.enabled else { return }
        let fd = open(Model.trashURL.path, O_EVTONLY)
        guard fd >= 0 else { return }
        let source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: fd, eventMask: [.write, .delete, .rename, .link], queue: .main)
        source.setEventHandler { [weak self, weak source] in
            let gone = source.map { !$0.data.isDisjoint(with: [.delete, .rename]) } ?? false
            Task { @MainActor in self?.trashChanged(gone: gone) }
        }
        source.setCancelHandler { close(fd) }
        trashWatch = source
        source.resume()
    }

    private func trashChanged(gone: Bool) {
        if gone {
            trashWatch?.cancel()
            trashWatch = nil
            watchTrash()
        }
        trashDebounce?.cancel()
        let work = DispatchWorkItem { [weak self] in
            Task { @MainActor in self?.measureTrash() }
        }
        trashDebounce = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 2, execute: work)
    }

    nonisolated static let selectable: Set<String> = ["caches", "temp"]

    nonisolated static let historyAction: [String: String] = ["caches": "m5", "temp": "mt", "trash": "m2", "auto": "m9"]

    nonisolated static func defaultSelection(_ items: [ToolItem]) -> [ToolItem] {
        items.filter { $0.index > 0 && $0.state != "excluded" }
    }

    var sheetSelectedKB: Double {
        let c: String
        switch phase {
        case .previewReady(let x), .previewing(let x): c = x
        default: return 0
        }
        if !Model.selectable.contains(c) { return sheetItems.filter { $0.index > 0 }.reduce(0) { $0 + $1.kb } }
        return sheetItems.filter { $0.index > 0 && sheetSelected.contains($0.index) }.reduce(0) { $0 + $1.kb }
    }

    var canClean: Bool {
        guard case .previewReady(let c) = phase, sheetError == nil else { return false }
        if Model.selectable.contains(c) { return !sheetSelected.isEmpty }
        return sheetItems.contains { $0.index > 0 }
    }

    var sheetEditable: Bool {
        switch phase {
        case .previewing, .previewReady: return true
        default: return false
        }
    }

    func toggleSheet(_ index: Int) {
        guard sheetEditable, index > 0 else { return }
        if sheetSelected.contains(index) { sheetSelected.remove(index) } else { sheetSelected.insert(index) }
    }

    func setSheet(_ indexes: [Int], on: Bool) {
        guard sheetEditable else { return }
        if on { sheetSelected.formUnion(indexes) } else { sheetSelected.subtract(indexes) }
    }

    private func selectArgs(_ command: String) -> [String] {
        guard Model.selectable.contains(command) else { return [] }
        return ["--select", sheetSelected.sorted().map(String.init).joined(separator: " ")]
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
        let entries = Model.historyEntries()
        let now = Date()
        freedMonth = entries.filter { Calendar.current.isDate($0.date, equalTo: now, toGranularity: .month) }.reduce(0) { $0 + $1.kb }
        freedTotal = entries.reduce(0) { $0 + $1.kb }
        history = Array(entries.suffix(8).reversed())
    }

    nonisolated static func historyEntries() -> [HistoryEntry] {
        guard let text = try? String(contentsOfFile: historyPath, encoding: .utf8) else { return [] }
        let fmt = DateFormatter()
        fmt.locale = Locale(identifier: "en_US_POSIX")
        fmt.dateFormat = "yyyy-MM-dd HH:mm"
        return text.split(separator: "\n").compactMap { line in
            let cols = line.split(separator: "\t", omittingEmptySubsequences: false).map(String.init)
            guard cols.count >= 3, let date = fmt.date(from: cols[0]) else { return nil }
            return HistoryEntry(date: date, action: cols[1], kb: Double(cols[2]) ?? 0, note: cols.count > 3 ? cols[3] : "")
        }
    }

    static func findCLI() -> String? {
        let fm = FileManager.default
        if Demo.enabled { return "demo" }
        if let env = ProcessInfo.processInfo.environment["MAC_CLEANER_BIN"], fm.fileExists(atPath: env) {
            return env
        }
        if let embedded = Bundle.main.path(forResource: "mac-cleaner", ofType: nil), fm.fileExists(atPath: embedded) {
            return embedded
        }
        for path in ["/opt/homebrew/bin/mac-cleaner", "/usr/local/bin/mac-cleaner"] where fm.fileExists(atPath: path) {
            return path
        }
        return nil
    }

    func preview(_ command: String) {
        guard !busy else { return }
        sheetItems = []
        sheetSelected = []
        sheetError = nil
        result = nil
        previewGeneration += 1
        let gen = previewGeneration
        phase = .previewing(command)
        run([command, "--list"], live: false, line: { [weak self] l in
            guard let self, self.previewGeneration == gen, let item = ToolItem.parse(l) else { return }
            self.sheetItems.append(item)
            if item.index > 0 && item.state != "excluded" && item.kb > 0 { self.sheetSelected.insert(item.index) }
        }) { [weak self] in
            guard let self, self.previewGeneration == gen else { return }
            self.finishPreview(command, failed: self.exitStatus != 0)
        }
    }

    private func finishPreview(_ command: String, failed: Bool) {
        if failed {
            sheetError = UninstallModel.lastMeaningfulLine(ToolItem.humanLines(output))
        } else {
            estimates[command] = Model.defaultSelection(sheetItems).reduce(0) { $0 + $1.kb }
            estimatedAt[command] = Date()
        }
        phase = .previewReady(command)
    }

    func stopPreview() {
        guard case .previewing(let command) = phase else { return }
        previewGeneration += 1
        runToken += 1
        let run = current
        current = nil
        run?.cancel()
        exitStatus = 0
        phase = .previewReady(command)
    }

    func clean() {
        guard case .previewReady(let command) = phase, canClean else { return }
        let args = [command, "--yes"] + selectArgs(command)
        let chosen = Model.selectable.contains(command)
            ? sheetItems.filter { $0.index > 0 && sheetSelected.contains($0.index) }
            : sheetItems.filter { $0.index > 0 }
        let estimate = chosen.reduce(0) { $0 + $1.kb }
        let sections: [String]
        switch command {
        case "auto": sections = chosen.filter { $0.kb > 0 }.map(\.label)
        case "trash": sections = [String(format: L.t("trashItems"), chosen.count)]
        case "temp":
            sections = [("tmp", "tempFiles"), ("clone", "appCopies")].compactMap { t, key in
                let n = chosen.filter { $0.type == t }.count
                return n > 0 ? "\(L.t(key)) · \(n)" : nil
            }
        default: sections = chosen.map(\.label)
        }
        let before = Model.historyLines().count
        phase = .cleaning(command)
        run(args, live: true) { [weak self] in
            guard let self else { return }
            let ok = self.exitStatus == 0
            let logged = Model.historyLines().dropFirst(before).filter { $0.action == Model.historyAction[command] }
            let freed = logged.isEmpty ? (ok ? estimate : 0) : logged.reduce(0) { $0 + $1.kb }
            self.result = CleanResult(ok: ok, freedKB: freed, sections: sections,
                                      message: ok ? "" : UninstallModel.lastMeaningfulLine(ToolItem.humanLines(self.output)))
            self.phase = .cleaned(command)
            self.refresh()
            self.refreshEstimates(force: true)
            if !self.panelVisible {
                AlertCenter.shared.notify(
                    title: String(format: L.t(ok ? "notifyDone" : "notifyFailed"), L.t(command)),
                    body: ok ? String(format: L.t("freedAmount"), L.human(kb: freed)) : L.t("notifyOpen"))
            }
        }
    }

    func back() {
        switch phase {
        case .previewing:
            previewGeneration += 1
            runToken += 1
            let run = current
            current = nil
            run?.cancel()
            phase = .idle
            dismiss()
        case .previewReady, .cleaned:
            dismiss()
        case .cleaning, .idle:
            break
        }
    }

    func attachPanel(_ window: NSWindow?) {
        guard let window, window !== panelWindow else { return }
        panelWindow = window
        if let panelObserver { NotificationCenter.default.removeObserver(panelObserver) }
        panelObserver = NotificationCenter.default.addObserver(
            forName: NSWindow.didResignKeyNotification, object: window, queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.panelClosed() }
        }
    }

    var panelMaxHeight: CGFloat {
        guard let screen = panelWindow?.screen ?? NSScreen.main else { return 900 }
        return max(300, screen.visibleFrame.height - 12)
    }

    func fitPanel(_ height: CGFloat) {
        guard let window = panelWindow else { return }
        let apply = {
            let frame = window.frame
            guard abs(frame.height - height) > 0.5 else { return }
            window.setFrame(NSRect(x: frame.minX, y: frame.maxY - height, width: frame.width, height: height), display: true)
        }
        apply()
        DispatchQueue.main.async(execute: apply)
    }

    func panelClosed() {
        if case .previewing = phase { back() }
        NetworkMonitor.shared.release("panel")
    }

    func dismiss() {
        guard !busy else { return }
        phase = .idle
        output = ""
        sheetItems = []
        sheetSelected = []
        sheetError = nil
        result = nil
    }

    private func run(_ args: [String], live: Bool, line: ((String) -> Void)? = nil, completion: @escaping () -> Void) {
        output = ""
        exitStatus = 0
        guard let cli = cliPath else {
            output = L.t("missing") + "\n" + Model.installHint
            exitStatus = 127
            completion()
            return
        }
        runToken += 1
        let token = runToken
        current = CLIRun.start(cli: cli, args: args, output: live ? { [weak self] text in
            guard let self, self.runToken == token else { return }
            self.output = text
        } : nil, line: line, completion: { [weak self] text, status in
            guard let self, self.runToken == token else { return }
            self.output = text
            self.exitStatus = status
            self.current = nil
            completion()
        })
    }

    nonisolated static func historyLines() -> [(action: String, kb: Double)] {
        guard let text = try? String(contentsOfFile: historyPath, encoding: .utf8) else { return [] }
        return text.split(separator: "\n").map { line in
            let cols = line.split(separator: "\t", omittingEmptySubsequences: false).map(String.init)
            return (cols.count > 1 ? cols[1] : "", cols.count > 2 ? Double(cols[2]) ?? 0 : 0)
        }
    }

    func freeRAM() {
        guard !busy else { return }
        purging = true
        notice = nil
        if Demo.enabled {
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) { [weak self] in
                guard let self else { return }
                self.purging = false
                self.notice = String(format: L.t("ramDone"), 18, 41)
            }
            return
        }
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
        if Demo.enabled {
            launchAtLogin = on
            return
        }
        do {
            if on { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
        } catch {}
        launchAtLogin = SMAppService.mainApp.status == .enabled
    }
}
