import AppKit
import SwiftUI

@MainActor
enum Windows {
    static var uninstall: UninstallWindow?

    static func openUninstaller(_ model: Model) {
        if uninstall == nil {
            uninstall = UninstallWindow(cliPath: model.cliPath) { [weak model] in
                model?.refresh()
                model?.refreshEstimates(force: true)
            }
        }
        uninstall?.show()
    }
}

@main
struct MacCleanerBarApp: App {
    @StateObject private var model = Model()

    var body: some Scene {
        MenuBarExtra {
            PanelView(model: model) { Windows.openUninstaller(model) }
        } label: {
            HStack(spacing: 3) {
                Image(nsImage: model.statusIcon)
                Text(model.freeLabel)
            }
        }
        .menuBarExtraStyle(.window)
    }
}
