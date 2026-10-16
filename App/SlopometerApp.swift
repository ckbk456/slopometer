import AppKit
import SwiftUI

@main
struct SlopometerApp: App {
    @Environment(\.openWindow) private var openWindow

    var body: some Scene {
        Window("Slopometer", id: "slopometer") {
            ScaffoldView()
        }
        .defaultSize(width: 640, height: 420)
        .windowResizability(.contentMinSize)

        MenuBarExtra("Slopometer", systemImage: "gauge.with.dots.needle.50percent") {
            Button("Show Slopometer") {
                openWindow(id: "slopometer")
                NSApplication.shared.activate(ignoringOtherApps: true)
            }
            Divider()
            Button("Quit Slopometer") {
                NSApplication.shared.terminate(nil)
            }
            .keyboardShortcut("q")
        }
    }
}
