import AppKit
import SwiftUI

@main
struct SlopometerApp: App {
    static let mainWindowID = "slopometer"

    @NSApplicationDelegateAdaptor private var delegate: AppDelegate
    @State private var model = AppModel()

    var body: some Scene {
        Window("Slopometer", id: Self.mainWindowID) {
            MainView()
                .environment(model)
                .onAppear { delegate.model = model }
        }
        .defaultSize(width: 760, height: 620)
        .windowResizability(.contentMinSize)

        MenuBarExtra {
            MenuPanel()
                .environment(model)
        } label: {
            MenuBarLabel()
                .environment(model)
                .onAppear { delegate.model = model }
        }
        .menuBarExtraStyle(.window)
    }
}

/// Opens the window for `slopometer://` links from the widget.
final class AppDelegate: NSObject, NSApplicationDelegate {
    @MainActor var model: AppModel?

    func application(_ application: NSApplication, open urls: [URL]) {
        Task { @MainActor in model?.openMainWindow() }
    }
}

private struct MenuBarLabel: View {
    @Environment(AppModel.self) private var model
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        HStack(spacing: 4) {
            Image(MenuPanel.iconName(for: model.menuBarMetric))
                .renderingMode(.template)
                .resizable()
                .frame(width: 16, height: 16)
            Text(model.menuBarTitle)
                .monospacedDigit()
        }
        .help(model.menuBarDescription)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Slopometer, \(model.menuBarDescription)")
        .onAppear { model.openWindowAction = openWindow }
    }
}
