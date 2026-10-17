import Foundation

public enum ChartStyle: String, Codable, CaseIterable, Identifiable, Sendable {
    case grid
    case columns
    case line

    public var id: String { rawValue }
    public var title: String { rawValue.capitalized }
}

/// Nonsecret preferences. The token is stored separately in Keychain.
public struct DashboardSettings: Codable, Equatable, Sendable {
    public static let ranges = [30, 90, 365]
    public static let averageWindows = [0, 7, 30]

    public var login = ""
    public var metric = Metric.contributions
    public var chartStyle = ChartStyle.grid
    public var rangeDays = 90
    /// 0 turns the moving average off.
    public var averageWindow = 7
    public var timeZoneID = TimeZone.current.identifier
    /// `owner/name` filter for PR metrics and the goal; empty means all readable repositories.
    public var repositories: [String] = []
    public var goal: Goal?

    public init() {}

    public var timeZone: TimeZone { TimeZone(identifier: timeZoneID) ?? .current }
}

/// What every surface renders: the app window, menu bar, and widget read the same values.
public struct DashboardSnapshot: Codable, Equatable, Sendable {
    public struct Point: Codable, Equatable, Identifiable, Sendable {
        public let day: CalendarDay
        public let count: Int?
        public let average: Double?
        public let isIncomplete: Bool
        public var id: CalendarDay { day }
    }

    public struct Quota: Codable, Equatable, Sendable {
        public struct Evidence: Codable, Equatable, Identifiable, Sendable {
            public let id: String
            public let number: Int
            public let title: String
            public let repository: String
            public let url: String
            public let isDraft: Bool
        }
        public let headline: String
        public let count: Int
        public let target: Int
        public let unit: String
        public let scopeLabel: String
        public let isReached: Bool
        public let coverageComplete: Bool
        public let evidence: [Evidence]
    }

    public enum Tier: String, Codable, Sendable {
        case notConfigured
        case usernameOnly
        case token
    }

    public let generatedAt: Date
    public let login: String
    public let tier: Tier
    public let metric: Metric
    public let chartStyle: ChartStyle
    public let rangeDays: Int
    public let averageWindow: Int
    public let sourceLabel: String
    public let scopeLabel: String
    public let points: [Point]
    /// The last `SnapshotBuilder.recentDays` days of the same series, whatever the selected
    /// range, so each widget size can show a fixed window. No averages.
    public let recentPoints: [Point]
    public let todayCount: Int?
    public let quota: Quota?
    public let lastSuccessfulSync: Date?
    /// Plain-language coverage, staleness, and token notes. Never empty when data is missing.
    public let notices: [String]

    public var unit: String { metric.unit }

    public static let placeholder = DashboardSnapshot(
        generatedAt: Date(), login: "", tier: .notConfigured, metric: .contributions,
        chartStyle: .grid, rangeDays: 30, averageWindow: 0, sourceLabel: "Not configured",
        scopeLabel: "", points: [], recentPoints: [], todayCount: nil, quota: nil,
        lastSuccessfulSync: nil,
        notices: ["Open Slopometer and enter a GitHub username."])
}

public enum SnapshotBuilder {
    public static let staleAfter: TimeInterval = 45 * 60
    /// 26 weeks: the large widget's grid.
    public static let recentDays = 26 * 7

    /// Lets surfaces that explain the token requirement themselves drop the duplicate.
    public static func tokenNeededNotice(for metric: Metric) -> String {
        "\(metric.title) needs a GitHub token. Add one in Settings."
    }

    /// - Parameters:
    ///   - tokenUsable: a token exists and the last sync verified its owner.
    ///   - problems: user-facing sync problems to surface alongside cached data.
    public static func build(
        settings: DashboardSettings, cache: MeasurementCache, tokenUsable: Bool,
        problems: [String], now: Date = Date()
    ) throws -> DashboardSnapshot {
        guard !settings.login.isEmpty else { return .placeholder }
        let state = try cache.syncState()
        let timeZone = settings.timeZone
        let today = CalendarDay.containing(now, in: timeZone)
        let warmUp = settings.averageWindow
        let span = max(settings.rangeDays + warmUp, recentDays)
        let allDays = CalendarDay.range(from: today.adding(days: -(span - 1)), through: today)
        var notices = problems
        let records = try cache.pullRequests()
        let prCoverageComplete = tokenUsable && !state.pullRequestResultsIncomplete

        let series: [DailyCount]
        let sourceLabel: String
        let scopeLabel: String
        let lastSync: Date?
        if settings.metric == .contributions {
            series = ContributionSeries.series(days: allDays, counts: try cache.calendar())
            sourceLabel = state.calendarSource?.label ?? "Not synced yet"
            scopeLabel = "Account-wide"
            lastSync = state.lastCalendarSync
            if state.calendarSource == .profilePage {
                notices.append(
                    "Username-only mode reads the public profile page. Add a token for PR metrics and quotas."
                )
            }
        } else if tokenUsable {
            let scope = PullRequestScope(
                metric: settings.metric, repositories: Set(settings.repositories),
                timeZone: timeZone)
            series = scope.series(
                days: allDays, records: records, coveredFrom: state.pullRequestCoverageStart)
            sourceLabel = "GitHub search API"
            scopeLabel = Goal.scopeLabel(for: settings.repositories)
            lastSync = state.lastPullRequestSync
            if state.pullRequestResultsIncomplete {
                notices.append(
                    "Some PRs may be missing (incomplete GitHub search, or a token that failed); counts may be low."
                )
            }
        } else {
            series = allDays.map { DailyCount(day: $0, count: nil) }
            sourceLabel = "Needs a GitHub token"
            scopeLabel = ""
            lastSync = nil
            notices.append(tokenNeededNotice(for: settings.metric))
        }

        if let lastSync, now.timeIntervalSince(lastSync) > staleAfter {
            notices.append(
                "Data is stale; last synced \(lastSync.formatted(.relative(presentation: .named)))."
            )
        }

        // Today is incomplete, so the trend uses completed days only.
        let completed = series.map { $0.day == today ? nil : $0.count }
        let averages =
            warmUp > 0
            ? (try? MovingAverage.trailing(completed, window: warmUp))
                ?? Array(repeating: nil, count: series.count)
            : Array(repeating: nil, count: series.count)
        let points = zip(series, averages).suffix(settings.rangeDays).map { daily, average in
            DashboardSnapshot.Point(
                day: daily.day, count: daily.count, average: average,
                isIncomplete: daily.day == today)
        }
        let recentPoints = series.suffix(recentDays).map { daily in
            DashboardSnapshot.Point(
                day: daily.day, count: daily.count, average: nil, isIncomplete: daily.day == today)
        }

        var quota: DashboardSnapshot.Quota?
        if let goal = settings.goal, goal.isValid, tokenUsable {
            let progress = QuotaProgress(
                goal: goal, repositories: settings.repositories, records: records, today: today,
                timeZone: timeZone,
                coverageComplete: prCoverageComplete)
            quota = DashboardSnapshot.Quota(
                headline: progress.headline, count: progress.count, target: progress.target,
                unit: goal.metric.unit, scopeLabel: progress.scopeLabel,
                isReached: progress.isReached, coverageComplete: progress.coverageComplete,
                evidence: progress.evidence.map {
                    .init(
                        id: $0.id, number: $0.number, title: $0.title, repository: $0.repository,
                        url: $0.url, isDraft: $0.isDraft)
                })
        } else if settings.goal != nil, !tokenUsable {
            notices.append("The daily PR quota needs a GitHub token.")
        }

        return DashboardSnapshot(
            generatedAt: now, login: settings.login,
            tier: tokenUsable ? .token : .usernameOnly, metric: settings.metric,
            chartStyle: settings.chartStyle, rangeDays: settings.rangeDays,
            averageWindow: settings.averageWindow, sourceLabel: sourceLabel,
            scopeLabel: scopeLabel, points: points, recentPoints: recentPoints,
            todayCount: points.last?.count, quota: quota,
            lastSuccessfulSync: lastSync, notices: notices)
    }
}

/// The snapshot file shared with the widget through the App Group container.
public enum SharedSnapshot {
    public static let appGroup = "5U4584QFCQ.dev.slopometer"
    private static let fileName = "snapshot.json"

    public static func url() -> URL? {
        FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: appGroup)?
            .appendingPathComponent(fileName)
    }

    public static func encode(_ snapshot: DashboardSnapshot) throws -> Data {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = .sortedKeys
        return try encoder.encode(snapshot)
    }

    public static func decode(_ data: Data) throws -> DashboardSnapshot {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(DashboardSnapshot.self, from: data)
    }

    /// Returns true when the stored snapshot changed, so callers reload widgets only then.
    @discardableResult
    public static func write(_ snapshot: DashboardSnapshot) throws -> Bool {
        guard let url = url() else { return false }
        let data = try encode(snapshot.withoutGenerationTime())
        if let existing = try? Data(contentsOf: url), existing == data { return false }
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try data.write(to: url, options: .atomic)
        return true
    }

    public static func read() -> DashboardSnapshot? {
        guard let url = url(), let data = try? Data(contentsOf: url) else { return nil }
        return try? decode(data)
    }
}

extension DashboardSnapshot {
    /// Equal content yields equal bytes, so unchanged data does not trigger widget reloads.
    func withoutGenerationTime() -> DashboardSnapshot {
        DashboardSnapshot(
            generatedAt: lastSuccessfulSync ?? Date(timeIntervalSince1970: 0), login: login,
            tier: tier, metric: metric, chartStyle: chartStyle, rangeDays: rangeDays,
            averageWindow: averageWindow, sourceLabel: sourceLabel, scopeLabel: scopeLabel,
            points: points, recentPoints: recentPoints, todayCount: todayCount, quota: quota,
            lastSuccessfulSync: lastSuccessfulSync, notices: notices)
    }
}
