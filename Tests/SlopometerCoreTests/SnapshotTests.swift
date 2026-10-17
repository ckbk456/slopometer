import Foundation
import SlopometerCore
import Testing

@Suite("Source record cache")
struct SourceCacheTests {
    @Test func replacingPRsRemovesDeletedOnesAndDeduplicates() throws {
        let cache = try MeasurementCache()
        let start = date("2026-01-01T00:00:00Z")
        let a = pr("a", created: "2026-10-01T00:00:00Z")
        try cache.replacePullRequests(
            [a, a, pr("gone", created: "2026-10-02T00:00:00Z")], coveringFrom: start,
            incomplete: false, at: date("2026-10-15T00:00:00Z"))
        #expect(try cache.pullRequests().count == 2)
        try cache.replacePullRequests(
            [a], coveringFrom: start, incomplete: true, at: date("2026-10-16T00:00:00Z"))
        #expect(try cache.pullRequests() == [a])
        #expect(try cache.syncState().pullRequestResultsIncomplete)
    }

    @Test func changingAccountClearsPreviousRecords() throws {
        let cache = try MeasurementCache()
        try cache.replaceCalendar([day("2026-10-15"): 3], source: .graphQL, at: Date())
        try cache.reset(for: "other")
        #expect(try cache.calendar().isEmpty)
        #expect(try cache.syncState().login == "other")
        #expect(try cache.syncState().calendarSource == nil)
    }
}

@Suite("Dashboard snapshot")
struct SnapshotTests {
    let now = date("2026-10-16T05:00:00Z")  // Midday in Bangkok.

    func settings(_ metric: Metric, average: Int = 0, range: Int = 30) -> DashboardSettings {
        var settings = DashboardSettings()
        settings.login = "me"
        settings.metric = metric
        settings.rangeDays = range
        settings.averageWindow = average
        settings.timeZoneID = "Asia/Bangkok"
        return settings
    }

    @Test func prMetricsWithoutATokenSayWhatIsMissing() throws {
        let snapshot = try SnapshotBuilder.build(
            settings: settings(.prsMerged), cache: MeasurementCache(), tokenUsable: false,
            problems: [], now: now)
        #expect(snapshot.tier == .usernameOnly)
        #expect(snapshot.points.allSatisfy { $0.count == nil })
        #expect(snapshot.notices.contains { $0.contains("needs a GitHub token") })
    }

    @Test func averagesUseCompletedDaysAndTodayIsMarkedIncomplete() throws {
        let cache = try MeasurementCache()
        var counts: [CalendarDay: Int] = [:]
        for offset in 0..<10 { counts[day("2026-10-16").adding(days: -offset)] = 2 }
        try cache.replaceCalendar(counts, source: .graphQL, at: now)
        let snapshot = try SnapshotBuilder.build(
            settings: settings(.contributions, average: 3, range: 5), cache: cache,
            tokenUsable: true, problems: [], now: now)
        #expect(snapshot.points.count == 5)
        #expect(snapshot.points.last?.isIncomplete == true)
        #expect(snapshot.points.last?.average == nil)
        #expect(snapshot.points.dropLast().allSatisfy { $0.average == 2 })
        #expect(snapshot.todayCount == 2)
        #expect(snapshot.scopeLabel == "Account-wide")
    }

    @Test func eachWidgetSizeHasAFixedWindowThatAgreesWithTheChart() throws {
        let cache = try MeasurementCache()
        var counts: [CalendarDay: Int] = [:]
        for offset in 0..<400 { counts[day("2026-10-16").adding(days: -offset)] = offset % 5 }
        try cache.replaceCalendar(counts, source: .graphQL, at: now)
        for range in DashboardSettings.ranges {
            var configured = settings(.contributions, average: 7, range: range)
            configured.chartStyle = .line
            let snapshot = try SnapshotBuilder.build(
                settings: configured, cache: cache, tokenUsable: true, problems: [], now: now)
            #expect(snapshot.widget(.small)?.points.isEmpty == true)
            #expect(snapshot.widget(.small)?.todayCount == snapshot.todayCount)
            #expect(snapshot.widget(.medium)?.points.count == WidgetSettings.stripDays)
            let large = try #require(snapshot.widget(.large))
            #expect(large.chartStyle == .grid)
            #expect(large.points.count == WidgetSettings.gridDays)
            #expect(large.windowLabel == "Last 26 weeks")
            #expect(large.points.last?.day == day("2026-10-16"))
            #expect(large.points.last?.isIncomplete == true)
            #expect(large.points.allSatisfy { $0.average == nil })
            let recent = Dictionary(uniqueKeysWithValues: large.points.map { ($0.day, $0.count) })
            for point in snapshot.points where recent[point.day] != nil {
                #expect(recent[point.day] == point.count)
            }
        }
    }

    @Test func widgetSizesFollowTheirOwnSettingsNotTheDashboard() throws {
        let cache = try MeasurementCache()
        try cache.replaceCalendar([day("2026-10-16"): 4], source: .graphQL, at: now)
        try cache.replacePullRequests(
            [pr("a", created: "2026-10-16T02:00:00Z", merged: "2026-10-16T03:00:00Z")],
            coveringFrom: date("2025-09-01T00:00:00Z"), incomplete: false, at: now)
        var configured = settings(.prsMerged)
        configured.widgets.small = WidgetPanelSettings(headline: .today, metric: .contributions)
        configured.widgets.large = WidgetPanelSettings(
            headline: .today, metric: .prsOpened, chartStyle: .columns, windowDays: 30)
        let snapshot = try SnapshotBuilder.build(
            settings: configured, cache: cache, tokenUsable: true, problems: [], now: now)
        #expect(snapshot.todayCount == 1)
        #expect(snapshot.widget(.small)?.metric == .contributions)
        #expect(snapshot.widget(.small)?.todayCount == 4)
        #expect(snapshot.widget(.small)?.headline == .today)
        let large = try #require(snapshot.widget(.large))
        #expect(large.chartStyle == .columns)
        #expect(large.points.count == 30)
        #expect(large.windowLabel == "Last 30 days")
        #expect(large.todayCount == 1)
    }

    @Test func settingsSavedBeforeWidgetSettingsKeepTheirValues() throws {
        let saved = Data(
            #"{"login":"me","metric":"prsOpened","chartStyle":"columns","rangeDays":30,"averageWindow":0,"timeZoneID":"Asia/Bangkok","repositories":[]}"#
                .utf8)
        let decoded = try JSONDecoder().decode(DashboardSettings.self, from: saved)
        #expect(decoded.login == "me")
        #expect(decoded.rangeDays == 30)
        for size in WidgetSize.allCases { #expect(decoded.widgets[size].metric == .prsOpened) }
        #expect(decoded.widgets.large.chartStyle == .columns)
        let roundTrip = try JSONDecoder().decode(
            DashboardSettings.self, from: JSONEncoder().encode(decoded))
        #expect(roundTrip == decoded)
    }

    @Test func quotaAndEvidenceComeFromTheSameRecords() throws {
        let cache = try MeasurementCache()
        try cache.replacePullRequests(
            [
                pr("a", created: "2026-10-01T00:00:00Z", merged: "2026-10-16T02:00:00Z"),
                pr("b", created: "2026-10-01T00:00:00Z", merged: "2026-10-15T02:00:00Z"),
            ], coveringFrom: date("2025-09-01T00:00:00Z"), incomplete: false, at: now)
        var configured = settings(.prsMerged)
        configured.goal = Goal(metric: .prsMerged, target: 2)
        let snapshot = try SnapshotBuilder.build(
            settings: configured, cache: cache, tokenUsable: true, problems: [], now: now)
        #expect(snapshot.quota?.headline == "Daily slop quota: 1 / 2 authored PRs merged")
        #expect(snapshot.quota?.evidence.map(\.id) == ["a"])
        #expect(snapshot.todayCount == 1)
        #expect(snapshot.points.suffix(2).map(\.count) == [1, 1])
    }

    @Test func snapshotsRoundTripThroughTheSharedFormat() throws {
        let snapshot = try SnapshotBuilder.build(
            settings: settings(.contributions), cache: MeasurementCache(), tokenUsable: false,
            problems: ["Offline"], now: now)
        let decoded = try SharedSnapshot.decode(SharedSnapshot.encode(snapshot))
        #expect(decoded == snapshot)
    }
}
