import Foundation
@testable import Sarvam

public final class MockClockProvider: ClockProvider, @unchecked Sendable {
    public var currentEpochMs: Int64
    public private(set) var sleepCalls: [Int64] = []
    private let lock = NSLock()

    public init(initialEpochMs: Int64 = 1_700_000_000_000) {
        self.currentEpochMs = initialEpochMs
    }

    public func nowEpochMs() -> Int64 {
        lock.withLock { currentEpochMs }
    }

    public func advance(ms: Int64) {
        lock.withLock { currentEpochMs += ms }
    }

    public func sleep(ms: Int64) async throws {
        lock.withLock {
            sleepCalls.append(ms)
            currentEpochMs += ms
        }
    }
}

public final class MockRandomProvider: RandomProvider, @unchecked Sendable {
    public var fixedDouble: Double
    public var fixedInt: Int64?

    public init(fixedDouble: Double = 0.5, fixedInt: Int64? = nil) {
        self.fixedDouble = fixedDouble
        self.fixedInt = fixedInt
    }

    public func nextDouble() -> Double {
        fixedDouble
    }

    public func nextInt(in range: ClosedRange<Int64>) -> Int64 {
        if let fi = fixedInt {
            return min(max(fi, range.lowerBound), range.upperBound)
        }
        return range.lowerBound + Int64(Double(range.upperBound - range.lowerBound) * fixedDouble)
    }
}
