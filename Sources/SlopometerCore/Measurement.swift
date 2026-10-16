import Foundation

public enum Metric: String, Codable, CaseIterable, Identifiable, Sendable {
    case contributions
    case prsOpened
    case prsMerged

    public var id: String { rawValue }

    public var requiresToken: Bool { self != .contributions }

    /// The real unit shown next to every count.
    public var unit: String {
        switch self {
        case .contributions: "contributions"
        case .prsOpened: "PRs opened"
        case .prsMerged: "authored PRs merged"
        }
    }

    public var title: String {
        switch self {
        case .contributions: "Contributions"
        case .prsOpened: "PRs opened"
        case .prsMerged: "Authored PRs merged"
        }
    }
}

/// A pull request authored by the measured account, as recorded by GitHub.
public struct PullRequestRecord: Codable, Hashable, Identifiable, Sendable {
    /// GitHub's stable global node ID, used for deduplication.
    public let id: String
    public let number: Int
    public let title: String
    /// `owner/name`.
    public let repository: String
    public let url: String
    public let isDraft: Bool
    public let createdAt: Date
    public let mergedAt: Date?

    public init(
        id: String, number: Int, title: String, repository: String, url: String,
        isDraft: Bool, createdAt: Date, mergedAt: Date?
    ) {
        self.id = id
        self.number = number
        self.title = title
        self.repository = repository
        self.url = url
        self.isDraft = isDraft
        self.createdAt = createdAt
        self.mergedAt = mergedAt
    }

    /// The instant this PR counts for `metric`, or nil when it does not count.
    public func timestamp(for metric: Metric) -> Date? {
        switch metric {
        case .contributions: nil
        case .prsOpened: createdAt
        case .prsMerged: mergedAt
        }
    }
}

/// One day's value. A nil count is unknown, never zero.
public struct DailyCount: Equatable, Sendable {
    public let day: CalendarDay
    public let count: Int?

    public init(day: CalendarDay, count: Int?) {
        self.day = day
        self.count = count
    }
}

/// Which PRs count, and on which day, for a metric, repository scope, and timezone.
public struct PullRequestScope: Sendable {
    public let metric: Metric
    /// Empty means every repository the token can read.
    public let repositories: Set<String>
    public let timeZone: TimeZone

    public init(metric: Metric, repositories: Set<String> = [], timeZone: TimeZone) {
        precondition(metric.requiresToken, "Contributions are not derived from PR records")
        self.metric = metric
        self.repositories = Set(repositories.map { $0.lowercased() })
        self.timeZone = timeZone
    }

    func includes(_ record: PullRequestRecord) -> Bool {
        repositories.isEmpty || repositories.contains(record.repository.lowercased())
    }

    /// Unique PRs counted on `day`, newest first.
    public func evidence(on day: CalendarDay, in records: [PullRequestRecord])
        -> [PullRequestRecord]
    {
        Self.unique(records).filter { record in
            guard includes(record), let timestamp = record.timestamp(for: metric) else {
                return false
            }
            return CalendarDay.containing(timestamp, in: timeZone) == day
        }
        .sorted { $0.timestamp(for: metric)! > $1.timestamp(for: metric)! }
    }

    /// Daily counts for `days`. Days starting before `coveredFrom` are unknown.
    public func series(
        days: [CalendarDay], records: [PullRequestRecord], coveredFrom: Date?
    ) -> [DailyCount] {
        var counts: [CalendarDay: Int] = [:]
        for record in Self.unique(records) where includes(record) {
            guard let timestamp = record.timestamp(for: metric) else { continue }
            counts[CalendarDay.containing(timestamp, in: timeZone), default: 0] += 1
        }
        return days.map { day in
            guard let coveredFrom, day.start(in: timeZone) >= coveredFrom else {
                return DailyCount(day: day, count: nil)
            }
            return DailyCount(day: day, count: counts[day] ?? 0)
        }
    }

    static func unique(_ records: [PullRequestRecord]) -> [PullRequestRecord] {
        var seen = Set<String>()
        return records.filter { seen.insert($0.id).inserted }
    }
}

/// Provider-supplied contribution counts. Days the provider did not return are unknown.
public enum ContributionSeries {
    public static func series(days: [CalendarDay], counts: [CalendarDay: Int]) -> [DailyCount] {
        days.map { DailyCount(day: $0, count: counts[$0]) }
    }
}
