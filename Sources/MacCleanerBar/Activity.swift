import AppKit
import Darwin
import IOKit

struct AppUsage: Identifiable, Equatable {
    let pid: pid_t
    let name: String
    let icon: NSImage?
    let cpu: Double?
    let memory: Int64
    let canQuit: Bool
    var id: pid_t { pid }
}

struct AppRef {
    let pid: pid_t
    let bundlePath: String
}

struct AppSample {
    let cpu: Double?
    let memory: Int64
}

final class ProcSampler: @unchecked Sendable {
    private let queue = DispatchQueue(label: "mac-cleaner.sampler", qos: .utility)
    private var previous: [pid_t: Double] = [:]
    private var previousAt: UInt64 = 0
    private let ticksToNs: Double

    init() {
        var tb = mach_timebase_info_data_t()
        mach_timebase_info(&tb)
        ticksToNs = tb.denom > 0 ? Double(tb.numer) / Double(tb.denom) : 1
    }

    func reset() {
        queue.async {
            self.previous = [:]
            self.previousAt = 0
        }
    }

    func sample(_ apps: [AppRef], completion: @escaping @MainActor ([pid_t: AppSample]) -> Void) {
        queue.async {
            let result = self.measure(apps)
            DispatchQueue.main.async { completion(result) }
        }
    }

    private func measure(_ apps: [AppRef]) -> [pid_t: AppSample] {
        let roots = apps.map { ($0.pid, $0.bundlePath.hasSuffix("/") ? $0.bundlePath : $0.bundlePath + "/") }
        var owner: [pid_t: pid_t] = [:]
        for a in apps { owner[a.pid] = a.pid }
        for pid in ProcSampler.allPIDs() where owner[pid] == nil {
            guard let path = ProcSampler.path(pid) else { continue }
            if let root = roots.first(where: { path.hasPrefix($0.1) }) { owner[pid] = root.0 }
        }
        let now = DispatchTime.now().uptimeNanoseconds
        let wall = previousAt > 0 && now > previousAt ? Double(now - previousAt) : 0
        var cpu: [pid_t: Double] = [:]
        var mem: [pid_t: Int64] = [:]
        var current: [pid_t: Double] = [:]
        for (pid, app) in owner {
            guard let (ticks, footprint) = ProcSampler.usage(pid) else { continue }
            let ns = Double(ticks) * ticksToNs
            current[pid] = ns
            mem[app, default: 0] += Int64(clamping: footprint)
            if let prev = previous[pid], ns >= prev { cpu[app, default: 0] += ns - prev }
        }
        previous = current
        previousAt = now
        var out: [pid_t: AppSample] = [:]
        for a in apps where mem[a.pid] != nil {
            out[a.pid] = AppSample(cpu: wall > 0 ? (cpu[a.pid] ?? 0) / wall * 100 : nil, memory: mem[a.pid] ?? 0)
        }
        return out
    }

    static func allPIDs() -> [pid_t] {
        let n = proc_listallpids(nil, 0)
        guard n > 0 else { return [] }
        var buf = [pid_t](repeating: 0, count: Int(n) + 64)
        let count = buf.withUnsafeMutableBytes { proc_listallpids($0.baseAddress, Int32($0.count)) }
        return Array(buf.prefix(Int(max(0, count)))).filter { $0 > 0 }
    }

    static func path(_ pid: pid_t) -> String? {
        var buf = [UInt8](repeating: 0, count: 4 * Int(MAXPATHLEN))
        let n = buf.withUnsafeMutableBytes { proc_pidpath(pid, $0.baseAddress, UInt32($0.count)) }
        guard n > 0 else { return nil }
        return String(decoding: buf.prefix(Int(n)), as: UTF8.self)
    }

    static func usage(_ pid: pid_t) -> (UInt64, UInt64)? {
        var info = rusage_info_v2()
        let r = withUnsafeMutablePointer(to: &info) { p in
            p.withMemoryRebound(to: rusage_info_t?.self, capacity: 1) { proc_pid_rusage(pid, RUSAGE_INFO_V2, $0) }
        }
        guard r == 0 else { return nil }
        return (info.ri_user_time &+ info.ri_system_time, info.ri_phys_footprint)
    }

    static let systemBundles: Set<String> = [
        "com.apple.finder", "com.apple.dock", "com.apple.systemuiserver", "com.apple.loginwindow",
        "com.apple.controlcenter", "com.apple.notificationcenterui", "com.apple.WindowManager",
    ]

    static func canQuit(_ app: NSRunningApplication) -> Bool {
        if let id = app.bundleIdentifier, systemBundles.contains(id) || id == Bundle.main.bundleIdentifier { return false }
        if let path = app.bundleURL?.path, path.hasPrefix("/System/Library/") || path.hasPrefix("/Library/Apple/") { return false }
        return true
    }
}

struct BatteryInfo: Equatable {
    let cycles: Int
    let health: Int
    let charge: Int
    let onAC: Bool
    let charging: Bool

    var needsService: Bool { health < 80 }
}

enum Battery {
    static func read() -> BatteryInfo? {
        let service = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("AppleSmartBattery"))
        guard service != 0 else { return nil }
        defer { IOObjectRelease(service) }
        var props: Unmanaged<CFMutableDictionary>?
        guard IORegistryEntryCreateCFProperties(service, &props, kCFAllocatorDefault, 0) == KERN_SUCCESS,
              let d = props?.takeRetainedValue() as? [String: Any] else { return nil }
        if let installed = d["BatteryInstalled"] as? Bool, !installed { return nil }
        let data = d["BatteryData"] as? [String: Any] ?? [:]
        func int(_ k: String) -> Int? { (d[k] as? Int) ?? (data[k] as? Int) }
        guard let design = int("DesignCapacity"), design > 0 else { return nil }
        let maxCap = int("MaxCapacity") ?? 100
        let full = int("NominalChargeCapacity") ?? int("AppleRawMaxCapacity") ?? (maxCap > 100 ? maxCap : nil)
        guard let full, full > 0 else { return nil }
        let current = int("CurrentCapacity") ?? 0
        let charge = maxCap > 100 ? current * 100 / maxCap : current
        return BatteryInfo(
            cycles: int("CycleCount") ?? 0,
            health: min(100, Int((Double(full) * 100 / Double(design)).rounded())),
            charge: max(0, min(100, charge)),
            onAC: d["ExternalConnected"] as? Bool ?? false,
            charging: d["IsCharging"] as? Bool ?? false
        )
    }
}
