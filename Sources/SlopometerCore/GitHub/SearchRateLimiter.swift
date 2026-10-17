import Foundation

/// Keeps search requests under GitHub's limit for authenticated search, which every
/// token of the same account shares. Requests go out immediately while budget remains;
/// the limiter waits only when the rolling window is full or GitHub reports no budget.
public actor SearchRateLimiter {
    /// GitHub allows 30 per minute; two are left spare for clock skew between windows.
    public static let requestsPerWindow = 28
    public static let window: TimeInterval = 60

    private let now: @Sendable () -> Date
    private let sleep: @Sendable (TimeInterval) async throws -> Void
    private var sent: [Date] = []
    private var blockedUntil: Date?

    public init(
        now: @escaping @Sendable () -> Date = { Date() },
        sleep: @escaping @Sendable (TimeInterval) async throws -> Void = {
            try await Task.sleep(for: .seconds($0))
        }
    ) {
        self.now = now
        self.sleep = sleep
    }

    /// Suspends until a search request may be sent, then counts it.
    public func acquire() async throws {
        while true {
            let current = now()
            sent.removeAll { current.timeIntervalSince($0) >= Self.window }
            let wait: TimeInterval
            if let blockedUntil, blockedUntil > current {
                wait = blockedUntil.timeIntervalSince(current)
            } else if sent.count >= Self.requestsPerWindow, let oldest = sent.first {
                wait = Self.window - current.timeIntervalSince(oldest)
            } else {
                sent.append(current)
                return
            }
            try await sleep(max(wait, 0.05))
        }
    }

    /// Learns GitHub's own count from a search response, so an exhausted budget waits
    /// until GitHub's reset instead of guessing.
    public func observe(remaining: Int?, resetAt: Date?) {
        if remaining == 0, let resetAt {
            blockedUntil = resetAt
        } else if remaining ?? 1 > 0 {
            blockedUntil = nil
        }
    }

    /// The number of requests counted in the current window.
    public var requestsInWindow: Int {
        let current = now()
        return sent.filter { current.timeIntervalSince($0) < Self.window }.count
    }
}
