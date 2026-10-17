import Foundation
import SlopometerCore
import Testing

func date(_ iso: String) -> Date {
    try! Date(iso, strategy: .iso8601)
}

func day(_ label: String) -> CalendarDay {
    CalendarDay(label)!
}

func pr(
    _ id: String, created: String, merged: String? = nil, repository: String = "me/app",
    draft: Bool = false
) -> PullRequestRecord {
    PullRequestRecord(
        id: id, number: abs(id.hashValue % 1000), title: "PR \(id)", repository: repository,
        url: "https://github.com/\(repository)/pull/1", isDraft: draft, createdAt: date(created),
        mergedAt: merged.map(date))
}

let newYork = TimeZone(identifier: "America/New_York")!
let bangkok = TimeZone(identifier: "Asia/Bangkok")!

@Suite("Calendar days")
struct CalendarDayTests {
    @Test func parsesOnlyCanonicalValidDates() {
        #expect(CalendarDay("2026-02-28")?.description == "2026-02-28")
        #expect(CalendarDay("2026-02-30") == nil)
        #expect(CalendarDay("2026-2-3") == nil)
        #expect(CalendarDay("not a day") == nil)
    }

    @Test func arithmeticCrossesMonthsAndYears() {
        #expect(day("2026-12-31").adding(days: 1) == day("2027-01-01"))
        #expect(day("2026-03-01").adding(days: -1) == day("2026-02-28"))
        #expect(CalendarDay.range(from: day("2026-10-30"), through: day("2026-11-02")).count == 4)
    }

    @Test func bucketsByCalendarDayAcrossDaylightSaving() {
        // 2026-03-08 is the US spring-forward day: 23 hours long in New York.
        #expect(
            CalendarDay.containing(date("2026-03-08T04:30:00Z"), in: newYork) == day("2026-03-07"))
        #expect(
            CalendarDay.containing(date("2026-03-08T05:30:00Z"), in: newYork) == day("2026-03-08"))
        #expect(
            CalendarDay.containing(date("2026-03-09T03:30:00Z"), in: newYork) == day("2026-03-08"))
        #expect(
            CalendarDay.containing(date("2026-03-09T04:30:00Z"), in: newYork) == day("2026-03-09"))
        let start = day("2026-03-09").start(in: newYork)
        #expect(start.timeIntervalSince(day("2026-03-08").start(in: newYork)) == 23 * 3600)
    }
}

@Suite("PR measurements")
struct PullRequestMeasurementTests {
    @Test func aPROpenedLastMonthAndMergedTodayCountsTodayForMerged() {
        let records = [pr("a", created: "2026-09-10T10:00:00Z", merged: "2026-10-16T10:00:00Z")]
        let merged = PullRequestScope(metric: .prsMerged, timeZone: bangkok)
        let opened = PullRequestScope(metric: .prsOpened, timeZone: bangkok)
        #expect(merged.evidence(on: day("2026-10-16"), in: records).map(\.id) == ["a"])
        #expect(opened.evidence(on: day("2026-10-16"), in: records).isEmpty)
        #expect(opened.evidence(on: day("2026-09-10"), in: records).map(\.id) == ["a"])
    }

    @Test func timezoneDecidesTheDay() {
        // 20:00 UTC is already the next day in Bangkok (UTC+7).
        let records = [pr("a", created: "2026-10-15T20:00:00Z", merged: "2026-10-15T20:00:00Z")]
        let utc = PullRequestScope(metric: .prsMerged, timeZone: TimeZone(identifier: "UTC")!)
        let local = PullRequestScope(metric: .prsMerged, timeZone: bangkok)
        #expect(utc.evidence(on: day("2026-10-15"), in: records).count == 1)
        #expect(local.evidence(on: day("2026-10-16"), in: records).count == 1)
    }

    @Test func duplicateRecordsCountOnce() {
        let record = pr("a", created: "2026-10-16T01:00:00Z")
        let scope = PullRequestScope(metric: .prsOpened, timeZone: bangkok)
        let series = scope.series(
            days: [day("2026-10-16")], records: [record, record],
            coveredFrom: date("2026-01-01T00:00:00Z"))
        #expect(series.map(\.count) == [1])
    }

    @Test func unmergedAndDraftPRsFollowTheirMetric() {
        let records = [pr("draft", created: "2026-10-16T01:00:00Z", draft: true)]
        let opened = PullRequestScope(metric: .prsOpened, timeZone: bangkok)
        let merged = PullRequestScope(metric: .prsMerged, timeZone: bangkok)
        #expect(opened.evidence(on: day("2026-10-16"), in: records).first?.isDraft == true)
        #expect(merged.evidence(on: day("2026-10-16"), in: records).isEmpty)
    }

    @Test func daysBeforeCoverageAreUnknownAndCoveredEmptyDaysAreZero() {
        let scope = PullRequestScope(metric: .prsOpened, timeZone: bangkok)
        let series = scope.series(
            days: [day("2026-10-14"), day("2026-10-15")], records: [],
            coveredFrom: day("2026-10-15").start(in: bangkok))
        #expect(series.map(\.count) == [nil, 0])
        #expect(
            scope.series(days: [day("2026-10-15")], records: [], coveredFrom: nil)[0].count == nil)
    }

    @Test func repositoryFilterIsCaseInsensitive() {
        let records = [
            pr("a", created: "2026-10-16T01:00:00Z", repository: "Me/App"),
            pr("b", created: "2026-10-16T01:00:00Z", repository: "me/other"),
        ]
        let scope = PullRequestScope(
            metric: .prsOpened, repositories: ["me/app"], timeZone: bangkok)
        #expect(scope.evidence(on: day("2026-10-16"), in: records).map(\.id) == ["a"])
    }
}

@Suite("Daily PR quota")
struct QuotaTests {
    let today = day("2026-10-16")
    let records = (1...4).map {
        pr("m\($0)", created: "2026-10-01T00:00:00Z", merged: "2026-10-16T0\($0):00:00Z")
    }

    @Test func progressMayExceedTheTarget() {
        let progress = QuotaProgress(
            goal: Goal(metric: .prsMerged, target: 3), records: records, today: today,
            timeZone: bangkok, coverageComplete: true)
        #expect(progress.count == 4)
        #expect(progress.isReached)
        #expect(progress.headline == "Daily slop quota: 4 / 3 authored PRs merged")
        #expect(progress.evidence.map(\.id) == ["m4", "m3", "m2", "m1"])
    }

    @Test func incompleteCoverageNeverClaimsTheTargetWasReached() {
        let progress = QuotaProgress(
            goal: Goal(metric: .prsMerged, target: 1), records: records, today: today,
            timeZone: bangkok, coverageComplete: false)
        #expect(progress.count == 4)
        #expect(!progress.isReached)
    }

    @Test func goalsMustBePositivePRTargets() {
        #expect(!Goal(metric: .contributions, target: 3).isValid)
        #expect(!Goal(metric: .prsMerged, target: 0).isValid)
        #expect(Goal(metric: .prsOpened, target: 1).isValid)
    }
}

@Suite("Repository filter checklist")
struct RepositoryFilterTests {
    let records = [
        pr("a", created: "2026-10-16T01:00:00Z", repository: "me/app"),
        pr("b", created: "2026-10-16T02:00:00Z", repository: "Me/App"),
        pr("c", created: "2026-10-16T03:00:00Z", repository: "org/api"),
        pr("d", created: "2026-10-16T04:00:00Z", repository: "me/docs"),
    ]
    var choices: [RepositoryChoice] { RepositoryFilter.choices(records: records, selected: []) }

    @Test func choicesMergeCaseAndSortBusiestFirst() {
        #expect(choices.map(\.id) == ["me/app", "me/docs", "org/api"])
        #expect(choices.map(\.pullRequests) == [2, 1, 1])
    }

    @Test func selectedRepositoryWithoutPullRequestsStaysListed() {
        let listed = RepositoryFilter.choices(records: records, selected: ["old/repo"])
        #expect(listed.last == RepositoryChoice(name: "old/repo", pullRequests: 0))
    }

    @Test func emptySelectionIncludesEverything() {
        #expect(choices.allSatisfy { RepositoryFilter.isIncluded($0.name, in: []) })
        #expect(RepositoryFilter.isIncluded("ME/APP", in: ["me/app"]))
        #expect(!RepositoryFilter.isIncluded("org/api", in: ["me/app"]))
    }

    @Test func untickingFromAllKeepsTheRest() {
        #expect(
            RepositoryFilter.toggling("org/api", in: [], choices: choices) == ["me/app", "me/docs"])
    }

    @Test func tickingEveryChoiceCollapsesToAll() {
        #expect(
            RepositoryFilter.toggling("org/api", in: ["me/app", "me/docs"], choices: choices)
                == [])
    }

    @Test func lastTickedRepositoryCannotBeUnticked() {
        #expect(RepositoryFilter.isLastIncluded("me/app", in: ["me/app"], choices: choices))
        #expect(RepositoryFilter.toggling("me/app", in: ["me/app"], choices: choices) == ["me/app"])
        let single = RepositoryFilter.choices(records: [records[0]], selected: [])
        #expect(RepositoryFilter.toggling("me/app", in: [], choices: single) == [])
    }
}
