import Foundation

public struct SyncRequest: Sendable {
    public let login: String
    public let token: String?
    public let timeZone: TimeZone
    public let now: Date
    /// Displayed range plus moving-average warm-up.
    public let historyDays: Int

    public init(
        login: String, token: String?, timeZone: TimeZone, now: Date = Date(),
        historyDays: Int = 395
    ) {
        self.login = login
        self.token = token?.isEmpty == true ? nil : token
        self.timeZone = timeZone
        self.now = now
        self.historyDays = historyDays
    }
}

public struct SyncReport: Equatable, Sendable {
    public var calendarError: GitHubError?
    public var pullRequestError: GitHubError?
    /// The token was verified as belonging to the configured login.
    public var tokenVerified = false

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

        var verifiedToken: String?
        if let token = request.token {
            do {
                let owner = try await client.viewerLogin(token: token)
                if owner.lowercased() == request.login.lowercased() {
                    verifiedToken = token
                    report.tokenVerified = true
                } else {
                    report.pullRequestError = .tokenOwnerMismatch(
                        expected: request.login, actual: owner)
                }
            } catch {
                report.pullRequestError = Self.githubError(error)
            }
        }

        do {
            if let token = verifiedToken {
                let counts = try await client.contributionCalendar(
                    login: request.login, token: token, from: start, to: request.now)
                try cache.replaceCalendar(counts, source: .graphQL, at: request.now)
            } else {
                let counts = try await client.profileCalendar(login: request.login)
                try cache.replaceCalendar(counts, source: .profilePage, at: request.now)
            }
        } catch {
            report.calendarError = Self.githubError(error)
        }

        if let token = verifiedToken {
            do {
                let fetch = try await client.authoredPullRequests(
                    login: request.login, token: token, from: start, to: request.now)
                try cache.replacePullRequests(
                    fetch.records, coveringFrom: start, incomplete: fetch.isIncomplete,
                    at: request.now)
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
