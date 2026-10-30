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

@Suite("Daily quota achievements")
struct QuotaHistoryTests {
    let first = date("2026-10-28T12:00:00Z")
    let next = date("2026-10-29T12:00:00Z")

    func settings() -> DashboardSettings {
        var settings = DashboardSettings()
        settings.login = "me"
        settings.timeZoneID = "UTC"
        settings.metric = .prsMerged
        settings.goal = Goal(metric: .prsMerged, target: 2)
        return settings
    }

    func cache(path: String? = nil, incomplete: Bool = false) throws -> MeasurementCache {
        let cache = try MeasurementCache(path: path)
        try cache.reset(for: "me")
        try cache.replacePullRequests(
            [
                pr("a", created: "2026-10-27T10:00:00Z", merged: "2026-10-28T10:00:00Z"),
                pr("b", created: "2026-10-27T11:00:00Z", merged: "2026-10-28T11:00:00Z"),
            ],
            coveringFrom: date("2026-10-01T00:00:00Z"), incomplete: incomplete, at: first)
        return cache
    }

    @Test func laterTargetChangesKeepTheEarnedDayAndOriginalTarget() throws {
        let cache = try cache()
        var settings = settings()
        try cache.recordQuota(settings: settings, confirmed: true, now: first)
        settings.goal?.target = 20
        try cache.recordQuota(settings: settings, confirmed: true, now: next)
        let wins = try cache.quotaAchievements(settings: settings, metric: .prsMerged)
        #expect(wins[day("2026-10-28")]?.target == 2)
        #expect(wins[day("2026-10-28")]?.count == 2)
        #expect(wins[day("2026-10-29")] == nil)
        #expect(wins[day("2026-10-27")] == nil)
    }

    @Test func sameDayEditsKeepAnEarnedWinButUnreachedTargetsApplyImmediately() throws {
        let cache = try cache()
        var settings = settings()
        settings.goal?.target = 3
        try cache.recordQuota(settings: settings, confirmed: true, now: first)
        #expect(try cache.quotaAchievements(settings: settings, metric: .prsMerged).isEmpty)
        settings.goal?.target = 2
        try cache.recordQuota(settings: settings, confirmed: false, now: first)
        #expect(try cache.quotaAchievements(settings: settings, metric: .prsMerged).isEmpty)
        try cache.recordQuota(settings: settings, confirmed: true, now: first)
        settings.goal?.target = 20
        try cache.recordQuota(settings: settings, confirmed: true, now: first)
        let snapshot = try SnapshotBuilder.build(
            settings: settings, cache: cache, tokenUsable: true, problems: [], now: first)
        #expect(snapshot.quota?.target == 20)
        #expect(snapshot.quota?.isReached == false)
        #expect(snapshot.quota?.achievement?.target == 2)
        #expect(snapshot.points.last?.achievement == snapshot.quota?.achievement)
        let decoded = try SharedSnapshot.decode(SharedSnapshot.encode(snapshot))
        #expect(decoded == snapshot)
    }

    @Test func delayedSyncUsesYesterdaysSavedTarget() throws {
        let cache = try cache()
        var settings = settings()
        try cache.recordQuota(settings: settings, confirmed: false, now: first)
        settings.goal?.target = 20
        try cache.recordQuota(settings: settings, confirmed: true, now: next)
        #expect(
            try cache.quotaAchievements(settings: settings, metric: .prsMerged)[day("2026-10-28")]?
                .target == 2)
    }

    @Test func widgetsUseTheirOwnMetricAndOldSnapshotsStillDecode() throws {
        let cache = try cache()
        var settings = settings()
        settings.widgets.medium.metric = .prsMerged
        settings.widgets.large.metric = .prsOpened
        try cache.recordQuota(settings: settings, confirmed: true, now: first)
        let snapshot = try SnapshotBuilder.build(
            settings: settings, cache: cache, tokenUsable: true, problems: [], now: first)
        #expect(snapshot.widget(.medium)?.points.last?.achievement == snapshot.quota?.achievement)
        #expect(snapshot.widget(.large)?.points.allSatisfy { $0.achievement == nil } == true)
        let encoded = try SharedSnapshot.encode(snapshot)
        var json = try #require(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
        var quota = try #require(json["quota"] as? [String: Any])
        quota.removeValue(forKey: "achievement")
        json["quota"] = quota
        let points = try #require(json["points"] as? [[String: Any]])
        json["points"] = points.map { point in
            var old = point
            old.removeValue(forKey: "achievement")
            return old
        }
        let old = try SharedSnapshot.decode(JSONSerialization.data(withJSONObject: json))
        #expect(old.quota?.achievement == nil)
        #expect(old.points.allSatisfy { $0.achievement == nil })
    }

    @Test func activityContributionsNeverBorrowPRWins() throws {
        let cache = try cache()
        var settings = settings()
        try cache.recordQuota(settings: settings, confirmed: true, now: first)
        try cache.replaceCalendar([day("2026-10-28"): 178], source: .graphQL, at: first)
        settings.metric = .contributions
        let snapshot = try SnapshotBuilder.build(
            settings: settings, cache: cache, tokenUsable: true, problems: [], now: first)
        let point = try #require(snapshot.points.last)
        #expect(point.count == 178)
        #expect(point.achievement == nil)
        #expect(snapshot.quota?.achievement?.metric == .prsMerged)
        #expect(snapshot.widget(.large)?.points.allSatisfy { $0.achievement == nil } == true)
        #expect(try SharedSnapshot.decode(SharedSnapshot.encode(snapshot)) == snapshot)
        let noToken = try SnapshotBuilder.build(
            settings: settings, cache: cache, tokenUsable: false, problems: [], now: first)
        #expect(noToken.points.last?.count == 178)
        #expect(noToken.points.allSatisfy { $0.achievement == nil })
        settings.repositories = ["other/repo"]
        let otherScope = try SnapshotBuilder.build(
            settings: settings, cache: cache, tokenUsable: true, problems: [], now: first)
        #expect(otherScope.points.allSatisfy { $0.achievement == nil })
        settings.repositories = []
        settings.goal = nil
        let noGoal = try SnapshotBuilder.build(
            settings: settings, cache: cache, tokenUsable: true, problems: [], now: first)
        #expect(noGoal.points.allSatisfy { $0.achievement == nil })
    }

    @Test func achievementsFromEarlierBuildsDecodeWithoutAMetric() throws {
        let old = Data(#"{"day":"2026-10-28","target":2,"count":2,"timeZoneID":"UTC"}"#.utf8)
        let achievement = try JSONDecoder().decode(QuotaAchievement.self, from: old)
        #expect(achievement.metric == nil)
        #expect(achievement.detail.contains("2 / 2 PRs"))
    }

    @Test func incompleteUnconfirmedAndUncoveredDataCannotEarnWins() throws {
        let settings = settings()
        for incomplete in [true, false] {
            let cache = try cache(incomplete: incomplete)
            try cache.recordQuota(settings: settings, confirmed: !incomplete, now: first)
            if incomplete {
                try cache.recordQuota(settings: settings, confirmed: true, now: first)
                #expect(try cache.quotaAchievements(settings: settings, metric: .prsMerged).isEmpty)
            }
        }
        let cache = try cache()
        try cache.recordQuota(settings: settings, confirmed: false, now: first)
        #expect(try cache.quotaAchievements(settings: settings, metric: .prsMerged).isEmpty)
        try cache.replacePullRequests(
            cache.pullRequests(), coveringFrom: first, incomplete: false, at: first)
        try cache.recordQuota(settings: settings, confirmed: true, now: first)
        #expect(try cache.quotaAchievements(settings: settings, metric: .prsMerged).isEmpty)
    }

    @Test func historyIsScopedAndHiddenWithoutAToken() throws {
        let cache = try cache()
        let original = settings()
        try cache.recordQuota(settings: original, confirmed: true, now: first)
        var changed = original
        changed.repositories = ["octo/other"]
        #expect(try cache.quotaAchievements(settings: changed, metric: .prsMerged).isEmpty)
        changed = original
        changed.timeZoneID = "Asia/Bangkok"
        #expect(try cache.quotaAchievements(settings: changed, metric: .prsMerged).isEmpty)
        changed = original
        changed.login = "other"
        #expect(try cache.quotaAchievements(settings: changed, metric: .prsMerged).isEmpty)
        #expect(try cache.quotaAchievements(settings: original, metric: .prsOpened).isEmpty)
        #expect(try cache.quotaAchievements(settings: original, metric: .contributions).isEmpty)
        let snapshot = try SnapshotBuilder.build(
            settings: original, cache: cache, tokenUsable: false, problems: [], now: first)
        #expect(snapshot.points.allSatisfy { $0.achievement == nil })
        #expect(snapshot.quota == nil)
    }

    @Test func winsSurviveRelaunchAndCountCorrectionsButNotDataRemoval() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(
            UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let path = directory.appendingPathComponent("cache.sqlite").path
        let settings = settings()
        do {
            let cache = try cache(path: path)
            try cache.recordQuota(settings: settings, confirmed: true, now: first)
        }
        let reopened = try MeasurementCache(path: path)
        try reopened.replacePullRequests(
            [], coveringFrom: date("2026-10-01T00:00:00Z"), incomplete: false, at: next)
        try reopened.recordQuota(settings: settings, confirmed: true, now: next)
        #expect(try reopened.quotaAchievements(settings: settings, metric: .prsMerged).count == 1)
        try reopened.eraseAll()
        #expect(try reopened.quotaAchievements(settings: settings, metric: .prsMerged).isEmpty)
    }

    @Test func accountResetRemovesWinsAndTimezoneControlsDayRollover() throws {
        let cache = try cache()
        var settings = settings()
        settings.timeZoneID = "Asia/Bangkok"
        try cache.recordQuota(settings: settings, confirmed: true, now: first)
        let win = try #require(
            cache.quotaAchievements(settings: settings, metric: .prsMerged)[day("2026-10-28")])
        #expect(win.isToday(at: date("2026-10-28T16:59:59Z")))
        #expect(!win.isToday(at: date("2026-10-28T17:00:00Z")))
        try cache.reset(for: "other")
        try cache.reset(for: "me")
        #expect(try cache.quotaAchievements(settings: settings, metric: .prsMerged).isEmpty)
    }
}

@Suite("Contribution daily goals")
struct ContributionGoalTests {
    let now = date("2026-10-28T12:00:00Z")
    let today = day("2026-10-28")

    func settings() -> DashboardSettings {
        var settings = DashboardSettings()
        settings.login = "me"
        settings.timeZoneID = "UTC"
        settings.metric = .contributions
        settings.goal = Goal(metric: .contributions, target: 10)
        return settings
    }

    func cache(_ counts: [CalendarDay: Int], source: CalendarSource = .profilePage) throws
        -> MeasurementCache
    {
        let cache = try MeasurementCache()
        try cache.reset(for: "me")
        try cache.replaceCalendar(counts, source: source, at: now)
        return cache
    }

    func snapshot(_ settings: DashboardSettings, _ cache: MeasurementCache, token: Bool = false)
        throws -> DashboardSnapshot
    {
        try SnapshotBuilder.build(
            settings: settings, cache: cache, tokenUsable: token, problems: [], now: now)
    }

    @Test func publicGoalUsesCalendarTotalsAcrossActivityMenuAndWidgets() throws {
        let settings = settings()
        let cache = try cache([today: 12, today.adding(days: -1): 100])
        try cache.recordQuota(settings: settings, confirmed: true, now: now)
        let snapshot = try snapshot(settings, cache)
        let quota = try #require(snapshot.quota)
        #expect(snapshot.tier == .usernameOnly)
        #expect(quota.count == 12)
        #expect(quota.target == 10)
        #expect(quota.isReached)
        #expect(quota.evidence.isEmpty)
        #expect(quota.scopeLabel.contains("unofficial"))
        #expect(quota.achievement?.metric == .contributions)
        #expect(quota.achievement?.detail.contains("GitHub calendar day") == true)
        #expect(snapshot.points.last?.achievement == quota.achievement)
        #expect(snapshot.widget(.medium)?.points.last?.achievement == quota.achievement)
        #expect(snapshot.widget(.large)?.points.last?.achievement == quota.achievement)
        #expect(snapshot.points.dropLast().allSatisfy { $0.achievement == nil })
        #expect(!snapshot.notices.contains { $0.contains("needs a GitHub token") })
        #expect(try SharedSnapshot.decode(SharedSnapshot.encode(snapshot)) == snapshot)
    }

    @Test func missingTodayIsUnknownWhileAReportedZeroIsARealCount() throws {
        let settings = settings()
        let cache = try cache([today.adding(days: -1): 100])
        try cache.recordQuota(settings: settings, confirmed: true, now: now)
        let unknown = try snapshot(settings, cache)
        #expect(unknown.quota == nil)
        #expect(unknown.todayCount == nil)
        #expect(unknown.notices.contains { $0.contains("not available yet") })
        #expect(try cache.quotaAchievements(settings: settings, metric: .contributions).isEmpty)
        try cache.replaceCalendar([today: 0], source: .profilePage, at: now)
        let zero = try snapshot(settings, cache)
        #expect(zero.quota?.count == 0)
        #expect(zero.quota?.isReached == false)
    }

    @Test func confirmationPreservesTargetsThroughDelayedCalendarUpdates() throws {
        var settings = settings()
        let cache = try cache([today: 12])
        try cache.recordQuota(settings: settings, confirmed: false, now: now)
        #expect(try cache.quotaAchievements(settings: settings, metric: .contributions).isEmpty)
        settings.goal?.target = 20
        let tomorrow = now.addingTimeInterval(24 * 60 * 60)
        try cache.recordQuota(settings: settings, confirmed: true, now: tomorrow)
        let win = try #require(
            cache.quotaAchievements(settings: settings, metric: .contributions)[today])
        #expect(win.target == 10)
        #expect(win.count == 12)
        try cache.replaceCalendar([today: 2], source: .profilePage, at: tomorrow)
        try cache.recordQuota(settings: settings, confirmed: true, now: tomorrow)
        #expect(
            try cache.quotaAchievements(settings: settings, metric: .contributions)[today] == win)
        #expect(
            try cache.quotaAchievements(settings: settings, metric: .contributions)[
                today.adding(days: 1)] == nil)
    }

    @Test func contributionHistoryIgnoresPRFiltersAndTimezoneButSeparatesAccountsAndSources() throws
    {
        var settings = settings()
        let cache = try cache([today: 12])
        try cache.recordQuota(settings: settings, confirmed: true, now: now)
        settings.repositories = ["another/repository"]
        settings.timeZoneID = "Asia/Ho_Chi_Minh"
        #expect(
            try cache.quotaAchievements(settings: settings, metric: .contributions)[today]?.target
                == 10)
        #expect(try snapshot(settings, cache).quota?.count == 12)
        try cache.replaceCalendar([today: 100], source: .graphQL, at: now)
        #expect(try cache.quotaAchievements(settings: settings, metric: .contributions).isEmpty)
        try cache.replaceCalendar([today: 12], source: .profilePage, at: now)
        #expect(
            try cache.quotaAchievements(settings: settings, metric: .contributions)[today]?.count
                == 12)
        settings.login = "someone-else"
        #expect(try snapshot(settings, cache).quota == nil)
        #expect(try cache.quotaAchievements(settings: settings, metric: .contributions).isEmpty)
    }

    @Test func contributionWinsNeverDecoratePRChartsOrWidgets() throws {
        var settings = settings()
        let cache = try cache([today: 12], source: .graphQL)
        try cache.recordQuota(settings: settings, confirmed: true, now: now)
        settings.metric = .prsOpened
        settings.widgets.large.metric = .prsMerged
        let snapshot = try snapshot(settings, cache, token: true)
        #expect(snapshot.quota?.achievement?.metric == .contributions)
        #expect(snapshot.points.allSatisfy { $0.achievement == nil })
        #expect(snapshot.widget(.large)?.points.allSatisfy { $0.achievement == nil } == true)
        settings.goal = Goal(metric: .prsMerged, target: 10)
        #expect(try self.snapshot(settings, cache).quota == nil)
    }

    @Test func publicGoalNotificationUsesContributionsAndIgnoresRepositoryChanges() throws {
        let settings = settings()
        let cache = try cache([today: 12])
        let quota = try snapshot(settings, cache).quota
        let completion = try #require(
            QuotaCompletion.due(
                quota: quota, goal: settings.goal, repositories: [], day: today, confirmed: true,
                announced: []))
        #expect(completion.body.contains("12 / 10 contributions"))
        #expect(
            QuotaCompletion.due(
                quota: quota, goal: settings.goal, repositories: ["me/repo"],
                day: today, confirmed: true, announced: [completion.key]) == nil)
        #expect(
            QuotaCompletion.due(
                quota: quota, goal: settings.goal, repositories: [],
                day: today, confirmed: false, announced: []) == nil)
    }

    @Test func goalConfirmationRequiresTheMatchingSourceToSucceed() {
        var report = SyncReport()
        #expect(!report.confirms(.contributions))
        #expect(!report.confirms(.prsMerged))
        report.calendarUpdated = true
        report.pullRequestError = .offline
        #expect(report.confirms(.contributions))
        #expect(!report.confirms(.prsMerged))
        report.calendarError = .offline
        report.tokenVerified = true
        report.pullRequestSyncMode = .changesOnly
        report.pullRequestError = nil
        #expect(!report.confirms(.contributions))
        #expect(report.confirms(.prsMerged))
        report.tokenErrors = ["missing": .unauthorized]
        #expect(!report.confirms(.prsMerged))
    }
}
