import Foundation

/// PCM audio resampling and audio level metering utility.
///
/// Converts multi-rate (e.g. 48kHz, 44.1kHz) mono/stereo Float32 or Int16 audio
/// into 16kHz mono linear-16 PCM suitable for Sarvam speech APIs.
public enum PcmResampler {
    /// Target sample rate required by Sarvam Realtime STT (16 kHz).
    public static let targetSampleRate: Int = 16000

    /// Resamples little-endian PCM16 audio to 16kHz mono linear-16 `Data`.
    ///
    /// - Parameters:
    ///   - inputBytes: Raw little-endian Int16 bytes.
    ///   - inputSampleRate: Source sample rate (e.g., 48000, 44100, 16000).
    ///   - channelCount: Number of channels in the input (1 for mono, 2 for stereo).
    /// - Returns: Resampled 16kHz mono Int16 little-endian `Data`.
    public static func resamplePcm16(
        inputBytes: Data,
        inputSampleRate: Int,
        channelCount: Int = 1
    ) -> Data {
        guard !inputBytes.isEmpty else { return Data() }
        precondition(channelCount == 1 || channelCount == 2, "channelCount must be 1 (mono) or 2 (stereo)")

        let bytesPerFrame = 2 * channelCount
        let numFrames = inputBytes.count / bytesPerFrame
        guard numFrames > 0 else { return Data() }

        var monoSamples = [Int16](repeating: 0, count: numFrames)
        inputBytes.withUnsafeBytes { rawBuffer in
            for i in 0..<numFrames {
                let offset = i * bytesPerFrame
                let left = rawBuffer.load(fromByteOffset: offset, as: Int16.self).littleEndian
                if channelCount == 1 {
                    monoSamples[i] = left
                } else {
                    let right = rawBuffer.load(fromByteOffset: offset + 2, as: Int16.self).littleEndian
                    monoSamples[i] = Int16((Int32(left) + Int32(right)) / 2)
                }
            }
        }

        if inputSampleRate == targetSampleRate {
            var out = Data(count: numFrames * 2)
            out.withUnsafeMutableBytes { outBuf in
                for i in 0..<numFrames {
                    outBuf.storeBytes(of: monoSamples[i].littleEndian, toByteOffset: i * 2, as: Int16.self)
                }
            }
            return out
        }

        return resampleMonoSamples(monoSamples, inputSampleRate: inputSampleRate)
    }

    /// Resamples Float32 audio (range `[-1.0, 1.0]`, little-endian bytes) to 16kHz mono linear-16 `Data`.
    ///
    /// - Parameters:
    ///   - inputBytes: Raw Float32 bytes.
    ///   - inputSampleRate: Source sample rate.
    ///   - channelCount: Number of channels (1 for mono, 2 for stereo).
    /// - Returns: Resampled 16kHz mono Int16 little-endian `Data`.
    public static func resampleFloat32(
        inputBytes: Data,
        inputSampleRate: Int,
        channelCount: Int = 1
    ) -> Data {
        guard !inputBytes.isEmpty else { return Data() }
        precondition(channelCount == 1 || channelCount == 2, "channelCount must be 1 (mono) or 2 (stereo)")

        let bytesPerFrame = 4 * channelCount
        let numFrames = inputBytes.count / bytesPerFrame
        guard numFrames > 0 else { return Data() }

        var monoSamples = [Int16](repeating: 0, count: numFrames)
        inputBytes.withUnsafeBytes { rawBuffer in
            for i in 0..<numFrames {
                let offset = i * bytesPerFrame
                let leftBits = rawBuffer.load(fromByteOffset: offset, as: UInt32.self).littleEndian
                let leftFloat = Float(bitPattern: leftBits)

                let monoFloat: Float
                if channelCount == 1 {
                    monoFloat = leftFloat
                } else {
                    let rightBits = rawBuffer.load(fromByteOffset: offset + 4, as: UInt32.self).littleEndian
                    let rightFloat = Float(bitPattern: rightBits)
                    monoFloat = (leftFloat + rightFloat) / 2.0
                }

                let clamped = max(-1.0, min(1.0, monoFloat))
                let shortVal = Int16(clamping: Int((clamped * 32767.0).rounded()))
                monoSamples[i] = shortVal
            }
        }

        if inputSampleRate == targetSampleRate {
            var out = Data(count: numFrames * 2)
            out.withUnsafeMutableBytes { outBuf in
                for i in 0..<numFrames {
                    outBuf.storeBytes(of: monoSamples[i].littleEndian, toByteOffset: i * 2, as: Int16.self)
                }
            }
            return out
        }

        return resampleMonoSamples(monoSamples, inputSampleRate: inputSampleRate)
    }

    /// Resamples an array of Float samples (`[-1.0, 1.0]`) to 16kHz mono linear-16 `Data`.
    ///
    /// - Parameters:
    ///   - inputFloats: Float audio samples in range [-1.0, 1.0].
    ///   - inputSampleRate: Source sample rate.
    ///   - channelCount: Number of channels (1 for mono, 2 for stereo interleaved).
    /// - Returns: Resampled 16kHz mono Int16 little-endian `Data`.
    public static func resampleFloat32(
        inputFloats: [Float],
        inputSampleRate: Int,
        channelCount: Int = 1
    ) -> Data {
        guard !inputFloats.isEmpty else { return Data() }
        precondition(channelCount == 1 || channelCount == 2, "channelCount must be 1 (mono) or 2 (stereo)")

        let numFrames = inputFloats.count / channelCount
        guard numFrames > 0 else { return Data() }

        var monoSamples = [Int16](repeating: 0, count: numFrames)
        for i in 0..<numFrames {
            let monoFloat: Float
            if channelCount == 1 {
                monoFloat = inputFloats[i]
            } else {
                monoFloat = (inputFloats[2 * i] + inputFloats[2 * i + 1]) / 2.0
            }

            let clamped = max(-1.0, min(1.0, monoFloat))
            let shortVal = Int16(clamping: Int((clamped * 32767.0).rounded()))
            monoSamples[i] = shortVal
        }

        if inputSampleRate == targetSampleRate {
            var out = Data(count: numFrames * 2)
            out.withUnsafeMutableBytes { outBuf in
                for i in 0..<numFrames {
                    outBuf.storeBytes(of: monoSamples[i].littleEndian, toByteOffset: i * 2, as: Int16.self)
                }
            }
            return out
        }

        return resampleMonoSamples(monoSamples, inputSampleRate: inputSampleRate)
    }

    private static func resampleMonoSamples(
        _ monoSamples: [Int16],
        inputSampleRate: Int
    ) -> Data {
        let numInput = monoSamples.count
        let outSampleCount = Int((Int64(numInput) * Int64(targetSampleRate) + Int64(inputSampleRate / 2)) / Int64(inputSampleRate))
        var out = Data(count: outSampleCount * 2)
        let ratio = Double(inputSampleRate) / Double(targetSampleRate)

        out.withUnsafeMutableBytes { outBuf in
            for i in 0..<outSampleCount {
                let pos = Double(i) * ratio
                let idx = Int(pos)
                let frac = pos - Double(idx)

                let s0 = Double(monoSamples[min(idx, numInput - 1)])
                let s1 = Double(monoSamples[min(idx + 1, numInput - 1)])
                let interp = Int(((1.0 - frac) * s0 + frac * s1).rounded())
                let clamped = Int16(clamping: interp)
                outBuf.storeBytes(of: clamped.littleEndian, toByteOffset: i * 2, as: Int16.self)
            }
        }
        return out
    }

    /// Computes RMS, Peak amplitude (0.0 to 1.0), and dBFS from PCM16 audio bytes.
    public static func calculateLevels(pcm16Bytes: Data) -> AudioLevel {
        let numSamples = pcm16Bytes.count / 2
        guard numSamples > 0 else {
            return AudioLevel(rms: 0.0, peak: 0.0, dbFs: -100.0)
        }

        var peak: Double = 0.0
        var sumSquares: Double = 0.0

        pcm16Bytes.withUnsafeBytes { raw in
            for i in 0..<numSamples {
                let sample = raw.load(fromByteOffset: i * 2, as: Int16.self).littleEndian
                let normalized = abs(Double(sample)) / 32768.0
                if normalized > peak {
                    peak = normalized
                }
                sumSquares += normalized * normalized
            }
        }

        let rms = sqrt(sumSquares / Double(numSamples))
        let dbFs = rms > 0.0 ? max(min(20.0 * log10(rms), 0.0), -100.0) : -100.0

        return AudioLevel(rms: rms, peak: peak, dbFs: dbFs)
    }

    /// Returns the RMS amplitude (0.0 to 1.0) of PCM16 audio bytes.
    public static func calculateRms(pcm16Bytes: Data) -> Double {
        calculateLevels(pcm16Bytes: pcm16Bytes).rms
    }

    /// Returns the peak amplitude (0.0 to 1.0) of PCM16 audio bytes.
    public static func calculatePeak(pcm16Bytes: Data) -> Double {
        calculateLevels(pcm16Bytes: pcm16Bytes).peak
    }
}
