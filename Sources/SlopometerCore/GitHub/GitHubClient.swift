import Foundation

public enum GitHubError: Error, Equatable, Sendable {
    case invalidLogin
    case notFound
    case unauthorized
    case tokenOwnerMismatch(expected: String, actual: String)
    case rateLimited(resetAt: Date?)
    case http(status: Int)
    case malformedResponse
    case offline

    public var message: String {
        switch self {
        case .invalidLogin: "That is not a valid GitHub username."
        case .notFound: "GitHub could not find that account."
        case .unauthorized: "GitHub rejected the token. Check it has not expired or been revoked."
        case .tokenOwnerMismatch(let expected, let actual):
            "The token belongs to \(actual), not \(expected). PR data is not counted."
        case .rateLimited(let resetAt):
            if let resetAt {
                "GitHub rate limit reached. Retrying after \(resetAt.formatted(date: .omitted, time: .shortened))."
            } else {
                "GitHub rate limit reached. Retrying later."
            }
        case .http(let status): "GitHub returned HTTP \(status)."
        case .malformedResponse: "GitHub returned data Slopometer could not read."
        case .offline: "GitHub is unreachable. Showing cached data."
        }
    }
}

public protocol HTTPTransport: Sendable {
    func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse)
}

public struct URLSessionTransport: HTTPTransport {
    private let session: URLSession

    public init(session: URLSession = .shared) {
        self.session = session
    }

    public func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        do {
            let (data, response) = try await session.data(for: request)
            guard let http = response as? HTTPURLResponse else {
                throw GitHubError.malformedResponse
            }
            return (data, http)
        } catch let error as URLError {
            throw error.code == .cancelled ? error : GitHubError.offline
        }
    }
}

public struct PullRequestFetch: Equatable, Sendable {
    public let records: [PullRequestRecord]
    /// GitHub reported incomplete search results for at least one window.
    public let isIncomplete: Bool
}

public struct GitHubClient: Sendable {
    public static let searchResultCap = 1000
    private static let pageSize = 100

    private let transport: HTTPTransport
    /// Awaited before every search request to stay under the search rate limit.
    private let searchPause: @Sendable () async throws -> Void

    public init(
        transport: HTTPTransport = URLSessionTransport(),
        searchPause: @escaping @Sendable () async throws -> Void = {
            try await Task.sleep(for: .milliseconds(2100))
        }
    ) {
        self.transport = transport
        self.searchPause = searchPause
    }

    public static func isValidLogin(_ login: String) -> Bool {
        login.range(of: #"^[A-Za-z0-9](?:[A-Za-z0-9-]{0,38})$"#, options: .regularExpression)
            != nil
    }

    // MARK: Username-only tier

    public func profileCalendar(login: String) async throws -> [CalendarDay: Int] {
        guard Self.isValidLogin(login) else { throw GitHubError.invalidLogin }
        var request = URLRequest(url: URL(string: "https://github.com/users/\(login)/contributions")!)
        request.setValue("Slopometer", forHTTPHeaderField: "User-Agent")
        request.setValue("text/html", forHTTPHeaderField: "Accept")
        let data = try await send(request)
        guard let html = String(data: data, encoding: .utf8) else {
            throw GitHubError.malformedResponse
        }
        return try ProfileCalendarParser.parse(html)
    }

    // MARK: Token tier

    public func viewerLogin(token: String) async throws -> String {
        let response: ViewerData = try await graphQL(
            token: token, query: "query { viewer { login } }", variables: [:])
        return response.viewer.login
    }

    /// Official calendar for `login`, requested in spans GitHub accepts (at most one year).
    public func contributionCalendar(login: String, token: String, from: Date, to: Date)
        async throws -> [CalendarDay: Int]
    {
        let query = """
            query($login: String!, $from: DateTime!, $to: DateTime!) {
              user(login: $login) {
                contributionsCollection(from: $from, to: $to) {
                  contributionCalendar { weeks { contributionDays { date contributionCount } } }
                }
              }
            }
            """
        var counts: [CalendarDay: Int] = [:]
        var spanStart = from
        while spanStart < to {
            let spanEnd = min(to, spanStart.addingTimeInterval(364 * 86_400))
            let response: CalendarData = try await graphQL(
                token: token, query: query,
                variables: [
                    "login": login, "from": Self.iso(spanStart), "to": Self.iso(spanEnd),
                ])
            guard let user = response.user else { throw GitHubError.notFound }
            for week in user.contributionsCollection.contributionCalendar.weeks {
                for day in week.contributionDays {
                    guard let calendarDay = CalendarDay(day.date) else {
                        throw GitHubError.malformedResponse
                    }
                    counts[calendarDay] = day.contributionCount
                }
            }
            spanStart = spanEnd
        }
        return counts
    }

    /// PRs authored by `login` that were created or merged in `[from, to]`, deduplicated.
    public func authoredPullRequests(login: String, token: String, from: Date, to: Date)
        async throws -> PullRequestFetch
    {
        guard Self.isValidLogin(login) else { throw GitHubError.invalidLogin }
        var byID: [String: PullRequestRecord] = [:]
        var incomplete = false
        for qualifier in ["created", "merged"] {
            let result = try await search(
                login: login, token: token, qualifier: qualifier, from: from, to: to)
            incomplete = incomplete || result.isIncomplete
            for record in result.records { byID[record.id] = record }
        }
        return PullRequestFetch(
            records: byID.values.sorted { $0.createdAt < $1.createdAt }, isIncomplete: incomplete)
    }

    /// Splits the window until each query fits under GitHub's search result cap.
    private func search(
        login: String, token: String, qualifier: String, from: Date, to: Date
    ) async throws -> PullRequestFetch {
        let query = "author:\(login) type:pr \(qualifier):\(Self.iso(from))..\(Self.iso(to))"
        let first = try await searchPage(query: query, token: token, page: 1)
        if first.total_count > Self.searchResultCap, to.timeIntervalSince(from) > 3600 {
            let middle = from.addingTimeInterval(to.timeIntervalSince(from) / 2)
            let early = try await search(
                login: login, token: token, qualifier: qualifier, from: from, to: middle)
            let late = try await search(
                login: login, token: token, qualifier: qualifier,
                from: middle.addingTimeInterval(1), to: to)
            return PullRequestFetch(
                records: early.records + late.records,
                isIncomplete: early.isIncomplete || late.isIncomplete)
        }

        var items = first.items
        var incomplete = first.incomplete_results || first.total_count > Self.searchResultCap
        let reachable = min(first.total_count, Self.searchResultCap)
        let pages = (reachable + Self.pageSize - 1) / Self.pageSize
        if pages > 1 {
            for page in 2...pages {
                let next = try await searchPage(query: query, token: token, page: page)
                incomplete = incomplete || next.incomplete_results
                items += next.items
            }
        }
        return PullRequestFetch(records: try items.map { try $0.record() }, isIncomplete: incomplete)
    }

    private func searchPage(query: String, token: String, page: Int) async throws
        -> SearchResponse
    {
        try await searchPause()
        var components = URLComponents(string: "https://api.github.com/search/issues")!
        components.queryItems = [
            URLQueryItem(name: "q", value: query),
            URLQueryItem(name: "per_page", value: String(Self.pageSize)),
            URLQueryItem(name: "page", value: String(page)),
            URLQueryItem(name: "sort", value: "created"),
            URLQueryItem(name: "order", value: "asc"),
        ]
        var request = URLRequest(url: components.url!)
        Self.authorize(&request, token: token)
        return try Self.decode(SearchResponse.self, from: try await send(request))
    }

    // MARK: Transport

    private func graphQL<Payload: Decodable>(
        token: String, query: String, variables: [String: String]
    ) async throws -> Payload {
        var request = URLRequest(url: URL(string: "https://api.github.com/graphql")!)
        request.httpMethod = "POST"
        Self.authorize(&request, token: token)
        request.httpBody = try JSONSerialization.data(withJSONObject: [
            "query": query, "variables": variables,
        ])
        let response = try Self.decode(GraphQLResponse<Payload>.self, from: try await send(request))
        if let errors = response.errors, !errors.isEmpty {
            if errors.contains(where: { $0.type == "NOT_FOUND" }) { throw GitHubError.notFound }
            if errors.contains(where: { $0.type == "RATE_LIMITED" }) {
                throw GitHubError.rateLimited(resetAt: nil)
            }
            throw GitHubError.malformedResponse
        }
        guard let data = response.data else { throw GitHubError.malformedResponse }
        return data
    }

    private func send(_ request: URLRequest) async throws -> Data {
        let (data, response) = try await transport.send(request)
        switch response.statusCode {
        case 200..<300:
            return data
        case 401:
            throw GitHubError.unauthorized
        case 403, 429:
            let retryAfter = response.value(forHTTPHeaderField: "Retry-After").flatMap(Double.init)
            let reset = response.value(forHTTPHeaderField: "X-RateLimit-Reset").flatMap(Double.init)
            let remaining = response.value(forHTTPHeaderField: "X-RateLimit-Remaining")
            if let retryAfter {
                throw GitHubError.rateLimited(resetAt: Date().addingTimeInterval(retryAfter))
            }
            if remaining == "0" || response.statusCode == 429 {
                throw GitHubError.rateLimited(
                    resetAt: reset.map { Date(timeIntervalSince1970: $0) })
            }
            throw GitHubError.http(status: response.statusCode)
        case 404, 422:
            throw GitHubError.notFound
        default:
            throw GitHubError.http(status: response.statusCode)
        }
    }

    private static func authorize(_ request: inout URLRequest, token: String) {
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("2022-11-28", forHTTPHeaderField: "X-GitHub-Api-Version")
        request.setValue("Slopometer", forHTTPHeaderField: "User-Agent")
    }

    private static func decode<T: Decodable>(_ type: T.Type, from data: Data) throws -> T {
        do {
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            return try decoder.decode(type, from: data)
        } catch {
            throw GitHubError.malformedResponse
        }
    }

    static func iso(_ date: Date) -> String {
        date.formatted(.iso8601)
    }
}

// MARK: Wire formats

struct GraphQLResponse<Payload: Decodable>: Decodable {
    struct Failure: Decodable {
        let type: String?
        let message: String
    }
    let data: Payload?
    let errors: [Failure]?
}

struct ViewerData: Decodable {
    struct Viewer: Decodable { let login: String }
    let viewer: Viewer
}

struct CalendarData: Decodable {
    struct User: Decodable { let contributionsCollection: Collection }
    struct Collection: Decodable { let contributionCalendar: Calendar }
    struct Calendar: Decodable { let weeks: [Week] }
    struct Week: Decodable { let contributionDays: [Day] }
    struct Day: Decodable {
        let date: String
        let contributionCount: Int
    }
    let user: User?
}

// swift-format-ignore: AlwaysUseLowerCamelCase
struct SearchResponse: Decodable {
    struct Item: Decodable {
        struct Link: Decodable { let merged_at: Date? }
        let node_id: String
        let number: Int
        let title: String
        let html_url: String
        let repository_url: String
        let draft: Bool?
        let created_at: Date
        let pull_request: Link?

        func record() throws -> PullRequestRecord {
            let parts = repository_url.split(separator: "/").suffix(2)
            guard parts.count == 2, pull_request != nil else { throw GitHubError.malformedResponse }
            return PullRequestRecord(
                id: node_id, number: number, title: title, repository: parts.joined(separator: "/"),
                url: html_url, isDraft: draft ?? false, createdAt: created_at,
                mergedAt: pull_request?.merged_at)
        }
    }
    let total_count: Int
    let incomplete_results: Bool
    let items: [Item]
}
