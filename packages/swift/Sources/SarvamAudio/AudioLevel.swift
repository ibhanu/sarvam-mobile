import Foundation

/// Audio level metrics for UI visualizers, waveform meters, and VAD analysis.
public struct AudioLevel: Sendable, Equatable {
    /// Root mean square amplitude normalized to 0.0 - 1.0.
    public let rms: Double

    /// Peak amplitude normalized to 0.0 - 1.0.
    public let peak: Double

    /// Decibels relative to full scale (-100.0 dBFS to 0.0 dBFS).
    public let dbFs: Double

    public init(rms: Double, peak: Double, dbFs: Double) {
        self.rms = rms
        self.peak = peak
        self.dbFs = dbFs
    }
}
