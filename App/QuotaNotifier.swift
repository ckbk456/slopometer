import AppKit
import Observation
import SlopometerCore
import UserNotifications

/// The opt-in "Daily slop quota reached" notification, at most once per goal and day.
/// The rules are in `QuotaCompletion`; this posts it and remembers what was announced.
@MainActor
@Observable
final class QuotaNotifier: NSObject {
    private static let enabledKey = "quotaNotification"
    private static let announcedKey = "quotaNotificationAnnounced"

    /// The person's choice. macOS permission is separate; see `isBlocked`.
    private(set) var isOn: Bool
    /// macOS has notifications for Slopometer turned off.
    private(set) var isBlocked = false
    @ObservationIgnored var openWindow: (() -> Void)?

    override init() {
        isOn = UserDefaults.standard.bool(forKey: Self.enabledKey)
        super.init()
        UNUserNotificationCenter.current().delegate = self
        if isOn { Task { await refreshPermission() } }
    }

    /// Turning it on asks macOS for permission the first time.
    func set(_ on: Bool) async {
        isOn = on
        UserDefaults.standard.set(on, forKey: Self.enabledKey)
        guard on else { return }
        let center = UNUserNotificationCenter.current()
        _ = try? await center.requestAuthorization(options: [.alert, .sound])
        await refreshPermission()
    }

    func refreshPermission() async {
        let settings = await UNUserNotificationCenter.current().notificationSettings()
        isBlocked = settings.authorizationStatus == .denied
    }

    func openSystemSettings() {
        let id = Bundle.main.bundleIdentifier ?? ""
        if let url = URL(
            string: "x-apple.systempreferences:com.apple.Notifications-Settings.extension?id=\(id)")
        {
            NSWorkspace.shared.open(url)
        }
    }

    /// Called after each sync. `confirmed` means the sync verified a token and fetched PRs.
    func check(
        quota: DashboardSnapshot.Quota?, goal: Goal?, repositories: [String],
        timeZone: TimeZone, confirmed: Bool
    ) {
        guard isOn else { return }
        let day = CalendarDay.containing(Date(), in: timeZone)
        var announced = Set(
            (UserDefaults.standard.stringArray(forKey: Self.announcedKey) ?? [])
                .filter { QuotaCompletion.isFrom(day, key: $0) })
        guard
            let completion = QuotaCompletion.due(
                quota: quota, goal: goal, repositories: repositories, day: day,
                confirmed: confirmed, announced: announced)
        else { return }
        announced.insert(completion.key)
        UserDefaults.standard.set(Array(announced), forKey: Self.announcedKey)

        let content = UNMutableNotificationContent()
        content.title = completion.title
        content.body = completion.body
        content.sound = .default
        UNUserNotificationCenter.current().add(
            UNNotificationRequest(identifier: completion.key, content: content, trigger: nil))
    }
}

extension QuotaNotifier: @preconcurrency UNUserNotificationCenterDelegate {
    /// Shown even while the app is frontmost, which a menu bar app often is.
    func userNotificationCenter(
        _ center: UNUserNotificationCenter, willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) ->
            Void
    ) {
        completionHandler([.banner, .sound])
    }

    /// Clicking the notification opens the app window, where the counted PRs are listed.
    func userNotificationCenter(
        _ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        openWindow?()
        completionHandler()
    }
}
