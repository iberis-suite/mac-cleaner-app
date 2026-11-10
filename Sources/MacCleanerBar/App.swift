import AppKit
import Combine
import SwiftUI

enum Catalog {
    static let tools: [(String, String)] = [
        ("uninstall", "xmark.app"), ("large", "doc.richtext"), ("downloads", "arrow.down.circle"),
        ("duplicates", "doc.on.doc"), ("startup", "power"), ("dev", "chevron.left.forwardslash.chevron.right"),
        ("cachesAdv", "square.stack.3d.down.right"), ("system", "gearshape.2"),
        ("diskmap", "chart.pie"), ("maintenance", "wrench.and.screwdriver"), ("privacy", "hand.raised"),
    ]

    static let groups: [(String, [String])] = [
        ("groupClean", ["large", "downloads", "duplicates", "cachesAdv", "dev", "system"]),
        ("groupApps", ["uninstall", "startup"]),
        ("groupDisk", ["diskmap"]),
        ("groupCare", ["maintenance", "privacy"]),
    ]

    static func icon(_ tool: String) -> String {
        tools.first { $0.0 == tool }?.1 ?? "house"
    }
}

@MainActor
final class Hub: ObservableObject {
    static let shared = Hub()

    @Published var current = "home"
    var cliPath: String?
    var onChange: () -> Void = {}
    private(set) var tools: [String: ToolModel] = [:]
    private(set) var care: [String: CareModel] = [:]
    private var uninstallModel: UninstallModel?
    private var diskMapModel: DiskMapModel?
    weak var window: NSWindow?
    private var relays: [AnyCancellable] = []

    private func relay<M: ObservableObject>(_ m: M) where M.ObjectWillChangePublisher == ObservableObjectPublisher {
        relays.append(m.objectWillChange.sink { [weak self] _ in self?.objectWillChange.send() })
    }

    func tool(_ t: String) -> ToolModel {
        if let m = tools[t] { return m }
        let m = ToolModel(tool: t, cliPath: cliPath)
        m.onChange = { [weak self] in self?.onChange() }
        relay(m)
        tools[t] = m
        return m
    }

    func careModel(_ t: String) -> CareModel {
        if let m = care[t] { return m }
        let m = CareModel(tool: t, cliPath: cliPath)
        m.onChange = { [weak self] in self?.onChange() }
        relay(m)
        care[t] = m
        return m
    }

    var uninstall: UninstallModel {
        if let m = uninstallModel { return m }
        let m = UninstallModel(cliPath: cliPath)
        m.onChange = { [weak self] in self?.onChange() }
        relay(m)
        uninstallModel = m
        return m
    }

    var diskMap: DiskMapModel {
        if let m = diskMapModel { return m }
        let m = DiskMapModel()
        relay(m)
        diskMapModel = m
        return m
    }

    func select(_ t: String) {
        current = t
        appear(t)
    }

    func appear(_ t: String) {
        switch t {
        case "home": break
        case "uninstall": if !uninstall.working && uninstall.selected == nil { uninstall.reload() }
        case "diskmap": diskMap.appear()
        case "maintenance", "privacy": careModel(t).appear()
        default: tool(t).appear()
        }
    }

    func busy(_ t: String) -> Bool {
        switch t {
        case "uninstall": return uninstallModel.map { $0.working || $0.loading } ?? false
        case "diskmap": return diskMapModel?.scanning ?? false
        case "maintenance", "privacy": return care[t].map { $0.working || $0.loading } ?? false
        default: return tools[t]?.busy ?? false
        }
    }

    func back() -> Bool {
        switch current {
        case "home": return false
        case "uninstall": return uninstall.back()
        case "diskmap": return diskMap.back()
        case "maintenance", "privacy": return careModel(current).back()
        default: return tool(current).back()
        }
    }

    func escape() {
        if back() { return }
        if current != "home" {
            current = "home"
        } else {
            window?.performClose(nil)
        }
    }

    func stopAll() {
        tools.values.forEach { $0.stop() }
        care.values.forEach { $0.stop() }
        uninstallModel?.stop()
        diskMapModel?.stop()
    }

    var showing: Bool { window?.isVisible == true && NSApp.isActive }

    static func finished(_ tool: String, ok: Bool) {
        let hub = Hub.shared
        if hub.showing && hub.current == tool { return }
        AlertCenter.shared.notify(title: String(format: L.t(ok ? "notifyDone" : "notifyFailed"), L.t(tool)),
                                  body: L.t("notifyOpen"), tool: tool)
    }
}

struct MainView: View {
    @ObservedObject var hub: Hub

    var body: some View {
        HStack(spacing: 0) {
            sidebar
            Divider()
            detail
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(minWidth: MainWindow.size.width, minHeight: MainWindow.size.height)
        .background(Color(nsColor: .windowBackgroundColor))
        .background(
            Button("") { hub.escape() }
                .keyboardShortcut(.cancelAction)
                .opacity(0)
                .frame(width: 0, height: 0)
        )
    }

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 2) {
            Color.clear.frame(height: 30)
            sidebarRow("home", icon: "house", title: L.t("home"))
            ForEach(Catalog.groups, id: \.0) { group in
                Text(L.t(group.0)).font(.system(size: 10.5, weight: .semibold)).foregroundStyle(.secondary)
                    .padding(.horizontal, 10).padding(.top, 10).padding(.bottom, 2)
                ForEach(group.1, id: \.self) { t in sidebarRow(t, icon: Catalog.icon(t), title: L.t(t)) }
            }
            Spacer()
        }
        .padding(.horizontal, 10)
        .padding(.bottom, 12)
        .frame(width: 210)
        .frame(maxHeight: .infinity)
        .background(Color.primary.opacity(0.035))
    }

    private func sidebarRow(_ t: String, icon: String, title: String) -> some View {
        let on = hub.current == t
        return Button { hub.select(t) } label: {
            HStack(spacing: 8) {
                Image(systemName: icon).font(.system(size: 12)).frame(width: 18)
                    .foregroundStyle(on ? Color.white : Color.accentBlue)
                Text(title).font(.system(size: 12.5)).lineLimit(1).minimumScaleFactor(0.8)
                Spacer(minLength: 4)
                if hub.busy(t) { ProgressView().controlSize(.mini) }
            }
            .foregroundStyle(on ? Color.white : Color.primary)
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .background(on ? Color.accentBlue : Color.clear, in: RoundedRectangle(cornerRadius: 7, style: .continuous))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private var detail: some View {
        let home = { hub.current = "home" }
        switch hub.current {
        case "home": HomeView(hub: hub)
        case "uninstall": UninstallView(model: hub.uninstall, home: home)
        case "diskmap": DiskMapView(model: hub.diskMap, home: home)
        case "maintenance", "privacy": CareView(model: hub.careModel(hub.current), home: home).id(hub.current)
        default: ToolView(model: hub.tool(hub.current), home: home).id(hub.current)
        }
    }
}

struct HomeView: View {
    @ObservedObject var hub: Hub

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Color.clear.frame(height: 18)
            Text("Mac Cleaner").font(.system(size: 20, weight: .bold, design: .rounded))
            Text(L.t("chooseTool")).font(.system(size: 12)).foregroundStyle(.secondary)
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    ForEach(Catalog.groups, id: \.0) { group in
                        Text(L.t(group.0)).font(.system(size: 11, weight: .semibold)).foregroundStyle(.secondary)
                        LazyVGrid(columns: [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)], spacing: 10) {
                            ForEach(group.1, id: \.self) { card($0) }
                        }
                    }
                }
            }
        }
        .padding(20)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private func card(_ t: String) -> some View {
        Button { hub.select(t) } label: {
            Card {
                HStack(spacing: 10) {
                    Image(systemName: Catalog.icon(t)).font(.system(size: 15)).foregroundStyle(Color.accentBlue)
                        .frame(width: 34, height: 34)
                        .background(Color.primary.opacity(0.07), in: RoundedRectangle(cornerRadius: 9, style: .continuous))
                    VStack(alignment: .leading, spacing: 2) {
                        Text(L.t(t)).font(.system(size: 12.5, weight: .semibold)).lineLimit(1)
                        Text(L.t("desc_" + t)).font(.system(size: 11)).foregroundStyle(.secondary).lineLimit(1)
                    }
                    Spacer(minLength: 0)
                    if hub.busy(t) { ProgressView().controlSize(.mini) }
                }
                .padding(10)
                .contentShape(Rectangle())
            }
        }
        .buttonStyle(.plain)
    }
}

@MainActor
final class MainWindow: NSObject, NSWindowDelegate {
    static let shared = MainWindow()
    static let size = NSSize(width: 760, height: 660)
    static let autosave = "MacCleanerMain"
    private var window: NSWindow?

    func show(_ tool: String, model: Model) {
        let hub = Hub.shared
        hub.cliPath = model.cliPath
        hub.onChange = { [weak model] in
            model?.refresh()
            model?.refreshEstimates(force: true)
        }
        model.panelWindow?.orderOut(nil)
        let w = window ?? make(hub)
        hub.select(tool)
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
        w.makeKeyAndOrderFront(nil)
    }

    private func make(_ hub: Hub) -> NSWindow {
        let w = NSWindow(contentRect: NSRect(origin: .zero, size: MainWindow.size),
                         styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
                         backing: .buffered, defer: false)
        w.title = "Mac Cleaner"
        w.titlebarAppearsTransparent = true
        w.titleVisibility = .hidden
        w.isReleasedWhenClosed = false
        w.minSize = MainWindow.size
        w.delegate = self
        w.contentView = NSHostingView(rootView: MainView(hub: hub))
        let saved = UserDefaults.standard.string(forKey: "NSWindow Frame \(MainWindow.autosave)") != nil
        w.setFrameAutosaveName(MainWindow.autosave)
        if !saved { MainWindow.center(w) }
        hub.window = w
        window = w
        return w
    }

    static func center(_ w: NSWindow) {
        let mouse = NSEvent.mouseLocation
        guard let screen = NSScreen.screens.first(where: { NSMouseInRect(mouse, $0.frame, false) }) ?? NSScreen.main else { return }
        let v = screen.visibleFrame
        let f = w.frame
        w.setFrameOrigin(NSPoint(x: v.midX - f.width / 2, y: v.midY - f.height / 2))
    }

    func windowWillClose(_ notification: Notification) {
        Hub.shared.stopAll()
        NSApp.setActivationPolicy(.accessory)
    }
}

@MainActor
enum Windows {
    static func open(_ tool: String, model: Model) {
        MainWindow.shared.show(tool, model: model)
    }
}

@main
struct MacCleanerBarApp: App {
    @StateObject private var model = Model()

    init() {
        if let dir = Snapshots.requestedDirectory {
            DispatchQueue.main.async { Snapshots.run(into: dir) }
        }
    }

    var body: some Scene {
        MenuBarExtra {
            PanelView(model: model) { Windows.open($0, model: model) }
        } label: {
            HStack(spacing: 3) {
                Image(nsImage: model.statusIcon)
                Text(model.freeLabel)
            }
        }
        .menuBarExtraStyle(.window)
    }
}
