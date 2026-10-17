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
            MenuContent()
                .environment(model)
        } label: {
            MenuBarLabel()
                .environment(model)
                .onAppear { delegate.model = model }
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
            Image(iconName)
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

    private var iconName: String {
        switch model.menuBarMetric {
        case .contributions: "octicon-calendar"
        case .prsOpened: "octicon-git-pull-request"
        case .prsMerged: "octicon-git-merge"
        }
    }
}

private struct MenuContent: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        if let quota = model.snapshot.quota {
            Text(quota.headline)
        }
        if let today = model.snapshot.todayCount {
            Text("Today so far: \(today) \(model.snapshot.unit)")
        }
        Text(freshness)
        Divider()
        Button(model.isSyncing ? "Refreshing…" : "Refresh Now") {
            Task { await model.refresh() }
        }
        .disabled(model.isSyncing || model.settings.login.isEmpty)
        .keyboardShortcut("r")
        Button("Open Slopometer…") { model.openMainWindow() }
            .keyboardShortcut("o")
        Divider()
        Text("Version \(BuildInfo.summary)")
        Button("Quit Slopometer") { NSApplication.shared.terminate(nil) }
            .keyboardShortcut("q")
    }

    private var freshness: String {
        guard let synced = model.snapshot.lastSuccessfulSync else { return "Not synced yet" }
        return "Synced \(synced.formatted(.relative(presentation: .named)))"
    }
}
