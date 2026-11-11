import AppKit
import SwiftUI

struct Ring: View {
    let fraction: Double?
    let value: String
    let label: String
    var tint: Color = Theme.accent
    var size: CGFloat = 88

    var body: some View {
        ZStack {
            Circle().stroke(Theme.track, lineWidth: size * 0.1)
            if let fraction {
                Circle()
                    .trim(from: 0, to: max(0.001, min(1, fraction)))
                    .stroke(tint, style: StrokeStyle(lineWidth: size * 0.1, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                    .shadow(color: tint.opacity(0.45), radius: 4)
            }
            VStack(spacing: 0) {
                Text(label).font(.system(size: size * 0.12)).foregroundStyle(.secondary)
                Text(value).font(.system(size: size * 0.2, weight: .bold, design: .rounded)).monospacedDigit()
                    .lineLimit(1).minimumScaleFactor(0.7)
            }
            .padding(.horizontal, size * 0.14)
        }
        .frame(width: size, height: size)
        .animation(.easeOut(duration: 0.4), value: fraction)
    }
}

struct Card<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        content.themeCard()
    }
}

struct PanelView: View {
    @ObservedObject var model: Model
    let openTool: (String) -> Void

    private let shortcuts: [(String, String)] = [
        ("ram", "memorychip"), ("temp", "trash"), ("caches", "square.stack.3d.up"), ("trash", "xmark.bin"),
    ]
    private var tools: [(String, String)] { Catalog.tools }

    var body: some View {
        VStack(spacing: 14) {
            Text("Mac Cleaner").font(.system(size: 22, weight: .bold, design: .rounded))
            if !model.fullDiskAccess { accessLine }
            if model.cliPath == nil { missingView }
            rings
            if model.phase == .idle {
                activitySection
                NetworkCard(net: NetworkMonitor.shared, compact: true)
                shortcutsGrid
                cleanAllButton
                toolsGrid
            } else {
                PreviewSheet(model: model)
            }
            Rectangle().fill(Theme.divider).frame(height: 1)
            footer
        }
        .padding(16)
        .frame(width: 360)
        .background(Theme.background)
        .background(WindowReader { model.attachPanel($0) })
        .onAppear { model.panelOpened() }
        .onDisappear { NetworkMonitor.shared.release("panel") }
    }

    @ViewBuilder
    private var accessLine: some View {
        if model.accessRequested {
            HStack(spacing: 6) {
                Image(systemName: "lock.shield")
                Text(L.t("fdaRelaunch")).lineLimit(2).fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 4)
                Button(L.t("relaunch")) { model.relaunch() }
                    .buttonStyle(.plain)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Theme.accent)
                Button { model.openFullDiskAccess() } label: {
                    Image(systemName: "arrow.up.right").font(.system(size: 9, weight: .semibold))
                }
                .buttonStyle(.plain)
                .help(L.t("fda"))
            }
            .font(.system(size: 11))
            .foregroundStyle(.secondary)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .themeCard(8)
        } else {
            Button { model.openFullDiskAccess() } label: {
                HStack(spacing: 6) {
                    Image(systemName: "lock.shield")
                    Text(L.t("fda"))
                    Spacer(minLength: 0)
                    Image(systemName: "arrow.up.right").font(.system(size: 9, weight: .semibold))
                }
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .themeCard(8)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
    }

    @State private var usageMode = 0

    private var activitySection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Button { model.setActivityExpanded(!model.activityExpanded) } label: {
                HStack(spacing: 6) {
                    Text(L.t("activity")).font(.system(size: 12, weight: .semibold)).foregroundStyle(.secondary)
                    if !model.activityExpanded, let b = model.battery {
                        Image(systemName: batterySymbol(b)).font(.system(size: 11)).foregroundStyle(.secondary)
                        Text("\(b.charge) %").font(.system(size: 11)).foregroundStyle(.secondary).monospacedDigit()
                    }
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(.tertiary)
                        .rotationEffect(.degrees(model.activityExpanded ? 90 : 0))
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            if model.activityExpanded {
                if let b = model.battery { batteryRow(b) }
                Picker("", selection: $usageMode) {
                    Text(L.t("cpu")).tag(0)
                    Text(L.t("memory")).tag(1)
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .controlSize(.small)
                Card {
                    VStack(spacing: 0) {
                        let list = usageMode == 0 ? model.topCPU : model.topMemory
                        if list.isEmpty {
                            Text(L.t("measuring")).font(.system(size: 11)).foregroundStyle(.secondary)
                                .frame(maxWidth: .infinity, minHeight: 66)
                        } else {
                            ForEach(list) { usageRow($0) }
                        }
                    }
                    .padding(.vertical, 4)
                    .padding(.horizontal, 8)
                }
            }
        }
    }

    private func batterySymbol(_ b: BatteryInfo) -> String {
        if b.charging || b.onAC { return "battery.100.bolt" }
        switch b.charge {
        case ..<13: return "battery.0"
        case ..<38: return "battery.25"
        case ..<63: return "battery.50"
        case ..<88: return "battery.75"
        default: return "battery.100"
        }
    }

    private func batteryRow(_ b: BatteryInfo) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 6) {
                Image(systemName: batterySymbol(b))
                    .font(.system(size: 13))
                    .foregroundStyle(b.needsService ? Theme.warn : Theme.accent)
                Text("\(b.charge) %").font(.system(size: 12, weight: .semibold)).monospacedDigit()
                Text("·").foregroundStyle(.tertiary)
                Text(String(format: L.t("batteryLine"), b.health, b.cycles,
                            L.t(b.needsService ? "batteryService" : "batteryNormal")))
                    .font(.system(size: 11))
                    .foregroundStyle(b.needsService ? Theme.warn : Color.secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            if !b.onAC, let top = model.topCPU.first {
                Text(String(format: L.t("drains"), top.name))
                    .font(.system(size: 10.5)).foregroundStyle(.secondary).lineLimit(1)
            }
        }
    }

    private func usageRow(_ u: AppUsage) -> some View {
        HStack(spacing: 8) {
            if let icon = u.icon {
                Image(nsImage: icon).resizable().frame(width: 18, height: 18)
            } else {
                Image(systemName: "app").frame(width: 18, height: 18)
            }
            Text(u.name).font(.system(size: 12)).lineLimit(1).truncationMode(.tail)
            Spacer(minLength: 4)
            Text(usageMode == 0 ? L.pct(u.cpu ?? 0) : L.human(bytes: u.memory))
                .font(.system(size: 11)).foregroundStyle(.secondary).monospacedDigit()
            if u.canQuit {
                Button(L.t("quitApp")) { model.quitApp(u) }
                    .buttonStyle(.plain)
                    .font(.system(size: 10.5, weight: .medium))
                    .foregroundStyle(Theme.accent)
            } else {
                Text(L.t("quitApp")).font(.system(size: 10.5, weight: .medium)).hidden()
            }
        }
        .frame(height: 22)
    }

    private var missingView: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(L.t("missing")).font(.callout)
            Text(Model.installHint)
                .font(.system(.caption, design: .monospaced))
                .textSelection(.enabled)
        }
        .padding(8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.warnFill, in: RoundedRectangle(cornerRadius: 8))
    }

    private var heatNote: (String, Int) {
        let l = model.heatLevel
        return (Heat.label(l), min(2, l))
    }

    private var heatHelp: String {
        let p = ChipProfile.current
        return String(format: L.t("heatHelp"), p.family, L.num(p.high, 0), L.deg(p.hot), Heat.label(Heat.level(model.thermalState)))
    }

    private var rings: some View {
        HStack(alignment: .top, spacing: 0) {
            VStack(spacing: 6) {
                Ring(fraction: Double(model.diskUsedPct) / 100, value: "\(model.diskUsedPct) %", label: L.t("disk"),
                     tint: model.diskUsedPct >= 85 ? .level(Model.level(pct: model.diskUsedPct)) : Theme.accent)
                Text(String(format: L.t("freeDisk"), model.freeLabel))
                    .font(.caption).foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity)
            VStack(spacing: 6) {
                Ring(fraction: Double(model.memUsedPct) / 100, value: "\(model.memUsedPct) %", label: L.t("memory"),
                     tint: model.memUsedPct >= 85 ? .level(2) : Theme.accent)
                Text(String(format: L.t("ramUsed"), model.memUsedPct))
                    .font(.caption).foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity)
            VStack(spacing: 6) {
                let t = model.sensors.temperature
                let (note, l) = heatNote
                Ring(fraction: t.map { $0 / ChipProfile.current.hot }, value: t.map { L.deg($0) } ?? "—",
                     label: L.t("heat"), tint: l > 0 ? .level(l) : Theme.accent)
                Text(note).font(.caption.weight(.semibold)).foregroundStyle(Color.level(l))
                if let n = model.sensors.fanCount {
                    Text(L.fans(n, rpm: model.sensors.fanRPM))
                        .font(.system(size: 10)).foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .frame(maxWidth: .infinity)
            .help(heatHelp)
        }
    }

    private func subtitle(_ key: String) -> String? {
        if key == "ram" { return model.purging ? L.t("running") : String(format: L.t("ramUsed"), model.memUsedPct) }
        if key == "trash" && model.trashUnreadable && !model.estimating.contains(key) { return "\u{2014}" }
        if model.estimating.contains(key) {
            let fresh = model.estimatedAt[key].map { Date().timeIntervalSince($0) < 600 } ?? false
            if !fresh || model.estimates[key] == nil { return L.t("estimating") }
        }
        if let kb = model.estimates[key] { return L.human(kb: kb) }
        return nil
    }

    private var shortcutsGrid: some View {
        VStack(spacing: 6) {
            LazyVGrid(columns: [GridItem(.flexible(), spacing: 8), GridItem(.flexible(), spacing: 8)], spacing: 8) {
                ForEach(shortcuts, id: \.0) { item in
                    Button {
                        if item.0 == "ram" { model.freeRAM() } else { model.preview(item.0) }
                    } label: {
                        shortcutLabel(item.0, icon: item.1)
                    }
                    .buttonStyle(.plain)
                    .help(item.0 == "trash" && model.trashUnreadable ? L.t("fda") : "")
                    .disabled(model.busy || (item.0 != "ram" && model.cliPath == nil))
                }
            }
            if let notice = model.notice {
                Text(notice).font(.caption).foregroundStyle(.secondary)
            }
        }
    }

    private func shortcutLabel(_ key: String, icon: String) -> some View {
        Card {
            HStack(spacing: 8) {
                IconTile(symbol: icon, size: 32, font: 15)
                VStack(alignment: .leading, spacing: 2) {
                    Text(L.t(key)).font(.system(size: 12, weight: .semibold)).lineLimit(1).minimumScaleFactor(0.75)
                    Text(subtitle(key) ?? " ").font(.system(size: 11)).foregroundStyle(.secondary).monospacedDigit()
                }
                .layoutPriority(1)
                Spacer(minLength: 0)
                Image(systemName: "chevron.right").font(.system(size: 9, weight: .semibold)).foregroundStyle(.tertiary)
            }
            .padding(.vertical, 10)
            .padding(.horizontal, 8)
            .contentShape(Rectangle())
        }
    }

    private var cleanAllButton: some View {
        Button { model.preview("auto") } label: {
            Text(L.t("auto"))
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(Theme.onAccent)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
                .background(Theme.button, in: RoundedRectangle(cornerRadius: 13, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 13, style: .continuous).stroke(Color.white.opacity(0.18), lineWidth: 1))
                .shadow(color: Theme.accent.opacity(0.35), radius: 8, y: 3)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(model.busy || model.cliPath == nil)
        .opacity(model.busy || model.cliPath == nil ? 0.5 : 1)
    }

    private var toolsGrid: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(L.t("tools")).font(.system(size: 12, weight: .semibold)).foregroundStyle(.secondary)
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 4, alignment: .top), count: 4), spacing: 10) {
                ForEach(tools, id: \.0) { item in
                    Button {
                        openTool(item.0)
                    } label: {
                        VStack(spacing: 5) {
                            IconTile(symbol: item.1, size: 40, font: 16)
                            Text(L.t(item.0))
                                .font(.system(size: 9.5))
                                .multilineTextAlignment(.center)
                                .lineLimit(2)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        .frame(maxWidth: .infinity)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .disabled(item.0 != "diskmap" && (model.busy || model.cliPath == nil))
                }
            }
        }
    }

    private var footer: some View {
        HStack {
            Text(String(format: L.t("freedMonth"), L.human(kb: model.freedMonth)))
                .font(.system(size: 12)).foregroundStyle(.secondary)
            Spacer()
            Menu {
                Toggle(L.t("login"), isOn: Binding(
                    get: { model.launchAtLogin },
                    set: { model.setLaunchAtLogin($0) }
                ))
                Toggle(L.t("alerts"), isOn: Binding(
                    get: { model.alertsEnabled },
                    set: { model.setAlerts($0) }
                ))
                Toggle(L.t("weekly"), isOn: Binding(
                    get: { model.weeklyEnabled },
                    set: { model.setWeekly($0) }
                ))
                .disabled(model.cliPath == nil)
                Divider()
                Button(L.t("quit")) { NSApplication.shared.terminate(nil) }
                    .keyboardShortcut("q")
            } label: {
                Image(systemName: "gearshape").font(.system(size: 15))
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()
        }
    }
}
