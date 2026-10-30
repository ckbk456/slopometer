import Foundation

public struct SyncRequest: Sendable {
    /// The expected account: a remembered token owner, else the typed username. Token
    /// owners found during the sync take precedence (see `AccountResolver`).
    public let login: String
    /// Saved tokens in the order they were added; empty means username only.
    public let tokens: [AccessToken]
    public let timeZone: TimeZone
    public let now: Date
    /// Displayed range plus moving-average warm-up.
    public let historyDays: Int

    public init(
        login: String, tokens: [AccessToken], timeZone: TimeZone, now: Date = Date(),
        historyDays: Int = 395
    ) {
        self.login = login
        self.tokens = tokens.filter { !$0.value.isEmpty }
        self.timeZone = timeZone
        self.now = now
        self.historyDays = historyDays
    }

    public init(
        login: String, token: String?, timeZone: TimeZone, now: Date = Date(),
        historyDays: Int = 395
    ) {
        self.init(
            login: login, tokens: token.map { [AccessToken(id: "default", value: $0)] } ?? [],
            timeZone: timeZone, now: now, historyDays: historyDays)
    }
}

/// How the PR records were refreshed.
public enum PullRequestSyncMode: Equatable, Sendable {
    /// The whole window was refetched, recent days first, and stale records removed.
    case fullReconcile
    /// Only PRs GitHub updated since each token's checkpoint were fetched and merged in.
    case changesOnly
}

public struct SyncReport: Equatable, Sendable {
    /// The account this sync measured: the earliest token owner found, else the request's login.
    public var login = ""
    /// Tokens this sync checked. A token added later is not covered by this report.
    public var checkedTokenIDs: Set<String> = []
    /// Each checked token's owner (`viewer.login`), by token ID. Missing when the check failed.
    public var tokenOwners: [String: String] = [:]
    public var calendarError: GitHubError?
    /// True only after this run successfully replaced the contribution calendar.
    public var calendarUpdated = false
    /// PR data was not refreshed: no token was usable, or the PR fetch failed.
    public var pullRequestError: GitHubError?
    /// At least one token was verified as belonging to the account.
    public var tokenVerified = false
    /// Tokens verified as belonging to the account, by token ID.
    public var verifiedTokenIDs: Set<String> = []
    /// Tokens that were rejected, belong to someone else, or could not be checked.
    public var tokenErrors: [String: GitHubError] = [:]
    /// Nil when no PR fetch was attempted.
    public var pullRequestSyncMode: PullRequestSyncMode?

    /// A failure of one source cannot confirm that source's goal from old cached data.
    public func confirms(_ metric: Metric) -> Bool {
        if metric == .contributions { return calendarUpdated && calendarError == nil }
        return tokenVerified && pullRequestSyncMode != nil && pullRequestError == nil
            && tokenErrors.isEmpty
    }

    public var rateLimitReset: Date? {
        for error in [calendarError, pullRequestError] {
            if case .rateLimited(let reset) = error { return reset }
        }
        return nil
    }
}

/// What a sync is doing, in the order it happens.
public enum SyncStage: Equatable, Sendable {
    case checkingTokens
    case updatingCalendar
    case fetchingRecentPullRequests
    case loadingOlderPullRequests
    case fetchingPullRequestChanges

    public var label: String {
        switch self {
        case .checkingTokens: "Checking tokens…"
        case .updatingCalendar: "Updating calendar…"
        case .fetchingRecentPullRequests: "Fetching recent PRs…"
        case .loadingOlderPullRequests: "Loading older PRs…"
        case .fetchingPullRequestChanges: "Fetching PR changes…"
        }
    }
}

/// Reported when a stage starts. `cacheChanged` means an earlier stage of this sync wrote
/// data the caller can already display.
public struct SyncProgress: Equatable, Sendable {
    public let stage: SyncStage
    public let cacheChanged: Bool
}

/// The one owner of GitHub requests. A first sync, a new token, or a daily reconcile
/// refetches the history window (recent days first) and replaces cached records, which
/// removes deleted or inaccessible PRs. Every other sync fetches only PRs GitHub updated
/// since each token's checkpoint and merges them in.
public actor SyncCoordinator {
    /// Fetched and published before the rest of the window on a full sync.
    public static let recentDays = 30
    /// A full refetch at least this often catches deleted PRs and lost repository access.
    public static let fullReconcileInterval: TimeInterval = 24 * 3600
    /// Re-requested before each checkpoint to cover GitHub's search indexing delay.
    public static let changesOverlap: TimeInterval = 6 * 3600

    private let client: GitHubClient
    private let cache: MeasurementCache

    public init(client: GitHubClient, cache: MeasurementCache) {
        self.client = client
        self.cache = cache
    }

    public func sync(
        _ request: SyncRequest, onProgress: @Sendable (SyncProgress) async -> Void = { _ in }
    ) async -> SyncReport {
        var report = SyncReport()
        report.checkedTokenIDs = Set(request.tokens.map(\.id))
        // Owners first: with tokens, the account is the earliest token's owner.
        for token in request.tokens {
            do {
                report.tokenOwners[token.id] = try await client.viewerLogin(token: token.value)
            } catch {
                report.tokenErrors[token.id] = Self.githubError(error)
            }
        }
        let login = AccountResolver.account(
            owners: request.tokens.map { report.tokenOwners[$0.id] }, fallback: request.login)
        report.login = login
        guard GitHubClient.isValidLogin(login) else {
            report.calendarError = .invalidLogin
            return report
        }
        do {
            if try cache.syncState().login?.lowercased() != login.lowercased() {
                try cache.reset(for: login)
            }
        } catch {
            report.calendarError = .malformedResponse
            return report
        }

        let today = CalendarDay.containing(request.now, in: request.timeZone)
        let start = today.adding(days: -request.historyDays).start(in: request.timeZone)

        await onProgress(SyncProgress(stage: .checkingTokens, cacheChanged: false))
        var verified: [AccessToken] = []
        for token in request.tokens {
            guard let owner = report.tokenOwners[token.id] else { continue }
            if AccountResolver.same(owner, login) {
                verified.append(token)
                report.verifiedTokenIDs.insert(token.id)
            } else {
                report.tokenErrors[token.id] = .tokenOwnerMismatch(expected: login, actual: owner)
            }
        }
        report.tokenVerified = !verified.isEmpty
        if verified.isEmpty, let first = request.tokens.first {
            report.pullRequestError = report.tokenErrors[first.id]
        }

        await onProgress(SyncProgress(stage: .updatingCalendar, cacheChanged: false))
        var cacheChanged = false
        do {
            if let token = verified.first {
                let counts = try await client.contributionCalendar(
                    login: login, token: token.value, from: start, to: request.now)
                try cache.replaceCalendar(counts, source: .graphQL, at: request.now)
            } else {
                let counts = try await client.profileCalendar(login: login)
                try cache.replaceCalendar(counts, source: .profilePage, at: request.now)
            }
            cacheChanged = true
            report.calendarUpdated = true
        } catch {
            report.calendarError = Self.githubError(error)
        }

        guard !verified.isEmpty else { return report }
        // A token that could not be used hides its repositories, so counts may be low.
        let missingTokens = verified.count < request.tokens.count
        do {
            let state = try cache.syncState()
            if Self.needsFullReconcile(state, verified: verified, start: start, now: request.now) {
                report.pullRequestSyncMode = .fullReconcile
                try await fullReconcile(
                    request, login: login, verified: verified, start: start,
                    missingTokens: missingTokens,
                    cacheChanged: cacheChanged, report: &report, onProgress: onProgress)
            } else {
                report.pullRequestSyncMode = .changesOnly
                try await fetchChanges(
                    request, login: login, verified: verified, start: start, state: state,
                    cacheChanged: cacheChanged, report: &report, onProgress: onProgress)
            }
        } catch {
            report.pullRequestError = Self.githubError(error)
        }
        return report
    }

    static func needsFullReconcile(
        _ state: SyncState, verified: [AccessToken], start: Date, now: Date
    ) -> Bool {
        guard let lastFull = state.lastFullPullRequestSync,
            let coverageStart = state.pullRequestCoverageStart
        else { return true }
        if start < coverageStart { return true }
        if now.timeIntervalSince(lastFull) >= fullReconcileInterval { return true }
        return verified.contains { state.pullRequestCheckpoints[$0.id] == nil }
    }

    /// Recent days for every token, published, then the rest of the window. The cache is
    /// replaced only when every verified token covered the whole window.
    private func fullReconcile(
        _ request: SyncRequest, login: String, verified: [AccessToken], start: Date,
        missingTokens: Bool,
        cacheChanged: Bool, report: inout SyncReport,
        onProgress: @Sendable (SyncProgress) async -> Void
    ) async throws {
        let today = CalendarDay.containing(request.now, in: request.timeZone)
        let recentStart = max(
            start, today.adding(days: -Self.recentDays).start(in: request.timeZone))

        await onProgress(
            SyncProgress(stage: .fetchingRecentPullRequests, cacheChanged: cacheChanged))
        var fetched: [PullRequestFetch] = []
        var checkpoints: [String: Date] = [:]
        for token in verified {
            fetched.append(
                try await client.authoredPullRequests(
                    login: login, token: token.value, from: recentStart, to: request.now))
        }
        let recent = GitHubClient.merge(fetched)
        guard recentStart > start else {
            try cache.replacePullRequests(
                recent.records, coveringFrom: start,
                incomplete: missingTokens || recent.isIncomplete,
                checkpoints: Self.checkpoints(for: verified, at: request.now), at: request.now)
            return
        }
        // Older records stay until the whole window is in; days before coverage are unknown.
        try cache.upsertPullRequests(
            recent.records, coveringFrom: recentStart, incomplete: recent.isIncomplete,
            at: request.now)

        await onProgress(SyncProgress(stage: .loadingOlderPullRequests, cacheChanged: true))
        var failure: GitHubError?
        for token in verified {
            do {
                fetched.append(
                    try await client.authoredPullRequests(
                        login: login, token: token.value, from: start,
                        to: recentStart.addingTimeInterval(-1)))
                checkpoints[token.id] = request.now
            } catch {
                failure = Self.githubError(error)
                if Self.stopsTheSync(failure!) { break }
            }
        }
        let all = GitHubClient.merge(fetched)
        if let failure {
            // Keep what was fetched. Coverage stays at the recent window, so older days
            // show as unknown, and the failed token has no checkpoint, so the next sync
            // refetches the window.
            try cache.upsertPullRequests(
                all.records, coveringFrom: recentStart, incomplete: all.isIncomplete,
                checkpoints: checkpoints, at: request.now)
            report.pullRequestError = failure
            return
        }
        try cache.replacePullRequests(
            all.records, coveringFrom: start, incomplete: missingTokens || all.isIncomplete,
            checkpoints: checkpoints, at: request.now)
    }

    /// PRs updated since each token's checkpoint, merged into the cache by node ID.
    private func fetchChanges(
        _ request: SyncRequest, login: String, verified: [AccessToken], start: Date,
        state: SyncState,
        cacheChanged: Bool, report: inout SyncReport,
        onProgress: @Sendable (SyncProgress) async -> Void
    ) async throws {
        await onProgress(
            SyncProgress(stage: .fetchingPullRequestChanges, cacheChanged: cacheChanged))
        var fetched: [PullRequestFetch] = []
        var checkpoints: [String: Date] = [:]
        var failure: GitHubError?
        for token in verified {
            // Every verified token has a checkpoint, or this would be a full reconcile.
            let checkpoint =
                state.pullRequestCheckpoints[token.id] ?? state.lastFullPullRequestSync ?? start
            do {
                fetched.append(
                    try await client.updatedPullRequests(
                        login: login, token: token.value,
                        since: checkpoint.addingTimeInterval(-Self.changesOverlap),
                        to: request.now))
                checkpoints[token.id] = request.now
            } catch {
                failure = Self.githubError(error)
                if Self.stopsTheSync(failure!) { break }
            }
        }
        let changes = GitHubClient.merge(fetched)
        // `updated:` also returns old PRs touched for other reasons; only window activity counts.
        let inWindow = changes.records.filter {
            $0.createdAt >= start || ($0.mergedAt ?? .distantPast) >= start
        }
        // A failed token keeps its records and checkpoint; the report carries the error.
        try cache.upsertPullRequests(
            inWindow, coveringFrom: start, incomplete: changes.isIncomplete,
            checkpoints: checkpoints, at: request.now)
        if let failure { report.pullRequestError = failure }
    }

    /// Errors that affect every token, so the remaining tokens are not tried.
    private static func stopsTheSync(_ error: GitHubError) -> Bool {
        switch error {
        case .rateLimited, .offline: true
        default: false
        }
    }

    private static func checkpoints(for tokens: [AccessToken], at date: Date) -> [String: Date] {
        Dictionary(uniqueKeysWithValues: tokens.map { ($0.id, date) })
    }

    private static func githubError(_ error: Error) -> GitHubError {
        (error as? GitHubError) ?? .malformedResponse
    }
}
