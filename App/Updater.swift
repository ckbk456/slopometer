import AppKit
import Observation
import Sparkle

/// Release updates through Sparkle. Info.plist holds the feed, the key that signs every
/// update, and whether to check on a schedule: release builds do, development builds only
/// check when asked, so a newer release never offers to replace the build under test.
@MainActor
@Observable
final class Updater: NSObject {
    /// The version a scheduled check found, until the person looks at it. A menu bar app
    /// has no Dock badge to show, so the menu bar panel points at it instead.
    private(set) var pendingVersion: String?
    @ObservationIgnored private var controller: SPUStandardUpdaterController!

    override init() {
        super.init()
        controller = SPUStandardUpdaterController(
            startingUpdater: true, updaterDelegate: nil, userDriverDelegate: self)
    }

    /// Sparkle keeps the choice in the app's preferences; Info.plist supplies the default.
    var checksAutomatically: Bool {
        get {
            access(keyPath: \.checksAutomatically)
            return controller.updater.automaticallyChecksForUpdates
        }
        set {
            withMutation(keyPath: \.checksAutomatically) {
                controller.updater.automaticallyChecksForUpdates = newValue
            }
        }
    }

    /// Checks now, or brings forward an update alert that is already waiting.
    func checkForUpdates() {
        controller.checkForUpdates(nil)
    }
}

extension Updater: @preconcurrency SPUStandardUserDriverDelegate {
    var supportsGentleScheduledUpdateReminders: Bool { true }

    func standardUserDriverWillHandleShowingUpdate(
        _ handleShowingUpdate: Bool, forUpdate update: SUAppcastItem, state: SPUUserUpdateState
    ) {
        // A Dock icon while the alert is up, so it can be found behind other windows.
        NSApp.setActivationPolicy(.regular)
        if !state.userInitiated { pendingVersion = update.displayVersionString }
    }

    func standardUserDriverDidReceiveUserAttention(forUpdate update: SUAppcastItem) {
        pendingVersion = nil
    }

    func standardUserDriverWillFinishUpdateSession() {
        pendingVersion = nil
        NSApp.setActivationPolicy(.accessory)
    }
}
