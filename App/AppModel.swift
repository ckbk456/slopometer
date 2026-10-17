import AppKit
import Observation
import SlopometerCore
import SwiftUI
import WidgetKit

/// Owns settings, polling, and the snapshot every surface renders.
@MainActor
@Observable
final class AppModel {
    private static let settingsKey = "settings"
    private static let classicTokensKey = "allowClassicTokens"
    private static let parkedGoalKey = "parkedGoal"
    static let pollInterval: TimeInterval = 15 * 60

    var settings: DashboardSettings {
        didSet {
            guard settings != oldValue else { return }
            persistSettings()
            rebuild()
            if settings.login != oldValue.login || settings.historyKey != oldValue.historyKey {
                Task { await refresh() }
            }
        }
    }
    private(set) var snapshot = DashboardSnapshot.placeholder
    /// Captured with the snapshot so failed rebuilds cannot relabel an older quota.
    private(set) var menuBarMetric = Metric.contributions
    private(set) var records: [PullRequestRecord] = []
    private(set) var isSyncing = false
    /// The quota's counts and target while the quota is off, so turning it on restores them.
    var parkedGoal: Goal {
        didSet {
            if let data = try? JSONEncoder().encode(parkedGoal) {
                UserDefaults.standard.set(data, forKey: Self.parkedGoalKey)
            }
        }
    }
    /// Saved tokens' nonsecret details, in the order they were added.
    private(set) var tokens: [TokenEntry]
    /// InsecuSlopometer™: accept classic tokens, which cannot be limited to read-only.
    var allowsClassicTokens: Bool {
        didSet { UserDefaults.standard.set(allowsClassicTokens, forKey: Self.classicTokensKey) }
    }
    private(set) var lastReport: SyncReport?
    private(set) var lastAttempt: Date?
    private(set) var startupError: String?
    /// Set when the snapshot could not be shared, so the widget is showing stale or no data.
    private(set) var widgetProblem: String?

    var openWindowAction: OpenWindowAction?

    private let cache: MeasurementCache?
    private let coordinator: SyncCoordinator?
    private var pollTask: Task<Void, Never>?
    private var consecutiveFailures = 0

    init() {
        if let data = UserDefaults.standard.data(forKey: Self.settingsKey),
            let saved = try? JSONDecoder().decode(DashboardSettings.self, from: data)
        {
            settings = saved
        } else {
            settings = DashboardSettings()
        }
        tokens = TokenStore.entries()
        allowsClassicTokens = UserDefaults.standard.bool(forKey: Self.classicTokensKey)
        parkedGoal =
            UserDefaults.standard.data(forKey: Self.parkedGoalKey)
            .flatMap { try? JSONDecoder().decode(Goal.self, from: $0) } ?? Goal()
        do {
            let cache = try MeasurementCache(path: Self.cachePath())
            self.cache = cache
            coordinator = SyncCoordinator(client: GitHubClient(), cache: cache)
        } catch {
            cache = nil
            coordinator = nil
            startupError = "The local cache could not be opened: \(error.localizedDescription)"
        }
        rebuild()
        startPolling()
        NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification, object: nil, queue: .main
        ) { [weak self] _ in
            Task { @MainActor in await self?.refreshIfStale() }
        }
    }

    // MARK: Derived state

    var hasToken: Bool { !tokens.isEmpty }

    /// A token exists and they were not all rejected or found to belong to someone else.
    var tokenUsable: Bool {
        guard hasToken else { return false }
        if lastReport?.tokenVerified == true { return true }
        switch lastReport?.pullRequestError {
        case .tokenOwnerMismatch, .unauthorized: return false
        default: return true
        }
    }

    /// Short text for the menu bar: quota progress, else today's count.
    var menuBarTitle: String {
        if let quota = snapshot.quota { return "\(quota.count)/\(quota.target)" }
        if let today = snapshot.todayCount { return "\(today)" }
        return "–"
    }

    /// Full wording for the compact badge's tooltip and accessibility label.
    var menuBarDescription: String {
        if let quota = snapshot.quota { return quota.headline }
        if let today = snapshot.todayCount { return "Today so far: \(today) \(snapshot.unit)" }
        return "\(menuBarMetric.title): no data yet"
    }

    /// PRs behind a day's count for the selected PR metric.
    func evidence(on day: CalendarDay) -> [PullRequestRecord] {
        guard settings.metric.requiresToken, tokenUsable else { return [] }
        return PullRequestScope(
            metric: settings.metric, repositories: Set(settings.repositories),
            timeZone: settings.timeZone
        ).evidence(on: day, in: records)
    }

    // MARK: Actions

    func refresh() async {
        guard let coordinator, !isSyncing, !settings.login.isEmpty else { return }
        isSyncing = true
        lastAttempt = Date()
        let report = await coordinator.sync(
            SyncRequest(
                login: settings.login, tokens: TokenStore.tokens(), timeZone: settings.timeZone,
                historyDays: settings.historyDays))
        lastReport = report
        consecutiveFailures =
            report.calendarError == nil && report.pullRequestError == nil
            ? 0 : consecutiveFailures + 1
        isSyncing = false
        rebuild()
    }

    func refreshIfStale() async {
        guard let lastAttempt else { return await refresh() }
        if Date().timeIntervalSince(lastAttempt) > 10 * 60 { await refresh() }
    }

    enum TokenSaveResult {
        case saved
        case duplicate
        case wrongKind
        case keychainFailed
    }

    func addToken(_ token: String, label: String, as kind: AccessToken.Kind) -> TokenSaveResult {
        let value = token.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty else { return .keychainFailed }
        guard AccessToken.Kind(of: value) == kind, kind == .fineGrained || allowsClassicTokens
        else { return .wrongKind }
        if TokenStore.tokens().contains(where: { $0.value == value }) { return .duplicate }
        let name = label.trimmingCharacters(in: .whitespaces)
        let fallback = tokens.isEmpty ? "Personal" : "Token \(tokens.count + 1)"
        guard TokenStore.add(value, label: name.isEmpty ? fallback : name) != nil else {
            return .keychainFailed
        }
        tokens = TokenStore.entries()
        lastReport = nil
        Task { await refresh() }
        return .saved
    }

    func removeToken(_ id: String) {
        TokenStore.remove(id)
        tokens = TokenStore.entries()
        lastReport = nil
        rebuild()
        Task { await refresh() }
    }

    /// Short status for one saved token from the last sync.
    func status(of token: TokenEntry) -> (text: String, ok: Bool) {
        switch lastReport?.tokenErrors[token.id] {
        case .tokenOwnerMismatch(_, let actual)?:
            return ("Belongs to @\(actual), not counted", false)
        case .unauthorized?: return ("Rejected by GitHub", false)
        case let error?: return ("Not checked: \(error.message)", false)
        case nil:
            if lastReport?.verifiedTokenIDs.contains(token.id) == true {
                return ("Verified for @\(settings.login)", true)
            }
            return ("Saved in Keychain", true)
        }
    }

    func openMainWindow() {
        openWindowAction?(id: SlopometerApp.mainWindowID)
        NSApp.activate()
    }

    // MARK: Internals

    private func rebuild() {
        guard let cache else { return }
        var problems: [String] = []
        if let startupError { problems.append(startupError) }
        if let error = lastReport?.calendarError { problems.append(error.message) }
        for token in tokens {
            guard let error = lastReport?.tokenErrors[token.id] else { continue }
            problems.append(
                tokens.count > 1 ? "Token “\(token.label)”: \(error.message)" : error.message)
        }
        // Without a verified token the PR error is a token error already listed above.
        if lastReport?.tokenVerified == true, let error = lastReport?.pullRequestError {
            problems.append(error.message)
        }
        do {
            records = try cache.pullRequests()
            snapshot = try SnapshotBuilder.build(
                settings: settings, cache: cache, tokenUsable: tokenUsable, problems: problems)
            menuBarMetric =
                snapshot.quota == nil
                ? snapshot.metric : settings.goal?.metric ?? snapshot.metric
        } catch {
            startupError = "Could not read the local cache: \(error.localizedDescription)"
            return
        }
        shareWithWidget()
    }

    /// The widget only sees what lands in the App Group container. Unsigned builds, or a
    /// second copy of the app signed differently, are refused access by macOS.
    private func shareWithWidget() {
        do {
            if try SharedSnapshot.write(snapshot) {
                WidgetCenter.shared.reloadAllTimelines()
            }
            widgetProblem = nil
        } catch {
            widgetProblem =
                "The widget can't be updated because macOS blocked access to Slopometer's shared folder. Quit every other copy of Slopometer and launch a signed build (make run)."
        }
    }

    private func startPolling() {
        pollTask = Task { [weak self] in
            while !Task.isCancelled {
                guard let self else { return }
                await self.refresh()
                try? await Task.sleep(for: .seconds(self.nextDelay()))
            }
        }
    }

    /// Conservative polling with backoff after errors and waiting out rate limits.
    private func nextDelay() -> TimeInterval {
        if let reset = lastReport?.rateLimitReset {
            return max(60, reset.timeIntervalSinceNow + 5)
        }
        guard consecutiveFailures > 0 else { return Self.pollInterval }
        return min(3600, 60 * pow(2, Double(min(consecutiveFailures, 6))))
    }

    private func persistSettings() {
        if let data = try? JSONEncoder().encode(settings) {
            UserDefaults.standard.set(data, forKey: Self.settingsKey)
        }
    }

    private static func cachePath() throws -> String {
        let directory = try FileManager.default.url(
            for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil,
            create: true
        ).appendingPathComponent("Slopometer", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory.appendingPathComponent("cache.sqlite").path
    }
}

extension DashboardSettings {
    /// Largest range plus the largest warm-up, so switching views needs no refetch.
    var historyDays: Int { (Self.ranges.max() ?? 365) + (Self.averageWindows.max() ?? 30) }

    /// Settings that change what must be fetched.
    var historyKey: String { timeZoneID }
}
