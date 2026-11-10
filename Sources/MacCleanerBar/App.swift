import AppKit
import SwiftUI

@main
struct MacCleanerBarApp: App {
    @StateObject private var model = Model()

    var body: some Scene {
        MenuBarExtra {
            PanelView(model: model)
        } label: {
            HStack(spacing: 3) {
                Image(nsImage: model.statusIcon)
                Text(model.freeLabel)
            }
        }
        .menuBarExtraStyle(.window)
    }
}
