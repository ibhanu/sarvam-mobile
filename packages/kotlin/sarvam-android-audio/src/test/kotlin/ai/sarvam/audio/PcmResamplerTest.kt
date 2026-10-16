package ai.sarvam.audio

import org.junit.Assert.assertArrayEquals
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test
import kotlin.math.sin

class PcmResamplerTest {

    @Test
    fun `resample 48kHz mono PCM16 to 16kHz produces exact sample count`() {
        // 480 samples = 10ms at 48kHz (960 bytes)
        val numInputSamples = 480
        val inputBytes = ByteArray(numInputSamples * 2)
        for (i in 0 until numInputSamples) {
            val sample = (sin(2.0 * Math.PI * 440.0 * i / 48000.0) * 16000.0).toInt().toShort()
            inputBytes[2 * i] = (sample.toInt() and 0xFF).toByte()
            inputBytes[2 * i + 1] = ((sample.toInt() shr 8) and 0xFF).toByte()
        }

        val resampled = PcmResampler.resamplePcm16(inputBytes, inputSampleRate = 48000, channelCount = 1)
        val outputSamples = resampled.size / 2

        // 480 / 3 = exactly 160 samples (320 bytes)
        assertEquals(160, outputSamples)
        assertEquals(320, resampled.size)
    }

    @Test
    fun `resample 48kHz 100ms mono PCM16 produces exactly 1600 samples`() {
        // 4800 samples = 100ms at 48kHz (9600 bytes)
        val numInputSamples = 4800
        val inputBytes = ByteArray(numInputSamples * 2)
        for (i in 0 until numInputSamples) {
            val sample = (i % 1000).toShort()
            inputBytes[2 * i] = (sample.toInt() and 0xFF).toByte()
            inputBytes[2 * i + 1] = ((sample.toInt() shr 8) and 0xFF).toByte()
        }

        val resampled = PcmResampler.resamplePcm16(inputBytes, inputSampleRate = 48000, channelCount = 1)
        val outputSamples = resampled.size / 2

        assertEquals(1600, outputSamples)
        assertEquals(3200, resampled.size)
    }

    @Test
    fun `resample 44_1kHz mono PCM16 to 16kHz produces exact sample count`() {
        // 4410 samples = 100ms at 44.1kHz (8820 bytes)
        val numInputSamples = 4410
        val inputBytes = ByteArray(numInputSamples * 2)

        val resampled = PcmResampler.resamplePcm16(inputBytes, inputSampleRate = 44100, channelCount = 1)
        val outputSamples = resampled.size / 2

        // 4410 * 16000 / 44100 = 1600 samples
        assertEquals(1600, outputSamples)
        assertEquals(3200, resampled.size)
    }

    @Test
    fun `resample 48kHz stereo to 16kHz mono averages left and right channels`() {
        // 3 stereo frames: (L=1000, R=3000), (L=1000, R=3000), (L=1000, R=3000)
        // Average should be 2000
        val inputBytes = ByteArray(3 * 4)
        for (i in 0 until 3) {
            val left = 1000.toShort()
            val right = 3000.toShort()
            val off = i * 4
            inputBytes[off] = (left.toInt() and 0xFF).toByte()
            inputBytes[off + 1] = ((left.toInt() shr 8) and 0xFF).toByte()
            inputBytes[off + 2] = (right.toInt() and 0xFF).toByte()
            inputBytes[off + 3] = ((right.toInt() shr 8) and 0xFF).toByte()
        }

        val resampled = PcmResampler.resamplePcm16(inputBytes, inputSampleRate = 48000, channelCount = 2)
        assertEquals(2, resampled.size) // 1 sample = 2 bytes

        val outSample = ((resampled[0].toInt() and 0xFF) or (resampled[1].toInt() shl 8)).toShort()
        assertEquals(2000, outSample.toInt())
    }

    @Test
    fun `resample 16kHz mono PCM16 returns identical samples`() {
        val input = byteArrayOf(0x12, 0x34, 0x56, 0x78)
        val resampled = PcmResampler.resamplePcm16(input, inputSampleRate = 16000, channelCount = 1)
        assertArrayEquals(input, resampled)
    }

    @Test
    fun `resample Float32 audio to 16kHz PCM16`() {
        val floatSamples = floatArrayOf(0.0f, 0.5f, 1.0f, -0.5f, -1.0f)
        val resampled = PcmResampler.resampleFloat32(floatSamples, inputSampleRate = 16000, channelCount = 1)
        assertEquals(10, resampled.size) // 5 samples * 2 bytes

        val s0 = ((resampled[0].toInt() and 0xFF) or (resampled[1].toInt() shl 8)).toShort()
        val s2 = ((resampled[4].toInt() and 0xFF) or (resampled[5].toInt() shl 8)).toShort()
        val s4 = ((resampled[8].toInt() and 0xFF) or (resampled[9].toInt() shl 8)).toShort()

        assertEquals(0, s0.toInt())
        assertTrue(s2 >= 32760) // Near full scale positive
        assertTrue(s4 <= -32760) // Near full scale negative
    }

    @Test
    fun `calculateLevels calculates peak, RMS, and dBFS accurately`() {
        // Silence
        val silence = ByteArray(320)
        val silenceLevel = PcmResampler.calculateLevels(silence)
        assertEquals(0.0, silenceLevel.peak, 0.0001)
        assertEquals(0.0, silenceLevel.rms, 0.0001)
        assertEquals(-100.0, silenceLevel.dbFs, 0.0001)

        // Full scale DC (all 32767)
        val fullScale = ByteArray(320)
        for (i in 0 until 160) {
            fullScale[2 * i] = 0xFF.toByte()
            fullScale[2 * i + 1] = 0x7F.toByte()
        }
        val fullLevel = PcmResampler.calculateLevels(fullScale)
        assertTrue(fullLevel.peak > 0.99)
        assertTrue(fullLevel.rms > 0.99)
        assertTrue(fullLevel.dbFs > -0.1 && fullLevel.dbFs <= 0.0)

        // Empty bytes
        val emptyLevel = PcmResampler.calculateLevels(ByteArray(0))
        assertEquals(0.0, emptyLevel.peak, 0.0001)
        assertEquals(0.0, emptyLevel.rms, 0.0001)
        assertEquals(-100.0, emptyLevel.dbFs, 0.0001)

        assertEquals(fullLevel.rms, PcmResampler.calculateRms(fullScale), 0.0001)
        assertEquals(fullLevel.peak, PcmResampler.calculatePeak(fullScale), 0.0001)
    }

    @Test
    fun `edge cases for resamplePcm16`() {
        assertEquals(0, PcmResampler.resamplePcm16(ByteArray(0), 16000).size)
        assertEquals(0, PcmResampler.resamplePcm16(ByteArray(1), 16000, 1).size)

        try {
            PcmResampler.resamplePcm16(ByteArray(4), 16000, 0)
            org.junit.Assert.fail("Expected IllegalArgumentException")
        } catch (_: IllegalArgumentException) {}

        try {
            PcmResampler.resamplePcm16(ByteArray(4), 16000, 3)
            org.junit.Assert.fail("Expected IllegalArgumentException")
        } catch (_: IllegalArgumentException) {}
    }

    @Test
    fun `edge cases for resampleFloat32 byteArray`() {
        assertEquals(0, PcmResampler.resampleFloat32(ByteArray(0), 16000).size)
        assertEquals(0, PcmResampler.resampleFloat32(ByteArray(3), 16000, 1).size)

        try {
            PcmResampler.resampleFloat32(ByteArray(4), 16000, 0)
            org.junit.Assert.fail("Expected IllegalArgumentException")
        } catch (_: IllegalArgumentException) {}

        // Mono 16kHz
        val mono16kFloatBytes = ByteArray(4)
        val bits = java.lang.Float.floatToIntBits(0.5f)
        mono16kFloatBytes[0] = (bits and 0xFF).toByte()
        mono16kFloatBytes[1] = ((bits shr 8) and 0xFF).toByte()
        mono16kFloatBytes[2] = ((bits shr 16) and 0xFF).toByte()
        mono16kFloatBytes[3] = ((bits shr 24) and 0xFF).toByte()
        val res16 = PcmResampler.resampleFloat32(mono16kFloatBytes, 16000, 1)
        assertEquals(2, res16.size)

        // Stereo 16kHz
        val stereo16kFloatBytes = ByteArray(8)
        System.arraycopy(mono16kFloatBytes, 0, stereo16kFloatBytes, 0, 4)
        System.arraycopy(mono16kFloatBytes, 0, stereo16kFloatBytes, 4, 4)
        val resStereo16 = PcmResampler.resampleFloat32(stereo16kFloatBytes, 16000, 2)
        assertEquals(2, resStereo16.size)

        // Mono 48kHz
        val mono48kFloatBytes = ByteArray(12) // 3 samples
        for (i in 0 until 3) {
            System.arraycopy(mono16kFloatBytes, 0, mono48kFloatBytes, i * 4, 4)
        }
        val res48 = PcmResampler.resampleFloat32(mono48kFloatBytes, 48000, 1)
        assertEquals(2, res48.size) // 3 samples at 48k -> 1 sample at 16k = 2 bytes

        // Stereo 48kHz
        val stereo48kFloatBytes = ByteArray(24) // 3 frames of 2 channels
        for (i in 0 until 6) {
            System.arraycopy(mono16kFloatBytes, 0, stereo48kFloatBytes, i * 4, 4)
        }
        val resStereo48 = PcmResampler.resampleFloat32(stereo48kFloatBytes, 48000, 2)
        assertEquals(2, resStereo48.size)
    }

    @Test
    fun `edge cases for resampleFloat32 floatArray`() {
        assertEquals(0, PcmResampler.resampleFloat32(FloatArray(0), 16000).size)

        try {
            PcmResampler.resampleFloat32(FloatArray(4), 16000, 0)
            org.junit.Assert.fail("Expected IllegalArgumentException")
        } catch (_: IllegalArgumentException) {}

        // Stereo 16kHz
        val stereo16 = floatArrayOf(0.5f, -0.5f, 1.0f, 1.0f)
        val outStereo16 = PcmResampler.resampleFloat32(stereo16, 16000, 2)
        assertEquals(4, outStereo16.size) // 2 frames * 2 bytes = 4 bytes

        // Mono 48kHz
        val mono48 = floatArrayOf(0.5f, 0.5f, 0.5f)
        val outMono48 = PcmResampler.resampleFloat32(mono48, 48000, 1)
        assertEquals(2, outMono48.size) // 3 samples at 48k -> 1 sample at 16k = 2 bytes

        // Stereo 48kHz
        val stereo48 = floatArrayOf(0.5f, 0.5f, 0.5f, 0.5f, 0.5f, 0.5f)
        val outStereo48 = PcmResampler.resampleFloat32(stereo48, 48000, 2)
        assertEquals(2, outStereo48.size)
    }
}
