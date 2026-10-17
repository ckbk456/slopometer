import Foundation

/// Which GitHub account the app measures, and how each saved token relates to it.
///
/// With tokens, the account is the owner (GraphQL `viewer.login`) of the earliest-added
/// token whose owner is known. A fine-grained token whose resource owner is an
/// organization is still owned by the user who created it, so it agrees. Tokens owned by
/// anyone else are kept but not counted. Without a token owner, the typed username is
/// the account.
public enum AccountResolver {
    /// - Parameters:
    ///   - owners: each saved token's owner in the order the tokens were added; nil when
    ///     not known (not checked yet, rejected, or unreachable).
    ///   - fallback: the typed username, used when no token owner is known.
    public static func account(owners: [String?], fallback: String) -> String {
        owners.lazy.compactMap { $0 }.first { !$0.isEmpty } ?? fallback
    }

    public static func same(_ a: String, _ b: String) -> Bool {
        a.lowercased() == b.lowercased()
    }
}

/// One saved token's standing for the current account.
public enum TokenState: Equatable, Sendable {
    /// No check for this account has covered the token yet and its owner is unknown.
    case checking
    /// Owned by the account; its PRs are counted.
    case counted(owner: String)
    /// Owned by someone else; kept but not counted.
    case otherOwner(String)
    /// GitHub rejected it (expired or revoked).
    case rejected
    /// The last check could not reach a verdict (offline, rate limit). Cached data from a
    /// token already known to belong to the account stays usable.
    case unavailable(String, cached: Bool)

    /// Whether the token feeds the PR data being shown.
    public var counts: Bool {
        switch self {
        case .counted: true
        case .unavailable(_, let cached): cached
        case .checking, .otherOwner, .rejected: false
        }
    }

    public var owner: String? {
        switch self {
        case .counted(let owner), .otherOwner(let owner): owner
        default: nil
        }
    }

    /// One line for Settings and the badge popover. Never includes the token value.
    public var summary: String {
        switch self {
        case .checking: "Checking…"
        case .counted(let owner): "Owned by @\(owner), counted"
        case .otherOwner(let owner): "Belongs to @\(owner), not counted"
        case .rejected: "Rejected by GitHub, not counted"
        case .unavailable(let message, _): "Not checked: \(message)"
        }
    }

    public var isProblem: Bool {
        switch self {
        case .otherOwner, .rejected, .unavailable: true
        case .checking, .counted: false
        }
    }

    /// Uses the last sync report only when it was made for `account` and covered this
    /// token, so a check made for a previous account or before the token was added never
    /// reads as verified. Otherwise falls back to the owner remembered from earlier checks.
    public static func resolve(
        tokenID: String, savedOwner: String?, account: String, report: SyncReport?
    ) -> TokenState {
        if let report, !account.isEmpty, AccountResolver.same(report.login, account),
            report.checkedTokenIDs.contains(tokenID)
        {
            switch report.tokenErrors[tokenID] {
            case .tokenOwnerMismatch(_, let actual)?: return .otherOwner(actual)
            case .unauthorized?: return .rejected
            case let error?:
                let cached = savedOwner.map { AccountResolver.same($0, account) } ?? false
                return .unavailable(error.message, cached: cached)
            case nil:
                if report.verifiedTokenIDs.contains(tokenID) {
                    return .counted(owner: report.tokenOwners[tokenID] ?? account)
                }
            }
        }
        guard let savedOwner, !account.isEmpty else { return .checking }
        return AccountResolver.same(savedOwner, account)
            ? .counted(owner: savedOwner) : .otherOwner(savedOwner)
    }
}

/// The plain name of the connection in use, shared by the Activity badge, Settings, and
/// the menu bar panel. Counts only tokens that are counted.
public enum ConnectionLabel {
    public static func describe(
        fineGrained: Int, classic: Int, checking: Int = 0
    ) -> String {
        let total = fineGrained + classic
        if total == 0 {
            return checking > 0 ? "Checking tokens…" : "Public profile (username only)"
        }
        if classic == 0 { return "Fine-grained tokens (\(total))" }
        if fineGrained == 0 { return "Classic tokens (\(total))" }
        return "Fine-grained + classic tokens (\(total))"
    }

    /// Where the account came from, for the disabled username field.
    public static func source(fineGrained: Int, classic: Int) -> String {
        if classic == 0 { return "your fine-grained tokens" }
        if fineGrained == 0 { return "your classic tokens" }
        return "your tokens"
    }
}

/// Coalesces refresh requests: a request made while a sync runs is not dropped but runs
/// once, right after the current sync, with whatever settings and tokens exist then.
public struct RefreshGate: Equatable, Sendable {
    public private(set) var isRunning = false
    public private(set) var hasPending = false

    public init() {}

    /// True when the caller should start a sync now; otherwise the request is queued.
    public mutating func request() -> Bool {
        if isRunning {
            hasPending = true
            return false
        }
        isRunning = true
        return true
    }

    /// Call when a sync ends. True when a queued request should run now (still running).
    public mutating func finish() -> Bool {
        if hasPending {
            hasPending = false
            return true
        }
        isRunning = false
        return false
    }
}
