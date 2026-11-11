import AppKit
import CoreLocation
import CoreWLAN
import SwiftUI
import SystemConfiguration

struct SpeedResult: Equatable {
    let down: Double
    let up: Double
    let rpm: Double?
}

enum LinkKind: Equatable {
    case none
    case wifi
    case ethernet
    case other
}

@MainActor
final class NetworkMonitor: NSObject, ObservableObject, CLLocationManagerDelegate {
    static let shared = NetworkMonitor()

    @Published var kind: LinkKind = .none
    @Published var ssid: String?
    @Published var rssi: Int?
    @Published var linkRate: Double?
    @Published var down: Double?
    @Published var up: Double?
    @Published var testing = false
    @Published var speed: SpeedResult?
    @Published var speedError: String?
    @Published var locationStatus: CLAuthorizationStatus = .notDetermined
    @Published var locationAsked = UserDefaults.standard.bool(forKey: "locationAsked")

    private var users: Set<String> = []
    private var timer: Timer?
    private var last: (date: Date, inBytes: UInt32, outBytes: UInt32, name: String)?
    private var test: Process?
    private lazy var location: CLLocationManager = {
        let m = CLLocationManager()
        m.delegate = self
        return m
    }()

    func retain(_ who: String) {
        users.insert(who)
        guard timer == nil else { return }
        if !Demo.enabled { locationStatus = location.authorizationStatus }
        sample()
        let t = Timer(timeInterval: 2, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.sample() }
        }
        RunLoop.main.add(t, forMode: .common)
        timer = t
    }

    func release(_ who: String) {
        users.remove(who)
        guard users.isEmpty else { return }
        timer?.invalidate()
        timer = nil
        last = nil
        down = nil
        up = nil
    }

    var bars: Int {
        guard let r = rssi, r != 0 else { return 0 }
        switch r {
        case (-55)...: return 4
        case (-67)...: return 3
        case (-75)...: return 2
        default: return 1
        }
    }

    var canAskLocation: Bool {
        kind == .wifi && ssid == nil && locationStatus == .notDetermined && !locationAsked && Bundle.main.bundleURL.pathExtension == "app"
    }

    var title: String {
        switch kind {
        case .wifi: return ssid.map { String(format: L.t("wifiNamed"), $0) } ?? L.t("wifiConnected")
        case .ethernet: return L.t("ethernet")
        case .other: return L.t("netConnected")
        case .none: return L.t("offline")
        }
    }

    var symbol: String {
        switch kind {
        case .wifi: return "wifi"
        case .ethernet: return "cable.connector"
        case .other: return "network"
        case .none: return "wifi.slash"
        }
    }

    func askLocation() {
        locationAsked = true
        UserDefaults.standard.set(true, forKey: "locationAsked")
        location.requestWhenInUseAuthorization()
    }

    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        let status = manager.authorizationStatus
        Task { @MainActor in
            self.locationStatus = status
            self.sample()
        }
    }

    private func sample() {
        if Demo.enabled {
            kind = .wifi
            ssid = "Maison"
            rssi = -52
            linkRate = 866
            down = 2_400_000
            up = 180_000
            return
        }
        let primary = NetworkMonitor.primaryInterface()
        let wifi = CWWiFiClient.shared().interface()
        let wifiName = wifi?.interfaceName
        let wifiUp = (wifi?.rssiValue() ?? 0) != 0
        if let primary, primary == wifiName, wifiUp {
            kind = .wifi
        } else if let primary, primary.hasPrefix("en") {
            kind = .ethernet
        } else if wifiUp {
            kind = .wifi
        } else {
            kind = primary == nil ? .none : .other
        }
        if kind == .wifi {
            ssid = wifi?.ssid()
            rssi = wifi?.rssiValue()
            linkRate = wifi?.transmitRate()
        } else {
            ssid = nil
            rssi = nil
            linkRate = nil
        }
        guard let name = primary ?? (wifiUp ? wifiName : nil), let bytes = NetworkMonitor.bytes(name) else {
            down = nil
            up = nil
            last = nil
            return
        }
        let now = Date()
        if let l = last, l.name == name {
            let dt = now.timeIntervalSince(l.date)
            if dt > 0.5 {
                down = Double(bytes.0 &- l.inBytes) / dt
                up = Double(bytes.1 &- l.outBytes) / dt
            }
        }
        last = (now, bytes.0, bytes.1, name)
    }

    nonisolated static func primaryInterface() -> String? {
        guard let store = SCDynamicStoreCreate(nil, "mac-cleaner" as CFString, nil, nil),
              let dict = SCDynamicStoreCopyValue(store, "State:/Network/Global/IPv4" as CFString) as? [String: Any] else { return nil }
        return dict["PrimaryInterface"] as? String
    }

    nonisolated static func bytes(_ name: String) -> (UInt32, UInt32)? {
        var head: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&head) == 0, let first = head else { return nil }
        defer { freeifaddrs(head) }
        var cursor: UnsafeMutablePointer<ifaddrs>? = first
        while let p = cursor {
            let ifa = p.pointee
            if let addr = ifa.ifa_addr, addr.pointee.sa_family == UInt8(AF_LINK), String(cString: ifa.ifa_name) == name,
               let data = ifa.ifa_data {
                let d = data.assumingMemoryBound(to: if_data.self).pointee
                return (d.ifi_ibytes, d.ifi_obytes)
            }
            cursor = ifa.ifa_next
        }
        return nil
    }

    func runSpeedTest() {
        guard !testing else { return }
        testing = true
        speedError = nil
        if Demo.enabled {
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { [weak self] in
                guard let self, self.testing else { return }
                self.testing = false
                self.speed = SpeedResult(down: 312_000_000, up: 48_000_000, rpm: 1240)
            }
            return
        }
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/networkQuality")
        p.arguments = ["-c"]
        let pipe = Pipe()
        p.standardOutput = pipe
        p.standardError = FileHandle.nullDevice
        p.standardInput = FileHandle.nullDevice
        p.terminationHandler = { [weak self] proc in
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            let status = proc.terminationStatus
            let reason = proc.terminationReason
            Task { @MainActor in
                guard let self, self.test === proc else { return }
                self.test = nil
                self.testing = false
                if reason == .uncaughtSignal { return }
                if status == 0, let r = NetworkMonitor.parseSpeed(data) {
                    self.speed = r
                } else {
                    self.speedError = L.t("speedFailed")
                }
            }
        }
        do {
            try p.run()
            test = p
        } catch {
            testing = false
            speedError = L.t("speedFailed")
        }
    }

    func cancelSpeedTest() {
        guard testing else { return }
        testing = false
        if let p = test, p.isRunning { p.terminate() }
        test = nil
    }

    nonisolated static func parseSpeed(_ data: Data) -> SpeedResult? {
        guard let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
        func num(_ k: String) -> Double? {
            if let v = obj[k] as? Double { return v }
            if let v = obj[k] as? Int { return Double(v) }
            if let v = obj[k] as? NSNumber { return v.doubleValue }
            return nil
        }
        guard let d = num("dl_throughput"), let u = num("ul_throughput") else { return nil }
        return SpeedResult(down: d, up: u, rpm: num("responsiveness") ?? num("dl_responsiveness"))
    }

    static func rate(_ bytesPerSecond: Double?) -> String {
        guard let b = bytesPerSecond else { return "—" }
        let kb = b / 1024
        if kb >= 1024 { return "\(L.num(kb / 1024, 1)) \(L.mb)/s" }
        return "\(L.num(kb, 0)) \(L.kb)/s"
    }

    static func mbps(_ bitsPerSecond: Double) -> String {
        "\(L.num(bitsPerSecond / 1_000_000, bitsPerSecond >= 100_000_000 ? 0 : 1)) Mbit/s"
    }
}

struct SignalBars: View {
    let bars: Int

    var body: some View {
        HStack(alignment: .bottom, spacing: 2) {
            ForEach(1...4, id: \.self) { i in
                RoundedRectangle(cornerRadius: 1)
                    .fill(i <= bars ? Theme.accent : Theme.track)
                    .frame(width: 3, height: CGFloat(3 + i * 3))
            }
        }
        .frame(height: 15, alignment: .bottom)
    }
}

struct NetworkCard: View {
    @ObservedObject var net: NetworkMonitor
    var compact = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 10) {
                IconTile(symbol: net.symbol, size: compact ? 30 : 34, font: 14)
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text(net.title).font(.system(size: 12.5, weight: .semibold)).lineLimit(1)
                        if net.kind == .wifi { SignalBars(bars: net.bars) }
                    }
                    Text(line).font(.system(size: 11)).foregroundStyle(.secondary).monospacedDigit().lineLimit(1)
                }
                Spacer(minLength: 4)
                if net.testing {
                    Button(L.t("cancel")) { net.cancelSpeedTest() }
                        .buttonStyle(.plain).font(.system(size: 11, weight: .medium)).foregroundStyle(Theme.accent)
                } else {
                    Button(L.t("speedTest")) { net.runSpeedTest() }
                        .buttonStyle(.plain).font(.system(size: 11, weight: .medium)).foregroundStyle(Theme.accent)
                        .disabled(net.kind == .none)
                }
            }
            if net.testing {
                HStack(spacing: 6) {
                    ProgressView().controlSize(.mini)
                    Text(L.t("speedRunning")).font(.system(size: 11)).foregroundStyle(.secondary)
                }
            } else if let s = net.speed {
                HStack(spacing: 12) {
                    metric("arrow.down", NetworkMonitor.mbps(s.down))
                    metric("arrow.up", NetworkMonitor.mbps(s.up))
                    if let r = s.rpm { metric("timer", String(format: L.t("rpmValue"), L.num(r, 0))) }
                    Spacer(minLength: 0)
                }
            } else if let e = net.speedError {
                Text(e).font(.system(size: 11)).foregroundStyle(Theme.warn)
            }
            if net.canAskLocation {
                HStack(alignment: .top, spacing: 6) {
                    Text(L.t("locationWhy")).font(.system(size: 10.5)).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 4)
                    Button(L.t("allow")) { net.askLocation() }
                        .buttonStyle(.plain).font(.system(size: 11, weight: .medium)).foregroundStyle(Theme.accent)
                }
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 9)
        .themeCard()
    }

    private var line: String {
        var parts = ["↓ " + NetworkMonitor.rate(net.down), "↑ " + NetworkMonitor.rate(net.up)]
        if !compact, let r = net.linkRate, r > 0 { parts.append(String(format: L.t("linkRate"), L.num(r, 0))) }
        return parts.joined(separator: "  ·  ")
    }

    private func metric(_ symbol: String, _ text: String) -> some View {
        HStack(spacing: 3) {
            Image(systemName: symbol).font(.system(size: 10, weight: .semibold)).foregroundStyle(Theme.accent)
            Text(text).font(.system(size: 11.5, weight: .semibold)).monospacedDigit()
        }
    }
}
