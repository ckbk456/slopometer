import Foundation
import Testing

@testable import SlopometerCore

@Suite("Quota notification")
struct QuotaCompletionTests {
    let goal = Goal(metric: .prsMerged, target: 3)
    let day = CalendarDay(year: 2026, month: 10, day: 18)!

    func quota(count: Int, complete: Bool = true) -> DashboardSnapshot.Quota {
        DashboardSnapshot.Quota(
            headline: "", count: count, target: 3, unit: "authored PRs merged",
            scopeLabel: "all readable repositories",
            isReached: complete && count >= 3, coverageComplete: complete, evidence: [])
    }

    func due(
        _ quota: DashboardSnapshot.Quota?, goal: Goal? = nil, repositories: [String] = [],
        day: CalendarDay? = nil, confirmed: Bool = true, announced: Set<String> = []
    ) -> QuotaCompletion? {
        QuotaCompletion.due(
            quota: quota, goal: goal ?? self.goal, repositories: repositories, day: day ?? self.day,
            confirmed: confirmed, announced: announced)
    }

    @Test func reachedQuotaIsAnnouncedWithItsUnitAndScope() {
        let completion = due(quota(count: 4))
        #expect(completion?.title == "Daily slop quota reached")
        #expect(completion?.body == "4 / 3 authored PRs merged today, all readable repositories.")
    }

    @Test func nothingBeforeTheTargetOrWithoutAQuota() {
        #expect(due(quota(count: 2)) == nil)
        #expect(due(nil) == nil)
    }

    @Test func incompleteCoverageNeverClaimsTheTarget() {
        #expect(due(quota(count: 5, complete: false)) == nil)
    }

    @Test func onlyAfterASyncConfirmedTheData() {
        #expect(due(quota(count: 4), confirmed: false) == nil)
    }

    @Test func oncePerGoalAndDay() throws {
        let first = try #require(due(quota(count: 3)))
        #expect(due(quota(count: 4), announced: [first.key]) == nil)
        // The next day, or a different goal the same day, is a new announcement.
        #expect(due(quota(count: 3), day: day.adding(days: 1), announced: [first.key]) != nil)
        #expect(
            due(quota(count: 3), repositories: ["octo/app"], announced: [first.key]) != nil)
        #expect(
            due(
                quota(count: 3), goal: Goal(metric: .prsMerged, target: 2),
                announced: [first.key]) != nil)
    }

    @Test func keysAreTiedToTheirDay() throws {
        let key = try #require(due(quota(count: 3))).key
        #expect(QuotaCompletion.isFrom(day, key: key))
        #expect(!QuotaCompletion.isFrom(day.adding(days: 1), key: key))
    }
}
