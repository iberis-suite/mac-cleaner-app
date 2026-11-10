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

@MainActor
final class Model: ObservableObject {
    static let installHint = "brew install chaibialaa/tap/mac-cleaner"

    @Published var diskTotal: Int64 = 0
    @Published var diskFree: Int64 = 0
    @Published var memFreePct: Int = 100
    @Published var history: [HistoryEntry] = []
    @Published var freed30: Double = 0
    @Published var phase: Phase = .idle
    @Published var output = ""
    @Published var exitStatus: Int32 = 0
    @Published var launchAtLogin = false

    let cliPath: String?
    private var timer: Timer?
    private var process: Process?
    private var outputData = Data()

    init() {
        cliPath = Model.findCLI()
        launchAtLogin = SMAppService.mainApp.status == .enabled
        refresh()
        timer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.refresh() }
        }
    }

    var busy: Bool {
        switch phase {
        case .previewing, .cleaning: return true
        default: return false
        }
    }

    var diskUsedPct: Int {
        diskTotal > 0 ? Int((diskTotal - diskFree) * 100 / diskTotal) : 0
    }

    var memUsedPct: Int { max(0, min(100, 100 - memFreePct)) }

    var level: Int {
        let p = max(diskUsedPct, memUsedPct)
        return p >= 85 ? 2 : (p >= 60 ? 1 : 0)
    }

    static func color(for pct: Int) -> NSColor {
        pct >= 85 ? .systemRed : (pct >= 60 ? .systemOrange : .systemGreen)
    }

    var freeLabel: String {
        let gb = Double(diskFree) / 1_000_000_000
        return String(format: "%.0f %@", gb, L.gb)
    }

    var statusIcon: NSImage {
        let color: NSColor = [.systemGreen, .systemOrange, .systemRed][level]
        let config = NSImage.SymbolConfiguration(pointSize: 13, weight: .regular)
            .applying(NSImage.SymbolConfiguration(paletteColors: [color]))
        let image = NSImage(systemSymbolName: "sparkles", accessibilityDescription: "Mac Cleaner")?
            .withSymbolConfiguration(config) ?? NSImage()
        image.isTemplate = false
        return image
    }

    func refresh() {
        readDisk()
        readHistory()
        launchAtLogin = SMAppService.mainApp.status == .enabled
        DispatchQueue.global(qos: .utility).async { [weak self] in
            let pct = Model.readMemFree()
            DispatchQueue.main.async {
                if let pct { self?.memFreePct = pct }
            }
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

    nonisolated private static func readMemFree() -> Int? {
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

    private func readHistory() {
        let base = ProcessInfo.processInfo.environment["XDG_STATE_HOME"]
            ?? (NSHomeDirectory() as NSString).appendingPathComponent(".local/state")
        let path = (base as NSString).appendingPathComponent("mac-cleaner/history.tsv")
        guard let text = try? String(contentsOfFile: path, encoding: .utf8) else {
            history = []
            freed30 = 0
            return
        }
        let fmt = DateFormatter()
        fmt.locale = Locale(identifier: "en_US_POSIX")
        fmt.dateFormat = "yyyy-MM-dd HH:mm"
        var all: [HistoryEntry] = []
        for line in text.split(separator: "\n") {
            let cols = line.split(separator: "\t", omittingEmptySubsequences: false).map(String.init)
            guard cols.count >= 3, let date = fmt.date(from: cols[0]) else { continue }
            all.append(HistoryEntry(date: date, label: cols[0], kb: Double(cols[2]) ?? 0, action: cols[1]))
        }
        let cutoff = Date().addingTimeInterval(-30 * 86400)
        freed30 = all.filter { $0.date >= cutoff }.reduce(0) { $0 + $1.kb }
        history = Array(all.suffix(3).reversed())
    }

    static func findCLI() -> String? {
        let fm = FileManager.default
        for path in ["/opt/homebrew/bin/mac-cleaner", "/usr/local/bin/mac-cleaner"] where fm.fileExists(atPath: path) {
            return path
        }
        if let env = ProcessInfo.processInfo.environment["MAC_CLEANER_BIN"], fm.fileExists(atPath: env) {
            return env
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
            self?.phase = .cleaned(command)
            self?.refresh()
        }
    }

    func dismiss() {
        guard !busy else { return }
        phase = .idle
        output = ""
    }

    private func append(_ data: Data) {
        outputData.append(data)
        output = Model.stripANSI(String(decoding: outputData, as: UTF8.self))
    }

    private func run(_ args: [String], completion: @escaping () -> Void) {
        output = ""
        outputData = Data()
        exitStatus = 0
        guard let cli = cliPath else {
            output = L.t("missing") + "\n" + Model.installHint
            exitStatus = 127
            completion()
            return
        }
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/bin/zsh")
        p.arguments = [cli] + args
        var env = ProcessInfo.processInfo.environment
        env["NO_COLOR"] = "1"
        env["TERM"] = "dumb"
        if env["LANG"] == nil && env["LC_ALL"] == nil && env["LC_CTYPE"] == nil {
            env["LC_CTYPE"] = "en_US.UTF-8"
        }
        p.environment = env
        p.standardInput = FileHandle.nullDevice
        let pipe = Pipe()
        p.standardOutput = pipe
        p.standardError = pipe
        pipe.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            guard !data.isEmpty else { return }
            DispatchQueue.main.async { self?.append(data) }
        }
        p.terminationHandler = { [weak self] proc in
            let rest = pipe.fileHandleForReading.readDataToEndOfFile()
            pipe.fileHandleForReading.readabilityHandler = nil
            let status = proc.terminationStatus
            DispatchQueue.main.async {
                guard let self else { return }
                if !rest.isEmpty { self.append(rest) }
                self.exitStatus = status
                self.process = nil
                completion()
            }
        }
        do {
            try p.run()
            process = p
        } catch {
            output = error.localizedDescription
            exitStatus = 1
            completion()
        }
    }

    nonisolated static func stripANSI(_ s: String) -> String {
        s.replacingOccurrences(of: "\u{1B}\\[[0-9;?]*[A-Za-z]", with: "", options: .regularExpression)
            .replacingOccurrences(of: "\r", with: "\n")
    }

    func openInTerminal(_ command: String?) {
        guard let cli = cliPath else {
            phase = .cleaned("")
            output = L.t("missing") + "\n" + Model.installHint
            return
        }
        let quoted = "'" + cli.replacingOccurrences(of: "'", with: "'\\''") + "'"
        let line = "exec /bin/zsh \(quoted)" + (command.map { " \($0)" } ?? "")
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("mac-cleaner-\(UUID().uuidString.prefix(8)).command")
        let script = "#!/bin/zsh\nrm -f \"$0\"\n\(line)\n"
        do {
            try script.write(to: url, atomically: true, encoding: .utf8)
            try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: url.path)
        } catch { return }
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/open")
        p.arguments = ["-a", "Terminal", url.path]
        try? p.run()
    }

    func setLaunchAtLogin(_ on: Bool) {
        do {
            if on { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
        } catch {}
        launchAtLogin = SMAppService.mainApp.status == .enabled
    }
}
