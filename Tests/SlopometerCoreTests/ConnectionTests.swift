import Foundation
import Testing

@testable import SlopometerCore

@Suite("Account and token identity")
struct ConnectionTests {
    let now = date("2026-10-16T05:00:00Z")

    /// GitHub as seen through tokens owned by different people. `rejected` answers 401.
    func ownersTransport(_ owners: [String: String], rejected: Set<String> = []) -> FakeTransport {
        FakeTransport { request in
            let token = request.value(forHTTPHeaderField: "Authorization")?
                .replacingOccurrences(of: "Bearer ", with: "")
            if let token, rejected.contains(token) { return (401, [:], Data()) }
            if request.url?.path == "/graphql" {
                let body = String(data: request.httpBody ?? Data(), encoding: .utf8) ?? ""
                if body.contains("viewer") {
                    return (200, [:], json(["data": ["viewer": ["login": owners[token ?? ""]!]]]))
                }
                let calendar = ["contributionCalendar": ["weeks": [] as [Any]]]
                return (200, [:], json(["data": ["user": ["contributionsCollection": calendar]]]))
            }
            let items = [searchItem("pr-\(token ?? "")", created: "2026-10-15T01:00:00Z")]
            return (200, [:], searchPage(total: items.count, items: items))
        }
    }

    @Test func accountIsTheEarliestKnownTokenOwnerElseTheUsername() {
        #expect(AccountResolver.account(owners: [], fallback: "typed") == "typed")
        #expect(AccountResolver.account(owners: [nil, nil], fallback: "typed") == "typed")
        #expect(AccountResolver.account(owners: [nil, "b", "c"], fallback: "typed") == "b")
        #expect(AccountResolver.account(owners: [], fallback: "") == "")
    }

    @Test func tokensDecideTheAccountEvenWhenAnotherUsernameWasTyped() async throws {
        let cache = try MeasurementCache()
        try cache.reset(for: "ckbk123")
        let report = await SyncCoordinator(
            client: client(ownersTransport(["t456": "ckbk456"])), cache: cache
        ).sync(
            SyncRequest(
                login: "ckbk123", tokens: [AccessToken(id: "a", value: "t456")],
                timeZone: bangkok, now: now))
        #expect(report.login == "ckbk456")
        #expect(report.verifiedTokenIDs == ["a"])
        #expect(report.tokenOwners == ["a": "ckbk456"])
        #expect(report.tokenErrors.isEmpty)
        #expect(try cache.syncState().login == "ckbk456")
        #expect(try cache.pullRequests().map(\.id) == ["pr-t456"])
    }

    @Test func tokensOfOtherUsersAreKeptButNotCounted() async throws {
        let cache = try MeasurementCache()
        let transport = ownersTransport(["first": "ckbk456", "second": "someone"])
        let report = await SyncCoordinator(client: client(transport), cache: cache).sync(
            SyncRequest(
                login: "",
                tokens: [
                    AccessToken(id: "a", value: "first"), AccessToken(id: "b", value: "second"),
                ], timeZone: bangkok, now: now))
        #expect(report.login == "ckbk456")
        #expect(report.verifiedTokenIDs == ["a"])
        #expect(
            report.tokenErrors == ["b": .tokenOwnerMismatch(expected: "ckbk456", actual: "someone")]
        )
        #expect(try cache.pullRequests().map(\.id) == ["pr-first"])
        #expect(try cache.syncState().pullRequestResultsIncomplete)
    }

    @Test func aRejectedFirstTokenLeavesTheAccountToTheNextOwner() async throws {
        let cache = try MeasurementCache()
        let transport = ownersTransport(["second": "ckbk456"], rejected: ["first"])
        let report = await SyncCoordinator(client: client(transport), cache: cache).sync(
            SyncRequest(
                login: "typed",
                tokens: [
                    AccessToken(id: "a", value: "first"), AccessToken(id: "b", value: "second"),
                ], timeZone: bangkok, now: now))
        #expect(report.login == "ckbk456")
        #expect(report.tokenErrors == ["a": .unauthorized])
        #expect(report.checkedTokenIDs == ["a", "b"])
    }

    func report(login: String, checked: Set<String>, verified: Set<String> = []) -> SyncReport {
        var report = SyncReport()
        report.login = login
        report.checkedTokenIDs = checked
        report.verifiedTokenIDs = verified
        report.tokenVerified = !verified.isEmpty
        for id in verified { report.tokenOwners[id] = login }
        return report
    }

    @Test func aCheckForAnotherAccountNeverReadsAsVerified() {
        // Verified for ckbk456, then the account became ckbk123 (bug: "Verified for @ckbk123").
        let stale = report(login: "ckbk456", checked: ["a"], verified: ["a"])
        #expect(
            TokenState.resolve(tokenID: "a", savedOwner: nil, account: "ckbk123", report: stale)
                == .checking)
        #expect(
            TokenState.resolve(
                tokenID: "a", savedOwner: "ckbk456", account: "ckbk123", report: stale)
                == .otherOwner("ckbk456"))
    }

    @Test func aTokenAddedAfterTheLastCheckIsCheckingUntilCovered() {
        let earlier = report(login: "me", checked: ["a"], verified: ["a"])
        #expect(
            TokenState.resolve(tokenID: "a", savedOwner: nil, account: "me", report: earlier)
                == .counted(owner: "me"))
        let added = TokenState.resolve(
            tokenID: "b", savedOwner: nil, account: "me", report: earlier)
        #expect(added == .checking)
        #expect(!added.counts)
    }

    @Test func rememberedOwnersCountWithoutAReportAndFailuresAreNamed() {
        #expect(
            TokenState.resolve(tokenID: "a", savedOwner: "Me", account: "me", report: nil).counts)
        var offline = report(login: "me", checked: ["a", "b"])
        offline.tokenErrors = ["a": .offline, "b": .unauthorized]
        let a = TokenState.resolve(tokenID: "a", savedOwner: "me", account: "me", report: offline)
        #expect(a == .unavailable(GitHubError.offline.message, cached: true))
        #expect(a.counts)
        let b = TokenState.resolve(tokenID: "b", savedOwner: "me", account: "me", report: offline)
        #expect(b == .rejected)
        #expect(b.summary == "Rejected by GitHub, not counted")
        #expect(TokenState.otherOwner("x").summary == "Belongs to @x, not counted")
    }

    @Test func connectionWordingCountsOnlyCountedTokens() {
        #expect(
            ConnectionLabel.describe(fineGrained: 0, classic: 0) == "Public profile (username only)"
        )
        #expect(
            ConnectionLabel.describe(fineGrained: 0, classic: 0, checking: 1) == "Checking tokens…")
        #expect(ConnectionLabel.describe(fineGrained: 2, classic: 0) == "Fine-grained tokens (2)")
        #expect(
            ConnectionLabel.describe(fineGrained: 1, classic: 1)
                == "Fine-grained + classic tokens (2)")
        #expect(ConnectionLabel.describe(fineGrained: 0, classic: 1) == "Classic tokens (1)")
        #expect(ConnectionLabel.source(fineGrained: 2, classic: 0) == "your fine-grained tokens")
    }

    @Test func refreshesDuringASyncRunOnceAfterIt() {
        var gate = RefreshGate()
        let first = gate.request()
        let duringSyncA = gate.request()  // Token added during the sync: queued, not dropped.
        let duringSyncB = gate.request()  // Username changed too: still one queued run.
        #expect(first && !duringSyncA && !duringSyncB)
        #expect(gate.hasPending)
        let runsQueued = gate.finish()  // The queued run starts right away.
        #expect(runsQueued && gate.isRunning)
        let runsAgain = gate.finish()
        #expect(!runsAgain && !gate.isRunning)
        let next = gate.request()
        #expect(next)
    }

    @Test func anotherAccountsCacheIsNeverShown() throws {
        let cache = try MeasurementCache()
        try cache.reset(for: "ckbk456")
        try cache.replaceCalendar([day("2026-10-16"): 9], source: .graphQL, at: now)
        try cache.replacePullRequests(
            [pr("a", created: "2026-10-16T01:00:00Z", merged: "2026-10-16T02:00:00Z")],
            coveringFrom: date("2025-09-01T00:00:00Z"), incomplete: false, at: now)
        var settings = DashboardSettings()
        settings.login = "ckbk123"
        settings.metric = .prsMerged
        settings.timeZoneID = "Asia/Bangkok"
        settings.goal = Goal(metric: .prsMerged, target: 20)
        let snapshot = try SnapshotBuilder.build(
            settings: settings, cache: cache, tokenUsable: true, problems: [], now: now)
        #expect(snapshot.login == "ckbk123")
        #expect(snapshot.quota == nil)
        #expect(snapshot.todayCount == nil)
        #expect(snapshot.points.allSatisfy { $0.count == nil })
        #expect(snapshot.widgets.allSatisfy { $0.points.allSatisfy { $0.count == nil } })
        #expect(snapshot.lastSuccessfulSync == nil)
        #expect(snapshot.notices.first == SnapshotBuilder.notSyncedNotice(for: "ckbk123"))
        #expect(try !cache.holds("ckbk123"))
        #expect(try cache.holds("CKBK456"))
    }
}
