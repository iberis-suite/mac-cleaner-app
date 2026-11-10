import Foundation
import IOKit

struct SensorReading: Equatable {
    var temperature: Double?
    var fanCount: Int?
    var fanRPM: Double?
}

private struct SMCVers {
    var major: UInt8 = 0
    var minor: UInt8 = 0
    var build: UInt8 = 0
    var reserved: UInt8 = 0
    var release: UInt16 = 0
}

private struct SMCPLimit {
    var version: UInt16 = 0
    var length: UInt16 = 0
    var cpuPLimit: UInt32 = 0
    var gpuPLimit: UInt32 = 0
    var memPLimit: UInt32 = 0
}

private struct SMCKeyInfo {
    var dataSize: UInt32 = 0
    var dataType: UInt32 = 0
    var dataAttributes: UInt8 = 0
}

private typealias SMCBytes = (
    UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8,
    UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8,
    UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8,
    UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8
)

private struct SMCKeyData {
    var key: UInt32 = 0
    var vers = SMCVers()
    var pLimitData = SMCPLimit()
    var keyInfo = SMCKeyInfo()
    var padding: UInt16 = 0
    var result: UInt8 = 0
    var status: UInt8 = 0
    var data8: UInt8 = 0
    var data32: UInt32 = 0
    var bytes: SMCBytes = (0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
                           0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0)
}

private func fourCC(_ s: String) -> UInt32 {
    s.utf8.prefix(4).reduce(0) { ($0 << 8) | UInt32($1) }
}

private func fourCCString(_ v: UInt32) -> String {
    String(bytes: [24, 16, 8, 0].map { UInt8((v >> $0) & 0xff) }, encoding: .ascii) ?? ""
}

final class SMC {
    private var conn: io_connect_t = 0

    init?() {
        let service = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("AppleSMC"))
        guard service != 0 else { return nil }
        defer { IOObjectRelease(service) }
        guard IOServiceOpen(service, mach_task_self_, 0, &conn) == kIOReturnSuccess else { return nil }
    }

    deinit {
        if conn != 0 { IOServiceClose(conn) }
    }

    private func call(_ input: inout SMCKeyData) -> SMCKeyData? {
        var output = SMCKeyData()
        var size = MemoryLayout<SMCKeyData>.stride
        let r = IOConnectCallStructMethod(conn, 2, &input, MemoryLayout<SMCKeyData>.stride, &output, &size)
        guard r == kIOReturnSuccess, output.result == 0 else { return nil }
        return output
    }

    func read(_ key: String) -> (type: String, bytes: [UInt8])? {
        var input = SMCKeyData()
        input.key = fourCC(key)
        input.data8 = 9
        guard let info = call(&input) else { return nil }
        let size = Int(info.keyInfo.dataSize)
        guard size > 0, size <= 32 else { return nil }
        input.keyInfo.dataSize = info.keyInfo.dataSize
        input.data8 = 5
        guard let out = call(&input) else { return nil }
        let all = withUnsafeBytes(of: out.bytes) { Array($0) }
        return (fourCCString(info.keyInfo.dataType), Array(all.prefix(size)))
    }

    func value(_ key: String) -> Double? {
        guard let (type, b) = read(key) else { return nil }
        switch type {
        case "flt " where b.count >= 4:
            let v = Float(bitPattern: UInt32(b[0]) | UInt32(b[1]) << 8 | UInt32(b[2]) << 16 | UInt32(b[3]) << 24)
            return v.isFinite ? Double(v) : nil
        case "fpe2" where b.count >= 2:
            return Double((UInt16(b[0]) << 8) | UInt16(b[1])) / 4
        case "sp78" where b.count >= 2:
            return Double(Int16(bitPattern: (UInt16(b[0]) << 8) | UInt16(b[1]))) / 256
        case "ui8 " where b.count >= 1:
            return Double(b[0])
        case "ui16" where b.count >= 2:
            return Double((UInt16(b[0]) << 8) | UInt16(b[1]))
        case "ui32" where b.count >= 4:
            return Double(UInt32(b[0]) << 24 | UInt32(b[1]) << 16 | UInt32(b[2]) << 8 | UInt32(b[3]))
        default:
            return nil
        }
    }

    func keys() -> [String] {
        guard let n = value("#KEY"), n > 0 else { return [] }
        var result: [String] = []
        for i in 0..<Int(min(n, 4096)) {
            var input = SMCKeyData()
            input.data8 = 8
            input.data32 = UInt32(i)
            if let out = call(&input) { result.append(fourCCString(out.key)) }
        }
        return result
    }
}

enum Sensors {
    nonisolated(unsafe) private static var cpuKeys: [String]?

    static func read() -> SensorReading {
        var r = SensorReading()
        if let smc = SMC() {
            if let n = smc.value("FNum") {
                let count = Int(n)
                r.fanCount = count
                if count > 0 {
                    let speeds = (0..<count).compactMap { smc.value("F\($0)Ac") }.filter { $0 >= 0 && $0 < 20000 }
                    if !speeds.isEmpty { r.fanRPM = speeds.reduce(0, +) / Double(speeds.count) }
                }
            }
            r.temperature = cpuTemperature(smc)
        }
        if r.temperature == nil { r.temperature = HIDThermal.cpuTemperature() }
        return r
    }

    private static func valid(_ v: Double) -> Bool { v >= 1 && v <= 130 }

    private static func cpuTemperature(_ smc: SMC) -> Double? {
        if cpuKeys == nil {
            let all = smc.keys()
            var keys = all.filter { $0.hasPrefix("Tp") }
            if keys.isEmpty { keys = all.filter { $0 == "TC0P" || $0 == "TC0D" || $0 == "TC0E" || $0 == "TC0F" } }
            if keys.isEmpty { keys = ["TC0P", "Tp09", "Tp01", "Tp05", "Tp0D", "Tp0H", "Tp0L", "Tp0P", "Tp0X", "Tp0b", "Tp1h", "Tp1t"] }
            cpuKeys = keys
        }
        let values = (cpuKeys ?? []).compactMap { smc.value($0) }.filter(valid)
        guard !values.isEmpty else { return nil }
        return values.reduce(0, +) / Double(values.count)
    }
}

enum HIDThermal {
    private typealias CreateFn = @convention(c) (CFAllocator?) -> Unmanaged<AnyObject>?
    private typealias MatchFn = @convention(c) (AnyObject, CFDictionary) -> Int32
    private typealias ServicesFn = @convention(c) (AnyObject) -> Unmanaged<CFArray>?
    private typealias PropFn = @convention(c) (AnyObject, CFString) -> Unmanaged<AnyObject>?
    private typealias EventFn = @convention(c) (AnyObject, Int64, Int32, Int64) -> Unmanaged<AnyObject>?
    private typealias FloatFn = @convention(c) (AnyObject, Int32) -> Double

    static func cpuTemperature() -> Double? {
        guard let h = dlopen("/System/Library/Frameworks/IOKit.framework/IOKit", RTLD_NOW) else { return nil }
        func sym<T>(_ name: String, _ t: T.Type) -> T? {
            guard let p = dlsym(h, name) else { return nil }
            return unsafeBitCast(p, to: t)
        }
        guard let create = sym("IOHIDEventSystemClientCreate", CreateFn.self),
              let setMatching = sym("IOHIDEventSystemClientSetMatching", MatchFn.self),
              let copyServices = sym("IOHIDEventSystemClientCopyServices", ServicesFn.self),
              let copyProp = sym("IOHIDServiceClientCopyProperty", PropFn.self),
              let copyEvent = sym("IOHIDServiceClientCopyEvent", EventFn.self),
              let getFloat = sym("IOHIDEventGetFloatValue", FloatFn.self),
              let client = create(kCFAllocatorDefault)?.takeRetainedValue() else { return nil }
        let matching = ["PrimaryUsagePage": 0xff00, "PrimaryUsage": 5] as CFDictionary
        _ = setMatching(client, matching)
        guard let services = copyServices(client)?.takeRetainedValue() as? [AnyObject] else { return nil }
        let kTemperature: Int64 = 15
        var values: [Double] = []
        for s in services {
            guard let name = copyProp(s, "Product" as CFString)?.takeRetainedValue() as? String,
                  name.hasPrefix("PMU tdie") || name.hasPrefix("PMU2 tdie") else { continue }
            guard let event = copyEvent(s, kTemperature, 0, 0)?.takeRetainedValue() else { continue }
            let v = getFloat(event, Int32(kTemperature << 16))
            if v >= 1 && v <= 130 { values.append(v) }
        }
        guard !values.isEmpty else { return nil }
        return values.reduce(0, +) / Double(values.count)
    }
}
