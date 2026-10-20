import Foundation
import SlopometerCore
import Testing

@Suite("Source record cache")
struct SourceCacheTests {
    @Test func erasingAllRemovesEveryRecordAndTheSyncState() throws {
        let cache = try MeasurementCache()
        try cache.reset(for: "me")
        try cache.save(CachedDay(seriesID: "demo", day: "2026-10-01", count: 2))
        try cache.replaceCalendar(
            [CalendarDay(year: 2026, month: 10, day: 1)!: 4], source: .profilePage,
            at: date("2026-10-15T00:00:00Z"))
        try cache.replacePullRequests(
            [pr("a", created: "2026-10-01T00:00:00Z")], coveringFrom: date("2026-01-01T00:00:00Z"),
            incomplete: false, checkpoints: ["token": date("2026-10-15T00:00:00Z")],
            at: date("2026-10-15T00:00:00Z"))
        try cache.eraseAll()
        #expect(try cache.days(in: "demo").isEmpty)
        #expect(try cache.calendar().isEmpty)
        #expect(try cache.pullRequests().isEmpty)
        #expect(try cache.syncState() == SyncState())
        // Still usable afterwards.
        try cache.reset(for: "someone")
        #expect(try cache.holds("someone"))
    }

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
                settings: configured, cache: cache, tokenUsable: true, problems: [], now: now,
                firstWeekday: 2)
            #expect(snapshot.widget(.small)?.points.isEmpty == true)
            #expect(snapshot.widget(.small)?.todayCount == snapshot.todayCount)
            #expect(snapshot.widget(.medium)?.points.count == WidgetSettings.stripDays)
            let large = try #require(snapshot.widget(.large))
            #expect(large.chartStyle == .grid)
            // Four full Monday-first weeks plus Monday through Friday the 16th.
            #expect(large.points.count == 4 * 7 + 5)
            #expect(large.points.first?.day == day("2026-09-14"))
            #expect(large.windowLabel == "Last 5 weeks")
            #expect(large.points.last?.day == day("2026-10-16"))
            #expect(large.points.last?.isIncomplete == true)
            #expect(large.points.allSatisfy { $0.average == nil })
            let recent = Dictionary(uniqueKeysWithValues: large.points.map { ($0.day, $0.count) })
            for point in snapshot.points where recent[point.day] != nil {
                #expect(recent[point.day] == point.count)
            }
        }
    }

    @Test func largeCalendarStartsOnTheFirstWeekdayFiveWeeksBack() throws {
        let cache = try MeasurementCache()
        var counts: [CalendarDay: Int] = [:]
        for offset in 0..<60 { counts[day("2026-10-16").adding(days: -offset)] = 1 }
        try cache.replaceCalendar(counts, source: .graphQL, at: now)
        // The shortest dashboard range without an average still covers every widget window.
        let configured = settings(.contributions, average: 0, range: 30)
        for (firstWeekday, start) in [(1, "2026-09-13"), (2, "2026-09-14"), (6, "2026-09-18")] {
            let snapshot = try SnapshotBuilder.build(
                settings: configured, cache: cache, tokenUsable: true, problems: [], now: now,
                firstWeekday: firstWeekday)
            let large = try #require(snapshot.widget(.large))
            #expect(large.points.first?.day == day(start))
            #expect(large.points.first?.day.weekday == firstWeekday)
            #expect(large.points.last?.day == day("2026-10-16"))
            #expect(large.points.allSatisfy { $0.count == 1 })
            let rows = WidgetSettings.calendarRows(
                large.points, firstWeekday: firstWeekday, day: \.day)
            #expect(rows.count == WidgetSettings.calendarWeeks)
            #expect(rows.allSatisfy { $0.count == 7 })
            #expect(rows.first?.allSatisfy { $0 != nil } == true)
            // Days after today are empty placeholders, not zero counts.
            let lastRow = try #require(rows.last)
            let todayColumn = try #require(lastRow.lastIndex { $0 != nil })
            #expect(lastRow[todayColumn]?.isIncomplete == true)
            #expect(lastRow[(todayColumn + 1)...].allSatisfy { $0 == nil })
        }
    }

    @Test func calendarRowsAlignAnyDaysToWeekdayColumns() {
        // Monday-first: Friday 2026-10-16 is column 4, so the week ends with two blanks.
        let days = CalendarDay.range(from: day("2026-10-01"), through: day("2026-10-16"))
        let rows = WidgetSettings.calendarRows(days, firstWeekday: 2, day: { $0 })
        #expect(rows.count == 3)
        #expect(rows[0].prefix(3).allSatisfy { $0 == nil })
        #expect(rows[0][3] == day("2026-10-01"))
        #expect(rows[2][4] == day("2026-10-16"))
        #expect(rows[2][5] == nil && rows[2][6] == nil)
        // Longer input keeps only the last weeks, ending with today's.
        let long = CalendarDay.range(from: day("2026-04-01"), through: day("2026-10-16"))
        let kept = WidgetSettings.calendarRows(long, firstWeekday: 1, day: { $0 })
        #expect(kept.count == WidgetSettings.calendarWeeks)
        #expect(kept[0][0] == day("2026-09-13"))
        #expect(WidgetSettings.calendarRows([CalendarDay](), firstWeekday: 1, day: { $0 }).isEmpty)
        #expect(WidgetSettings.calendarDays(through: day("2026-10-11"), firstWeekday: 1) == 29)
        #expect(WidgetSettings.calendarDays(through: day("2026-10-17"), firstWeekday: 1) == 35)
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

    @Test func missingWidgetSettingsUseTheDefaults() throws {
        let saved = Data(
            #"{"login":"me","metric":"prsOpened","chartStyle":"columns","rangeDays":30,"averageWindow":0,"timeZoneID":"Asia/Bangkok","repositories":[]}"#
                .utf8)
        let decoded = try JSONDecoder().decode(DashboardSettings.self, from: saved)
        #expect(decoded.login == "me")
        #expect(decoded.rangeDays == 30)
        #expect(decoded.widgets == WidgetSettings())
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

    @Test func writerBuildRoundTripsAndOldSnapshotsStillDecode() throws {
        var snapshot = DashboardSnapshot.placeholder
        snapshot.writerBuild = BuildStamp(version: "0.11.1", build: "42", commit: "abc1234")
        let data = try SharedSnapshot.encode(snapshot)
        #expect(try SharedSnapshot.decode(data).writerBuild == snapshot.writerBuild)
        // A snapshot written before 0.11.1 has no writerBuild key.
        var json = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
        json["writerBuild"] = nil
        let old = try SharedSnapshot.decode(JSONSerialization.data(withJSONObject: json))
        #expect(old.writerBuild == nil)
        #expect(old.login == snapshot.login)
    }

    @Test func snapshotsCarryTheAppearanceAndOldOnesFollowTheSystem() throws {
        var configured = settings(.contributions)
        configured.appearance = .light
        let snapshot = try SnapshotBuilder.build(
            settings: configured, cache: MeasurementCache(), tokenUsable: false, problems: [],
            now: now)
        #expect(snapshot.appearance == .light)
        let data = try SharedSnapshot.encode(snapshot)
        #expect(try SharedSnapshot.decode(data).appearance == .light)
        // A snapshot written before appearance modes has no appearance key.
        var json = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
        json["appearance"] = nil
        let old = try SharedSnapshot.decode(JSONSerialization.data(withJSONObject: json))
        #expect(old.appearance == nil)
    }

    @Test func buildMismatchNeedsBothBuildsKnownAndDifferent() {
        let widget = BuildStamp(version: "0.11.1", build: "42", commit: "abc1234")
        let differs = { BuildStamp.differs(writer: $0, reader: widget) }
        #expect(!differs(nil))
        #expect(!differs(widget))
        #expect(!differs(BuildStamp(version: "0.11.1", build: "42", commit: "abc1234-modified")))
        #expect(differs(BuildStamp(version: "0.10.0", build: "42", commit: "abc1234")))
        #expect(differs(BuildStamp(version: "0.11.1", build: "41", commit: "abc1234")))
        #expect(!differs(BuildStamp(version: "0.10.0", build: "unknown", commit: "unknown")))
        #expect(
            !BuildStamp.differs(
                writer: BuildStamp(version: "0.10.0", build: "40", commit: "x"),
                reader: BuildStamp(version: "unknown", build: "unknown", commit: "unknown")))
    }
}
