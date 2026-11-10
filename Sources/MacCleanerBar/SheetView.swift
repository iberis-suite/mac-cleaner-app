import AppKit
import SwiftUI

enum ItemStyle {
    private static let symbols: [String: String] = [
        "apps": "app.badge", "logs": "doc.text", "xcode": "hammer", "devsupport": "iphone",
        "sim": "ipad.and.iphone", "npm": "shippingbox", "composer": "shippingbox", "gradle": "cube",
        "brew": "mug", "docker": "server.rack", "nodemod": "folder.badge.gearshape",
        "temp": "hourglass", "trash": "xmark.bin", "clone": "square.on.square", "kept": "lock",
        "skipped": "lock", "worktree": "arrow.triangle.branch", "unity": "cube.transparent",
        "file": "doc", "keep": "lock.fill", "copy": "doc.on.doc",
    ]

    private static var checked: [String: Bool] = [:]

    static func valid(_ name: String) -> Bool {
        if let v = checked[name] { return v }
        let v = NSImage(systemSymbolName: name, accessibilityDescription: nil) != nil
        checked[name] = v
        return v
    }

    static func symbol(_ item: ToolItem) -> String {
        var name = symbols[item.type] ?? "doc"
        if item.type == "dir" || item.type == "tmp" {
            var isDir: ObjCBool = false
            let exists = FileManager.default.fileExists(atPath: item.path, isDirectory: &isDir)
            if item.path.hasSuffix(".app") { name = "app" } else { name = exists && isDir.boolValue ? "folder" : "doc" }
        }
        if item.type == "file" && item.path.hasSuffix(".app") { name = "app" }
        return valid(name) ? name : "doc"
    }

    static func command(_ c: String) -> String {
        ["caches": "square.stack.3d.up", "temp": "trash", "trash": "xmark.bin", "auto": "sparkles"][c] ?? "sparkles"
    }
}

enum AppNames {
    private static var cache: [String: String] = [:]

    static func name(_ id: String) -> String {
        if let n = cache[id] { return n }
        var result = id
        let lower = id.lowercased()
        if let app = NSWorkspace.shared.runningApplications.first(where: { $0.bundleIdentifier?.lowercased() == lower }),
           let n = app.localizedName, !n.isEmpty {
            result = n
        } else if id.contains("."), let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: id) {
            result = (FileManager.default.displayName(atPath: url.path) as NSString).deletingPathExtension
        }
        cache[id] = result
        return result
    }
}

struct SizeBar: View {
    let fraction: Double

    var body: some View {
        GeometryReader { g in
            ZStack(alignment: .leading) {
                Capsule().fill(Color.primary.opacity(0.08))
                Capsule().fill(Color.accentBlue.opacity(0.85))
                    .frame(width: max(fraction > 0 ? 3 : 0, g.size.width * min(1, max(0, fraction))))
            }
        }
        .frame(height: 4)
    }
}

struct ItemRow: View {
    let item: ToolItem
    let maxKB: Double
    var checkable = false
    var on = false
    var excluded = false
    var toggle: () -> Void = {}

    var body: some View {
        HStack(spacing: 8) {
            if checkable {
                Image(systemName: on ? "checkmark.square.fill" : "square")
                    .font(.system(size: 14))
                    .foregroundStyle(on ? Color.accentBlue : Color.secondary)
            }
            Image(systemName: ItemStyle.symbol(item))
                .font(.system(size: 12))
                .foregroundStyle(Color.accentBlue)
                .frame(width: 22, height: 22)
                .background(Color.primary.opacity(0.07), in: RoundedRectangle(cornerRadius: 6, style: .continuous))
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text(item.label).font(.system(size: 12)).lineLimit(1).truncationMode(.middle)
                    if excluded {
                        Text(L.t("excluded")).font(.system(size: 9.5, weight: .medium)).foregroundStyle(.secondary)
                            .padding(.horizontal, 5).padding(.vertical, 1)
                            .background(Color.primary.opacity(0.08), in: Capsule())
                    }
                    Spacer(minLength: 6)
                    Text(L.human(kb: item.kb)).font(.system(size: 11)).monospacedDigit().foregroundStyle(.secondary)
                }
                SizeBar(fraction: maxKB > 0 ? item.kb / maxKB : 0)
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .background(checkable && on ? Color.accentBlue.opacity(0.12) : Color.clear,
                    in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .contentShape(Rectangle())
        .onTapGesture { if checkable { toggle() } }
        .help(item.path.hasPrefix("/") ? item.path : item.label)
    }
}

struct SkippedRow: View {
    let items: [ToolItem]
    @State private var open = false

    private var names: [String] {
        Array(Set(items.map { AppNames.name($0.label) }))
            .sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
    }

    var body: some View {
        let list = names
        VStack(alignment: .leading, spacing: 6) {
            Button { open.toggle() } label: {
                HStack(spacing: 6) {
                    Image(systemName: "lock").font(.system(size: 11)).foregroundStyle(.secondary)
                    Text(list.count == 1 ? L.t("skippedOne") : String(format: L.t("skippedMany"), list.count))
                        .font(.system(size: 11.5, weight: .medium)).foregroundStyle(.secondary)
                    Spacer()
                    Image(systemName: "chevron.right").font(.system(size: 9, weight: .semibold)).foregroundStyle(.tertiary)
                        .rotationEffect(.degrees(open ? 90 : 0))
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            if open {
                ScrollView {
                    Text(list.joined(separator: " · "))
                        .font(.system(size: 11)).foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .textSelection(.enabled)
                }
                .frame(maxHeight: 90)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(Color.primary.opacity(0.05), in: RoundedRectangle(cornerRadius: 9, style: .continuous))
        .help(L.t("skippedHelp"))
    }
}

struct DetailsBox: View {
    let text: String
    var loading = false
    var height: CGFloat = 140
    var onOpen: () -> Void = {}
    @State private var open = false

    var body: some View {
        let isOpen = open
        VStack(alignment: .leading, spacing: 6) {
            Button {
                open = !isOpen
                if !isOpen { onOpen() }
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "chevron.right").font(.system(size: 9, weight: .semibold)).foregroundStyle(.tertiary)
                        .rotationEffect(.degrees(isOpen ? 90 : 0))
                    Text(L.t("details")).font(.system(size: 11.5, weight: .medium)).foregroundStyle(.secondary)
                    if loading { ProgressView().controlSize(.mini) }
                    Spacer()
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            if isOpen {
                ScrollView([.horizontal, .vertical]) {
                    Text(text.isEmpty ? (loading ? L.t("running") : L.t("noOutput")) : text)
                        .font(.system(size: 10, design: .monospaced))
                        .fixedSize(horizontal: true, vertical: true)
                        .textSelection(.enabled)
                        .padding(8)
                        .frame(maxWidth: .infinity, alignment: .topLeading)
                }
                .frame(height: height)
                .background(Color.black.opacity(0.25), in: RoundedRectangle(cornerRadius: 9, style: .continuous))
            }
        }
    }
}

struct BlueButton: View {
    let title: String
    var enabled = true
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.white)
                .padding(.horizontal, 18)
                .padding(.vertical, 8)
                .background(Color.accentBlue.opacity(enabled ? 1 : 0.4), in: RoundedRectangle(cornerRadius: 9, style: .continuous))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
    }
}

struct PreviewSheet: View {
    @ObservedObject var model: Model

    private var command: String {
        switch model.phase {
        case .previewing(let c), .previewReady(let c), .cleaning(let c), .cleaned(let c): return c
        case .idle: return ""
        }
    }

    private var checkable: Bool { Model.selectable.contains(command) }

    private var rows: [ToolItem] { model.sheetItems.filter { $0.index > 0 } }

    private var skipped: [ToolItem] { model.sheetItems.filter { $0.index == 0 && ($0.type == "skipped" || $0.type == "kept") } }

    private var title: String {
        switch model.phase {
        case .previewing, .previewReady: return "\(L.t("preview")) · \(L.t(command))"
        case .cleaning: return "\(L.t(command)) · \(L.t("running"))"
        case .cleaned: return L.t(command)
        case .idle: return ""
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: ItemStyle.command(command))
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(Color.accentBlue)
                    .frame(width: 26, height: 26)
                    .background(Color.primary.opacity(0.08), in: RoundedRectangle(cornerRadius: 7, style: .continuous))
                Text(title).font(.system(size: 14, weight: .semibold)).lineLimit(1)
                Spacer()
                if model.busy { ProgressView().controlSize(.small) }
            }
            switch model.phase {
            case .previewing:
                waiting(L.t("analyzing"))
            case .previewReady:
                if let error = model.sheetError {
                    errorCard(error)
                } else {
                    listCard
                    if !skipped.isEmpty { SkippedRow(items: skipped) }
                }
                DetailsBox(text: model.output, loading: model.detailsLoading) { model.loadDetails() }
                    .id(command)
                previewFooter
            case .cleaning:
                waiting(L.t("cleaning"))
                DetailsBox(text: model.output, loading: true)
            case .cleaned:
                resultView
                DetailsBox(text: model.output)
                HStack {
                    Spacer()
                    BlueButton(title: L.t("close")) { model.dismiss() }.keyboardShortcut(.defaultAction)
                }
            case .idle:
                EmptyView()
            }
        }
    }

    private func waiting(_ text: String) -> some View {
        Card {
            VStack(spacing: 10) {
                ProgressView().controlSize(.regular)
                Text(text).font(.system(size: 12)).foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, minHeight: 150)
        }
    }

    private func errorCard(_ text: String) -> some View {
        Card {
            HStack(alignment: .top, spacing: 8) {
                Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
                VStack(alignment: .leading, spacing: 3) {
                    Text(String(format: L.t("exitCode"), model.exitStatus)).font(.system(size: 12, weight: .semibold))
                    Text(text).font(.system(size: 11)).foregroundStyle(.secondary).lineLimit(4)
                }
                Spacer(minLength: 0)
            }
            .padding(10)
        }
    }

    private var listCard: some View {
        let items = rows
        let maxKB = items.map(\.kb).max() ?? 0
        return Card {
            if items.isEmpty {
                VStack(spacing: 6) {
                    Image(systemName: "checkmark.circle").font(.system(size: 22)).foregroundStyle(Color.green)
                    Text(L.t("nothingToClean")).font(.system(size: 12)).foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, minHeight: 110)
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 2) {
                        if command == "temp" {
                            group("tmp", title: L.t("tempFiles"), items: items, maxKB: maxKB)
                            group("clone", title: L.t("appCopies"), items: items, maxKB: maxKB)
                        } else {
                            ForEach(items) { row($0, maxKB: maxKB) }
                        }
                    }
                    .padding(5)
                }
                .frame(height: min(300, CGFloat(items.count) * 39 + (command == "temp" ? 60 : 12)))
            }
        }
    }

    @ViewBuilder
    private func group(_ type: String, title: String, items: [ToolItem], maxKB: Double) -> some View {
        let list = items.filter { $0.type == type }
        if !list.isEmpty {
            let indexes = list.map(\.index)
            let all = indexes.allSatisfy { model.sheetSelected.contains($0) }
            HStack(spacing: 6) {
                Text("\(title) · \(list.count)").font(.system(size: 11, weight: .semibold)).foregroundStyle(.secondary)
                Spacer()
                Text(L.human(kb: list.reduce(0) { $0 + $1.kb })).font(.system(size: 11)).monospacedDigit().foregroundStyle(.secondary)
                Button(L.t(all ? "selectNone" : "selectAll")) { model.setSheet(indexes, on: !all) }
                    .buttonStyle(.plain)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(Color.accentBlue)
            }
            .padding(.horizontal, 8)
            .padding(.top, 6)
            .padding(.bottom, 2)
            ForEach(list) { row($0, maxKB: maxKB) }
        }
    }

    private func row(_ item: ToolItem, maxKB: Double) -> some View {
        let on = model.sheetSelected.contains(item.index)
        return ItemRow(item: item, maxKB: maxKB, checkable: checkable, on: on,
                       excluded: item.state == "excluded" && !on) { model.toggleSheet(item.index) }
    }

    private var previewFooter: some View {
        HStack(alignment: .bottom, spacing: 10) {
            VStack(alignment: .leading, spacing: 0) {
                Text(L.t(checkable ? "selectedTotal" : "total")).font(.system(size: 11)).foregroundStyle(.secondary)
                Text(L.human(kb: model.sheetSelectedKB))
                    .font(.system(size: 24, weight: .bold, design: .rounded)).monospacedDigit()
                    .lineLimit(1).minimumScaleFactor(0.7)
            }
            Spacer()
            Button(L.t("cancel")) { model.dismiss() }
                .buttonStyle(.plain)
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
                .keyboardShortcut(.cancelAction)
            BlueButton(title: L.t("clean"), enabled: model.canClean) { model.clean() }
                .keyboardShortcut(.defaultAction)
        }
    }

    @ViewBuilder
    private var resultView: some View {
        if let r = model.result {
            Card {
                VStack(spacing: 8) {
                    Image(systemName: r.ok ? "checkmark.circle.fill" : "xmark.octagon.fill")
                        .font(.system(size: 40))
                        .foregroundStyle(r.ok ? Color.green : Color.red)
                    Text(r.ok ? String(format: L.t("freedAmount"), L.human(kb: r.freedKB)) : L.t("cleanFailed"))
                        .font(.system(size: 22, weight: .bold, design: .rounded)).monospacedDigit()
                    if !r.ok {
                        Text(r.message).font(.system(size: 11)).foregroundStyle(.secondary)
                            .multilineTextAlignment(.center).lineLimit(3)
                    }
                    if r.ok && !r.sections.isEmpty {
                        VStack(alignment: .leading, spacing: 4) {
                            ForEach(Array(r.sections.prefix(12).enumerated()), id: \.offset) { _, s in
                                HStack(spacing: 6) {
                                    Image(systemName: "checkmark").font(.system(size: 10, weight: .bold)).foregroundStyle(Color.green)
                                    Text(s).font(.system(size: 12)).lineLimit(1).truncationMode(.middle)
                                }
                            }
                            if r.sections.count > 12 {
                                Text(String(format: L.t("andMore"), r.sections.count - 12))
                                    .font(.system(size: 11)).foregroundStyle(.secondary)
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.top, 4)
                    }
                }
                .frame(maxWidth: .infinity)
                .padding(14)
            }
        }
    }
}
