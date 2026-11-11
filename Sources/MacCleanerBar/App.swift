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
    @ObservedObject var model: Model

    var body: some View {
        HStack(spacing: 0) {
            sidebar
            Rectangle().fill(Theme.divider).frame(width: 1)
            detail
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(minWidth: MainWindow.size.width, minHeight: MainWindow.size.height)
        .background(Theme.background)
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
            sidebarRow("home", icon: "square.grid.2x2", title: L.t("home"))
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
        .background(Theme.sidebar)
    }

    private func sidebarRow(_ t: String, icon: String, title: String) -> some View {
        let on = hub.current == t
        return Button { hub.select(t) } label: {
            HStack(spacing: 8) {
                Image(systemName: icon).font(.system(size: 12)).frame(width: 18)
                    .foregroundStyle(on ? Theme.onAccent : Theme.accent)
                Text(title).font(.system(size: 12.5)).lineLimit(1).minimumScaleFactor(0.8)
                Spacer(minLength: 4)
                if hub.busy(t) { ProgressView().controlSize(.mini) }
            }
            .foregroundStyle(on ? Theme.onAccent : Color.primary)
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .background(on ? AnyShapeStyle(Theme.button) : AnyShapeStyle(Color.clear), in: RoundedRectangle(cornerRadius: 7, style: .continuous))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private var detail: some View {
        let home = { hub.current = "home" }
        switch hub.current {
        case "home": DashboardView(hub: hub, model: model)
        case "uninstall": UninstallView(model: hub.uninstall, home: home)
        case "diskmap": DiskMapView(model: hub.diskMap, home: home)
        case "maintenance", "privacy": CareView(model: hub.careModel(hub.current), home: home).id(hub.current)
        default: ToolView(model: hub.tool(hub.current), home: home).id(hub.current)
        }
    }
}

struct DashboardView: View {
    @ObservedObject var hub: Hub
    @ObservedObject var model: Model
    @ObservedObject var net = NetworkMonitor.shared

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                Color.clear.frame(height: 12)
                VStack(alignment: .leading, spacing: 2) {
                    Text(L.t("dashboard")).font(.system(size: 22, weight: .bold, design: .rounded))
                    Text(L.t("chooseTool")).font(.system(size: 11)).foregroundStyle(.secondary)
                }
                HStack(spacing: 10) {
                    ringCard(Ring(fraction: Double(model.diskUsedPct) / 100, value: "\(model.diskUsedPct) %", label: L.t("disk"),
                                  tint: model.diskUsedPct >= 85 ? .level(Model.level(pct: model.diskUsedPct)) : Theme.accent, size: 92),
                             lines: [String(format: L.t("freeDisk"), model.freeLabel),
                                     String(format: L.t("ofTotal"), L.human(bytes: model.diskTotal))])
                    ringCard(Ring(fraction: Double(model.memUsedPct) / 100, value: "\(model.memUsedPct) %", label: L.t("memory"),
                                  tint: model.memUsedPct >= 85 ? .level(2) : Theme.accent, size: 92),
                             lines: [String(format: L.t("ramUsed"), model.memUsedPct), " "])
                    let t = model.sensors.temperature
                    let l = min(2, model.heatLevel)
                    ringCard(Ring(fraction: t.map { $0 / ChipProfile.current.hot }, value: t.map { L.deg($0) } ?? "—", label: L.t("heat"),
                                  tint: l > 0 ? .level(l) : Theme.accent, size: 92),
                             lines: [Heat.label(model.heatLevel), model.sensors.fanCount.map { L.fans($0, rpm: model.sensors.fanRPM) } ?? " "],
                             firstColor: Color.level(l))
                }
                NetworkCard(net: net)
                HStack(alignment: .top, spacing: 10) {
                    VStack(spacing: 10) {
                        freedCard
                        if let b = model.battery { batteryCard(b) }
                    }
                    VStack(spacing: 10) {
                        estimatesCard
                        weeklyCard
                    }
                }
                historyCard
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 20)
        }
        .onAppear {
            model.refresh()
            model.refreshEstimates(force: false)
            net.retain("dashboard")
        }
        .onDisappear { net.release("dashboard") }
    }

    private func ringCard(_ ring: Ring, lines: [String], firstColor: Color = .secondary) -> some View {
        VStack(spacing: 6) {
            ring
            Text(lines[0]).font(.system(size: 11.5, weight: .medium)).foregroundStyle(firstColor).lineLimit(1)
            Text(lines[1]).font(.system(size: 10.5)).foregroundStyle(.secondary).lineLimit(1).minimumScaleFactor(0.8)
        }
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity)
        .themeCard(14)
    }

    private func cardTitle(_ text: String, symbol: String) -> some View {
        HStack(spacing: 8) {
            IconTile(symbol: symbol, size: 26, font: 12)
            Text(text).font(.system(size: 12.5, weight: .semibold))
            Spacer(minLength: 0)
        }
    }

    private var freedCard: some View {
        VStack(alignment: .leading, spacing: 6) {
            cardTitle(L.t("freedTitle"), symbol: "sparkles")
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(L.human(kb: model.freedMonth)).font(.system(size: 26, weight: .bold, design: .rounded)).monospacedDigit()
                Text(L.t("thisMonth")).font(.system(size: 11)).foregroundStyle(.secondary)
            }
            Text(String(format: L.t("freedAll"), L.human(kb: model.freedTotal))).font(.system(size: 11)).foregroundStyle(.secondary)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .themeCard(14)
    }

    private var estimatesCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            cardTitle(L.t("toClean"), symbol: "wand.and.stars")
            ForEach(["temp", "caches", "trash"], id: \.self) { c in
                HStack(spacing: 8) {
                    Image(systemName: ItemStyle.command(c)).font(.system(size: 12)).foregroundStyle(Theme.accent).frame(width: 18)
                    Text(L.t(c)).font(.system(size: 12))
                    Spacer()
                    Text(estimate(c)).font(.system(size: 12, weight: .semibold)).monospacedDigit()
                    Button(L.t("open")) { model.openPanelPreview(c) }
                        .buttonStyle(.plain)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(Theme.accent)
                        .disabled(model.busy || model.cliPath == nil)
                }
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .themeCard(14)
    }

    private func estimate(_ c: String) -> String {
        if c == "trash" && model.trashUnreadable { return "\u{2014}" }
        if let kb = model.estimates[c] { return L.human(kb: kb) }
        return model.estimating.contains(c) ? L.t("estimating") : "\u{2014}"
    }

    private func batteryCard(_ b: BatteryInfo) -> some View {
        HStack(spacing: 10) {
            IconTile(symbol: b.charging || b.onAC ? "battery.100.bolt" : "battery.75", size: 34, font: 14)
            VStack(alignment: .leading, spacing: 2) {
                Text("\(L.t("battery")) · \(b.charge) %").font(.system(size: 12.5, weight: .semibold)).monospacedDigit()
                Text(String(format: L.t("batteryLine"), b.health, b.cycles, L.t(b.needsService ? "batteryService" : "batteryNormal")))
                    .font(.system(size: 11)).foregroundStyle(b.needsService ? Theme.warn : Color.secondary)
                    .lineLimit(2).fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 9)
        .themeCard()
    }

    private var weeklyCard: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                cardTitle(L.t("weekly"), symbol: "calendar.badge.clock")
                Toggle("", isOn: Binding(get: { model.weeklyEnabled }, set: { model.setWeekly($0) }))
                    .toggleStyle(.switch).controlSize(.mini).labelsHidden()
                    .disabled(model.cliPath == nil)
            }
            if let next = model.weeklyNext {
                Text(String(format: L.t("nextRun"), DashboardView.dateTime(next))).font(.system(size: 11)).foregroundStyle(.secondary)
                if let last = model.weeklyLast {
                    Text(String(format: L.t("lastRun"), DashboardView.dateTime(last))).font(.system(size: 11)).foregroundStyle(.secondary)
                }
            } else {
                Text(L.t("weeklyOff")).font(.system(size: 11)).foregroundStyle(.secondary)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .themeCard(14)
    }

    private var historyCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            cardTitle(L.t("historyTitle"), symbol: "clock.arrow.circlepath")
            if model.history.isEmpty {
                Text(L.t("historyEmpty")).font(.system(size: 11.5)).foregroundStyle(.secondary).padding(.vertical, 6)
            } else {
                ForEach(model.history) { h in
                    HStack(spacing: 8) {
                        Image(systemName: h.symbol).font(.system(size: 11)).foregroundStyle(Theme.accent).frame(width: 18)
                        Text(h.title).font(.system(size: 12)).lineLimit(1)
                        if !h.note.isEmpty {
                            Text(h.note).font(.system(size: 10.5)).foregroundStyle(.secondary).lineLimit(1).truncationMode(.tail)
                        }
                        Spacer(minLength: 6)
                        Text(h.kb > 0 ? L.human(kb: h.kb) : "\u{2014}").font(.system(size: 11.5, weight: .semibold)).monospacedDigit()
                        Text(DashboardView.dateTime(h.date)).font(.system(size: 10.5)).foregroundStyle(.secondary).monospacedDigit()
                            .frame(width: 128, alignment: .trailing)
                    }
                }
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .themeCard(14)
    }

    static func dateTime(_ d: Date) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: L.fr ? "fr_FR" : "en_US")
        f.setLocalizedDateFormatFromTemplate("EEE d MMM HH:mm")
        return f.string(from: d)
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
        let w = window ?? make(hub, model: model)
        hub.select(tool)
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
        w.makeKeyAndOrderFront(nil)
    }

    private func make(_ hub: Hub, model: Model) -> NSWindow {
        let w = NSWindow(contentRect: NSRect(origin: .zero, size: MainWindow.size),
                         styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
                         backing: .buffered, defer: false)
        w.title = "Mac Cleaner"
        w.titlebarAppearsTransparent = true
        w.titleVisibility = .hidden
        w.isReleasedWhenClosed = false
        w.minSize = MainWindow.size
        w.delegate = self
        w.contentView = NSHostingView(rootView: MainView(hub: hub, model: model))
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
