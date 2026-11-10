import AppKit
import SwiftUI

struct PanelView: View {
    @ObservedObject var model: Model

    private let actions = ["auto", "caches", "temp", "trash"]
    private let advanced: [(String, String?)] = [("ram", "ram"), ("large", "large"), ("dev", "dev"), ("menu", nil)]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: "sparkles")
                Text("Mac Cleaner").font(.headline)
                Spacer()
            }
            if model.cliPath == nil {
                missingView
            }
            gauges
            Divider()
            if model.phase == .idle {
                actionsView
            } else {
                runView
            }
            Divider()
            historyView
            Divider()
            footer
        }
        .padding(14)
        .frame(width: 340)
        .onAppear { model.refresh() }
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
        .background(Color.orange.opacity(0.15))
        .cornerRadius(6)
    }

    private var gauges: some View {
        VStack(spacing: 8) {
            gauge(L.t("disk"), pct: model.diskUsedPct,
                  detail: "\(L.human(bytes: model.diskTotal - model.diskFree)) / \(L.human(bytes: model.diskTotal))")
            gauge(L.t("memory"), pct: model.memUsedPct,
                  detail: "\(model.memFreePct) % \(L.t("free"))")
        }
    }

    private func gauge(_ title: String, pct: Int, detail: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack {
                Text(title).font(.subheadline)
                Spacer()
                Text("\(pct) %").font(.subheadline.monospacedDigit()).bold()
            }
            ProgressView(value: Double(pct), total: 100)
                .tint(Color(nsColor: Model.color(for: pct)))
            Text(detail).font(.caption).foregroundColor(.secondary)
        }
    }

    private var actionsView: some View {
        VStack(alignment: .leading, spacing: 8) {
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 6) {
                ForEach(actions, id: \.self) { cmd in
                    Button { model.preview(cmd) } label: {
                        Text(L.t(cmd)).frame(maxWidth: .infinity)
                    }
                    .disabled(model.busy || model.cliPath == nil)
                }
            }
            Text(L.t("advanced")).font(.caption).foregroundColor(.secondary)
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 6) {
                ForEach(advanced, id: \.0) { item in
                    Button { model.openInTerminal(item.1) } label: {
                        Label(L.t(item.0), systemImage: "terminal").frame(maxWidth: .infinity)
                    }
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
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(runTitle).font(.subheadline).bold()
                Spacer()
                if model.busy { ProgressView().controlSize(.small) }
            }
            ScrollViewReader { proxy in
                ScrollView {
                    Text(model.output.isEmpty ? (model.busy ? L.t("running") : L.t("noOutput")) : model.output)
                        .font(.system(size: 10, design: .monospaced))
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(6)
                    Color.clear.frame(height: 1).id("end")
                }
                .frame(height: 200)
                .background(Color(nsColor: .textBackgroundColor))
                .cornerRadius(6)
                .onChange(of: model.output) { _ in proxy.scrollTo("end", anchor: .bottom) }
            }
            if !model.busy && model.exitStatus != 0 {
                Text(String(format: L.t("exitCode"), model.exitStatus)).font(.caption).foregroundColor(.red)
            }
            HStack {
                Spacer()
                switch model.phase {
                case .previewReady:
                    Button(L.t("cancel")) { model.dismiss() }
                    Button(L.t("clean")) { model.clean() }
                        .keyboardShortcut(.defaultAction)
                        .disabled(model.exitStatus != 0)
                case .cleaned:
                    Button(L.t("close")) { model.dismiss() }.keyboardShortcut(.defaultAction)
                default:
                    Button(L.t("cancel")) {}.disabled(true)
                }
            }
        }
    }

    private var historyView: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(L.t("history")).font(.subheadline).bold()
            if model.history.isEmpty {
                Text(L.t("noHistory")).font(.caption).foregroundColor(.secondary)
            } else {
                Text(String(format: L.t("freed30"), L.human(kb: model.freed30))).font(.caption)
                ForEach(model.history) { entry in
                    HStack {
                        Text(entry.label).font(.caption.monospacedDigit()).foregroundColor(.secondary)
                        Text(entry.action).font(.caption)
                        Spacer()
                        Text(L.human(kb: entry.kb)).font(.caption.monospacedDigit())
                    }
                }
            }
        }
    }

    private var footer: some View {
        HStack {
            Toggle(L.t("login"), isOn: Binding(
                get: { model.launchAtLogin },
                set: { model.setLaunchAtLogin($0) }
            ))
            .toggleStyle(.checkbox)
            .font(.caption)
            Spacer()
            Button(L.t("quit")) { NSApplication.shared.terminate(nil) }
                .keyboardShortcut("q")
        }
    }
}
