import Foundation

public enum ChartStyle: String, Codable, CaseIterable, Identifiable, Sendable {
    case grid
    case columns
    case line

    public var id: String { rawValue }
    public var title: String { rawValue.capitalized }
}

/// Light, dark, or following the system, for the app window, menu bar panel, and widget.
public enum AppearanceMode: String, Codable, CaseIterable, Identifiable, Sendable {
    case system
    case light
    case dark

    public var id: String { rawValue }
    public var title: String { rawValue.capitalized }
}

/// Spacing and control size in the app window and menu bar panel. Widgets keep the
/// system's fixed sizes.
public enum Density: String, Codable, CaseIterable, Identifiable, Sendable {
    case comfortable
    case compact

    public var id: String { rawValue }
    public var title: String { rawValue.capitalized }
}

/// Nonsecret preferences. The token is stored separately in Keychain.
public struct DashboardSettings: Codable, Equatable, Sendable {
    public static let ranges = [30, 90, 180, 365]
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
    public var widgets = WidgetSettings()
    /// Colors for the app, menu bar, and widget.
    public var theme = ColorTheme.standard
    public var appearance = AppearanceMode.system
    public var density = Density.comfortable
    /// Themes the person named, in the order they saved them.
    public var savedThemes: [SavedTheme] = []
    /// The current theme's other palette while light and dark share one.
    public var setAsidePalette: SetAsidePalette?
    /// Named dashboard configurations, in the order they were saved.
    public var savedConfigurations: [SavedConfiguration] = []
    /// The configuration last chosen or saved; it may have been edited since.
    public var configurationID: String?

    public init() {}

    /// Missing keys keep their defaults, so adding a setting never discards saved ones.
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let defaults = Self()
        login = try container.decodeIfPresent(String.self, forKey: .login) ?? defaults.login
        metric = try container.decodeIfPresent(Metric.self, forKey: .metric) ?? defaults.metric
        chartStyle =
            try container.decodeIfPresent(ChartStyle.self, forKey: .chartStyle)
            ?? defaults.chartStyle
        rangeDays =
            try container.decodeIfPresent(Int.self, forKey: .rangeDays) ?? defaults.rangeDays
        averageWindow =
            try container.decodeIfPresent(Int.self, forKey: .averageWindow)
            ?? defaults.averageWindow
        timeZoneID =
            try container.decodeIfPresent(String.self, forKey: .timeZoneID)
            ?? defaults.timeZoneID
        repositories =
            try container.decodeIfPresent([String].self, forKey: .repositories)
            ?? defaults.repositories
        goal = try container.decodeIfPresent(Goal.self, forKey: .goal)
        widgets =
            try container.decodeIfPresent(WidgetSettings.self, forKey: .widgets)
            ?? defaults.widgets
        theme = try container.decodeIfPresent(ColorTheme.self, forKey: .theme) ?? defaults.theme
        appearance =
            try container.decodeIfPresent(AppearanceMode.self, forKey: .appearance)
            ?? defaults.appearance
        density = try container.decodeIfPresent(Density.self, forKey: .density) ?? defaults.density
        savedThemes =
            try container.decodeIfPresent([SavedTheme].self, forKey: .savedThemes)
            ?? defaults.savedThemes
        setAsidePalette = try container.decodeIfPresent(
            SetAsidePalette.self, forKey: .setAsidePalette)
        savedConfigurations =
            try container.decodeIfPresent(
                [SavedConfiguration].self, forKey: .savedConfigurations)
            ?? defaults.savedConfigurations
        configurationID = try container.decodeIfPresent(String.self, forKey: .configurationID)
    }

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

        public init(day: CalendarDay, count: Int?, average: Double?, isIncomplete: Bool) {
            self.day = day
            self.count = count
            self.average = average
            self.isIncomplete = isIncomplete
        }
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

    /// One widget size's content, built from the same daily series as the dashboard.
    public struct Widget: Codable, Equatable, Sendable {
        public let size: WidgetSize
        public let headline: WidgetHeadline
        public let metric: Metric
        public let chartStyle: ChartStyle
        /// Empty for small. No averages; today is marked incomplete.
        public let points: [Point]
        public let todayCount: Int?

        public var unit: String { metric.unit }

        /// Names the fixed window the size shows.
        public var windowLabel: String {
            switch size {
            case .small: "Today"
            case .medium: "Last \(WidgetSettings.stripDays) days"
            case .large:
                chartStyle == .grid
                    ? "Last \(WidgetSettings.calendarWeeks) weeks" : "Last \(points.count) days"
            }
        }
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
    /// One entry per `WidgetSize`, configured separately from the dashboard.
    public let widgets: [Widget]
    public let todayCount: Int?
    public let quota: Quota?
    public let lastSuccessfulSync: Date?
    /// Plain-language coverage, staleness, and token notes. Never empty when data is missing.
    public let notices: [String]
    /// The build that wrote the shared copy; nil in memory and in snapshots from before 0.11.1,
    /// which still decode because the key is optional.
    public var writerBuild: BuildStamp? = nil
    /// The app's colors, so the widget draws what the app shows. Nil in snapshots written
    /// before themes; readers fall back to the standard theme.
    public var theme: ColorTheme? = nil
    /// Nil in snapshots written before appearance modes; readers follow the system.
    public var appearance: AppearanceMode? = nil

    public var unit: String { metric.unit }

    public func widget(_ size: WidgetSize) -> Widget? { widgets.first { $0.size == size } }

    public static let placeholder = DashboardSnapshot(
        generatedAt: Date(), login: "", tier: .notConfigured, metric: .contributions,
        chartStyle: .grid, rangeDays: 30, averageWindow: 0, sourceLabel: "Not configured",
        scopeLabel: "", points: [], widgets: [], todayCount: nil, quota: nil,
        lastSuccessfulSync: nil,
        notices: ["Open Slopometer and enter a GitHub username."])
}

public enum SnapshotBuilder {
    public static let staleAfter: TimeInterval = 45 * 60

    /// Lets surfaces that explain the token requirement themselves drop the duplicate.
    public static func tokenNeededNotice(for metric: Metric) -> String {
        "\(metric.title) needs a GitHub token. Add one in Settings."
    }

    /// Shown while the cache holds no data for the displayed account yet.
    public static func notSyncedNotice(for login: String) -> String {
        "No data for @\(login) yet. It appears after the next sync."
    }

    /// - Parameters:
    ///   - tokenUsable: a token verified for `settings.login` exists.
    ///   - problems: user-facing sync problems to surface alongside cached data.
    ///   - firstWeekday: the week start for the large widget's calendar (1 is Sunday).
    public static func build(
        settings: DashboardSettings, cache: MeasurementCache, tokenUsable: Bool,
        problems: [String], now: Date = Date(),
        firstWeekday: Int = Calendar.current.firstWeekday
    ) throws -> DashboardSnapshot {
        guard !settings.login.isEmpty else { return .placeholder }
        // A cache still holding another account's data (it is only reset by the next sync)
        // is treated as empty, so nothing from that account appears under this one.
        let holdsAccount = try cache.holds(settings.login)
        let state = holdsAccount ? try cache.syncState() : SyncState()
        let timeZone = settings.timeZone
        let today = CalendarDay.containing(now, in: timeZone)
        let warmUp = settings.averageWindow
        let span = max(settings.rangeDays + warmUp, WidgetSettings.minimumHistoryDays)
        let allDays = CalendarDay.range(from: today.adding(days: -(span - 1)), through: today)
        var notices = problems
        if !holdsAccount { notices.insert(notSyncedNotice(for: settings.login), at: 0) }
        let records = holdsAccount ? try cache.pullRequests() : []
        let prCoverageComplete = tokenUsable && !state.pullRequestResultsIncomplete
        let calendar = holdsAccount ? try cache.calendar() : [:]
        /// Every surface reads its metric's counts from here, so they agree day by day.
        func dailySeries(_ metric: Metric) -> [DailyCount] {
            if metric == .contributions {
                return ContributionSeries.series(days: allDays, counts: calendar)
            }
            guard tokenUsable else { return allDays.map { DailyCount(day: $0, count: nil) } }
            return PullRequestScope(
                metric: metric, repositories: Set(settings.repositories), timeZone: timeZone
            ).series(days: allDays, records: records, coveredFrom: state.pullRequestCoverageStart)
        }

        let series: [DailyCount]
        let sourceLabel: String
        let scopeLabel: String
        let lastSync: Date?
        if settings.metric == .contributions {
            series = dailySeries(.contributions)
            sourceLabel = state.calendarSource?.label ?? "Not synced yet"
            scopeLabel = "Account-wide"
            lastSync = state.lastCalendarSync
            if state.calendarSource == .profilePage {
                notices.append(
                    "Username only: read from your public profile page. Add a token for PR stats."
                )
            }
        } else if tokenUsable {
            series = dailySeries(settings.metric)
            sourceLabel = "GitHub search API"
            scopeLabel = Goal.scopeLabel(for: settings.repositories)
            lastSync = state.lastPullRequestSync
            if state.pullRequestResultsIncomplete {
                notices.append(
                    "Some PRs may be missing (incomplete search or a failed token), so counts may be low."
                )
            }
        } else {
            series = dailySeries(settings.metric)
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
        var seriesByMetric = [settings.metric: series]
        let widgets = WidgetSize.allCases.map { size in
            let panel = settings.widgets[size]
            let daily = seriesByMetric[panel.metric] ?? dailySeries(panel.metric)
            seriesByMetric[panel.metric] = daily
            return DashboardSnapshot.Widget(
                size: size, headline: panel.headline, metric: panel.metric,
                chartStyle: panel.chartStyle,
                points: daily.suffix(
                    panel.days(for: size, through: today, firstWeekday: firstWeekday)
                ).map {
                    DashboardSnapshot.Point(
                        day: $0.day, count: $0.count, average: nil, isIncomplete: $0.day == today)
                },
                todayCount: daily.last?.count)
        }

        var quota: DashboardSnapshot.Quota?
        if let goal = settings.goal, goal.isValid, tokenUsable, holdsAccount {
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
            scopeLabel: scopeLabel, points: points, widgets: widgets,
            todayCount: points.last?.count, quota: quota,
            lastSuccessfulSync: lastSync, notices: notices, theme: settings.theme,
            appearance: settings.appearance)
    }
}

/// The snapshot file shared with the widget through the App Group container.
public enum SharedSnapshot {
    /// The running build's group from its Info.plist (Debug builds use their own), or the
    /// release group where there is none, as in package tests.
    public static let appGroup =
        Bundle.main.object(forInfoDictionaryKey: "SlopometerAppGroup") as? String
        ?? "5U4584QFCQ.vn.infinitex.slopometer"
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

    /// Deletes the shared file, so the widget shows its empty state. A missing file is fine.
    public static func remove() throws {
        guard let url = url(), FileManager.default.fileExists(atPath: url.path) else { return }
        try FileManager.default.removeItem(at: url)
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
            points: points, widgets: widgets, todayCount: todayCount, quota: quota,
            lastSuccessfulSync: lastSuccessfulSync, notices: notices, writerBuild: writerBuild,
            theme: theme, appearance: appearance)
    }
}
