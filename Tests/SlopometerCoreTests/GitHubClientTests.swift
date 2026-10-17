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

func client(_ transport: FakeTransport) -> GitHubClient {
    GitHubClient(transport: transport, searchPause: {})
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
            if query.contains("created:") {
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
        #expect(transport.searchQueries.count == 4)
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
