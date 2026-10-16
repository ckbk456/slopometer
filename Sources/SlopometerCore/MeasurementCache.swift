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

/// A small cache foundation, not a GitHub sync engine or a PR event store.
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
        try migrator.migrate(database)
    }

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
}
