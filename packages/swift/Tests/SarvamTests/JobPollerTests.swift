import Foundation
import Testing
@testable import Sarvam

@Suite("JobPoller Structured Concurrency Tests")
struct JobPollerTests {
    private final class SafeCounter: @unchecked Sendable {
        private var _val: Int = 0
        private let lock = NSLock()

        func increment() -> Int {
            lock.withLock {
                _val += 1
                return _val
            }
        }

        var value: Int {
            lock.withLock { _val }
        }
    }

    @Test("Polling successfully completes when isComplete returns true")
    func testSuccessfulPolling() async throws {
        let mockClock = MockClockProvider(initialEpochMs: 1_000_000)
        let counter = SafeCounter()

        let result: String = try await JobPoller.waitUntilComplete(
            pollInterval: 1.0,
            timeoutInterval: 10.0,
            clock: mockClock
        ) {
            let attempts = counter.increment()
            if attempts >= 3 {
                return (true, "FINISHED")
            }
            return (false, "PENDING")
        }

        #expect(result == "FINISHED")
        #expect(counter.value == 3)
        #expect(mockClock.sleepCalls == [1000, 1000])
    }

    @Test("Polling throws timeoutError when elapsed time exceeds timeoutInterval")
    func testTimeout() async throws {
        let mockClock = MockClockProvider(initialEpochMs: 1_000_000)

        do {
            let _: String = try await JobPoller.waitUntilComplete(
                pollInterval: 2.0,
                timeoutInterval: 5.0,
                clock: mockClock
            ) {
                return (false, "STILL_RUNNING")
            }
            Issue.record("Expected timeoutError but succeeded")
        } catch let SarvamError.timeoutError(phase, message) {
            #expect(phase == .total)
            #expect(message.contains("timed out"))
        } catch {
            Issue.record("Unexpected error: \(error)")
        }
    }

    @Test("Structured concurrency cancellation stops polling immediately")
    func testCancellation() async throws {
        let mockClock = MockClockProvider(initialEpochMs: 1_000_000)

        let task = Task<String, Error> {
            try await JobPoller.waitUntilComplete(
                pollInterval: 1.0,
                timeoutInterval: 100.0,
                clock: mockClock
            ) {
                return (false, "RUNNING")
            }
        }

        // Cancel the task
        task.cancel()

        do {
            _ = try await task.value
            Issue.record("Expected CancellationError but got value")
        } catch is CancellationError {
            // Expected
        } catch {
            Issue.record("Expected CancellationError, got \(error)")
        }
    }
}
