import Foundation
import GRDB

/// The series key must include metric, author/repository scope, and timezone policy.
/// Day is an ISO calendar date (YYYY-MM-DD), already bucketed by the caller.
public struct CachedDay: Codable, Equatable, FetchableRecord, PersistableRecord, Sendable {
    public static let databaseTableName = "daily_measurements"

    public let seriesID: String
    public let day: String
    public let count: Int?

    public init(seriesID: String, day: String, count: Int?) {
        self.seriesID = seriesID
        self.day = day
        self.count = count
    }
}

/// Where a contribution calendar came from. A stored calendar has exactly one source.
public enum CalendarSource: String, Codable, Sendable {
    /// Undocumented public profile page; username only.
    case profilePage
    /// GraphQL `contributionsCollection`; requires a token.
    case graphQL

    public var label: String {
        switch self {
        case .profilePage: "GitHub profile page (unofficial)"
        case .graphQL: "GitHub GraphQL API"
        }
    }
}

/// What the last syncs established. Timestamps are only advanced by successful syncs.
public struct SyncState: Codable, Equatable, Sendable {
    public var login: String?
    public var calendarSource: CalendarSource?
    public var lastCalendarSync: Date?
    public var lastPullRequestSync: Date?
    /// PR records are complete for activity at or after this instant.
    public var pullRequestCoverageStart: Date?
    public var pullRequestResultsIncomplete = false
    /// When the whole window was last refetched and stale records removed.
    public var lastFullPullRequestSync: Date?
    /// Per token ID, the instant up to which that token's PR changes were fetched.
    /// Missing for a token that has not completed a fetch; a failed fetch never advances it.
    public var pullRequestCheckpoints: [String: Date] = [:]

    public init() {}

    /// Fields added after a cache was written decode as their defaults.
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        login = try container.decodeIfPresent(String.self, forKey: .login)
        calendarSource = try container.decodeIfPresent(CalendarSource.self, forKey: .calendarSource)
        lastCalendarSync = try container.decodeIfPresent(Date.self, forKey: .lastCalendarSync)
        lastPullRequestSync = try container.decodeIfPresent(Date.self, forKey: .lastPullRequestSync)
        pullRequestCoverageStart = try container.decodeIfPresent(
            Date.self, forKey: .pullRequestCoverageStart)
        pullRequestResultsIncomplete =
            try container.decodeIfPresent(Bool.self, forKey: .pullRequestResultsIncomplete) ?? false
        lastFullPullRequestSync = try container.decodeIfPresent(
            Date.self, forKey: .lastFullPullRequestSync)
        pullRequestCheckpoints =
            try container.decodeIfPresent([String: Date].self, forKey: .pullRequestCheckpoints)
            ?? [:]
    }
}

extension PullRequestRecord: FetchableRecord, PersistableRecord {
    public static let databaseTableName = "pull_requests"
}

private struct ContributionRow: Codable, FetchableRecord, PersistableRecord {
    static let databaseTableName = "contribution_days"
    let day: String
    let count: Int
}

private struct StateRow: Codable, FetchableRecord, PersistableRecord {
    static let databaseTableName = "sync_state"
    let id: Int
    let json: String
}

private struct QuotaDayRow: Codable, FetchableRecord, PersistableRecord {
    static let databaseTableName = "quota_days"
    let scope: String
    let day: String
    var target: Int
    var achievedCount: Int?
}

/// Local cache of GitHub source records and derived values. Not the source of truth.
public final class MeasurementCache: Sendable {
    private let database: DatabaseQueue

    public init(path: String? = nil) throws {
        if let path {
            database = try DatabaseQueue(path: path)
        } else {
            database = try DatabaseQueue()
        }

        var migrator = DatabaseMigrator()
        migrator.registerMigration("createDailyMeasurements") { db in
            try db.create(table: CachedDay.databaseTableName) { table in
                table.column("seriesID", .text).notNull()
                table.column("day", .text).notNull()
                table.column("count", .integer)
                table.primaryKey(["seriesID", "day"])
                table.check(sql: "count IS NULL OR count >= 0")
            }
        }
        migrator.registerMigration("createSourceRecords") { db in
            try db.create(table: PullRequestRecord.databaseTableName) { table in
                table.primaryKey("id", .text)
                table.column("number", .integer).notNull()
                table.column("title", .text).notNull()
                table.column("repository", .text).notNull()
                table.column("url", .text).notNull()
                table.column("isDraft", .boolean).notNull()
                table.column("createdAt", .datetime).notNull()
                table.column("mergedAt", .datetime)
            }
            try db.create(table: ContributionRow.databaseTableName) { table in
                table.primaryKey("day", .text)
                table.column("count", .integer).notNull().check { $0 >= 0 }
            }
            try db.create(table: StateRow.databaseTableName) { table in
                table.primaryKey("id", .integer)
                table.column("json", .text).notNull()
            }
        }
        migrator.registerMigration("createQuotaHistory") { db in
            try db.create(table: QuotaDayRow.databaseTableName) { table in
                table.column("scope", .text).notNull()
                table.column("day", .text).notNull()
                table.column("target", .integer).notNull().check { $0 > 0 }
                table.column("achievedCount", .integer)
                table.primaryKey(["scope", "day"])
            }
        }
        try migrator.migrate(database)
    }

    // MARK: Derived daily values

    public func save(_ day: CachedDay) throws {
        guard !day.seriesID.isEmpty else { throw MeasurementError.emptySeries }
        if let count = day.count, count < 0 {
            throw MeasurementError.negativeCount
        }
        try database.write { db in
            try day.save(db)
        }
    }

    public func days(in seriesID: String) throws -> [CachedDay] {
        try database.read { db in
            try CachedDay
                .filter(Column("seriesID") == seriesID)
                .order(Column("day"))
                .fetchAll(db)
        }
    }

    // MARK: Daily quota history

    /// Save today's target. Only a confirmed sync of the goal metric can earn a win.
    /// Historical targets and earned wins never change; days before tracking stay unknown.
    public func recordQuota(
        settings: DashboardSettings, confirmed: Bool, now: Date = Date()
    ) throws {
        guard !settings.login.isEmpty, let goal = settings.goal, goal.isValid else { return }
        let today = CalendarDay.containing(now, in: settings.timeZone)
        try database.write { db in
            let state = try Self.state(db)
            guard let login = state.login,
                login.lowercased() == settings.login.lowercased()
            else { return }
            guard
                let scope = try Self.quotaScope(
                    settings, metric: goal.metric, source: state.calendarSource)
            else { return }
            var rows = try QuotaDayRow.filter(Column("scope") == scope).fetchAll(db)
            if let index = rows.firstIndex(where: { $0.day == today.description }) {
                if rows[index].achievedCount == nil { rows[index].target = goal.target }
            } else {
                rows.append(QuotaDayRow(scope: scope, day: today.description, target: goal.target))
            }
            let canConfirmPRs =
                confirmed && goal.metric.requiresToken
                && !state.pullRequestResultsIncomplete && state.lastPullRequestSync != nil
            let records = canConfirmPRs ? try PullRequestRecord.fetchAll(db) : []
            let contributionCounts =
                confirmed && goal.metric == .contributions
                    && state.lastCalendarSync != nil
                ? try Dictionary(
                    uniqueKeysWithValues: ContributionRow.fetchAll(db).map {
                        ($0.day, $0.count)
                    }) : [:]
            let prScope =
                goal.metric.requiresToken
                ? PullRequestScope(
                    metric: goal.metric, repositories: Set(settings.repositories),
                    timeZone: settings.timeZone) : nil
            for var row in rows {
                if row.achievedCount == nil, let day = CalendarDay(row.day), day <= today {
                    var count: Int?
                    if goal.metric == .contributions {
                        count = contributionCounts[row.day]
                    } else if canConfirmPRs, let start = state.pullRequestCoverageStart,
                        day.start(in: settings.timeZone) >= start
                    {
                        count = prScope?.evidence(on: day, in: records).count
                    }
                    if let count, count >= row.target { row.achievedCount = count }
                }
                try row.save(db)
            }
        }
    }

    public func quotaAchievements(settings: DashboardSettings, metric: Metric) throws
        -> [CalendarDay: QuotaAchievement]
    {
        guard try holds(settings.login) else { return [:] }
        return try database.read { db in
            guard
                let scope = try Self.quotaScope(
                    settings, metric: metric, source: Self.state(db).calendarSource)
            else { return [:] }
            var result: [CalendarDay: QuotaAchievement] = [:]
            for row in try QuotaDayRow.filter(Column("scope") == scope).fetchAll(db) {
                guard let count = row.achievedCount, let day = CalendarDay(row.day) else {
                    continue
                }
                result[day] = QuotaAchievement(
                    day: day, target: row.target, count: count, timeZoneID: settings.timeZoneID,
                    metric: metric)
            }
            return result
        }
    }

    /// Target is intentionally absent: changing tomorrow's quota cannot relabel old days.
    private static func quotaScope(
        _ settings: DashboardSettings, metric: Metric, source: CalendarSource?
    ) throws -> String? {
        let parts: [String]
        if metric == .contributions {
            // Calendar sources may label activity on different dates. Never mix their wins.
            guard let source else { return nil }
            parts = [
                settings.login.lowercased(), metric.rawValue, "provider-calendar", source.rawValue,
            ]
        } else {
            parts =
                [settings.login.lowercased(), metric.rawValue, settings.timeZoneID]
                + Set(settings.repositories.map { $0.lowercased() }).sorted()
        }
        return String(decoding: try JSONEncoder().encode(parts), as: UTF8.self)
    }

    // MARK: Source records

    public func syncState() throws -> SyncState {
        try database.read { db in
            guard let row = try StateRow.fetchOne(db, key: 1) else { return SyncState() }
            return try JSONDecoder().decode(SyncState.self, from: Data(row.json.utf8))
        }
    }

    /// Whether cached records may be shown for `login`. A cache that names another account
    /// still holds that account's data until the next sync resets it. A cache that names no
    /// account (never synced) holds nothing from another account.
    public func holds(_ login: String) throws -> Bool {
        guard let owner = try syncState().login else { return true }
        return owner.lowercased() == login.lowercased()
    }

    /// Clears everything recorded for a previous account.
    public func reset(for login: String) throws {
        try database.write { db in
            try QuotaDayRow.deleteAll(db)
            try PullRequestRecord.deleteAll(db)
            try ContributionRow.deleteAll(db)
            var state = SyncState()
            state.login = login
            try Self.write(state, db)
        }
    }

    /// Deletes every record and the sync state, for Remove All Data. The tables and their
    /// migrations stay, so the cache can be used again.
    public func eraseAll() throws {
        try database.write { db in
            try CachedDay.deleteAll(db)
            try QuotaDayRow.deleteAll(db)
            try PullRequestRecord.deleteAll(db)
            try ContributionRow.deleteAll(db)
            try StateRow.deleteAll(db)
        }
    }

    /// Replaces the whole calendar so a series never mixes sources or keeps stale days.
    public func replaceCalendar(_ counts: [CalendarDay: Int], source: CalendarSource, at date: Date)
        throws
    {
        guard counts.values.allSatisfy({ $0 >= 0 }) else { throw MeasurementError.negativeCount }
        try database.write { db in
            try ContributionRow.deleteAll(db)
            for (day, count) in counts {
                try ContributionRow(day: day.description, count: count).insert(db)
            }
            var state = try Self.state(db)
            state.calendarSource = source
            state.lastCalendarSync = date
            try Self.write(state, db)
        }
    }

    public func calendar() throws -> [CalendarDay: Int] {
        try database.read { db in
            var counts: [CalendarDay: Int] = [:]
            for row in try ContributionRow.fetchAll(db) {
                guard let day = CalendarDay(row.day) else { continue }
                counts[day] = row.count
            }
            return counts
        }
    }

    /// Replaces all PR records with a complete fetch, so deleted or inaccessible PRs
    /// disappear and repeated syncs cannot double-count. Records this as a full sync and
    /// sets every given token's checkpoint.
    public func replacePullRequests(
        _ records: [PullRequestRecord], coveringFrom start: Date, incomplete: Bool,
        checkpoints: [String: Date] = [:], at date: Date
    ) throws {
        try database.write { db in
            try PullRequestRecord.deleteAll(db)
            for record in PullRequestScope.unique(records) {
                try record.insert(db)
            }
            var state = try Self.state(db)
            state.pullRequestCoverageStart = start
            state.pullRequestResultsIncomplete = incomplete
            state.lastPullRequestSync = date
            state.lastFullPullRequestSync = date
            state.pullRequestCheckpoints = checkpoints
            try Self.write(state, db)
        }
    }

    /// Inserts or updates records by node ID and keeps the rest, for incremental and
    /// partial fetches. Coverage can only widen; an incomplete flag only clears with a
    /// full replacement. Checkpoints are set for the given tokens only.
    public func upsertPullRequests(
        _ records: [PullRequestRecord], coveringFrom start: Date, incomplete: Bool,
        checkpoints: [String: Date] = [:], at date: Date
    ) throws {
        try database.write { db in
            for record in PullRequestScope.unique(records) {
                try record.save(db)
            }
            var state = try Self.state(db)
            state.pullRequestCoverageStart = min(state.pullRequestCoverageStart ?? start, start)
            state.pullRequestResultsIncomplete = state.pullRequestResultsIncomplete || incomplete
            state.lastPullRequestSync = date
            state.pullRequestCheckpoints.merge(checkpoints) { _, new in new }
            try Self.write(state, db)
        }
    }

    public func pullRequests() throws -> [PullRequestRecord] {
        try database.read { db in
            try PullRequestRecord.order(Column("createdAt")).fetchAll(db)
        }
    }

    private static func state(_ db: Database) throws -> SyncState {
        guard let row = try StateRow.fetchOne(db, key: 1) else { return SyncState() }
        return try JSONDecoder().decode(SyncState.self, from: Data(row.json.utf8))
    }

    private static func write(_ state: SyncState, _ db: Database) throws {
        let json = String(decoding: try JSONEncoder().encode(state), as: UTF8.self)
        try StateRow(id: 1, json: json).save(db)
    }
}
