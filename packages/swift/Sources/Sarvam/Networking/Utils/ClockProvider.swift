import Foundation

/// Provider for time and delay primitives, injectable for deterministic unit testing.
public protocol ClockProvider: Sendable {
    /// Returns current Unix epoch timestamp in milliseconds.
    func nowEpochMs() -> Int64

    /// Suspends execution for the specified duration in milliseconds.
    func sleep(ms: Int64) async throws
}

/// Standard system wall clock and task sleep implementation.
public struct SystemClockProvider: ClockProvider {
    public init() {}

    public func nowEpochMs() -> Int64 {
        Int64(Date().timeIntervalSince1970 * 1000)
    }

    public func sleep(ms: Int64) async throws {
        guard ms > 0 else { return }
        try await Task.sleep(nanoseconds: UInt64(ms) * 1_000_000)
    }
}
