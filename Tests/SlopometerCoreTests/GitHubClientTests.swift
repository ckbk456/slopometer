import Foundation
import Testing

@testable import SlopometerCore

/// Serves canned responses and records every request. Handlers run in request order.
final class FakeTransport: HTTPTransport, @unchecked Sendable {
    typealias Handler = (URLRequest) throws -> (Int, [String: String], Data)
    private let lock = NSLock()
    private var handler: Handler
    private(set) var requests: [URLRequest] = []

    init(_ handler: @escaping Handler) {
        self.handler = handler
    }

    func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        let (status, headers, body) = try lock.withLock {
            requests.append(request)
            return try handler(request)
        }
        let response = HTTPURLResponse(
            url: request.url!, statusCode: status, httpVersion: nil, headerFields: headers)!
        return (body, response)
    }

    var searchQueries: [String] {
        lock.withLock {
            requests.compactMap { request in
                guard request.url?.path == "/search/issues" else { return nil }
                return URLComponents(url: request.url!, resolvingAgainstBaseURL: false)?
                    .queryItems?.first { $0.name == "q" }?.value
            }
        }
    }
}

func json(_ object: Any) -> Data {
    try! JSONSerialization.data(withJSONObject: object)
}

func searchItem(_ id: String, created: String, merged: String? = nil) -> [String: Any] {
    [
        "node_id": id, "number": 7, "title": "Title \(id)",
        "html_url": "https://github.com/me/app/pull/7",
        "repository_url": "https://api.github.com/repos/me/app", "draft": false,
        "created_at": created,
        "pull_request": ["merged_at": merged as Any? ?? NSNull()],
    ]
}

func searchPage(total: Int, items: [[String: Any]], incomplete: Bool = false) -> Data {
    json(["total_count": total, "incomplete_results": incomplete, "items": items])
}

/// A clock that only sleeping advances, so limiter waits are observable and instant.
final class FakeClock: @unchecked Sendable {
    private let lock = NSLock()
    private var time: Date
    private(set) var sleeps: [TimeInterval] = []

    init(_ start: Date = date("2026-10-16T00:00:00Z")) {
        time = start
    }

    var now: Date { lock.withLock { time } }

    func sleep(_ seconds: TimeInterval) {
        lock.withLock {
            sleeps.append(seconds)
            time = time.addingTimeInterval(seconds)
        }
    }

    func limiter() -> SearchRateLimiter {
        SearchRateLimiter(now: { self.now }, sleep: { self.sleep($0) })
    }
}

func client(_ transport: FakeTransport, clock: FakeClock = FakeClock()) -> GitHubClient {
    GitHubClient(transport: transport, searchLimiter: clock.limiter())
}

@Suite("Public profile calendar")
struct ProfileCalendarTests {
    @Test func parsesTheRecordedMarkup() throws {
        let url = Bundle.module.url(forResource: "profile-calendar", withExtension: "html")!
        let counts = try ProfileCalendarParser.parse(String(contentsOf: url, encoding: .utf8))
        #expect(counts[day("2025-10-12")] == 0)
        #expect(counts[day("2025-10-26")] == 1)
        #expect(counts[day("2025-11-02")] == 1234)
        #expect(counts.count == 3)
    }

    @Test func changedMarkupIsAnErrorNotZeroActivity() {
        #expect(throws: GitHubError.malformedResponse) {
            try ProfileCalendarParser.parse("<html>redesigned</html>")
        }
    }
}

@Suite("GitHub client")
struct GitHubClientTests {
    let from = date("2026-01-01T00:00:00Z")
    let to = date("2026-10-16T00:00:00Z")

    @Test func mergesCreatedAndMergedSearchesWithoutDuplicates() async throws {
        let transport = FakeTransport { request in
            let query = URLComponents(url: request.url!, resolvingAgainstBaseURL: false)!
                .queryItems!.first { $0.name == "q" }!.value!
            if !query.contains("merged:") {
                return (
                    200, [:],
                    searchPage(
                        total: 1,
                        items: [
                            searchItem(
                                "a", created: "2026-05-01T00:00:00Z", merged: "2026-05-02T00:00:00Z"
                            )
                        ])
                )
            }
            return (
                200, [:],
                searchPage(
                    total: 2,
                    items: [
                        searchItem(
                            "a", created: "2026-05-01T00:00:00Z", merged: "2026-05-02T00:00:00Z"),
                        searchItem(
                            "old", created: "2025-11-01T00:00:00Z", merged: "2026-02-01T00:00:00Z"),
                    ])
            )
        }
        let fetch = try await client(transport).authoredPullRequests(
            login: "me", token: "t", from: from, to: to)
        #expect(fetch.records.map(\.id) == ["old", "a"])
        #expect(fetch.records.first?.repository == "me/app")
        #expect(!fetch.isIncomplete)
        #expect(transport.searchQueries.allSatisfy { $0.hasPrefix("author:me type:pr ") })
        // The merged search skips PRs the created search already returned.
        #expect(
            transport.searchQueries == [
                "author:me type:pr created:2026-01-01T00:00:00Z..2026-10-16T00:00:00Z",
                "author:me type:pr merged:2026-01-01T00:00:00Z..2026-10-16T00:00:00Z"
                    + " created:<2026-01-01T00:00:00Z",
            ])
    }

    @Test func fetchesChangesSinceACheckpointWithOneSearch() async throws {
        let transport = FakeTransport { _ in
            (
                200, [:],
                searchPage(
                    total: 1,
                    items: [searchItem("old", created: "2025-11-01T00:00:00Z", merged: nil)])
            )
        }
        let fetch = try await client(transport).updatedPullRequests(
            login: "me", token: "t", since: date("2026-10-15T18:00:00Z"), to: to)
        #expect(fetch.records.map(\.id) == ["old"])
        #expect(
            transport.searchQueries == [
                "author:me type:pr updated:2026-10-15T18:00:00Z..2026-10-16T00:00:00Z"
            ])
    }

    @Test func splitsWindowsThatExceedTheSearchCap() async throws {
        let transport = FakeTransport { request in
            let query = URLComponents(url: request.url!, resolvingAgainstBaseURL: false)!
                .queryItems!.first { $0.name == "q" }!.value!
            let isFullWindow = query.contains("2026-01-01T00:00:00Z..2026-10-16T00:00:00Z")
            return (200, [:], searchPage(total: isFullWindow ? 1500 : 0, items: []))
        }
        _ = try await client(transport).authoredPullRequests(
            login: "me", token: "t", from: from, to: to)
        // Each qualifier: one oversized probe, then two halves.
        #expect(transport.searchQueries.count == 6)
    }

    @Test func paginatesUpToTheReportedTotal() async throws {
        let transport = FakeTransport { request in
            let page = URLComponents(url: request.url!, resolvingAgainstBaseURL: false)!
                .queryItems!.first { $0.name == "page" }!.value!
            let items = (0..<(page == "3" ? 50 : 100)).map {
                searchItem("p\(page)-\($0)", created: "2026-05-01T00:00:00Z")
            }
            return (200, [:], searchPage(total: 250, items: items))
        }
        let fetch = try await client(transport).authoredPullRequests(
            login: "me", token: "t", from: from, to: to)
        #expect(fetch.records.count == 250)
        #expect(transport.searchQueries.count == 6)
    }

    @Test func reportsIncompleteSearchResults() async throws {
        let transport = FakeTransport { _ in
            (200, [:], searchPage(total: 0, items: [], incomplete: true))
        }
        let fetch = try await client(transport).authoredPullRequests(
            login: "me", token: "t", from: from, to: to)
        #expect(fetch.isIncomplete)
    }

    @Test func mapsRateLimitsAndRejectedTokens() async {
        let limited = FakeTransport { _ in
            (403, ["X-RateLimit-Remaining": "0", "X-RateLimit-Reset": "1800000000"], Data())
        }
        await #expect(
            throws: GitHubError.rateLimited(resetAt: Date(timeIntervalSince1970: 1_800_000_000))
        ) {
            try await client(limited).viewerLogin(token: "t")
        }
        let rejected = FakeTransport { _ in (401, [:], Data()) }
        await #expect(throws: GitHubError.unauthorized) {
            try await client(rejected).viewerLogin(token: "t")
        }
    }

    @Test func searchesWaitOnlyWhenTheMinuteBudgetIsSpent() async throws {
        let clock = FakeClock()
        let transport = FakeTransport { _ in (200, [:], searchPage(total: 0, items: [])) }
        let client = client(transport, clock: clock)
        for _ in 0..<(SearchRateLimiter.requestsPerWindow / 2) {
            _ = try await client.authoredPullRequests(login: "me", token: "t", from: from, to: to)
        }
        #expect(clock.sleeps.isEmpty)
        #expect(transport.searchQueries.count == SearchRateLimiter.requestsPerWindow)
        _ = try await client.authoredPullRequests(login: "me", token: "t", from: from, to: to)
        #expect(clock.sleeps.count == 1)
        #expect(clock.sleeps[0] > 59 && clock.sleeps[0] <= 60)
    }

    @Test func anExhaustedSearchBudgetWaitsForGitHubsReset() async throws {
        let clock = FakeClock()
        let reset = clock.now.addingTimeInterval(20)
        let transport = FakeTransport { _ in
            (
                200,
                [
                    "X-RateLimit-Remaining": "0",
                    "X-RateLimit-Reset": String(Int(reset.timeIntervalSince1970)),
                ], searchPage(total: 0, items: [])
            )
        }
        _ = try await client(transport, clock: clock).authoredPullRequests(
            login: "me", token: "t", from: from, to: to)
        #expect(clock.sleeps == [20])
    }

    @Test func rejectsInvalidLoginsBeforeAnyRequest() async {
        let transport = FakeTransport { _ in
            Issue.record("unexpected request")
            return (500, [:], Data())
        }
        await #expect(throws: GitHubError.invalidLogin) {
            try await client(transport).profileCalendar(login: "../evil")
        }
    }

    @Test func requestsTheGraphQLCalendarInSpansOfAtMostAYear() async throws {
        let transport = FakeTransport { _ in
            (
                200, [:],
                json([
                    "data": [
                        "user": [
                            "contributionsCollection": [
                                "contributionCalendar": [
                                    "weeks": [
                                        [
                                            "contributionDays": [
                                                ["date": "2026-10-15", "contributionCount": 4]
                                            ]
                                        ]
                                    ]
                                ]
                            ]
                        ]
                    ]
                ])
            )
        }
        let counts = try await client(transport).contributionCalendar(
            login: "me", token: "t", from: date("2025-09-16T00:00:00Z"), to: to)
        #expect(counts[day("2026-10-15")] == 4)
        #expect(transport.requests.count == 2)
    }
}

@Suite("Sync coordinator")
struct SyncCoordinatorTests {
    let now = date("2026-10-16T05:00:00Z")

    /// The account is the token owner; a different typed username is not a mismatch.
    @Test func theTokenOwnerReplacesTheTypedUsername() async throws {
        let cache = try MeasurementCache()
        let transport = FakeTransport { _ in
            (200, [:], json(["data": ["viewer": ["login": "someone-else"]]]))
        }
        let report = await SyncCoordinator(client: client(transport), cache: cache).sync(
            SyncRequest(login: "me", token: "t", timeZone: bangkok, now: now))
        #expect(report.login == "someone-else")
        #expect(report.tokenVerified)
        #expect(report.tokenErrors.isEmpty)
        #expect(try cache.syncState().login == "someone-else")
    }

    @Test func usernameOnlySyncNeverSendsCredentials() async throws {
        let cache = try MeasurementCache()
        let transport = FakeTransport { _ in
            let url = Bundle.module.url(forResource: "profile-calendar", withExtension: "html")!
            return (200, [:], try Data(contentsOf: url))
        }
        let report = await SyncCoordinator(client: client(transport), cache: cache).sync(
            SyncRequest(login: "me", token: nil, timeZone: bangkok, now: now))
        var expected = SyncReport()
        expected.login = "me"
        #expect(report == expected)
        #expect(
            transport.requests.allSatisfy { $0.value(forHTTPHeaderField: "Authorization") == nil })
        #expect(try cache.calendar().count == 3)
    }

    /// Answers as GitHub would for tokens `personal` and `org`, which see different PRs.
    func twoOwnerTransport(rejecting rejected: String? = nil) -> FakeTransport {
        FakeTransport { request in
            let token = request.value(forHTTPHeaderField: "Authorization")?
                .replacingOccurrences(of: "Bearer ", with: "")
            if token == rejected { return (401, [:], Data()) }
            if request.url?.path == "/graphql" {
                let body = String(data: request.httpBody ?? Data(), encoding: .utf8) ?? ""
                if body.contains("viewer") {
                    return (200, [:], json(["data": ["viewer": ["login": "me"]]]))
                }
                let calendar = ["contributionCalendar": ["weeks": [] as [Any]]]
                return (200, [:], json(["data": ["user": ["contributionsCollection": calendar]]]))
            }
            let items =
                token == "personal"
                ? [searchItem("shared", created: "2026-10-15T01:00:00Z")]
                : [
                    searchItem("shared", created: "2026-10-15T01:00:00Z"),
                    searchItem("org-only", created: "2026-10-15T02:00:00Z"),
                ]
            return (200, [:], searchPage(total: items.count, items: items))
        }
    }

    @Test func pullRequestsFromEveryTokenAreMergedOnce() async throws {
        let cache = try MeasurementCache()
        let transport = twoOwnerTransport()
        let report = await SyncCoordinator(client: client(transport), cache: cache).sync(
            SyncRequest(
                login: "me",
                tokens: [
                    AccessToken(id: "a", value: "personal"), AccessToken(id: "b", value: "org"),
                ], timeZone: bangkok, now: now))
        #expect(report.verifiedTokenIDs == ["a", "b"])
        #expect(report.pullRequestError == nil)
        #expect(try cache.pullRequests().map(\.id).sorted() == ["org-only", "shared"])
        #expect(try !cache.syncState().pullRequestResultsIncomplete)
        // Recent window then older window, created and merged searches, per token.
        #expect(transport.searchQueries.count == 8)
        #expect(report.pullRequestSyncMode == .fullReconcile)
    }

    @Test func aFailedTokenKeepsTheOthersButMarksCoverageIncomplete() async throws {
        let cache = try MeasurementCache()
        let report = await SyncCoordinator(
            client: client(twoOwnerTransport(rejecting: "org")), cache: cache
        ).sync(
            SyncRequest(
                login: "me",
                tokens: [
                    AccessToken(id: "a", value: "personal"), AccessToken(id: "b", value: "org"),
                ], timeZone: bangkok, now: now))
        #expect(report.tokenVerified)
        #expect(report.tokenErrors == ["b": .unauthorized])
        #expect(report.pullRequestError == nil)
        #expect(try cache.pullRequests().map(\.id) == ["shared"])
        #expect(try cache.syncState().pullRequestResultsIncomplete)
        #expect(try cache.syncState().calendarSource == .graphQL)
    }

    @Test func tokenKindFollowsGitHubPrefixes() {
        #expect(AccessToken.Kind(of: "github_pat_11ABC") == .fineGrained)
        #expect(AccessToken.Kind(of: "ghp_abc") == .classic)
        #expect(AccessToken.Kind(of: "0123456789abcdef0123456789abcdef01234567") == .classic)
    }

    @Test func failedSyncKeepsCachedDataAndLastSuccess() async throws {
        let cache = try MeasurementCache()
        try cache.reset(for: "me")
        try cache.replaceCalendar(
            [day("2026-10-15"): 2], source: .profilePage, at: date("2026-10-15T00:00:00Z"))
        let offline = FakeTransport { _ in throw GitHubError.offline }
        let report = await SyncCoordinator(client: client(offline), cache: cache).sync(
            SyncRequest(login: "me", token: nil, timeZone: bangkok, now: now))
        #expect(report.calendarError == .offline)
        #expect(try cache.calendar() == [day("2026-10-15"): 2])
        #expect(try cache.syncState().lastCalendarSync == date("2026-10-15T00:00:00Z"))
    }
}

/// Records what a sync had published when each stage began.
final class StageLog: @unchecked Sendable {
    private let lock = NSLock()
    private(set) var entries: [(SyncStage, Bool, [String])] = []

    func record(_ progress: SyncProgress, cache: MeasurementCache) {
        let ids = (try? cache.pullRequests().map(\.id).sorted()) ?? []
        lock.withLock { entries.append((progress.stage, progress.cacheChanged, ids)) }
    }
}

@Suite("Incremental sync")
struct IncrementalSyncTests {
    let now = date("2026-10-16T05:00:00Z")
    let token = AccessToken(id: "a", value: "personal")

    /// Verifies the token as `me`, serves an empty calendar, and answers searches from
    /// `items`, which receives the query string.
    func serving(_ items: @escaping @Sendable (String) throws -> [[String: Any]]) -> FakeTransport {
        FakeTransport { request in
            if request.url?.path == "/graphql" {
                let body = String(data: request.httpBody ?? Data(), encoding: .utf8) ?? ""
                if body.contains("viewer") {
                    return (200, [:], json(["data": ["viewer": ["login": "me"]]]))
                }
                let calendar = ["contributionCalendar": ["weeks": [] as [Any]]]
                return (200, [:], json(["data": ["user": ["contributionsCollection": calendar]]]))
            }
            let query = URLComponents(url: request.url!, resolvingAgainstBaseURL: false)!
                .queryItems!.first { $0.name == "q" }!.value!
            let found = try items(query)
            return (200, [:], searchPage(total: found.count, items: found))
        }
    }

    func request(at date: Date, tokens: [AccessToken]? = nil) -> SyncRequest {
        SyncRequest(login: "me", tokens: tokens ?? [token], timeZone: bangkok, now: date)
    }

    /// Full window on the first sync: an old PR and a recent one.
    @Sendable static func history(_ query: String) -> [[String: Any]] {
        // Windows start at Bangkok midnight, 17:00Z the day before.
        if query.contains("created:2026-09-15T17:00:00Z..") {  // recent window
            return [searchItem("recent", created: "2026-10-15T01:00:00Z")]
        }
        if query.contains("created:2025-09-15T17:00:00Z..2026-09-15T16:59:59Z") {  // older
            return [searchItem("old", created: "2026-01-10T01:00:00Z")]
        }
        return []
    }

    @Test func firstSyncPublishesRecentPullRequestsBeforeOlderHistory() async throws {
        let cache = try MeasurementCache()
        let log = StageLog()
        let report = await SyncCoordinator(client: client(serving(Self.history)), cache: cache)
            .sync(request(at: now)) { log.record($0, cache: cache) }
        #expect(report.pullRequestError == nil)
        #expect(report.pullRequestSyncMode == .fullReconcile)
        #expect(
            log.entries.map(\.0) == [
                .checkingTokens, .updatingCalendar, .fetchingRecentPullRequests,
                .loadingOlderPullRequests,
            ])
        #expect(log.entries.map(\.1) == [false, false, true, true])
        // When older history starts loading, the recent PR is already in the cache.
        #expect(log.entries[3].2 == ["recent"])
        #expect(try cache.pullRequests().map(\.id) == ["old", "recent"])
        let state = try cache.syncState()
        #expect(state.lastFullPullRequestSync == now)
        #expect(state.pullRequestCheckpoints == ["a": now])
        #expect(state.pullRequestCoverageStart == day("2025-09-16").start(in: bangkok))
    }

    @Test func coverageIsOnlyTheRecentWindowUntilOlderHistoryLoads() async throws {
        let cache = try MeasurementCache()
        let seen = StageLog()
        _ = await SyncCoordinator(client: client(serving(Self.history)), cache: cache)
            .sync(request(at: now)) { progress in
                guard progress.stage == .loadingOlderPullRequests else { return }
                let start = try? cache.syncState().pullRequestCoverageStart
                let recentOnly = start == day("2026-09-16").start(in: bangkok)
                seen.record(
                    SyncProgress(stage: progress.stage, cacheChanged: recentOnly), cache: cache)
            }
        #expect(seen.entries.map(\.1) == [true])
    }

    @Test func theNextSyncFetchesOnlyChangesAndMergesThemIn() async throws {
        let cache = try MeasurementCache()
        _ = await SyncCoordinator(client: client(serving(Self.history)), cache: cache)
            .sync(request(at: now))
        let later = now.addingTimeInterval(15 * 60)
        let transport = serving { query in
            // Six hours before the checkpoint, up to this sync's time.
            #expect(query == "author:me type:pr updated:2026-10-15T23:00:00Z..2026-10-16T05:15:00Z")
            return [
                searchItem(
                    "recent", created: "2026-10-15T01:00:00Z", merged: "2026-10-16T05:10:00Z"),
                searchItem("new", created: "2026-10-16T05:05:00Z"),
            ]
        }
        let report = await SyncCoordinator(client: client(transport), cache: cache)
            .sync(request(at: later))
        #expect(report.pullRequestError == nil)
        #expect(report.pullRequestSyncMode == .changesOnly)
        #expect(transport.searchQueries.count == 1)
        let records = try cache.pullRequests()
        #expect(records.map(\.id) == ["old", "recent", "new"])
        #expect(records.first { $0.id == "recent" }?.mergedAt == date("2026-10-16T05:10:00Z"))
        let state = try cache.syncState()
        #expect(state.pullRequestCheckpoints == ["a": later])
        #expect(state.lastFullPullRequestSync == now)
        #expect(state.lastPullRequestSync == later)
    }

    @Test func changesOutsideTheWindowAreNotAdded() async throws {
        let cache = try MeasurementCache()
        _ = await SyncCoordinator(client: client(serving(Self.history)), cache: cache)
            .sync(request(at: now))
        let transport = serving { _ in
            [
                searchItem("ancient-comment", created: "2024-01-01T00:00:00Z"),
                searchItem(
                    "ancient-merged", created: "2024-01-01T00:00:00Z",
                    merged: "2026-10-16T05:10:00Z"),
            ]
        }
        _ = await SyncCoordinator(client: client(transport), cache: cache)
            .sync(request(at: now.addingTimeInterval(15 * 60)))
        #expect(try cache.pullRequests().map(\.id) == ["ancient-merged", "old", "recent"])
    }

    @Test func aDayLaterTheWholeWindowIsReconciledAndRemovedPRsDisappear() async throws {
        let cache = try MeasurementCache()
        _ = await SyncCoordinator(client: client(serving(Self.history)), cache: cache)
            .sync(request(at: now))
        let later = now.addingTimeInterval(25 * 3600)
        let transport = serving { query in
            query.contains("created:2026-09-16T17:00:00Z..")
                ? [searchItem("recent", created: "2026-10-15T01:00:00Z")] : []
        }
        let report = await SyncCoordinator(client: client(transport), cache: cache)
            .sync(request(at: later))
        #expect(report.pullRequestSyncMode == .fullReconcile)
        #expect(transport.searchQueries.allSatisfy { !$0.contains("updated:") })
        #expect(try cache.pullRequests().map(\.id) == ["recent"])
        #expect(try cache.syncState().lastFullPullRequestSync == later)
    }

    @Test func aNewTokenForcesAFullReconcile() async throws {
        let cache = try MeasurementCache()
        _ = await SyncCoordinator(client: client(serving(Self.history)), cache: cache)
            .sync(request(at: now))
        let transport = serving(Self.history)
        let report = await SyncCoordinator(client: client(transport), cache: cache)
            .sync(
                request(
                    at: now.addingTimeInterval(60),
                    tokens: [token, AccessToken(id: "b", value: "org")]))
        #expect(report.pullRequestSyncMode == .fullReconcile)
        #expect(try cache.syncState().pullRequestCheckpoints.keys.sorted() == ["a", "b"])
    }

    @Test func aFailedChangeFetchKeepsRecordsAndTheCheckpoint() async throws {
        let cache = try MeasurementCache()
        _ = await SyncCoordinator(client: client(serving(Self.history)), cache: cache)
            .sync(request(at: now))
        let transport = serving { _ in throw GitHubError.offline }
        let report = await SyncCoordinator(client: client(transport), cache: cache)
            .sync(request(at: now.addingTimeInterval(15 * 60)))
        #expect(report.pullRequestSyncMode == .changesOnly)
        #expect(report.pullRequestError == .offline)
        #expect(try cache.pullRequests().map(\.id) == ["old", "recent"])
        let state = try cache.syncState()
        #expect(state.pullRequestCheckpoints == ["a": now])
        #expect(!state.pullRequestResultsIncomplete)
    }

    @Test func aFailedOlderWindowKeepsRecentPRsWithNarrowCoverage() async throws {
        let cache = try MeasurementCache()
        let transport = serving { query in
            if query.contains("created:2025-09-15T17:00:00Z..") {
                throw GitHubError.http(status: 502)
            }
            return Self.history(query)
        }
        let report = await SyncCoordinator(client: client(transport), cache: cache)
            .sync(request(at: now))
        #expect(report.pullRequestError == .http(status: 502))
        #expect(try cache.pullRequests().map(\.id) == ["recent"])
        let state = try cache.syncState()
        #expect(state.pullRequestCoverageStart == day("2026-09-16").start(in: bangkok))
        #expect(state.lastFullPullRequestSync == nil)
        #expect(state.pullRequestCheckpoints.isEmpty)
        // The next sync starts over with a full window.
        let retry = await SyncCoordinator(client: client(serving(Self.history)), cache: cache)
            .sync(request(at: now.addingTimeInterval(60)))
        #expect(retry.pullRequestSyncMode == .fullReconcile)
        #expect(try cache.pullRequests().map(\.id) == ["old", "recent"])
    }
}

@Suite("Token-carrying requests leave nothing behind")
struct TransportHygieneTests {
    @Test func theDefaultSessionHasNoCacheCookiesOrCredentialStore() {
        let configuration = URLSessionTransport.makeSession().configuration
        #expect(configuration.urlCache == nil)
        #expect(configuration.httpCookieStorage == nil)
        #expect(configuration.httpShouldSetCookies == false)
        #expect(configuration.urlCredentialStorage == nil)
        #expect(configuration.requestCachePolicy == .reloadIgnoringLocalAndRemoteCacheData)
    }

    @Test func authorizedRequestsIgnoreEveryCache() async throws {
        let transport = FakeTransport { _ in
            (200, [:], json(["data": ["viewer": ["login": "octocat"]]]))
        }
        let client = GitHubClient(transport: transport)
        _ = try await client.viewerLogin(token: "ghp_test")
        let request = try #require(transport.requests.first)
        #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer ghp_test")
        #expect(request.cachePolicy == .reloadIgnoringLocalAndRemoteCacheData)
    }
}
