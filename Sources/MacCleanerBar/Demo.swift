import AppKit
import SwiftUI

enum Demo {
    static let enabled: Bool = ProcessInfo.processInfo.environment["MAC_CLEANER_DEMO"] == "1"
        || CommandLine.arguments.contains("--snapshots")

    static let home = NSHomeDirectory()

    private static func row(_ i: Int, _ kb: Double, _ label: String, _ path: String, _ type: String, _ state: String = "") -> String {
        "\(i)\t\(Int(kb))\t\(label)\t\(path)\t\(type)" + (state.isEmpty ? "" : "\t\(state)")
    }

    private static func h(_ rel: String) -> String { (home as NSString).appendingPathComponent(rel) }

    static func list(_ cmd: String) -> String {
        let gb = 1_048_576.0, mb = 1024.0
        var r: [String] = []
        switch cmd {
        case "caches":
            r = [row(1, 2.1 * gb, "Caches des apps", h("Library/Caches"), "apps", "safe"),
                 row(2, 640 * mb, "Journaux", h("Library/Logs"), "logs", "safe"),
                 row(3, 1.4 * gb, "Xcode DerivedData", h("Library/Developer/Xcode/DerivedData"), "xcode", "safe"),
                 row(4, 380 * mb, "Cache npm", h(".npm/_cacache"), "npm", "safe"),
                 row(5, 290 * mb, "Homebrew", h("Library/Caches/Homebrew"), "brew", "safe"),
                 row(6, 3.2 * gb, "Images Docker", h("Library/Containers/com.docker.docker"), "docker", "excluded"),
                 row(0, 120 * mb, "com.apple.Safari", h("Library/Caches/com.apple.Safari"), "skipped")]
        case "temp":
            r = [row(1, 420 * mb, "TemporaryItems", "/private/var/folders/xy/T/TemporaryItems", "tmp"),
                 row(2, 180 * mb, "com.apple.dt.Xcode", "/private/var/folders/xy/T/com.apple.dt.Xcode", "tmp"),
                 row(3, 64 * mb, "pip-build-env", "/private/var/folders/xy/T/pip-build-env", "tmp"),
                 row(4, 610 * mb, "Figma", "/private/var/folders/xy/X/Figma.app.code_sign_clone", "clone"),
                 row(5, 230 * mb, "Slack", "/private/var/folders/xy/X/Slack.app.code_sign_clone", "clone")]
        case "trash":
            r = [row(1, 512 * mb, "Projet-final-v3.zip", h(".Trash/Projet-final-v3.zip"), "file"),
                 row(2, 230 * mb, "Captures 2025", h(".Trash/Captures 2025"), "dir"),
                 row(3, 88 * mb, "Installer.dmg", h(".Trash/Installer.dmg"), "file")]
        case "auto":
            r = [row(1, 2.1 * gb, "Caches des apps", "-", "apps"),
                 row(2, 640 * mb, "Journaux", "-", "logs"),
                 row(3, 1.4 * gb, "Xcode DerivedData", "-", "xcode"),
                 row(4, 664 * mb, L.fr ? "Fichiers temporaires" : "Temporary files", "-", "temp"),
                 row(5, 830 * mb, L.t("trash"), "-", "trash")]
        case "large":
            r = [row(1, 8.4 * gb, "Tournage-brut.mov", h("Movies/Tournage-brut.mov"), "file"),
                 row(2, 4.1 * gb, "ubuntu-24.04.iso", h("Downloads/ubuntu-24.04.iso"), "file"),
                 row(3, 2.7 * gb, "Sauvegarde-photos.zip", h("Documents/Sauvegarde-photos.zip"), "file"),
                 row(4, 1.2 * gb, "Xcode_16.xip", h("Downloads/Xcode_16.xip"), "file"),
                 row(5, 760 * mb, "presentation-finale.key", h("Documents/presentation-finale.key"), "file")]
        case "downloads":
            r = [row(1, 1.2 * gb, "Xcode_16.xip", h("Downloads/Xcode_16.xip"), "file"),
                 row(2, 540 * mb, "Docker.dmg", h("Downloads/Docker.dmg"), "file"),
                 row(3, 210 * mb, "Factures 2024", h("Downloads/Factures 2024"), "dir"),
                 row(4, 48 * mb, "notice.pdf", h("Downloads/notice.pdf"), "file")]
        case "duplicates":
            r = ["STEP\tsize", "STEP\thash", row(1, 320 * mb, "video.mp4", h("Documents/video.mp4"), "keep"),
                 row(1, 320 * mb, "video copie.mp4", h("Desktop/video copie.mp4"), "copy"),
                 row(2, 24 * mb, "rapport.pdf", h("Documents/rapport.pdf"), "keep"),
                 row(2, 24 * mb, "rapport (1).pdf", h("Downloads/rapport (1).pdf"), "copy"),
                 row(2, 24 * mb, "rapport (2).pdf", h("Downloads/rapport (2).pdf"), "copy")]
        case "startup":
            r = [row(1, 0, "Spotify", "", "login", "on"),
                 row(2, 0, "com.adobe.ccxprocess", h("Library/LaunchAgents/com.adobe.ccxprocess.plist"), "agent", "on"),
                 row(3, 0, "com.google.keystone.agent", h("Library/LaunchAgents/com.google.keystone.agent.plist"), "agent", "off"),
                 row(4, 0, "com.docker.vmnetd", "/Library/LaunchDaemons/com.docker.vmnetd.plist", "daemon", "on")]
        case "dev":
            r = [row(1, 1.8 * gb, "app · feature/paiement · fusionnée", h("code/app-paiement"), "worktree"),
                 row(2, 740 * mb, "site · détachée · inactive 120 j", h("code/site-old"), "worktree"),
                 row(1, 3.6 * gb, "JeuProto", h("code/JeuProto/Library"), "unity")]
        case "cachesAdv":
            return list("caches")
        case "maintenance":
            r = [row(1, 0, L.fr ? "Vider le cache DNS" : "Flush the DNS cache", "dscacheutil -flushcache", "dns", "root"),
                 row(2, 0, L.fr ? "Réindexer Spotlight" : "Reindex Spotlight", "mdutil -E /", "spotlight", "root"),
                 row(3, 0, L.fr ? "Reconstruire la base « Ouvrir avec »" : "Rebuild the \u{201C}Open With\u{201D} database", "lsregister -kill -r", "launch", "user"),
                 row(4, 0, L.fr ? "Scripts périodiques (daily, weekly, monthly)" : "Periodic scripts (daily, weekly, monthly)", "periodic daily weekly monthly", "periodic", "root")]
        case "privacy":
            let hist = L.fr ? "Historique" : "History"
            r = [row(1, 410 * mb, "Safari · \(hist)", h("Library/Safari/History.db"), "history", "safari"),
                 row(2, 2 * mb, "Safari · Cookies", h("Library/Cookies/Cookies.binarycookies"), "cookies", "safari"),
                 row(3, 640 * mb, "Safari · Cache", h("Library/Caches/com.apple.Safari"), "cache", "safari"),
                 row(4, 96 * mb, "Chrome · Default · \(hist)", h("Library/Application Support/Google/Chrome/Default/History"), "history", "chrome"),
                 row(5, 4 * mb, "Chrome · Default · Cookies", h("Library/Application Support/Google/Chrome/Default/Network/Cookies"), "cookies", "chrome"),
                 row(6, 1.1 * gb, "Chrome · Default · Cache", h("Library/Caches/Google/Chrome/Default"), "cache", "chrome"),
                 row(0, 0, "Firefox", h("Library/Application Support/Firefox/Profiles"), "running", "firefox")]
        case "system":
            r = [row(0, 2.5 * gb, "swap", "\(Int(3 * gb))", "swap"),
                 row(0, 0, "com.apple.TimeMachine.2026-11-10-091502.local", "-", "snapshot"),
                 row(0, 0, "com.apple.TimeMachine.2026-11-11-091744.local", "-", "snapshot"),
                 row(0, 390 * gb, "Data", "Data", "volume"),
                 row(0, 13 * gb, "Macintosh HD", "System", "volume"),
                 row(0, 18 * gb, "Preboot", "Preboot", "volume"),
                 row(0, 3 * gb, "VM", "VM", "volume"),
                 row(0, 428 * gb, "disk3", "\(Int(460 * gb))", "container", "\(Int(32 * gb))"),
                 row(0, 119 * gb, "free", "\(Int(126 * gb))", "free", "\(Int(7 * gb))")]
        default:
            r = []
        }
        return r.joined(separator: "\n")
    }

    static func dryRun(_ cmd: String) -> String {
        let items = ToolItem.parseList(list(cmd)).filter { $0.index > 0 }
        return items.map { "  [\(L.fr ? "aperçu" : "dry run")] \($0.shortPath)" }.joined(separator: "\n")
    }

    static func yes(_ cmd: String, _ args: [String]) -> String {
        let picked = (args.firstIndex(of: "--select").map { args[$0 + 1] } ?? "1 2 3 4").split(separator: " ").compactMap { Int($0) }
        switch cmd {
        case "maintenance":
            let keys = ["dns", "spotlight", "launch", "periodic"]
            return picked.filter { $0 >= 1 && $0 <= 4 }.flatMap { ["STEP\t\(keys[$0 - 1])\trunning", "STEP\t\(keys[$0 - 1])\tdone"] }
                .joined(separator: "\n")
        case "privacy":
            let items = ToolItem.parseList(list("privacy")).filter { picked.contains($0.index) }
            return (picked.flatMap { ["STEP\t\($0)\trunning", "STEP\t\($0)\tdone"] }
                + ["RESULT\t\(Int(items.reduce(0) { $0 + $1.kb }))\t\(items.count)"]).joined(separator: "\n")
        case "system":
            return ["STEP\tthin\trunning", "STEP\tthin\tdone", "STEP\tpurge\trunning", "STEP\tpurge\tdone",
                    "RESULT\tfree\t\(Int(119 * 1_048_576.0))\t\(Int(126.4 * 1_048_576.0))"].joined(separator: "\n")
        default:
            return L.fr ? "Fait (mode démo, rien n'a été touché)" : "Done (demo mode, nothing was touched)"
        }
    }

    static func uninstall(_ path: String) -> String {
        let name = ((path as NSString).lastPathComponent as NSString).deletingPathExtension
        let id = "com.example." + name.lowercased()
        return [row(1, 412 * 1024, "\(name).app", path, "app"),
                row(2, 96 * 1024, name, h("Library/Application Support/\(name)"), "dir"),
                row(3, 38 * 1024, id, h("Library/Caches/\(id)"), "dir"),
                row(4, 12, "\(id).plist", h("Library/Preferences/\(id).plist"), "file")].joined(separator: "\n")
    }

    static func respond(_ args: [String]) -> (String, Int32) {
        guard let cmd = args.first else { return ("", 1) }
        if cmd == "uninstall", args.count > 1 {
            return args.contains("--yes") ? ("OK", 0) : (uninstall(args[1]), 0)
        }
        if args.contains("--list") { return (list(cmd), 0) }
        if args.contains("--yes") { return (yes(cmd, args), 0) }
        return (dryRun(cmd), 0)
    }

    static func history() -> [HistoryEntry] {
        let now = Date()
        func ago(_ h: Double) -> Date { now.addingTimeInterval(-h * 3600) }
        return [HistoryEntry(date: ago(2), action: "m9", kb: 3.4 * 1_048_576, note: ""),
                HistoryEntry(date: ago(26), action: "m4", kb: 8.4 * 1_048_576, note: ""),
                HistoryEntry(date: ago(50), action: "m1", kb: 0, note: "31% → 58%"),
                HistoryEntry(date: ago(74), action: "m5", kb: 2.1 * 1_048_576, note: ""),
                HistoryEntry(date: ago(122), action: "m3", kb: 546 * 1024, note: "Figma"),
                HistoryEntry(date: ago(170), action: "m14", kb: 0, note: "dns, launch")]
    }

    @MainActor
    static func fill(_ m: Model) {
        if Snapshots.active && m.diskTotal > 0 { return }
        m.diskTotal = 494_000_000_000
        m.diskFree = 128_000_000_000
        m.memFreePct = 38
        m.sensors = SensorReading(temperature: 52, fanCount: 1, fanRPM: 1830)
        m.battery = BatteryInfo(cycles: 212, health: 91, charge: 76, onAC: false, charging: false)
        m.fullDiskAccess = true
        m.freedMonth = 6.8 * 1_048_576
        m.freedTotal = 41.3 * 1_048_576
        m.history = Demo.history()
        m.weeklyEnabled = true
        m.thermalState = .nominal
    }

    static func usages(byCPU: Bool) -> [AppUsage] {
        let apps: [(String, String, Double, Int64)] = [
            ("Safari", "/Applications/Safari.app", 18.4, 1_900_000_000),
            ("Mail", "/System/Applications/Mail.app", 6.2, 640_000_000),
            ("Music", "/System/Applications/Music.app", 3.1, 410_000_000),
            ("Photos", "/System/Applications/Photos.app", 1.4, 1_200_000_000),
        ]
        let list = apps.enumerated().map { i, a in
            AppUsage(pid: pid_t(90_000 + i), name: a.0, icon: NSWorkspace.shared.icon(forFile: a.1),
                     cpu: a.2, memory: a.3, canQuit: true)
        }
        let sorted = byCPU ? list.sorted { ($0.cpu ?? 0) > ($1.cpu ?? 0) } : list.sorted { $0.memory > $1.memory }
        return Array(sorted.prefix(3))
    }

    static let apps: [AppItem] = ["Blender", "Discord", "Figma", "Notion", "OBS", "Slack", "Spotify", "VLC", "Zoom"]
        .map { AppItem(path: "/Applications/\($0).app", name: $0) }

    static let appSizes: [String: Int64] = Dictionary(uniqueKeysWithValues: zip(
        apps.map(\.path), [1_200_000_000, 410_000_000, 520_000_000, 380_000_000, 640_000_000, 470_000_000, 290_000_000, 160_000_000, 220_000_000]))

    static func diskEntries(_ dir: URL) -> [DiskEntry] {
        let g: Int64 = 1_000_000_000
        let spec: [(String, Double, Bool)]
        if dir.path == "/" {
            spec = [("Users", 180, true), ("System", 14, true), ("Applications", 38, true), ("Library", 12, true),
                    ("private", 9, true), ("opt", 4, true)]
        } else if dir.path == home {
            spec = [("Library", 48, true), ("Movies", 31, true), ("Developer", 22, true), ("Pictures", 14, true),
                    ("Downloads", 9, true), ("Documents", 6, true), ("Music", 3, true), ("Desktop", 1.2, true),
                    (".zsh_history", 0.002, false)]
        } else {
            spec = [("Caches", 14, true), ("Application Support", 12, true), ("Containers", 9, true), ("Developer", 7, true),
                    ("Mail", 3, true), ("Logs", 1.1, true), ("Preferences", 0.04, true)]
        }
        return spec.map { DiskEntry(url: dir.appendingPathComponent($0.0), name: $0.0, size: Int64($0.1 * Double(g)), isDir: $0.2) }
    }
}

@MainActor
enum Snapshots {
    static var active = false

    static var requestedDirectory: String? {
        let a = CommandLine.arguments
        guard let i = a.firstIndex(of: "--snapshots"), i + 1 < a.count else { return nil }
        return a[i + 1]
    }

    struct Shot {
        let name: String
        let window: Bool
        let make: () -> AnyView
    }

    static func run(into dir: String) {
        active = true
        NetworkMonitor.shared.retain("snapshots")
        let url = URL(fileURLWithPath: dir)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        for (dark, suffix) in [(true, "sombre"), (false, "clair")] {
            let app = NSAppearance(named: dark ? .darkAqua : .aqua)
            NSApp.appearance = app
            for (i, shot) in shots().enumerated() {
                let file = url.appendingPathComponent(String(format: "%02d-%@-%@.png", i + 1, shot.name, suffix))
                render(shot, appearance: app, to: file)
            }
        }
        exit(0)
    }

    private static func render(_ shot: Shot, appearance: NSAppearance?, to file: URL) {
        let view = shot.make()
        let host = NSHostingView(rootView: view)
        host.appearance = appearance
        var size = MainWindow.size
        if !shot.window {
            host.frame = NSRect(x: 0, y: 0, width: 360, height: 400)
            size = NSSize(width: 360, height: max(200, host.fittingSize.height))
        }
        let style: NSWindow.StyleMask = shot.window ? [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView] : [.borderless]
        let w = NSWindow(contentRect: NSRect(origin: NSPoint(x: -30_000, y: -30_000), size: size), styleMask: style,
                         backing: .buffered, defer: false)
        w.appearance = appearance
        w.titlebarAppearsTransparent = true
        w.titleVisibility = .hidden
        w.isReleasedWhenClosed = false
        w.backgroundColor = .windowBackgroundColor
        w.contentView = host
        w.orderFrontRegardless()
        RunLoop.main.run(until: Date().addingTimeInterval(0.3))
        host.layoutSubtreeIfNeeded()
        RunLoop.main.run(until: Date().addingTimeInterval(0.1))
        let target: NSView = shot.window ? (host.superview ?? host) : host
        let bounds = target.bounds
        guard let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(bounds.width * 2), pixelsHigh: Int(bounds.height * 2),
                                         bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                                         colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0) else { return }
        rep.size = bounds.size
        target.cacheDisplay(in: bounds, to: rep)
        try? rep.representation(using: .png, properties: [:])?.write(to: file)
        w.orderOut(nil)
    }

    private static func panel(_ name: String, _ setup: @escaping (Model) -> Void) -> Shot {
        Shot(name: name, window: false) {
            let m = Model()
            m.estimates = ["temp": 664 * 1024, "caches": 4.8 * 1_048_576, "trash": 830 * 1024]
            setup(m)
            return AnyView(PanelView(model: m) { _ in })
        }
    }

    private static func window(_ name: String, _ setup: @escaping (Hub) -> Void) -> Shot {
        Shot(name: name, window: true) {
            let m = Model()
            m.estimates = ["temp": 664 * 1024, "caches": 4.8 * 1_048_576, "trash": 830 * 1024]
            let hub = Hub()
            hub.cliPath = "demo"
            setup(hub)
            return AnyView(MainView(hub: hub, model: m))
        }
    }

    private static func items(_ cmd: String) -> [ToolItem] { ToolItem.parseList(Demo.list(cmd)) }

    private static func fill(_ m: ToolModel, _ all: [ToolItem], partial: Bool = false) {
        let rows = all.filter { $0.index > 0 }
        let keep = partial ? Array(rows.prefix(max(1, rows.count / 2))) : rows
        m.items = m.sortsBySize ? keep.sorted { $0.kb > $1.kb } : keep
        m.skipped = partial ? [] : all.filter { $0.index == 0 }
        m.selected = Set(m.items.filter { $0.type != "keep" && $0.state != "excluded" }.prefix(m.tool == "startup" ? 1 : 3).map(\.key))
    }

    private static func shots() -> [Shot] {
        var s: [Shot] = []
        s.append(panel("panneau-normal") { _ in })
        s.append(panel("panneau-activite") { m in
            m.activityExpanded = true
            m.topCPU = Demo.usages(byCPU: true)
            m.topMemory = Demo.usages(byCPU: false)
        })
        s.append(panel("panneau-disque-plein") { m in m.diskFree = 21_000_000_000 })
        s.append(panel("panneau-chaleur") { m in
            m.sensors = SensorReading(temperature: 97, fanCount: 1, fanRPM: 5400)
            m.thermalState = .serious
        })
        s.append(panel("panneau-sans-acces-disque") { m in m.fullDiskAccess = false })
        s.append(panel("panneau-acces-relancer") { m in
            m.fullDiskAccess = false
            m.accessRequested = true
        })
        for c in ["temp", "caches", "trash", "auto"] {
            let all = items(c)
            s.append(panel("apercu-\(c)-chargement") { m in m.phase = .previewing(c) })
            s.append(panel("apercu-\(c)-en-recherche") { m in
                let part = Array(all.filter { $0.index > 0 }.prefix(2))
                m.sheetItems = part
                m.sheetSelected = Set(Model.defaultSelection(part).map(\.index))
                m.phase = .previewing(c)
            })
            s.append(panel("apercu-\(c)-liste") { m in
                m.sheetItems = all
                m.sheetSelected = Set(Model.defaultSelection(all).map(\.index))
                m.phase = .previewReady(c)
            })
            s.append(panel("apercu-\(c)-en-cours") { m in m.phase = .cleaning(c) })
            s.append(panel("apercu-\(c)-resultat") { m in
                let chosen = Model.defaultSelection(all)
                m.result = CleanResult(ok: true, freedKB: chosen.reduce(0) { $0 + $1.kb }, sections: chosen.map(\.label), message: "")
                m.phase = .cleaned(c)
            })
            s.append(panel("apercu-\(c)-erreur") { m in
                m.sheetError = L.fr ? "Accès refusé : ~/Library/Caches (autoriser l'accès complet au disque)" : "Permission denied: ~/Library/Caches"
                m.output = "rm: ~/Library/Caches/com.apple.Safari: Operation not permitted"
                m.exitStatus = 1
                m.phase = .previewReady(c)
            })
        }
        s.append(panel("apercu-trash-vide") { m in m.phase = .previewReady("trash") })
        s.append(window("fenetre-accueil") { _ in })
        for t in ["large", "downloads", "duplicates", "startup", "dev", "cachesAdv"] {
            let cmd = t == "cachesAdv" ? "caches" : t
            let all = items(cmd)
            s.append(window("outil-\(t)-chargement") { h in
                h.current = t
                h.tool(t).listing = true
            })
            s.append(window("outil-\(t)-en-recherche") { h in
                h.current = t
                let m = h.tool(t)
                fill(m, all, partial: true)
                m.listing = true
                if t == "duplicates" { m.step = "hash" }
            })
            s.append(window("outil-\(t)-liste") { h in
                h.current = t
                fill(h.tool(t), all)
            })
            s.append(window("outil-\(t)-apercu") { h in
                h.current = t
                let m = h.tool(t)
                fill(m, all)
                m.stage = .preview
            })
            s.append(window("outil-\(t)-en-cours") { h in
                h.current = t
                let m = h.tool(t)
                fill(m, all)
                m.stage = .working
            })
            s.append(window("outil-\(t)-resultat") { h in
                h.current = t
                let m = h.tool(t)
                fill(m, all)
                let n = m.chosen.count
                let kb = m.selectedKB
                m.items = m.items.filter { !m.selected.contains($0.key) }
                m.selected = []
                m.stage = .done
                m.result = ToolResult(ok: true, title: t == "startup" ? String(format: L.t("disabledN"), n)
                                      : String(format: L.t("freedItems"), L.human(kb: kb), n),
                                      detail: t == "startup" ? L.t("startupNote") : "")
            })
            s.append(window("outil-\(t)-vide") { h in
                h.current = t
                h.tool(t).items = []
            })
        }
        let sys = items("system")
        s.append(window("outil-system-chargement") { h in
            h.current = "system"
            h.tool("system").listing = true
        })
        s.append(window("outil-system-liste") { h in
            h.current = "system"
            h.tool("system").info = sys
        })
        s.append(window("outil-system-apercu") { h in
            h.current = "system"
            let m = h.tool("system")
            m.info = sys
            m.stage = .preview
        })
        s.append(window("outil-system-en-cours") { h in
            h.current = "system"
            let m = h.tool("system")
            m.info = sys
            m.stage = .working
            m.steps = ["thin": "done", "purge": "running"]
        })
        s.append(window("outil-system-resultat") { h in
            h.current = "system"
            let m = h.tool("system")
            m.info = sys
            m.stage = .done
            m.result = ToolResult(ok: true, title: String(format: L.t("freeFromTo"), L.human(kb: 119 * 1_048_576), L.human(kb: 126.4 * 1_048_576)))
        })
        s.append(window("outil-large-erreur") { h in
            h.current = "large"
            let m = h.tool("large")
            m.failed = true
            m.output = "find: /Users/demo/Library/Mail: Operation not permitted\nmac-cleaner: accès refusé"
            m.message = L.fr ? "Accès refusé à certains dossiers." : "Permission denied on some folders."
        })
        let leftovers = ToolItem.parseList(Demo.uninstall("/Applications/Figma.app")).map { Leftover(path: $0.path, kb: $0.kb, type: $0.type) }
        s.append(window("desinstaller-liste") { h in
            h.current = "uninstall"
            h.uninstall.reload()
        })
        s.append(window("desinstaller-chargement") { h in
            h.current = "uninstall"
            let m = h.uninstall
            m.reload()
            m.selected = Demo.apps[2]
            m.leftovers = Array(leftovers.prefix(2))
            m.loading = true
        })
        s.append(window("desinstaller-selection") { h in
            h.current = "uninstall"
            let m = h.uninstall
            m.reload()
            m.selected = Demo.apps[2]
            m.leftovers = leftovers
            m.total = leftovers.reduce(0) { $0 + $1.kb }
        })
        s.append(window("desinstaller-en-cours") { h in
            h.current = "uninstall"
            let m = h.uninstall
            m.reload()
            m.selected = Demo.apps[2]
            m.leftovers = leftovers
            m.total = leftovers.reduce(0) { $0 + $1.kb }
            m.working = true
        })
        s.append(window("desinstaller-resultat") { h in
            h.current = "uninstall"
            let m = h.uninstall
            m.reload()
            m.result = ToolResult(ok: true, title: String(format: L.t("uninstalled"), "Figma"),
                                  detail: String(format: L.t("uninstalledSize"), L.human(kb: leftovers.reduce(0) { $0 + $1.kb })))
        })
        s.append(window("carte-dossier-perso") { h in
            h.current = "diskmap"
            h.diskMap.load()
        })
        s.append(window("carte-sous-dossier") { h in
            h.current = "diskmap"
            let m = h.diskMap
            m.load()
            if let lib = m.entries.first { m.open(lib) }
        })
        s.append(window("carte-macintosh-hd") { h in
            h.current = "diskmap"
            h.diskMap.setRoot(true)
        })
        s.append(window("carte-calcul") { h in
            h.current = "diskmap"
            let m = h.diskMap
            m.load()
            m.entries = m.entries.enumerated().map { i, e in
                DiskEntry(url: e.url, name: e.name, size: i < 3 ? e.size : 0, isDir: e.isDir)
            }
            m.scanning = true
            m.done = 3
            m.total = 8
        })
        for t in ["maintenance", "privacy"] {
            let all = items(t)
            let fillCare: (CareModel) -> Void = { m in
                m.tasks = all.filter { $0.index > 0 }
                m.notes = all.filter { $0.index == 0 }
                m.selected = Set(m.tasks.filter { t == "maintenance" || $0.type != "cookies" }.map(\.index))
            }
            s.append(window("\(t)-chargement") { h in
                h.current = t
                let m = h.careModel(t)
                if t == "privacy" { m.tasks = Array(all.prefix(3)) }
                m.loading = true
            })
            s.append(window("\(t)-pret") { h in
                h.current = t
                fillCare(h.careModel(t))
            })
            s.append(window("\(t)-en-cours") { h in
                h.current = t
                let m = h.careModel(t)
                fillCare(m)
                let order = m.selected.sorted()
                m.states = Dictionary(uniqueKeysWithValues: order.enumerated().map { i, k in
                    (k, i == 0 ? "done" : (i == 1 ? (t == "maintenance" ? "failed" : "running") : (i == 2 && t == "maintenance" ? "running" : "waiting")))
                })
                m.working = true
            })
            s.append(window("\(t)-termine") { h in
                h.current = t
                let m = h.careModel(t)
                fillCare(m)
                m.states = Dictionary(uniqueKeysWithValues: m.selected.map { ($0, "done") })
                m.finished = true
                let kb = m.selectedKB
                m.result = ToolResult(ok: true, title: t == "maintenance" ? String(format: L.t("tasksDone"), m.selected.count)
                                      : String(format: L.t("erasedItems"), L.human(kb: kb), m.selected.count),
                                      detail: t == "maintenance" ? L.t("maintAfter") : "")
            })
        }
        s.append(window("privacy-erreur") { h in
            h.current = "privacy"
            let m = h.careModel("privacy")
            m.failed = true
            m.output = "rm: ~/Library/Safari/History.db: Operation not permitted"
            m.message = L.fr ? "Accès refusé à l'historique Safari." : "Permission denied on Safari history."
        })
        s.append(window("outil-dev-sans-unity") { h in
            h.current = "dev"
            let m = h.tool("dev")
            m.items = items("dev").filter { $0.type != "unity" }
            m.selected = Set(m.items.prefix(1).map(\.key))
        })
        s.append(window("outil-dev-unity-seul") { h in
            h.current = "dev"
            let m = h.tool("dev")
            m.items = items("dev").filter { $0.type == "unity" }
        })
        return s
    }
}
