import Foundation

/// Polling configuration options for long-running asynchronous jobs.
public struct PollingOptions: Sendable, Equatable {
    public var pollInterval: TimeInterval
    public var timeoutInterval: TimeInterval

    public init(pollInterval: TimeInterval = 2.0, timeoutInterval: TimeInterval = 300.0) {
        self.pollInterval = pollInterval
        self.timeoutInterval = timeoutInterval
    }
}

/// Generic, cancellable polling helper respecting Swift structured concurrency.
public enum JobPoller {
    /// Repeatedly checks job status until terminal status or timeout is reached.
    ///
    /// Respects structured concurrency cancellation via `Task.checkCancellation()`.
    ///
    /// - Parameters:
    ///   - pollInterval: Seconds between consecutive poll attempts.
    ///   - timeoutInterval: Maximum duration in seconds before timing out.
    ///   - clock: Injectable `ClockProvider` for deterministic testing.
    ///   - check: Closure returning a tuple `(isComplete: Bool, value: T)`.
    /// - Returns: The final value `T` upon successful completion.
    /// - Throws: `CancellationError` if the task was cancelled, `SarvamError.timeoutError` if timeout was exceeded, or underlying errors.
    public static func waitUntilComplete<T: Sendable>(
        pollInterval: TimeInterval = 2.0,
        timeoutInterval: TimeInterval = 300.0,
        clock: ClockProvider = SystemClockProvider(),
        check: @Sendable () async throws -> (isComplete: Bool, value: T)
    ) async throws -> T {
        let startTimeMs = clock.nowEpochMs()
        let timeoutMs = Int64(timeoutInterval * 1000)
        let pollIntervalMs = max(Int64(pollInterval * 1000), 1)

        while true {
            try Task.checkCancellation()
            let (isComplete, value) = try await check()
            if isComplete {
                return value
            }

            try Task.checkCancellation()
            let elapsedMs = clock.nowEpochMs() - startTimeMs
            if elapsedMs >= timeoutMs {
                throw SarvamError.timeoutError(
                    phase: .total,
                    message: "Job polling timed out after \(timeoutInterval) seconds"
                )
            }

            try await clock.sleep(ms: pollIntervalMs)
        }
    }
}
