import AppKit
import SwiftUI
import UserNotifications

final class AlertCenter: NSObject, UNUserNotificationCenterDelegate {
    static let shared = AlertCenter()
    var onOpen: (() -> Void)?
    var onOpenTool: ((String) -> Void)?

    static var available: Bool {
        Bundle.main.bundleIdentifier != nil && Bundle.main.bundleURL.pathExtension == "app"
    }

    func setUp(enabled: Bool) {
        guard AlertCenter.available else { return }
        let center = UNUserNotificationCenter.current()
        center.delegate = self
        let d = UserDefaults.standard
        guard enabled, !d.bool(forKey: "alertsAsked") else { return }
        d.set(true, forKey: "alertsAsked")
        center.requestAuthorization(options: [.alert, .sound]) { _, _ in }
    }

    func post(kind: String, title: String, body: String) {
        guard AlertCenter.available else { return }
        let d = UserDefaults.standard
        let key = "alertLast.\(kind)"
        if let last = d.object(forKey: key) as? Date, Date().timeIntervalSince(last) < 86_400 { return }
        d.set(Date(), forKey: key)
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        let request = UNNotificationRequest(identifier: "mac-cleaner.\(kind)", content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request)
    }

    func notify(title: String, body: String, tool: String? = nil) {
        guard AlertCenter.available else { return }
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        if let tool { content.userInfo = ["tool": tool] }
        let request = UNNotificationRequest(identifier: "mac-cleaner.done.\(UUID().uuidString)", content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request)
    }

    func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification,
                                withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        completionHandler([.banner, .sound])
    }

    func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse,
                                withCompletionHandler completionHandler: @escaping () -> Void) {
        let tool = response.notification.request.content.userInfo["tool"] as? String
        let open = onOpen
        let openTool = onOpenTool
        DispatchQueue.main.async {
            if let tool, let openTool { openTool(tool) } else { open?() }
        }
        completionHandler()
    }
}

@MainActor
enum StatusItemOpener {
    static func open(panel: NSWindow?) {
        if panel?.isVisible == true { return }
        for window in NSApp.windows {
            if let button = find(window.contentView) {
                button.performClick(nil)
                return
            }
        }
    }

    private static func find(_ view: NSView?) -> NSStatusBarButton? {
        guard let view else { return nil }
        if let button = view as? NSStatusBarButton { return button }
        for sub in view.subviews {
            if let button = find(sub) { return button }
        }
        return nil
    }
}

enum DiskAccess {
    static func hasFullAccess() -> Bool {
        let fm = FileManager.default
        let home = NSHomeDirectory() as NSString
        for rel in ["Library/Safari", ".Trash"] {
            let path = home.appendingPathComponent(rel)
            guard fm.fileExists(atPath: path) else { continue }
            do {
                _ = try fm.contentsOfDirectory(atPath: path)
                return true
            } catch {
                return false
            }
        }
        return true
    }

    static func trashSize() -> Int64? {
        let url = URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent(".Trash")
        guard (try? FileManager.default.contentsOfDirectory(atPath: url.path)) != nil else { return nil }
        let keys: [URLResourceKey] = [.totalFileAllocatedSizeKey, .isRegularFileKey]
        guard let e = FileManager.default.enumerator(at: url, includingPropertiesForKeys: keys) else { return nil }
        var total: Int64 = 0
        for case let item as URL in e {
            guard let v = try? item.resourceValues(forKeys: Set(keys)), v.isRegularFile == true else { continue }
            total += Int64(v.totalFileAllocatedSize ?? 0)
        }
        return total
    }

    static let settingsURL = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles")!
}

struct WindowReader: NSViewRepresentable {
    let onWindow: (NSWindow?) -> Void

    final class Tracker: NSView {
        var onWindow: ((NSWindow?) -> Void)?

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            onWindow?(window)
        }
    }

    func makeNSView(context: Context) -> Tracker {
        let view = Tracker()
        view.onWindow = onWindow
        return view
    }

    func updateNSView(_ nsView: Tracker, context: Context) {}
}

extension Model {
    func checkAlerts() {
        guard alertsEnabled else {
            hotStreak = 0
            return
        }
        let center = AlertCenter.shared
        if diskTotal > 0, diskFree * 10 < diskTotal {
            let pct = Int(diskFree * 100 / diskTotal)
            center.post(kind: "disk", title: L.t("alertDiskTitle"),
                        body: String(format: L.t("alertDiskBody"), freeLabel, pct))
        }
        if heatLevel >= 2 { hotStreak += 1 } else { hotStreak = 0 }
        if hotStreak >= 2 {
            let body: String
            if let t = sensors.temperature, (temperatureLevel ?? 0) >= 2 {
                body = String(format: L.t("alertHeatBody"), L.deg(t))
            } else {
                body = String(format: L.t("alertHeatState"), Heat.label(heatLevel))
            }
            center.post(kind: "heat", title: L.t("alertHeatTitle"), body: body)
        }
        if let at = trashCheckedAt, Date().timeIntervalSince(at) < 1800 {
            alertTrash(trashBytes)
            return
        }
        guard !trashMeasuring else { return }
        trashMeasuring = true
        DispatchQueue.global(qos: .utility).async { [weak self] in
            let size = DiskAccess.trashSize()
            DispatchQueue.main.async {
                guard let self else { return }
                self.trashMeasuring = false
                self.trashCheckedAt = Date()
                self.trashBytes = size
                self.alertTrash(size)
            }
        }
    }

    private func alertTrash(_ bytes: Int64?) {
        guard alertsEnabled, let bytes, bytes > 5_000_000_000 else { return }
        AlertCenter.shared.post(kind: "trash", title: L.t("alertTrashTitle"),
                                body: String(format: L.t("alertTrashBody"), L.human(bytes: bytes)))
    }
}
