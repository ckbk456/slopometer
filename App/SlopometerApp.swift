import AppKit
import SlopometerCore
import SwiftUI

@main
struct SlopometerApp: App {
    static let mainWindowID = "slopometer"

    @NSApplicationDelegateAdaptor private var delegate: AppDelegate
    @State private var model = AppModel()

    var body: some Scene {
        Window("Slopometer", id: Self.mainWindowID) {
            Themed { MainView() }
                .environment(model)
                .onAppear { delegate.model = model }
        }
        .defaultSize(width: 760, height: 620)
        .windowResizability(.contentMinSize)

        MenuBarExtra {
            Themed { MenuPanel() }
                .environment(model)
        } label: {
            MenuBarLabel()
                .environment(model)
                .onAppear { delegate.model = model }
        }
        .menuBarExtraStyle(.window)
    }
}

/// Applies the person's color theme to a scene's content. It reads the model's settings,
/// so editing the theme re-renders the window and the panel at once, and it sits inside
/// the scene's own color scheme, so each appearance gets its resolved colors.
private struct Themed<Content: View>: View {
    @Environment(AppModel.self) private var model
    @ViewBuilder let content: Content

    var body: some View {
        content
            .slopTheme(model.settings.theme.resolved())
            // App-wide, so the window and the menu bar panel switch together, from first
            // appearance on. Both scenes set the same value.
            .onChange(of: model.settings.appearance, initial: true) { _, mode in
                NSApp.appearance = mode.nsAppearance
            }
    }
}

extension AppearanceMode {
    /// Nil follows the system.
    fileprivate var nsAppearance: NSAppearance? {
        switch self {
        case .system: nil
        case .light: NSAppearance(named: .aqua)
        case .dark: NSAppearance(named: .darkAqua)
        }
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
