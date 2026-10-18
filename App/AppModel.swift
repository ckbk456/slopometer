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
            if settings.login != oldValue.login {
                // A check made for the previous username says nothing about this one.
                lastReport = nil
            }
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
    /// Coalesces refreshes; a request made during a sync runs right after it.
    private var gate = RefreshGate()
    var isSyncing: Bool { gate.isRunning }
    /// What the running sync is doing, for the refresh controls.
    private(set) var syncStage: SyncStage?
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
    /// The opt-in notification for reaching the daily PR quota.
    let quotaNotifier = QuotaNotifier()

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
        quotaNotifier.openWindow = { [weak self] in self?.openMainWindow() }
        startPolling()
        NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification, object: nil, queue: .main
        ) { [weak self] _ in
            Task { @MainActor in await self?.refreshIfStale() }
        }
    }

    // MARK: Derived state

    var hasToken: Bool { !tokens.isEmpty }

    /// The measured account: the earliest saved token's known owner, else the typed username.
    var accountLogin: String {
        AccountResolver.account(owners: tokens.map(\.owner), fallback: settings.login)
    }

    /// Whether the account comes from token owners rather than the typed username.
    var accountFromTokens: Bool { tokens.contains { $0.owner != nil } }

    /// The last report, only when it was made for the account now displayed.
    private var currentReport: SyncReport? {
        guard let lastReport, AccountResolver.same(lastReport.login, accountLogin) else {
            return nil
        }
        return lastReport
    }

    /// Each saved token's standing for the current account, in the order they were added.
    func state(of token: TokenEntry) -> TokenState {
        TokenState.resolve(
            tokenID: token.id, savedOwner: token.owner, account: accountLogin,
            report: currentReport)
    }

    /// A token verified for the current account (in a check this session, or remembered).
    var tokenUsable: Bool { tokens.contains { state(of: $0).counts } }

    /// The connection in use, worded the same in the badge, Settings, and menu bar panel.
    var connectionLabel: String {
        let states = tokens.map { ($0.kind, state(of: $0)) }
        return ConnectionLabel.describe(
            fineGrained: states.filter { $0.0 == .fineGrained && $0.1.counts }.count,
            classic: states.filter { $0.0 == .classic && $0.1.counts }.count,
            checking: states.filter { $0.1 == .checking }.count)
    }

    /// Where a token-derived account came from, for the disabled username field.
    var accountSource: String {
        let counted = tokens.filter { state(of: $0).counts }
        return ConnectionLabel.source(
            fineGrained: counted.filter { $0.kind == .fineGrained }.count,
            classic: counted.filter { $0.kind == .classic }.count)
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

    /// Syncs now, or right after the sync in progress, so a change made during a sync
    /// (new token, removed token, new username) is never dropped.
    func refresh() async {
        guard let coordinator, !accountLogin.isEmpty || hasToken else { return }
        guard gate.request() else { return }
        repeat {
            await sync(with: coordinator)
        } while gate.finish()
    }

    private func sync(with coordinator: SyncCoordinator) async {
        guard !accountLogin.isEmpty || hasToken else { return }
        lastAttempt = Date()
        // Read at the start of each run, so a queued run uses the latest settings and tokens.
        let report = await coordinator.sync(
            SyncRequest(
                login: accountLogin, tokens: TokenStore.tokens(), timeZone: settings.timeZone,
                historyDays: settings.historyDays)
        ) { [weak self] progress in
            await MainActor.run { self?.advance(to: progress) }
        }
        var owners: [String: String?] = report.tokenOwners.mapValues { Optional($0) }
        for (id, error) in report.tokenErrors where error == .unauthorized {
            owners[id] = .some(nil)
        }
        TokenStore.setOwners(owners)
        tokens = TokenStore.entries()
        lastReport = report
        consecutiveFailures =
            report.calendarError == nil && report.pullRequestError == nil
            ? 0 : consecutiveFailures + 1
        syncStage = nil
        rebuild()
        // Only a sync that verified a token and fetched PRs confirms today's count.
        let confirmed = currentReport.map { $0.tokenVerified && $0.pullRequestError == nil }
        quotaNotifier.check(
            quota: snapshot.quota, goal: settings.goal, repositories: settings.repositories,
            timeZone: settings.timeZone, confirmed: confirmed ?? false)
    }

    /// Shows each stage and publishes data the sync has already written, so the calendar
    /// and recent PRs appear before older history finishes loading.
    private func advance(to progress: SyncProgress) {
        syncStage = progress.stage
        if progress.cacheChanged { rebuild() }
    }

    /// Text for the refresh control: the running stage, else the action.
    var refreshLabel: String {
        isSyncing ? syncStage?.label ?? "Refreshing…" : "Refresh Now"
    }

    func refreshIfStale() async {
        guard let lastAttempt else { return await refresh() }
        if Date().timeIntervalSince(lastAttempt) > 10 * 60 { await refresh() }
    }

    enum TokenSaveResult {
        case saved
        case duplicate
        case classicNotAllowed
        case keychainFailed
    }

    /// Saves a token; its kind follows GitHub's prefix. Classic tokens need InsecuSlopometer™.
    func addToken(_ token: String, label: String) -> TokenSaveResult {
        let value = token.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty else { return .keychainFailed }
        guard AccessToken.Kind(of: value) == .fineGrained || allowsClassicTokens
        else { return .classicNotAllowed }
        if TokenStore.tokens().contains(where: { $0.value == value }) { return .duplicate }
        let name = label.trimmingCharacters(in: .whitespaces)
        let fallback = tokens.isEmpty ? "Personal" : "Token \(tokens.count + 1)"
        guard TokenStore.add(value, label: name.isEmpty ? fallback : name) != nil else {
            return .keychainFailed
        }
        tokens = TokenStore.entries()
        lastReport = nil
        rebuild()
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

    func openMainWindow() {
        openWindowAction?(id: SlopometerApp.mainWindowID)
        NSApp.activate()
    }

    // MARK: Internals

    private func rebuild() {
        guard let cache else { return }
        var problems: [String] = []
        if let startupError { problems.append(startupError) }
        let report = currentReport
        if let error = report?.calendarError { problems.append(error.message) }
        for token in tokens {
            guard let error = report?.tokenErrors[token.id] else { continue }
            problems.append(
                tokens.count > 1 ? "Token “\(token.label)”: \(error.message)" : error.message)
        }
        // Without a verified token the PR error is a token error already listed above.
        if report?.tokenVerified == true, let error = report?.pullRequestError {
            problems.append(error.message)
        }
        // The snapshot names the measured account, which may come from the tokens.
        var measured = settings
        measured.login = accountLogin
        do {
            records = try cache.holds(measured.login) ? cache.pullRequests() : []
            snapshot = try SnapshotBuilder.build(
                settings: measured, cache: cache, tokenUsable: tokenUsable, problems: problems)
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
            // Stamped with this build, so a widget from another build can say so.
            var shared = snapshot
            shared.writerBuild = BuildInfo.stamp
            if try SharedSnapshot.write(shared) {
                WidgetCenter.shared.reloadAllTimelines()
            }
            widgetProblem = nil
        } catch {
            widgetProblem =
                "macOS blocked the widget's shared folder, so the widget can't update. Quit other copies of Slopometer and run a signed build (make run)."
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
