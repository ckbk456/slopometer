import Foundation
import SlopometerCore
import Testing

@Suite("SQLite measurement cache")
struct MeasurementCacheTests {
    @Test func repeatedSyncReplacesTheSameDayWithoutDuplicatingIt() throws {
        let cache = try MeasurementCache()
        try cache.save(CachedDay(seriesID: "demo", day: "2026-10-01", count: 1))
        let revised = CachedDay(seriesID: "demo", day: "2026-10-01", count: 3)
        try cache.save(revised)
        #expect(try cache.days(in: "demo") == [revised])
    }

    @Test func separateSeriesAndUnknownCountsStaySeparate() throws {
        let cache = try MeasurementCache()
        try cache.save(CachedDay(seriesID: "a", day: "2026-10-02", count: nil))
        try cache.save(CachedDay(seriesID: "a", day: "2026-10-01", count: 0))
        try cache.save(CachedDay(seriesID: "b", day: "2026-10-01", count: 9))
        let days = try cache.days(in: "a")
        #expect(days.map(\.day) == ["2026-10-01", "2026-10-02"])
        #expect(days.map(\.count) == [0, nil])
    }

    @Test func invalidWritesDoNotCorruptExistingData() throws {
        let cache = try MeasurementCache()
        #expect(throws: MeasurementError.negativeCount) {
            try cache.save(CachedDay(seriesID: "demo", day: "2026-10-01", count: -1))
        }
        #expect(throws: MeasurementError.emptySeries) {
            try cache.save(CachedDay(seriesID: "", day: "2026-10-01", count: 1))
        }
        #expect(try cache.days(in: "demo").isEmpty)
    }

    @Test func fileBackedDataSurvivesOpeningANewConnection() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("slopometer-tests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let path = directory.appendingPathComponent("cache.sqlite").path
        let record = CachedDay(seriesID: "demo", day: "2026-10-01", count: 5)
        try MeasurementCache(path: path).save(record)
        let reopened = try MeasurementCache(path: path)
        #expect(try reopened.days(in: "demo") == [record])
    }

    @Test func syncStateWrittenBeforeCheckpointsStillDecodes() throws {
        let legacy = Data(#"{"login":"me","pullRequestResultsIncomplete":true}"#.utf8)
        let state = try JSONDecoder().decode(SyncState.self, from: legacy)
        #expect(state.login == "me")
        #expect(state.pullRequestResultsIncomplete)
        #expect(state.lastFullPullRequestSync == nil)
        #expect(state.pullRequestCheckpoints.isEmpty)
    }

    @Test func upsertKeepsOtherRecordsAndOnlyWidensCoverage() throws {
        let cache = try MeasurementCache()
        try cache.reset(for: "me")
        let first = Date(timeIntervalSince1970: 1_700_000_000)
        let record = PullRequestRecord(
            id: "x", number: 1, title: "x", repository: "me/app", url: "u", isDraft: false,
            createdAt: first, mergedAt: nil)
        try cache.replacePullRequests(
            [record], coveringFrom: first, incomplete: false, checkpoints: ["a": first],
            at: first)
        let later = first.addingTimeInterval(900)
        let merged = PullRequestRecord(
            id: "x", number: 1, title: "x", repository: "me/app", url: "u", isDraft: false,
            createdAt: first, mergedAt: later)
        let other = PullRequestRecord(
            id: "y", number: 2, title: "y", repository: "me/app", url: "u", isDraft: false,
            createdAt: later, mergedAt: nil)
        try cache.upsertPullRequests(
            [merged, other], coveringFrom: later, incomplete: true, checkpoints: ["b": later],
            at: later)
        #expect(try cache.pullRequests() == [merged, other])
        let state = try cache.syncState()
        #expect(state.pullRequestCoverageStart == first)
        #expect(state.pullRequestResultsIncomplete)
        #expect(state.pullRequestCheckpoints == ["a": first, "b": later])
        #expect(state.lastFullPullRequestSync == first)
        #expect(state.lastPullRequestSync == later)
    }
}
