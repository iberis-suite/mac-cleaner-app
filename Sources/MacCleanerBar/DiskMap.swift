import AppKit
import SwiftUI

struct DiskEntry: Identifiable, Hashable, Sendable {
    let url: URL
    let name: String
    var size: Int64
    let isDir: Bool

    var id: String { url.path }
}

enum DiskScan {
    static let keys: [URLResourceKey] = [.isDirectoryKey, .isSymbolicLinkKey, .totalFileAllocatedSizeKey, .fileAllocatedSizeKey]
    static let keySet = Set(keys)
    static let skipped: Set<String> = ["/System/Volumes", "/Volumes", "/dev", "/.nofollow", "/.resolve", "/.vol"]

    static func size(_ v: URLResourceValues?) -> Int64 {
        Int64(v?.totalFileAllocatedSize ?? v?.fileAllocatedSize ?? 0)
    }

    static func children(of dir: URL) -> [DiskEntry] {
        let fm = FileManager.default
        guard let urls = try? fm.contentsOfDirectory(at: dir, includingPropertiesForKeys: keys, options: []) else { return [] }
        return urls.compactMap { u in
            if skipped.contains(u.path) || (dir.path == "/" && u.lastPathComponent.hasPrefix(".")) { return nil }
            let v = try? u.resourceValues(forKeys: keySet)
            let link = v?.isSymbolicLink == true
            let dir = v?.isDirectory == true && !link
            return DiskEntry(url: u, name: u.lastPathComponent, size: dir ? 0 : size(v), isDir: dir)
        }
    }

    static func measure(_ entry: DiskEntry, cancelled: () -> Bool) -> (Int64, [DiskEntry])? {
        guard entry.isDir else { return (entry.size, []) }
        var subs = children(of: entry.url)
        var index: [String: Int] = [:]
        for (i, s) in subs.enumerated() { index[s.name] = i }
        guard let en = FileManager.default.enumerator(at: entry.url, includingPropertiesForKeys: keys, options: [],
                                                      errorHandler: { _, _ in true }) else { return (0, subs) }
        let base = entry.url.standardizedFileURL.pathComponents.count
        var total: Int64 = 0
        var n = 0
        while let f = en.nextObject() as? URL {
            n += 1
            if n % 4096 == 0 && cancelled() { return nil }
            if skipped.contains(f.path) {
                en.skipDescendants()
                continue
            }
            let v = try? f.resourceValues(forKeys: keySet)
            if v?.isDirectory == true && v?.isSymbolicLink != true { continue }
            let s = size(v)
            total += s
            let comps = f.standardizedFileURL.pathComponents
            if comps.count > base + 1, let i = index[comps[base]] { subs[i].size += s }
        }
        if cancelled() { return nil }
        return (total, subs.sorted { $0.size > $1.size })
    }
}

final class CancelFlag: @unchecked Sendable {
    private let lock = NSLock()
    private var value = false

    var isCancelled: Bool {
        lock.lock()
        defer { lock.unlock() }
        return value
    }

    func cancel() {
        lock.lock()
        value = true
        lock.unlock()
    }
}

@MainActor
final class DiskMapModel: ObservableObject {
    @Published var trail: [URL] = [URL(fileURLWithPath: NSHomeDirectory())]
    @Published var entries: [DiskEntry] = []
    @Published var scanning = false
    @Published var done = 0
    @Published var total = 0
    @Published var message: String?
    @Published var failed = false
    private var cache: [String: [DiskEntry]] = [:]
    private var task: Task<Void, Never>?
    private var cancel: CancelFlag?
    private var generation = 0

    var current: URL { trail.last ?? URL(fileURLWithPath: NSHomeDirectory()) }

    var fromRoot: Bool { trail.first?.path == "/" }

    var currentSize: Int64 { entries.reduce(0) { $0 + $1.size } }

    func setRoot(_ root: Bool) {
        guard root != fromRoot else { return }
        trail = [URL(fileURLWithPath: root ? "/" : NSHomeDirectory())]
        load()
    }

    func open(_ e: DiskEntry) {
        guard e.isDir else { return }
        trail.append(e.url)
        load()
    }

    func go(to i: Int) {
        guard i < trail.count - 1 else { return }
        trail = Array(trail.prefix(i + 1))
        load()
    }

    func title(at i: Int) -> String {
        if i == 0 { return fromRoot ? "Macintosh HD" : L.t("homeFolder") }
        return FileManager.default.displayName(atPath: trail[i].path)
    }

    func load() {
        cancel?.cancel()
        task?.cancel()
        generation += 1
        let gen = generation
        message = nil
        failed = false
        if let c = cache[current.path] {
            entries = c
            scanning = false
            return
        }
        let dir = current
        if Demo.enabled {
            entries = Demo.diskEntries(dir)
            cache[dir.path] = entries
            scanning = false
            return
        }
        scanning = true
        done = 0
        entries = []
        let flag = CancelFlag()
        cancel = flag
        task = Task { [weak self] in
            let list = await Task.detached(priority: .utility) { DiskScan.children(of: dir) }.value
            guard let me = self, me.generation == gen else { return }
            me.entries = list.sorted { $0.size > $1.size }
            me.total = list.filter(\.isDir).count
            var result = list
            var subCache: [String: [DiskEntry]] = [:]
            for (i, e) in list.enumerated() where e.isDir {
                if flag.isCancelled { return }
                let measured = await Task.detached(priority: .utility) {
                    DiskScan.measure(e, cancelled: { flag.isCancelled })
                }.value
                guard let (size, subs) = measured, let me = self, me.generation == gen else { return }
                result[i].size = size
                subCache[e.url.path] = subs
                me.entries = result.sorted { $0.size > $1.size }
                me.done += 1
            }
            guard let me = self, me.generation == gen else { return }
            let final = result.sorted { $0.size > $1.size }
            me.entries = final
            me.cache[dir.path] = final
            for (k, v) in subCache where me.cache[k] == nil { me.cache[k] = v }
            me.scanning = false
        }
    }

    func stop() {
        cancel?.cancel()
        task?.cancel()
        generation += 1
        scanning = false
    }

    func showInFinder(_ e: DiskEntry) {
        NSWorkspace.shared.activateFileViewerSelecting([e.url])
    }

    func canTrash(_ e: DiskEntry) -> Bool {
        e.url.path.hasPrefix(NSHomeDirectory() + "/") && !scanning
    }

    func back() -> Bool {
        if scanning && trail.count == 1 {
            stop()
            return true
        }
        guard trail.count > 1 else { return false }
        go(to: trail.count - 2)
        return true
    }

    var backKey: String {
        if trail.count > 1 { return "back" }
        return scanning ? "cancel" : "home"
    }

    func appear() {
        if !scanning && entries.isEmpty { load() }
    }

    func trash(_ e: DiskEntry) {
        guard canTrash(e) else { return }
        let alert = NSAlert()
        alert.messageText = String(format: L.t("trashAsk"), e.name)
        alert.informativeText = String(format: L.t("trashInfo"), L.human(bytes: e.size))
        alert.alertStyle = .warning
        alert.addButton(withTitle: L.t("toTrash"))
        alert.addButton(withTitle: L.t("cancel"))
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        if Demo.enabled {
            message = L.t("demoNoAction")
            return
        }
        NSWorkspace.shared.recycle([e.url]) { [weak self] _, error in
            DispatchQueue.main.async {
                guard let self else { return }
                if let error {
                    self.failed = true
                    self.message = String(format: L.t("trashFailed"), error.localizedDescription)
                    return
                }
                self.entries.removeAll { $0.url == e.url }
                for k in Array(self.cache.keys) where e.url.path.hasPrefix(k == "/" ? "/" : k + "/") || k.hasPrefix(e.url.path) {
                    self.cache.removeValue(forKey: k)
                }
                self.cache[self.current.path] = self.entries
                self.failed = false
                self.message = String(format: L.t("trashed"), e.name)
            }
        }
    }
}

struct DiskMapView: View {
    @ObservedObject var model: DiskMapModel
    let home: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            ToolHeader(title: L.t("diskmap"), backTitle: L.t(model.backKey), back: { if !model.back() { home() } }) {
                Picker("", selection: Binding(get: { model.fromRoot }, set: { model.setRoot($0) })) {
                    Text(L.t("homeFolder")).tag(false)
                    Text("Macintosh HD").tag(true)
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .controlSize(.small)
                .fixedSize()
            }
            breadcrumb
            list
            if let m = model.message {
                Text(m).font(.caption).foregroundStyle(model.failed ? Color.red : Color.secondary).lineLimit(2)
            }
            HStack(spacing: 10) {
                Text(L.human(bytes: model.currentSize)).font(.system(size: 12, weight: .semibold)).monospacedDigit()
                if model.scanning {
                    ProgressView().controlSize(.small)
                    Text(String(format: L.t("measuringN"), model.done, model.total))
                        .font(.system(size: 11)).foregroundStyle(.secondary).monospacedDigit()
                }
                Spacer()
                if model.scanning {
                    SecondaryButton(title: L.t("cancel")) { model.stop() }
                }
            }
            .frame(minHeight: 32)
        }
        .padding(20)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private var breadcrumb: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 4) {
                ForEach(Array(model.trail.indices), id: \.self) { i in
                    if i > 0 {
                        Image(systemName: "chevron.right").font(.system(size: 9, weight: .semibold)).foregroundStyle(.tertiary)
                    }
                    let last = i == model.trail.count - 1
                    Button { model.go(to: i) } label: {
                        HStack(spacing: 4) {
                            if i == 0 { Image(systemName: model.fromRoot ? "internaldrive" : "house") }
                            Text(model.title(at: i)).lineLimit(1)
                        }
                        .font(.system(size: 12, weight: last ? .semibold : .regular))
                        .foregroundStyle(last ? Color.primary : Color.accentBlue)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 3)
                        .background(last ? Color.primary.opacity(0.07) : Color.clear, in: RoundedRectangle(cornerRadius: 6, style: .continuous))
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .disabled(last)
                }
            }
        }
    }

    private var list: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 2) {
                if model.entries.isEmpty {
                    Group {
                        if model.scanning { ProgressView().controlSize(.small) }
                        else { Text(L.t("emptyFolder")).font(.callout).foregroundStyle(.secondary) }
                    }
                    .frame(maxWidth: .infinity).padding(.vertical, 30)
                } else {
                    let maxSize = model.entries.map(\.size).max() ?? 0
                    ForEach(model.entries) { row($0, maxSize: maxSize) }
                }
            }
            .padding(6)
        }
        .frame(maxHeight: .infinity)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private func row(_ e: DiskEntry, maxSize: Int64) -> some View {
        HStack(spacing: 8) {
            Button { model.open(e) } label: {
                HStack(spacing: 8) {
                    Image(systemName: e.isDir ? "folder.fill" : "doc")
                        .font(.system(size: 12))
                        .foregroundStyle(Color.accentBlue)
                        .frame(width: 22, height: 22)
                        .background(Color.primary.opacity(0.07), in: RoundedRectangle(cornerRadius: 6, style: .continuous))
                    VStack(alignment: .leading, spacing: 3) {
                        HStack(spacing: 6) {
                            Text(e.name).font(.system(size: 12)).lineLimit(1).truncationMode(.middle)
                            Spacer(minLength: 6)
                            if e.isDir && e.size == 0 && model.scanning {
                                Text(L.t("estimating")).font(.system(size: 11)).foregroundStyle(.tertiary)
                            } else {
                                Text(L.human(bytes: e.size)).font(.system(size: 11)).monospacedDigit().foregroundStyle(.secondary)
                            }
                        }
                        SizeBar(fraction: maxSize > 0 ? Double(e.size) / Double(maxSize) : 0)
                    }
                    Image(systemName: "chevron.right").font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(.tertiary).opacity(e.isDir ? 1 : 0)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help(e.url.path)
            Button { model.showInFinder(e) } label: {
                Image(systemName: "magnifyingglass.circle").font(.system(size: 13)).foregroundStyle(Color.accentBlue)
            }
            .buttonStyle(.plain)
            .help(L.t("showInFinder"))
            Button { model.trash(e) } label: {
                Image(systemName: "trash").font(.system(size: 12)).foregroundStyle(Color.red.opacity(model.canTrash(e) ? 0.9 : 0.25))
            }
            .buttonStyle(.plain)
            .disabled(!model.canTrash(e))
            .help(L.t("toTrash"))
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 4)
    }
}
