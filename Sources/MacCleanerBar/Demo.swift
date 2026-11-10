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
            r = [row(1, 320 * mb, "video.mp4", h("Documents/video.mp4"), "keep"),
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
            r = [row(1, 0, "Vider le cache DNS", "dscacheutil -flushcache; killall -HUP mDNSResponder", "dns", "root"),
                 row(2, 0, "Réindexer Spotlight", "mdutil -E /", "spotlight", "root"),
                 row(3, 0, "Reconstruire « Ouvrir avec »", "lsregister -kill -r", "launchservices", "user"),
                 row(0, 0, "Scripts périodiques", "periodic daily weekly monthly", "periodic", "root")]
        case "privacy":
            r = [row(1, 410 * mb, "Safari · Historique", h("Library/Safari/History.db"), "history", "safari"),
                 row(2, 220 * mb, "Chrome · Cache", h("Library/Caches/Google/Chrome"), "cache", "chrome")]
        default:
            r = []
        }
        return r.joined(separator: "\n")
    }

    static func dryRun(_ cmd: String) -> String {
        switch cmd {
        case "system":
            return L.fr
                ? "Système — aperçu\n  Snapshots Time Machine locaux     2   6,2 Go\n  Binaires universels (amincir)   14   1,1 Go\n  Total estimé : 7,3 Go\n  Rien n'a été fait."
                : "System — preview\n  Local Time Machine snapshots      2   6.2 GB\n  Universal binaries (thin)        14   1.1 GB\n  Estimated total: 7.3 GB\n  Nothing was done."
        case "privacy":
            return L.fr
                ? "Confidentialité — aperçu\n  Safari   Historique   410 Mo\n  Chrome   Cache        220 Mo\n  Firefox  ouvert, ignoré\n  Total : 630 Mo"
                : "Privacy — preview\n  Safari   History   410 MB\n  Chrome   Cache     220 MB\n  Firefox  open, skipped\n  Total: 630 MB"
        case "maintenance":
            return L.fr
                ? "Entretien — aperçu\n  sudo dscacheutil -flushcache\n  sudo mdutil -E /\n  lsregister -kill -r -domain local -domain user"
                : "Maintenance — preview\n  sudo dscacheutil -flushcache\n  sudo mdutil -E /\n  lsregister -kill -r -domain local -domain user"
        default:
            let items = ToolItem.parseList(list(cmd)).filter { $0.index > 0 }
            let lines = items.map { "  ✓ \(L.human(kb: $0.kb).padding(toLength: 9, withPad: " ", startingAt: 0)) \($0.shortPath)" }
            let total = L.human(kb: items.reduce(0) { $0 + $1.kb })
            return ([L.fr ? "Aperçu — rien n'est supprimé" : "Preview — nothing is deleted"] + lines
                + [L.fr ? "Total : \(total)" : "Total: \(total)"]).joined(separator: "\n")
        }
    }

    static func yes(_ cmd: String) -> String {
        dryRun(cmd).replacingOccurrences(of: L.fr ? "Aperçu — rien n'est supprimé" : "Preview — nothing is deleted",
                                         with: L.fr ? "Fait (mode démo, rien n'a été touché)" : "Done (demo mode, nothing was touched)")
    }

    static func uninstall(_ path: String) -> String {
        let name = ((path as NSString).lastPathComponent as NSString).deletingPathExtension
        let id = "com.example." + name.lowercased()
        let rows = [("app", "412.0 MB", path), ("support", "96.4 MB", "~/Library/Application Support/\(name)"),
                    ("cache", "38.1 MB", "~/Library/Caches/\(id)"), ("prefs", "12.0 KB", "~/Library/Preferences/\(id).plist")]
        return rows.map { "  \($0.0)  \($0.1)  \($0.2)" }.joined(separator: "\n") + "\nTotal : 546.5 MB"
    }

    static func respond(_ args: [String]) -> (String, Int32) {
        guard let cmd = args.first else { return ("", 1) }
        if cmd == "uninstall", args.count > 1 {
            return args.contains("--yes") ? ("OK", 0) : (uninstall(args[1]), 0)
        }
        if args.contains("--list") { return (list(cmd), 0) }
        if args.contains("--yes") { return (yes(cmd), 0) }
        return (dryRun(cmd), 0)
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
            return AnyView(PanelView(model: m) { _ in }.background(Color(nsColor: .windowBackgroundColor)))
        }
    }

    private static func window(_ name: String, _ setup: @escaping (Hub) -> Void) -> Shot {
        Shot(name: name, window: true) {
            let hub = Hub()
            hub.cliPath = "demo"
            setup(hub)
            return AnyView(MainView(hub: hub))
        }
    }

    private static func items(_ cmd: String) -> [ToolItem] { ToolItem.parseList(Demo.list(cmd)) }

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
        for c in ["temp", "caches", "trash", "auto"] {
            let all = items(c)
            s.append(panel("apercu-\(c)-chargement") { m in m.phase = .previewing(c) })
            s.append(panel("apercu-\(c)-liste") { m in
                m.sheetItems = all
                m.sheetSelected = Set(Model.defaultSelection(all).map(\.index))
                m.phase = .previewReady(c)
            })
            s.append(panel("apercu-\(c)-en-cours") { m in
                m.output = Demo.yes(c).components(separatedBy: "\n").prefix(3).joined(separator: "\n")
                m.phase = .cleaning(c)
            })
            s.append(panel("apercu-\(c)-resultat") { m in
                let chosen = Model.defaultSelection(all)
                m.result = CleanResult(ok: true, freedKB: chosen.reduce(0) { $0 + $1.kb }, sections: chosen.map(\.label), message: "")
                m.output = Demo.yes(c)
                m.phase = .cleaned(c)
            })
            s.append(panel("apercu-\(c)-erreur") { m in
                m.sheetError = L.fr ? "Accès refusé : ~/Library/Caches (autoriser l'accès complet au disque)" : "Permission denied: ~/Library/Caches"
                m.exitStatus = 1
                m.phase = .previewReady(c)
            })
        }
        s.append(panel("apercu-trash-vide") { m in m.phase = .previewReady("trash") })
        s.append(window("fenetre-accueil") { _ in })
        for t in ["large", "downloads", "duplicates", "startup", "dev", "cachesAdv", "system"] {
            let cmd = t == "cachesAdv" ? "caches" : t
            let all = items(cmd)
            let fill: (ToolModel) -> Void = { m in
                if t == "system" {
                    m.output = Demo.dryRun("system")
                } else {
                    m.items = all.filter { $0.index > 0 }
                    m.skipped = all.filter { $0.index == 0 }
                    m.selected = Set(m.items.filter { $0.type != "keep" && $0.state != "excluded" }.prefix(t == "startup" ? 1 : 3).map(\.key))
                }
            }
            s.append(window("outil-\(t)-chargement") { h in
                h.current = t
                h.tool(t).listing = true
            })
            s.append(window("outil-\(t)-liste") { h in
                h.current = t
                fill(h.tool(t))
            })
            s.append(window("outil-\(t)-apercu") { h in
                h.current = t
                let m = h.tool(t)
                fill(m)
                m.stage = .preview
                if t != "system" { m.output = Demo.dryRun(cmd) }
                m.message = L.t("previewNote") + (m.needsSudo ? " " + L.t("sudoNote") : "")
            })
            s.append(window("outil-\(t)-en-cours") { h in
                h.current = t
                let m = h.tool(t)
                fill(m)
                m.stage = .working
                m.output = Demo.yes(cmd).components(separatedBy: "\n").prefix(3).joined(separator: "\n")
            })
            s.append(window("outil-\(t)-resultat") { h in
                h.current = t
                let m = h.tool(t)
                fill(m)
                m.selected = []
                m.stage = .done
                m.output = Demo.yes(cmd)
                m.message = L.t("doneNote")
            })
            s.append(window("outil-\(t)-vide") { h in
                h.current = t
                h.tool(t).items = []
            })
        }
        s.append(window("outil-large-erreur") { h in
            h.current = "large"
            let m = h.tool("large")
            m.failed = true
            m.output = "find: /Users/demo/Library/Mail: Operation not permitted\nmac-cleaner: accès refusé"
            m.message = L.fr ? "Accès refusé à certains dossiers." : "Permission denied on some folders."
        })
        s.append(window("desinstaller-liste") { h in
            h.current = "uninstall"
            h.uninstall.reload()
        })
        s.append(window("desinstaller-chargement") { h in
            h.current = "uninstall"
            let m = h.uninstall
            m.reload()
            m.selected = Demo.apps[2]
            m.loading = true
        })
        s.append(window("desinstaller-selection") { h in
            h.current = "uninstall"
            let m = h.uninstall
            m.reload()
            m.selected = Demo.apps[2]
            m.leftovers = [Leftover(path: "/Applications/Figma.app", size: L.human(kb: 412 * 1024)),
                           Leftover(path: "~/Library/Application Support/Figma", size: L.human(kb: 96 * 1024)),
                           Leftover(path: "~/Library/Caches/com.figma.Desktop", size: L.human(kb: 38 * 1024))]
            m.total = L.human(kb: 546 * 1024)
        })
        s.append(window("desinstaller-en-cours") { h in
            h.current = "uninstall"
            let m = h.uninstall
            m.reload()
            m.selected = Demo.apps[2]
            m.total = L.human(kb: 546 * 1024)
            m.working = true
        })
        s.append(window("desinstaller-resultat") { h in
            h.current = "uninstall"
            let m = h.uninstall
            m.reload()
            m.message = String(format: L.t("uninstalled"), "Figma")
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
            let fill: (CareModel) -> Void = { m in
                if t == "maintenance" {
                    m.tasks = items("maintenance")
                    m.selected = Set(m.tasks.filter { $0.index > 0 }.map(\.index))
                }
                m.output = Demo.dryRun(t)
                m.message = L.t("previewNote")
            }
            s.append(window("\(t)-chargement") { h in
                h.current = t
                let m = h.careModel(t)
                if t == "maintenance" { m.tasks = items("maintenance") }
                m.loading = true
            })
            s.append(window("\(t)-pret") { h in
                h.current = t
                fill(h.careModel(t))
            })
            s.append(window("\(t)-en-cours") { h in
                h.current = t
                let m = h.careModel(t)
                fill(m)
                m.message = nil
                m.working = true
            })
            s.append(window("\(t)-termine") { h in
                h.current = t
                let m = h.careModel(t)
                fill(m)
                m.finished = true
                m.message = L.t("done")
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
