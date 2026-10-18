import Foundation

/// The single daily PR goal. Requires a token because it is built from PR records.
public struct Goal: Codable, Equatable, Sendable {
    public var metric: Metric
    public var target: Int

    public init(metric: Metric = .prsMerged, target: Int = 3) {
        self.metric = metric
        self.target = target
    }

    /// Targets a person can type or step to; typed values are clamped into it.
    public static let targetRange = 1...999

    public var isValid: Bool { metric.requiresToken && target > 0 }

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

    /// "Daily slop quota: 3 / 5 authored PRs merged"
    public var headline: String {
        "Daily slop quota: \(count) / \(target) \(metric.unit)"
    }
}

/// The notification for reaching the daily PR quota: at most one per goal and day.
public struct QuotaCompletion: Equatable, Sendable {
    /// The goal (metric, target, repository filter) and the day in the goal timezone.
    public let key: String
    public let title: String
    public let body: String

    /// Nil unless the last sync confirmed the PR data, the quota is reached with complete
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
            repositories.sorted().joined(separator: ","),
        ].joined(separator: "|")
    }

    /// Whether an announced key belongs to `day`, so older ones can be dropped.
    public static func isFrom(_ day: CalendarDay, key: String) -> Bool {
        key.hasPrefix("\(day.description)|")
    }
}
