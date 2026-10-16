import Foundation

/// Provider for pseudo-random numbers, injectable for deterministic unit testing.
public protocol RandomProvider: Sendable {
    /// Returns a pseudo-random floating point number in `0.0 ..< 1.0`.
    func nextDouble() -> Double

    /// Returns a pseudo-random integer in the given closed range.
    func nextInt(in range: ClosedRange<Int64>) -> Int64
}

/// Standard system random generator using Swift standard library.
public struct SystemRandomProvider: RandomProvider {
    public init() {}

    public func nextDouble() -> Double {
        Double.random(in: 0.0..<1.0)
    }

    public func nextInt(in range: ClosedRange<Int64>) -> Int64 {
        Int64.random(in: range)
    }
}
