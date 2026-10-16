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

    public init() {}
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

    // MARK: Source records

    public func syncState() throws -> SyncState {
        try database.read { db in
            guard let row = try StateRow.fetchOne(db, key: 1) else { return SyncState() }
            return try JSONDecoder().decode(SyncState.self, from: Data(row.json.utf8))
        }
    }

    /// Clears everything recorded for a previous account.
    public func reset(for login: String) throws {
        try database.write { db in
            try PullRequestRecord.deleteAll(db)
            try ContributionRow.deleteAll(db)
            var state = SyncState()
            state.login = login
            try Self.write(state, db)
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
    /// disappear and repeated syncs cannot double-count.
    public func replacePullRequests(
        _ records: [PullRequestRecord], coveringFrom start: Date, incomplete: Bool, at date: Date
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
