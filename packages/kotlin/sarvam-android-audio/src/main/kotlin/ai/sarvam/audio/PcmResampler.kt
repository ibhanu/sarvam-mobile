package ai.sarvam.audio

import kotlin.math.log10
import kotlin.math.roundToInt
import kotlin.math.sqrt

public data class AudioLevel(
    public val rms: Double,
    public val peak: Double,
    public val dbFs: Double
)

public object PcmResampler {

    public const val TARGET_SAMPLE_RATE: Int = 16000

    /**
     * Resamples little-endian PCM16 audio to 16kHz mono linear16 ByteArray.
     * Supports mono (channelCount=1) or stereo (channelCount=2) input.
     */
    public fun resamplePcm16(
        inputBytes: ByteArray,
        inputSampleRate: Int,
        channelCount: Int = 1
    ): ByteArray {
        if (inputBytes.isEmpty()) return ByteArray(0)
        require(channelCount in 1..2) { "channelCount must be 1 (mono) or 2 (stereo)" }

        val bytesPerFrame = 2 * channelCount
        val numFrames = inputBytes.size / bytesPerFrame
        if (numFrames == 0) return ByteArray(0)

        // Convert input to mono short samples
        val monoSamples = ShortArray(numFrames)
        for (i in 0 until numFrames) {
            val offset = i * bytesPerFrame
            val left = (inputBytes[offset].toInt() and 0xFF) or (inputBytes[offset + 1].toInt() shl 8)
            val leftShort = left.toShort()
            if (channelCount == 1) {
                monoSamples[i] = leftShort
            } else {
                val right = (inputBytes[offset + 2].toInt() and 0xFF) or (inputBytes[offset + 3].toInt() shl 8)
                val rightShort = right.toShort()
                monoSamples[i] = ((leftShort.toInt() + rightShort.toInt()) / 2).toShort()
            }
        }

        if (inputSampleRate == TARGET_SAMPLE_RATE) {
            // Already 16kHz mono
            val out = ByteArray(numFrames * 2)
            for (i in 0 until numFrames) {
                val s = monoSamples[i].toInt()
                out[2 * i] = (s and 0xFF).toByte()
                out[2 * i + 1] = ((s shr 8) and 0xFF).toByte()
            }
            return out
        }

        return resampleMonoSamples(monoSamples, inputSampleRate)
    }

    /**
     * Resamples Float32 audio (range [-1.0, 1.0], little-endian bytes) to 16kHz mono linear16 ByteArray.
     */
    public fun resampleFloat32(
        inputBytes: ByteArray,
        inputSampleRate: Int,
        channelCount: Int = 1
    ): ByteArray {
        if (inputBytes.isEmpty()) return ByteArray(0)
        require(channelCount in 1..2) { "channelCount must be 1 (mono) or 2 (stereo)" }

        val bytesPerFrame = 4 * channelCount
        val numFrames = inputBytes.size / bytesPerFrame
        if (numFrames == 0) return ByteArray(0)

        val monoSamples = ShortArray(numFrames)
        for (i in 0 until numFrames) {
            val offset = i * bytesPerFrame
            val leftBits = (inputBytes[offset].toInt() and 0xFF) or
                    ((inputBytes[offset + 1].toInt() and 0xFF) shl 8) or
                    ((inputBytes[offset + 2].toInt() and 0xFF) shl 16) or
                    ((inputBytes[offset + 3].toInt() and 0xFF) shl 24)
            val leftFloat = java.lang.Float.intBitsToFloat(leftBits)

            val monoFloat = if (channelCount == 1) {
                leftFloat
            } else {
                val rightBits = (inputBytes[offset + 4].toInt() and 0xFF) or
                        ((inputBytes[offset + 5].toInt() and 0xFF) shl 8) or
                        ((inputBytes[offset + 6].toInt() and 0xFF) shl 16) or
                        ((inputBytes[offset + 7].toInt() and 0xFF) shl 24)
                val rightFloat = java.lang.Float.intBitsToFloat(rightBits)
                (leftFloat + rightFloat) / 2.0f
            }
            val shortVal = (monoFloat.coerceIn(-1.0f, 1.0f) * 32767.0f).roundToInt().coerceIn(-32768, 32767)
            monoSamples[i] = shortVal.toShort()
        }

        if (inputSampleRate == TARGET_SAMPLE_RATE) {
            val out = ByteArray(numFrames * 2)
            for (i in 0 until numFrames) {
                val s = monoSamples[i].toInt()
                out[2 * i] = (s and 0xFF).toByte()
                out[2 * i + 1] = ((s shr 8) and 0xFF).toByte()
            }
            return out
        }

        return resampleMonoSamples(monoSamples, inputSampleRate)
    }

    /**
     * Resamples FloatArray directly to 16kHz mono linear16 ByteArray.
     */
    public fun resampleFloat32(
        inputFloats: FloatArray,
        inputSampleRate: Int,
        channelCount: Int = 1
    ): ByteArray {
        if (inputFloats.isEmpty()) return ByteArray(0)
        require(channelCount in 1..2) { "channelCount must be 1 (mono) or 2 (stereo)" }

        val numFrames = inputFloats.size / channelCount
        val monoSamples = ShortArray(numFrames)
        for (i in 0 until numFrames) {
            val monoFloat = if (channelCount == 1) {
                inputFloats[i]
            } else {
                (inputFloats[2 * i] + inputFloats[2 * i + 1]) / 2.0f
            }
            monoSamples[i] = (monoFloat.coerceIn(-1.0f, 1.0f) * 32767.0f).roundToInt().coerceIn(-32768, 32767).toShort()
        }

        if (inputSampleRate == TARGET_SAMPLE_RATE) {
            val out = ByteArray(numFrames * 2)
            for (i in 0 until numFrames) {
                val s = monoSamples[i].toInt()
                out[2 * i] = (s and 0xFF).toByte()
                out[2 * i + 1] = ((s shr 8) and 0xFF).toByte()
            }
            return out
        }

        return resampleMonoSamples(monoSamples, inputSampleRate)
    }

    private fun resampleMonoSamples(
        monoSamples: ShortArray,
        inputSampleRate: Int
    ): ByteArray {
        val numInput = monoSamples.size
        val outSampleCount = ((numInput.toLong() * TARGET_SAMPLE_RATE + inputSampleRate / 2) / inputSampleRate).toInt()
        val out = ByteArray(outSampleCount * 2)
        val ratio = inputSampleRate.toDouble() / TARGET_SAMPLE_RATE.toDouble()

        for (i in 0 until outSampleCount) {
            val pos = i * ratio
            val idx = pos.toInt()
            val frac = pos - idx

            val s0 = monoSamples[minOf(idx, numInput - 1)].toDouble()
            val s1 = monoSamples[minOf(idx + 1, numInput - 1)].toDouble()
            val interp = ((1.0 - frac) * s0 + frac * s1).roundToInt().coerceIn(-32768, 32767)

            out[2 * i] = (interp and 0xFF).toByte()
            out[2 * i + 1] = ((interp shr 8) and 0xFF).toByte()
        }
        return out
    }

    /**
     * Calculates RMS, Peak amplitude (0.0 to 1.0), and dBFS for UI voice waveforms.
     */
    public fun calculateLevels(pcm16Bytes: ByteArray): AudioLevel {
        val numSamples = pcm16Bytes.size / 2
        if (numSamples == 0) return AudioLevel(rms = 0.0, peak = 0.0, dbFs = -100.0)

        var peak = 0.0
        var sumSquares = 0.0

        for (i in 0 until numSamples) {
            val sample = ((pcm16Bytes[2 * i].toInt() and 0xFF) or (pcm16Bytes[2 * i + 1].toInt() shl 8)).toShort()
            val normalized = kotlin.math.abs(sample.toInt()).toDouble() / 32768.0
            if (normalized > peak) peak = normalized
            sumSquares += normalized * normalized
        }

        val rms = sqrt(sumSquares / numSamples)
        val dbFs = if (rms > 0.0) (20.0 * log10(rms)).coerceIn(-100.0, 0.0) else -100.0

        return AudioLevel(
            rms = rms,
            peak = peak,
            dbFs = dbFs
        )
    }

    public fun calculateRms(pcm16Bytes: ByteArray): Double = calculateLevels(pcm16Bytes).rms

    public fun calculatePeak(pcm16Bytes: ByteArray): Double = calculateLevels(pcm16Bytes).peak
}
