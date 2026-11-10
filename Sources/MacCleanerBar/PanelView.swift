import AppKit
import SwiftUI

extension Color {
    static let accentBlue = Color(red: 0.09, green: 0.45, blue: 1.0)

    static func level(_ l: Int) -> Color { Color(nsColor: Model.nsColor(level: l)) }
}

struct Ring: View {
    let fraction: Double?
    let value: String
    let label: String
    var tint: Color = .accentBlue

    var body: some View {
        ZStack {
            Circle().stroke(Color.primary.opacity(0.12), lineWidth: 7)
            if let fraction {
                Circle()
                    .trim(from: 0, to: max(0.001, min(1, fraction)))
                    .stroke(tint, style: StrokeStyle(lineWidth: 7, lineCap: .round))
                    .rotationEffect(.degrees(-90))
            }
            VStack(spacing: 1) {
                Text(value).font(.system(size: 17, weight: .semibold, design: .rounded)).monospacedDigit()
                Text(label).font(.system(size: 10)).foregroundStyle(.secondary)
            }
        }
        .frame(width: 84, height: 84)
        .animation(.easeOut(duration: 0.4), value: fraction)
    }
}

struct Card<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        content
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(Color.primary.opacity(0.08)))
    }
}

struct PanelView: View {
    @ObservedObject var model: Model
    let openUninstaller: () -> Void

    private let shortcuts: [(String, String)] = [
        ("ram", "memorychip"), ("temp", "trash"), ("caches", "square.stack.3d.up"), ("trash", "xmark.bin"),
    ]
    private let tools: [(String, String)] = [
        ("uninstall", "xmark.app"), ("large", "doc.richtext"), ("downloads", "arrow.down.circle"),
        ("duplicates", "doc.on.doc"), ("startup", "power"), ("dev", "chevron.left.forwardslash.chevron.right"),
        ("system", "gearshape.2"),
    ]

    var body: some View {
        VStack(spacing: 14) {
            Text("Mac Cleaner").font(.system(size: 20, weight: .bold, design: .rounded))
            if model.cliPath == nil { missingView }
            rings
            if model.phase == .idle {
                shortcutsGrid
                cleanAllButton
                toolsGrid
            } else {
                runView
            }
            Divider().opacity(0.5)
            footer
        }
        .padding(16)
        .frame(width: 360)
        .background(.ultraThinMaterial)
        .onAppear { model.panelOpened() }
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
        .background(Color.orange.opacity(0.15), in: RoundedRectangle(cornerRadius: 8))
    }

    private var heatNote: (String, Int)? {
        guard let t = model.sensors.temperature else { return nil }
        let l = Model.heatLevel(t)
        return ([L.t("heatNormal"), L.t("heatHigh"), L.t("heatHot")][l], l)
    }

    private var rings: some View {
        HStack(alignment: .top, spacing: 0) {
            VStack(spacing: 6) {
                Ring(fraction: Double(model.diskUsedPct) / 100, value: "\(model.diskUsedPct) %", label: L.t("disk"),
                     tint: model.diskUsedPct >= 85 ? .level(Model.level(pct: model.diskUsedPct)) : .accentBlue)
                Text(String(format: L.t("freeDisk"), model.freeLabel))
                    .font(.caption).foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity)
            VStack(spacing: 6) {
                Ring(fraction: Double(model.memUsedPct) / 100, value: "\(model.memUsedPct) %", label: L.t("memory"),
                     tint: model.memUsedPct >= 85 ? .level(2) : .accentBlue)
                Text(String(format: L.t("ramUsed"), model.memUsedPct))
                    .font(.caption).foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity)
            VStack(spacing: 6) {
                let t = model.sensors.temperature
                Ring(fraction: t.map { $0 / 100 }, value: t.map { String(format: "%.0f °C", $0) } ?? "—",
                     label: L.t("heat"), tint: t.map { Model.heatLevel($0) > 0 ? .level(Model.heatLevel($0)) : .accentBlue } ?? .accentBlue)
                if let (note, l) = heatNote {
                    Text(note).font(.caption.weight(.semibold)).foregroundStyle(Color.level(l))
                }
                if let n = model.sensors.fanCount {
                    Text(L.fans(n, rpm: model.sensors.fanRPM))
                        .font(.system(size: 10)).foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .frame(maxWidth: .infinity)
        }
    }

    private func subtitle(_ key: String) -> String? {
        if key == "ram" { return model.purging ? L.t("running") : String(format: L.t("ramUsed"), model.memUsedPct) }
        if let kb = model.estimates[key] { return L.human(kb: kb) }
        if model.estimating.contains(key) { return L.t("estimating") }
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
                Image(systemName: icon)
                    .font(.system(size: 14, weight: .medium))
                    .frame(width: 30, height: 30)
                    .background(Color.primary.opacity(0.08), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
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
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 11)
                .background(Color.accentBlue, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(model.busy || model.cliPath == nil)
        .opacity(model.busy || model.cliPath == nil ? 0.5 : 1)
    }

    private var toolsGrid: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(L.t("tools")).font(.system(size: 12, weight: .semibold)).foregroundStyle(.secondary)
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 4), count: 4), spacing: 10) {
                ForEach(tools, id: \.0) { item in
                    Button {
                        if item.0 == "uninstall" { openUninstaller() } else { model.openInTerminal(item.0) }
                    } label: {
                        VStack(spacing: 5) {
                            Image(systemName: item.1)
                                .font(.system(size: 15))
                                .foregroundStyle(Color.accentBlue)
                                .frame(width: 38, height: 38)
                                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
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
                    .disabled(model.busy || model.cliPath == nil)
                }
            }
        }
    }

    private var runTitle: String {
        switch model.phase {
        case .previewing(let c), .previewReady(let c): return "\(L.t("preview")) · \(L.t(c))"
        case .cleaning(let c): return "\(L.t(c)) · \(L.t("running"))"
        case .cleaned(let c): return c.isEmpty ? "Mac Cleaner" : "\(L.t(c)) · \(L.t("done"))"
        case .idle: return ""
        }
    }

    private var runView: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(runTitle).font(.system(size: 13, weight: .semibold))
                Spacer()
                if model.busy { ProgressView().controlSize(.small) }
            }
            ScrollViewReader { proxy in
                ScrollView {
                    Text(model.output.isEmpty ? (model.busy ? L.t("running") : L.t("noOutput")) : model.output)
                        .font(.system(size: 10, design: .monospaced))
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(8)
                    Color.clear.frame(height: 1).id("end")
                }
                .frame(height: 260)
                .background(Color.black.opacity(0.25), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                .onChange(of: model.output) { _ in proxy.scrollTo("end", anchor: .bottom) }
            }
            if !model.busy && model.exitStatus != 0 {
                Text(String(format: L.t("exitCode"), model.exitStatus)).font(.caption).foregroundStyle(.red)
            }
            HStack {
                Spacer()
                switch model.phase {
                case .previewReady:
                    Button(L.t("cancel")) { model.dismiss() }
                    Button(L.t("clean")) { model.clean() }
                        .keyboardShortcut(.defaultAction)
                        .tint(.accentBlue)
                        .disabled(model.exitStatus != 0)
                case .cleaned:
                    Button(L.t("close")) { model.dismiss() }.keyboardShortcut(.defaultAction)
                default:
                    Button(L.t("cancel")) {}.disabled(true)
                }
            }
            .controlSize(.large)
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
                Button(L.t("menu")) { model.openInTerminal(nil) }
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
