import Foundation

/// One daily goal: provider calendar contributions, or token-backed PR records.
public struct Goal: Codable, Equatable, Sendable {
    public var metric: Metric
    public var target: Int

    public init(metric: Metric = .prsMerged, target: Int = 3) {
        self.metric = metric
        self.target = target
    }

    /// Targets a person can type or step to; typed values are clamped into it.
    public static let targetRange = 1...999

    /// Keeps only the digits someone typed, no longer than the largest target.
    public static func targetDigits(_ typed: String) -> String {
        String(
            typed.filter(\.isASCII).filter(\.isNumber).prefix(String(targetRange.upperBound).count))
    }

    /// The target typed digits stand for, clamped into `targetRange`; nil while empty.
    public static func target(typed: String) -> Int? {
        Int(targetDigits(typed)).map {
            min(max($0, targetRange.lowerBound), targetRange.upperBound)
        }
    }

    public var isValid: Bool { target > 0 }

    /// Describes a repository filter; empty means every repository the token can read.
    public static func scopeLabel(for repositories: [String]) -> String {
        switch repositories.count {
        case 0: "all readable repositories"
        case 1: repositories[0]
        default: "\(repositories.count) repositories"
        }
    }
}

public struct QuotaProgress: Equatable, Sendable {
    public let metric: Metric
    public let target: Int
    /// Not capped at the target.
    public let count: Int
    public let scopeLabel: String
    public let evidence: [PullRequestRecord]
    public let coverageComplete: Bool

    /// Never claims the target is reached when coverage is incomplete.
    public var isReached: Bool { coverageComplete && count >= target }

    public init(
        goal: Goal, repositories: [String] = [], records: [PullRequestRecord], today: CalendarDay,
        timeZone: TimeZone, coverageComplete: Bool
    ) {
        let scope = PullRequestScope(
            metric: goal.metric, repositories: Set(repositories), timeZone: timeZone)
        evidence = scope.evidence(on: today, in: records)
        metric = goal.metric
        target = goal.target
        count = evidence.count
        scopeLabel = Goal.scopeLabel(for: repositories)
        self.coverageComplete = coverageComplete
    }

    /// A known provider-calendar total. Missing days must not be passed as zero.
    public init(goal: Goal, contributionCount: Int, source: CalendarSource) {
        metric = .contributions
        target = goal.target
        count = contributionCount
        scopeLabel = "\(source.label), account-wide"
        evidence = []
        coverageComplete = true
    }

    /// "Daily slop quota: 3 / 5 authored PRs merged"
    public var headline: String {
        "Daily slop quota: \(count) / \(target) \(metric.unit)"
    }
}

/// The notification for reaching the daily quota: at most one per goal and day.
public struct QuotaCompletion: Equatable, Sendable {
    /// The goal (metric, target, repository filter) and the day in the goal timezone.
    public let key: String
    public let title: String
    public let body: String

    /// Nil unless the last sync confirmed the goal metric's data, the quota is reached with complete
    /// coverage, and this goal was not already announced on `day`. Announced keys from
    /// earlier days are ignored, so they can be kept until the day changes.
    public static func due(
        quota: DashboardSnapshot.Quota?, goal: Goal?, repositories: [String], day: CalendarDay,
        confirmed: Bool, announced: Set<String>
    ) -> QuotaCompletion? {
        guard confirmed, let quota, let goal, quota.isReached, quota.coverageComplete else {
            return nil
        }
        let key = Self.key(goal: goal, repositories: repositories, day: day)
        guard !announced.contains(key) else { return nil }
        return QuotaCompletion(
            key: key, title: "Daily slop quota reached",
            body: "\(quota.count) / \(quota.target) \(quota.unit) today, \(quota.scopeLabel).")
    }

    static func key(goal: Goal, repositories: [String], day: CalendarDay) -> String {
        [
            day.description, goal.metric.rawValue, String(goal.target),
            goal.metric.requiresToken ? repositories.sorted().joined(separator: ",") : "",
        ].joined(separator: "|")
    }

    /// Whether an announced key belongs to `day`, so older ones can be dropped.
    public static func isFrom(_ day: CalendarDay, key: String) -> Bool {
        key.hasPrefix("\(day.description)|")
    }
}

/// A win earned against the target saved for that day, independent of later edits.
public struct QuotaAchievement: Codable, Equatable, Sendable {
    public let day: CalendarDay
    public let target: Int
    public let count: Int
    public let timeZoneID: String
    /// Optional for snapshots written before achievements carried their metric.
    public let metric: Metric?

    public init(
        day: CalendarDay, target: Int, count: Int, timeZoneID: String, metric: Metric? = nil
    ) {
        self.day = day
        self.target = target
        self.count = count
        self.timeZoneID = timeZoneID
        self.metric = metric
    }

    public var detail: String {
        let datePolicy = metric == .contributions ? "GitHub calendar day" : timeZoneID
        return "Quota reached · \(count) / \(target) \(metric?.unit ?? "PRs") · \(datePolicy)"
    }

    public var label: String { "Quota reached · \(count) / \(target)" }

    public func isToday(at date: Date) -> Bool {
        guard let zone = TimeZone(identifier: timeZoneID) else { return false }
        return CalendarDay.containing(date, in: zone) == day
    }
}
