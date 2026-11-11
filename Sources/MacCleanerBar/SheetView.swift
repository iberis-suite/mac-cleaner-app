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
                Capsule().fill(Theme.track)
                Capsule().fill(Theme.button)
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
                    .foregroundStyle(on ? Theme.accent : Color.secondary)
            }
            IconTile(symbol: ItemStyle.symbol(item), size: 24, font: 12)
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text(item.label).font(.system(size: 12)).lineLimit(1).truncationMode(.middle)
                    if excluded {
                        Text(L.t("excluded")).font(.system(size: 9.5, weight: .medium)).foregroundStyle(.secondary)
                            .padding(.horizontal, 5).padding(.vertical, 1)
                            .background(Theme.tile, in: Capsule())
                    }
                    Spacer(minLength: 6)
                    Text(L.human(kb: item.kb)).font(.system(size: 11)).monospacedDigit().foregroundStyle(.secondary)
                }
                SizeBar(fraction: maxKB > 0 ? item.kb / maxKB : 0)
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .background(checkable && on ? Theme.selection : Color.clear,
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
        .themeCard(9)
        .help(L.t("skippedHelp"))
    }
}

struct BlueButton: View {
    let title: String
    var enabled = true
    var destructive = false
    var busy = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            ZStack {
                Text(title).opacity(busy ? 0 : 1)
                if busy { ProgressView().controlSize(.small) }
            }
            .font(.system(size: 13, weight: .semibold))
            .foregroundStyle(.white)
            .padding(.horizontal, 16)
            .padding(.vertical, 7)
            .background(destructive ? AnyShapeStyle(Theme.destructive) : AnyShapeStyle(Theme.button),
                        in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            .opacity(enabled && !busy ? 1 : 0.45)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!enabled || busy)
    }
}

struct SecondaryButton: View {
    let title: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 13))
                .padding(.horizontal, 12)
                .padding(.vertical, 7)
                .themeCard(8)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

struct BackButton: View {
    let title: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 3) {
                Image(systemName: "chevron.left").font(.system(size: 11, weight: .semibold))
                Text(title).font(.system(size: 12, weight: .medium))
            }
            .foregroundStyle(Theme.accent)
            .padding(.vertical, 2)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

struct ToolHeader<Trailing: View>: View {
    let title: String
    let backTitle: String
    let back: () -> Void
    @ViewBuilder var trailing: Trailing

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            BackButton(title: backTitle, action: back)
            HStack(alignment: .firstTextBaseline) {
                Text(title).font(.system(size: 20, weight: .bold, design: .rounded)).lineLimit(1)
                Spacer(minLength: 8)
                trailing
            }
        }
    }
}

struct RunningNote: View {
    let text: String

    var body: some View {
        HStack(spacing: 8) {
            ProgressView().controlSize(.small)
            Text(text).font(.system(size: 11)).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
    }
}

struct ErrorNote: View {
    let summary: String
    var detail = ""
    @State private var open = false

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .top, spacing: 6) {
                Image(systemName: "exclamationmark.triangle.fill").font(.system(size: 11)).foregroundStyle(Theme.warn)
                Text(summary.isEmpty ? L.t("cleanFailed") : summary)
                    .font(.system(size: 12, weight: .medium)).lineLimit(2)
                Spacer(minLength: 0)
                if !detail.isEmpty {
                    Button { open.toggle() } label: {
                        HStack(spacing: 3) {
                            Text(L.t("techDetails"))
                            Image(systemName: "chevron.right").rotationEffect(.degrees(open ? 90 : 0))
                        }
                        .font(.system(size: 11)).foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                }
            }
            if open {
                ScrollView([.horizontal, .vertical]) {
                    Text(detail).font(.system(size: 10, design: .monospaced))
                        .fixedSize(horizontal: true, vertical: true).textSelection(.enabled).padding(8)
                        .frame(maxWidth: .infinity, alignment: .topLeading)
                }
                .frame(height: 110)
                .background(Theme.console, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            }
        }
        .padding(10)
        .background(Theme.warnFill, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
    }
}

struct EmptyNote: View {
    var text = L.t("nothingToClean")

    var body: some View {
        VStack(spacing: 6) {
            Image(systemName: "checkmark.circle").font(.system(size: 24)).foregroundStyle(Theme.good)
            Text(text).font(.system(size: 12)).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 40)
    }
}


struct ScanStatus: View {
    let listing: Bool
    var step: String?
    let count: Int
    var kb: Double?
    var stop: (() -> Void)?

    var body: some View {
        HStack(spacing: 8) {
            if listing {
                ProgressView().controlSize(.small)
                Text(step ?? L.t("searching")).font(.system(size: 12, weight: .medium)).foregroundStyle(Theme.accent)
            }
            Text(summary).font(.system(size: 12)).monospacedDigit().foregroundStyle(.secondary)
            Spacer(minLength: 0)
            if listing, let stop {
                Button(L.t("stop")) { stop() }
                    .buttonStyle(.plain)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(Theme.accent)
            }
        }
        .frame(minHeight: 18)
    }

    private var summary: String {
        let found = String(format: L.t("foundN"), count)
        guard let kb, count > 0 else { return found }
        return found + " · " + L.human(kb: kb)
    }
}

struct SummaryCard: View {
    let symbol: String
    let title: String
    var subtitle = ""
    var busy = false

    var body: some View {
        HStack(spacing: 10) {
            if busy {
                ProgressView().controlSize(.small).frame(width: 30, height: 30)
            } else {
                IconTile(symbol: symbol)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.system(size: 13, weight: .semibold)).monospacedDigit()
                if !subtitle.isEmpty {
                    Text(subtitle).font(.system(size: 11)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(10)
        .themeCard()
    }
}

struct StepList: View {
    let steps: [(String, String)]

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(Array(steps.enumerated()), id: \.offset) { _, s in
                StepRow(title: s.0, state: s.1)
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .themeCard()
    }
}

struct StepRow: View {
    let title: String
    let state: String
    var detail = ""

    var body: some View {
        HStack(spacing: 8) {
            Group {
                switch state {
                case "running": ProgressView().controlSize(.mini)
                case "done": Image(systemName: "checkmark.circle.fill").foregroundStyle(Theme.good)
                case "failed": Image(systemName: "xmark.circle.fill").foregroundStyle(Theme.bad)
                case "skipped": Image(systemName: "minus.circle").foregroundStyle(.secondary)
                default: Image(systemName: "circle").foregroundStyle(.tertiary)
                }
            }
            .font(.system(size: 13))
            .frame(width: 18)
            VStack(alignment: .leading, spacing: 1) {
                Text(title).font(.system(size: 12))
                if state == "failed" || !detail.isEmpty {
                    Text(state == "failed" ? L.t("stepFailed") : detail).font(.system(size: 10.5))
                        .foregroundStyle(state == "failed" ? Theme.bad : Color.secondary)
                }
            }
            Spacer(minLength: 6)
            Text(L.t("state_" + state)).font(.system(size: 10.5, weight: .medium)).foregroundStyle(.secondary)
        }
    }
}

struct ResultCard: View {
    let result: ToolResult

    var body: some View {
        if result.ok {
            HStack(spacing: 12) {
                Image(systemName: "checkmark.circle.fill").font(.system(size: 30)).foregroundStyle(Theme.good)
                VStack(alignment: .leading, spacing: 2) {
                    Text(result.title).font(.system(size: 16, weight: .bold, design: .rounded)).monospacedDigit()
                    if !result.detail.isEmpty {
                        Text(result.detail).font(.system(size: 11)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                    }
                }
                Spacer(minLength: 0)
            }
            .padding(12)
            .themeCard()
        } else {
            ErrorNote(summary: result.title, detail: result.raw)
        }
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

    private var isPreviewing: Bool {
        if case .previewing = model.phase { return true }
        return false
    }

    private var destructive: Bool { command == "trash" || command == "auto" }

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
            if case .cleaning = model.phase {
                Text(" ").font(.system(size: 12)).padding(.vertical, 2).hidden()
            } else {
                BackButton(title: L.t(isPreviewing ? "cancel" : "back")) { model.back() }
                    .keyboardShortcut(.cancelAction)
            }
            HStack(spacing: 8) {
                IconTile(symbol: ItemStyle.command(command), size: 26, font: 13)
                Text(title).font(.system(size: 14, weight: .semibold)).lineLimit(1)
                Spacer()
            }
            switch model.phase {
            case .previewing:
                ScanStatus(listing: true, count: rows.count, kb: rows.reduce(0) { $0 + $1.kb }) { model.stopPreview() }
                if rows.isEmpty {
                    waiting(L.t("searching"))
                } else {
                    listCard
                }
                previewFooter
            case .previewReady:
                if let error = model.sheetError {
                    ErrorNote(summary: error, detail: ToolItem.humanLines(model.output))
                } else {
                    listCard
                    if !skipped.isEmpty { SkippedRow(items: skipped) }
                }
                previewFooter
            case .cleaning:
                waiting(L.t("cleaning"))
                Text(L.t("keepRunningPanel")).font(.system(size: 11)).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            case .cleaned:
                resultView
                HStack {
                    Spacer()
                    BlueButton(title: L.t("done")) { model.dismiss() }.keyboardShortcut(.defaultAction)
                }
            case .idle:
                EmptyView()
            }
        }
    }

    private func waiting(_ text: String) -> some View {
        VStack(spacing: 10) {
            ProgressView().controlSize(.regular)
            Text(text).font(.system(size: 12)).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, minHeight: 150)
        .themeCard()
    }

    private var listCard: some View {
        let items = rows
        let maxKB = items.map(\.kb).max() ?? 0
        return Group {
            if items.isEmpty {
                VStack(spacing: 6) {
                    Image(systemName: "checkmark.circle").font(.system(size: 22)).foregroundStyle(Theme.good)
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
        .themeCard()
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
                    .foregroundStyle(Theme.accent)
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
            SecondaryButton(title: L.t("cancel")) { model.back() }
            BlueButton(title: L.t("clean"), enabled: model.canClean, destructive: destructive) { model.clean() }
                .keyboardShortcut(.defaultAction)
        }
    }

    @ViewBuilder
    private var resultView: some View {
        if let r = model.result {
            if r.ok {
                VStack(spacing: 8) {
                    Image(systemName: "checkmark.circle.fill").font(.system(size: 40)).foregroundStyle(Theme.good)
                    Text(String(format: L.t("freedAmount"), L.human(kb: r.freedKB)))
                        .font(.system(size: 22, weight: .bold, design: .rounded)).monospacedDigit()
                    if !r.sections.isEmpty {
                        VStack(alignment: .leading, spacing: 4) {
                            ForEach(Array(r.sections.prefix(12).enumerated()), id: \.offset) { _, s in
                                HStack(spacing: 6) {
                                    Image(systemName: "checkmark").font(.system(size: 10, weight: .bold)).foregroundStyle(Theme.good)
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
                .themeCard()
            } else {
                ErrorNote(summary: r.message.isEmpty ? L.t("cleanFailed") : r.message, detail: ToolItem.humanLines(model.output))
            }
        }
    }
}
