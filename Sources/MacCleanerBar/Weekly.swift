import Foundation

enum WeeklyJob {
    static let label = "com.iberis-suite.mac-cleaner.weekly"

    static var plistURL: URL {
        URL(fileURLWithPath: NSHomeDirectory())
            .appendingPathComponent("Library/LaunchAgents/\(label).plist")
    }

    static var logPath: String {
        (NSHomeDirectory() as NSString).appendingPathComponent("Library/Logs/mac-cleaner-weekly.log")
    }

    static var isInstalled: Bool { FileManager.default.fileExists(atPath: plistURL.path) }

    static func plistData(cli: String, lang: String, log: String) throws -> Data {
        let dict: [String: Any] = [
            "Label": label,
            "ProgramArguments": ["/bin/zsh", cli, "auto", "--yes"],
            "StartCalendarInterval": ["Weekday": 1, "Hour": 10, "Minute": 0],
            "StandardOutPath": log,
            "StandardErrorPath": log,
            "EnvironmentVariables": [
                "NO_COLOR": "1",
                "MAC_CLEANER_LANG": lang,
                "PATH": "/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin",
            ],
            "RunAtLoad": false,
            "ProcessType": "Background",
        ]
        return try PropertyListSerialization.data(fromPropertyList: dict, format: .xml, options: 0)
    }

    static func write(cli: String, lang: String, to url: URL, log: String) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try plistData(cli: cli, lang: lang, log: log).write(to: url, options: .atomic)
    }

    @discardableResult
    static func enable(cli: String, lang: String) -> Bool {
        do {
            try write(cli: cli, lang: lang, to: plistURL, log: logPath)
        } catch {
            return false
        }
        launchctl(["bootout", "gui/\(getuid())/\(label)"])
        if launchctl(["bootstrap", "gui/\(getuid())", plistURL.path]) != 0 {
            try? FileManager.default.removeItem(at: plistURL)
            return false
        }
        return true
    }

    static func disable() {
        launchctl(["bootout", "gui/\(getuid())/\(label)"])
        try? FileManager.default.removeItem(at: plistURL)
    }

    @discardableResult
    private static func launchctl(_ args: [String]) -> Int32 {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/bin/launchctl")
        p.arguments = args
        p.standardInput = FileHandle.nullDevice
        p.standardOutput = FileHandle.nullDevice
        p.standardError = FileHandle.nullDevice
        guard (try? p.run()) != nil else { return -1 }
        p.waitUntilExit()
        return p.terminationStatus
    }
}
