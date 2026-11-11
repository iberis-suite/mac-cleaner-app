import AppKit
import SwiftUI

struct AppItem: Identifiable, Hashable {
    let path: String
    let name: String
    var id: String { path }
}

struct Leftover: Identifiable {
    let id = UUID()
    let path: String
    let kb: Double
    var type = "file"

    var shortPath: String {
        let home = NSHomeDirectory()
        return path.hasPrefix(home) ? "~" + path.dropFirst(home.count) : path
    }
}

@MainActor
final class UninstallModel: ObservableObject {
    @Published var apps: [AppItem] = []
    @Published var sizes: [String: Int64] = [:]
    @Published var query = ""
    @Published var selected: AppItem?
    @Published var leftovers: [Leftover] = []
    @Published var total: Double?
    @Published var loading = false
    @Published var working = false
    @Published var message: String?
    @Published var failed = false
    @Published var confirming = false
    @Published var lastOutput = ""
    @Published var result: ToolResult?

    let cliPath: String?
    private var run: CLIRun?
    private var sizeGeneration = 0
    var onChange: (() -> Void)?

    init(cliPath: String?) {
        self.cliPath = cliPath
    }

    var filtered: [AppItem] {
        let q = query.trimmingCharacters(in: .whitespaces)
        return q.isEmpty ? apps : apps.filter { $0.name.localizedCaseInsensitiveContains(q) }
    }

    func reload() {
        if Demo.enabled {
            apps = Demo.apps
            sizes = Demo.appSizes
            return
        }
        let fm = FileManager.default
        let dirs = ["/Applications", (NSHomeDirectory() as NSString).appendingPathComponent("Applications")]
        var found: [AppItem] = []
        for dir in dirs {
            guard let names = try? fm.contentsOfDirectory(atPath: dir) else { continue }
            for n in names where n.hasSuffix(".app") {
                let path = (dir as NSString).appendingPathComponent(n)
                let bid = Bundle(path: path)?.bundleIdentifier ?? ""
                if bid.hasPrefix("com.apple.") { continue }
                found.append(AppItem(path: path, name: (n as NSString).deletingPathExtension))
            }
        }
        apps = found.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        if let s = selected, !apps.contains(s) { clearSelection() }
        computeSizes()
    }

    private func computeSizes() {
        sizeGeneration += 1
        let gen = sizeGeneration
        let paths = apps.map(\.path).filter { sizes[$0] == nil }
        DispatchQueue.global(qos: .utility).async { [weak self] in
            for p in paths {
                let size = UninstallModel.allocatedSize(p)
                DispatchQueue.main.async {
                    guard let self, self.sizeGeneration == gen else { return }
                    self.sizes[p] = size
                }
            }
        }
    }

    nonisolated static func allocatedSize(_ path: String) -> Int64 {
        let keys: [URLResourceKey] = [.totalFileAllocatedSizeKey, .fileAllocatedSizeKey]
        guard let e = FileManager.default.enumerator(at: URL(fileURLWithPath: path), includingPropertiesForKeys: keys,
                                                     options: [], errorHandler: { _, _ in true }) else { return 0 }
        var total: Int64 = 0
        for case let url as URL in e {
            if let v = try? url.resourceValues(forKeys: Set(keys)) {
                total += Int64(v.totalFileAllocatedSize ?? v.fileAllocatedSize ?? 0)
            }
        }
        return total
    }

    func clearSelection() {
        run?.cancel()
        selected = nil
        leftovers = []
        total = nil
        loading = false
        failed = false
    }

    func select(_ app: AppItem) {
        guard !working, selected != app else { return }
        run?.cancel()
        result = nil
        selected = app
        leftovers = []
        total = nil
        message = nil
        failed = false
        guard let cli = cliPath else {
            message = L.t("missing") + " " + Model.installHint
            return
        }
        loading = true
        run = CLIRun.start(cli: cli, args: ["uninstall", app.path, "--list"], line: { [weak self] l in
            guard let self, self.selected == app, self.loading, let item = ToolItem.parse(l), item.index > 0 else { return }
            self.leftovers.append(Leftover(path: item.path, kb: item.kb, type: item.type))
        }) { [weak self] text, status in
            guard let self, self.selected == app, self.loading else { return }
            self.loading = false
            self.failed = status != 0
            self.lastOutput = text
            if status == 0 {
                self.total = self.leftovers.reduce(0) { $0 + $1.kb }
            } else {
                self.message = UninstallModel.summary(ToolItem.humanLines(text), status: status)
            }
        }
    }

    nonisolated static func lastMeaningfulLine(_ text: String) -> String {
        text.components(separatedBy: "\n").map { $0.trimmingCharacters(in: .whitespaces) }
            .last { !$0.isEmpty } ?? ""
    }

    nonisolated static func summary(_ text: String, status: Int32) -> String {
        let line = lastMeaningfulLine(text)
        return line.isEmpty || status == 15 ? String(format: L.t("exitCode"), status) : line
    }

    var canTrash: Bool { selected != nil && !loading && !working && !failed && cliPath != nil }

    func askTrash() {
        guard canTrash else { return }
        confirming = true
    }

    func trash() {
        confirming = false
        guard let app = selected, let cli = cliPath, !working, !loading, !failed else { return }
        working = true
        message = nil
        result = nil
        let size = total ?? 0
        run = CLIRun.start(cli: cli, args: ["uninstall", app.path, "--yes"]) { [weak self] text, status in
            guard let self else { return }
            self.working = false
            self.failed = status != 0
            self.lastOutput = text
            if status == 0 {
                self.result = ToolResult(ok: true, title: String(format: L.t("uninstalled"), app.name),
                                         detail: String(format: L.t("uninstalledSize"), L.human(kb: size)))
            } else {
                self.message = UninstallModel.summary(ToolItem.humanLines(text), status: status)
            }
            Hub.finished("uninstall", ok: status == 0)
            if status == 0 {
                self.clearSelection()
                self.failed = false
                self.sizes[app.path] = nil
                self.reload()
            }
            self.onChange?()
        }
    }

    func back() -> Bool {
        if working { return false }
        if selected != nil {
            clearSelection()
            message = nil
            return true
        }
        if !query.isEmpty {
            query = ""
            return true
        }
        return false
    }

    var backKey: String {
        if working { return "home" }
        if loading { return "cancel" }
        return selected != nil || !query.isEmpty ? "back" : "home"
    }

    func stop() {
        if !working { clearSelection() }
    }
}

struct UninstallView: View {
    @ObservedObject var model: UninstallModel
    let home: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            ToolHeader(title: L.t("uninstall"), backTitle: L.t(model.backKey), back: { if !model.back() { home() } }) {
                EmptyView()
            }
            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                TextField(L.t("search"), text: $model.query).textFieldStyle(.plain)
            }
            .padding(8)
            .themeField()
            appList
            details
            if let r = model.result { ResultCard(result: r) }
            if let message = model.message {
                if model.failed {
                    ErrorNote(summary: message, detail: model.lastOutput)
                } else {
                    Text(message).font(.caption).foregroundStyle(.secondary).lineLimit(2)
                }
            }
            Group {
                if model.working {
                    RunningNote(text: L.t("keepRunning"))
                } else {
                    HStack(spacing: 10) {
                        Spacer()
                        if model.selected != nil {
                            SecondaryButton(title: L.t("cancel")) { _ = model.back() }
                        }
                        BlueButton(title: L.t("toTrash") + "…", enabled: model.canTrash, destructive: true) { model.askTrash() }
                            .keyboardShortcut(.defaultAction)
                    }
                }
            }
            .frame(minHeight: 32)
        }
        .padding(20)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .alert(String(format: L.t("uninstallAsk"), model.selected?.name ?? ""), isPresented: $model.confirming) {
            Button(L.t("toTrash"), role: .destructive) { model.trash() }
            Button(L.t("cancel"), role: .cancel) {}
        } message: {
            Text(String(format: L.t("uninstallInfo"), model.total.map { L.human(kb: $0) } ?? "—"))
        }
    }

    private var appList: some View {
        ScrollView {
            LazyVStack(spacing: 2) {
                if model.filtered.isEmpty {
                    Text(L.t("noApps")).font(.callout).foregroundStyle(.secondary).padding(.vertical, 20)
                }
                ForEach(model.filtered) { app in
                    Button { model.select(app) } label: { row(app) }
                        .buttonStyle(.plain)
                }
            }
            .padding(4)
        }
        .frame(maxHeight: .infinity)
        .themeCard()
    }

    private func row(_ app: AppItem) -> some View {
        let isSelected = model.selected == app
        return HStack(spacing: 10) {
            Image(nsImage: NSWorkspace.shared.icon(forFile: app.path))
                .resizable()
                .frame(width: 28, height: 28)
            Text(app.name).font(.system(size: 13)).lineLimit(1)
            Spacer()
            Text(model.sizes[app.path].map { L.human(bytes: $0) } ?? "…")
                .font(.system(size: 12)).monospacedDigit()
                .foregroundStyle(isSelected ? Color.white.opacity(0.9) : Color.secondary)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .foregroundStyle(isSelected ? Theme.onAccent : Color.primary)
        .background(isSelected ? AnyShapeStyle(Theme.button) : AnyShapeStyle(Color.clear), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .contentShape(Rectangle())
    }

    @ViewBuilder
    private var details: some View {
        VStack(alignment: .leading, spacing: 6) {
            if model.selected == nil {
                Text(L.t("selectApp")).font(.callout).foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, minHeight: 60)
            } else if model.loading && model.leftovers.isEmpty {
                HStack { Spacer(); ProgressView().controlSize(.small); Spacer() }.frame(minHeight: 60)
            } else {
                HStack(spacing: 6) {
                    Text(L.t("leftovers")).font(.system(size: 12, weight: .semibold)).foregroundStyle(.secondary)
                    if model.loading { ProgressView().controlSize(.mini) }
                    Spacer()
                    Text(String(format: L.t("foundN"), model.leftovers.count)).font(.system(size: 11)).foregroundStyle(.secondary)
                }
                ScrollView {
                    VStack(spacing: 4) {
                        ForEach(model.leftovers) { item in
                            HStack(spacing: 8) {
                                Image(systemName: item.type == "app" ? "app.dashed" : (item.type == "dir" ? "folder" : "doc"))
                                    .foregroundStyle(Theme.accent)
                                    .frame(width: 16)
                                VStack(alignment: .leading, spacing: 1) {
                                    Text((item.path as NSString).lastPathComponent).font(.system(size: 11.5)).lineLimit(1).truncationMode(.middle)
                                    Text(item.shortPath).font(.system(size: 10)).foregroundStyle(.secondary).lineLimit(1).truncationMode(.middle)
                                }
                                Spacer()
                                Text(L.human(kb: item.kb)).font(.system(size: 11)).monospacedDigit().foregroundStyle(.secondary)
                            }
                            .help(item.path)
                        }
                    }
                }
                .frame(maxHeight: 130)
                if let total = model.total {
                    Divider().overlay(Theme.divider)
                    HStack {
                        Text(L.t("total")).font(.system(size: 13, weight: .semibold))
                        Spacer()
                        Text(L.human(kb: total)).font(.system(size: 13, weight: .semibold)).monospacedDigit()
                    }
                }
            }
        }
        .padding(10)
        .themeCard()
    }
}
