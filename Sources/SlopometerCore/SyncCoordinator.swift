import Foundation

public struct SyncRequest: Sendable {
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

public struct SyncReport: Equatable, Sendable {
    public var calendarError: GitHubError?
    /// PR data was not refreshed: no token was usable, or the PR fetch failed.
    public var pullRequestError: GitHubError?
    /// At least one token was verified as belonging to the configured login.
    public var tokenVerified = false
    /// Tokens verified as belonging to the configured login, by token ID.
    public var verifiedTokenIDs: Set<String> = []
    /// Tokens that were rejected, belong to someone else, or could not be checked.
    public var tokenErrors: [String: GitHubError] = [:]

    public var rateLimitReset: Date? {
        for error in [calendarError, pullRequestError] {
            if case .rateLimited(let reset) = error { return reset }
        }
        return nil
    }
}

/// The one owner of GitHub requests. Each sync refetches the history window and
/// replaces cached records, which reconciles delayed merges and removed PRs.
public actor SyncCoordinator {
    private let client: GitHubClient
    private let cache: MeasurementCache

    public init(client: GitHubClient, cache: MeasurementCache) {
        self.client = client
        self.cache = cache
    }

    public func sync(_ request: SyncRequest) async -> SyncReport {
        var report = SyncReport()
        guard GitHubClient.isValidLogin(request.login) else {
            report.calendarError = .invalidLogin
            return report
        }
        do {
            if try cache.syncState().login?.lowercased() != request.login.lowercased() {
                try cache.reset(for: request.login)
            }
        } catch {
            report.calendarError = .malformedResponse
            return report
        }

        let today = CalendarDay.containing(request.now, in: request.timeZone)
        let start = today.adding(days: -request.historyDays).start(in: request.timeZone)

        var verified: [AccessToken] = []
        for token in request.tokens {
            do {
                let owner = try await client.viewerLogin(token: token.value)
                if owner.lowercased() == request.login.lowercased() {
                    verified.append(token)
                    report.verifiedTokenIDs.insert(token.id)
                } else {
                    report.tokenErrors[token.id] = .tokenOwnerMismatch(
                        expected: request.login, actual: owner)
                }
            } catch {
                report.tokenErrors[token.id] = Self.githubError(error)
            }
        }
        report.tokenVerified = !verified.isEmpty
        if verified.isEmpty, let first = request.tokens.first {
            report.pullRequestError = report.tokenErrors[first.id]
        }

        do {
            if let token = verified.first {
                let counts = try await client.contributionCalendar(
                    login: request.login, token: token.value, from: start, to: request.now)
                try cache.replaceCalendar(counts, source: .graphQL, at: request.now)
            } else {
                let counts = try await client.profileCalendar(login: request.login)
                try cache.replaceCalendar(counts, source: .profilePage, at: request.now)
            }
        } catch {
            report.calendarError = Self.githubError(error)
        }

        if !verified.isEmpty {
            do {
                // Each token sees a different set of repositories; merge by node ID.
                var byID: [String: PullRequestRecord] = [:]
                // A token that could not be used hides its repositories, so counts may be low.
                var incomplete = verified.count < request.tokens.count
                for token in verified {
                    let fetch = try await client.authoredPullRequests(
                        login: request.login, token: token.value, from: start, to: request.now)
                    incomplete = incomplete || fetch.isIncomplete
                    for record in fetch.records { byID[record.id] = record }
                }
                try cache.replacePullRequests(
                    byID.values.sorted { $0.createdAt < $1.createdAt }, coveringFrom: start,
                    incomplete: incomplete, at: request.now)
            } catch {
                report.pullRequestError = Self.githubError(error)
            }
        }
        return report
    }

    private static func githubError(_ error: Error) -> GitHubError {
        (error as? GitHubError) ?? .malformedResponse
    }
}
