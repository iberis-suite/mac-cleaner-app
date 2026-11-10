import AppKit
import SwiftUI

@MainActor
enum Windows {
    static var uninstall: UninstallWindow?
    static var tools: [String: ToolWindow] = [:]
    static var diskMap: DiskMapWindow?
    static var care: [String: CareWindow] = [:]

    static func open(_ tool: String, model: Model) {
        let changed: () -> Void = { [weak model] in
            model?.refresh()
            model?.refreshEstimates(force: true)
        }
        if tool == "uninstall" {
            if uninstall == nil { uninstall = UninstallWindow(cliPath: model.cliPath, onChange: changed) }
            uninstall?.show()
            return
        }
        if tool == "diskmap" {
            if diskMap == nil { diskMap = DiskMapWindow() }
            diskMap?.show()
            return
        }
        if tool == "maintenance" || tool == "privacy" {
            let c = care[tool] ?? CareWindow(tool: tool, cliPath: model.cliPath, onChange: changed)
            care[tool] = c
            c.show()
            return
        }
        let w = tools[tool] ?? ToolWindow(tool: tool, cliPath: model.cliPath, onChange: changed)
        tools[tool] = w
        w.show()
    }
}

@main
struct MacCleanerBarApp: App {
    @StateObject private var model = Model()

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
