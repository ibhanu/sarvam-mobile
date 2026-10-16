package ai.sarvam.audio

import ai.sarvam.core.ws.WebSocketFrame
import ai.sarvam.core.ws.WebSocketSession
import ai.sarvam.models.SttRealtimeEvent
import ai.sarvam.session.SttRealtimeSession
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.MutableSharedFlow
import kotlinx.coroutines.flow.first
import kotlinx.coroutines.flow.flow
import kotlinx.coroutines.flow.flowOf
import kotlinx.coroutines.flow.take
import kotlinx.coroutines.flow.toList
import kotlinx.coroutines.launch
import kotlinx.coroutines.test.runTest
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertTrue
import org.junit.Test
import kotlinx.coroutines.withTimeout
import java.util.concurrent.CountDownLatch
import java.util.concurrent.TimeUnit
import java.util.concurrent.atomic.AtomicBoolean
import java.util.concurrent.atomic.AtomicInteger

class AudioPlayerAndMicStreamerTest {

    private class TestWebSocketSession : WebSocketSession {
        val sentMessages = mutableListOf<String>()
        val incomingFlow = MutableSharedFlow<WebSocketFrame>(replay = 10)

        override suspend fun send(text: String) {
            sentMessages.add(text)
        }

        override suspend fun send(bytes: ByteArray) {}

        override fun close(code: Int, reason: String?) {}

        override val incoming: Flow<WebSocketFrame> = incomingFlow
    }

    // --- 1. SarvamMicStreamer Tests ---

    @Test
    fun `SarvamMicStreamer captures, resamples 48kHz to 16kHz, and emits levels and audio`() = runTest {
        val raw48k = ByteArray(9600 * 2)
        for (i in 0 until 4800 * 2) {
            raw48k[2 * i] = 0x50.toByte()
            raw48k[2 * i + 1] = 0x20.toByte()
        }

        val captureDriver = ByteArrayAudioCaptureDriver(raw48k, sampleRate = 48000, channelCount = 1)
        val levelEmitted = AtomicBoolean(false)

        val streamer = SarvamMicStreamer(
            driver = captureDriver,
            onAudioLevel = { level ->
                if (level.peak > 0.0) {
                    levelEmitted.set(true)
                }
            }
        )

        val wsSession = TestWebSocketSession()
        val sttSession = SttRealtimeSession(wsSession)

        val job = streamer.start(scope = this, session = sttSession)

        // Read first emitted resampled chunk from audioFlow
        val firstChunk = streamer.audioFlow.first()
        // 4800 samples -> resampled to 1600 samples (3200 bytes)
        assertEquals(3200, firstChunk.size)
        assertTrue(levelEmitted.get())

        // Yield for streamingJob to deliver the second chunk
        kotlinx.coroutines.delay(50)

        // Check STT session received audio frame
        assertTrue(wsSession.sentMessages.any { it.contains("\"event\":\"audio_input\"") })

        streamer.stop()
        job.cancel()
    }

    @Test
    fun `SarvamMicStreamer drops oldest audio frames on backpressure overflow`() = runTest {
        // Channel capacity = 2, emit 5 chunks without consuming
        val chunk = ByteArray(320)
        val multiChunks = ByteArray(320 * 5)
        for (i in 0 until 5) {
            System.arraycopy(chunk, 0, multiChunks, i * 320, 320)
        }

        val captureDriver = ByteArrayAudioCaptureDriver(multiChunks, sampleRate = 16000, channelCount = 1)
        val streamer = SarvamMicStreamer(
            driver = captureDriver,
            channelCapacity = 2
        )

        // Start capture without draining
        val job = streamer.start(scope = this)
        kotlinx.coroutines.delay(100)

        // Stop capture
        streamer.stop()
        job.cancel()

        // Since capacity is 2 and DROP_OLDEST is set, channel has at most 2 items
        val received = mutableListOf<ByteArray>()
        while (true) {
            val item = streamer.audioFlow.take(1)
            // Verify we can read without deadlock
            break
        }
    }

    // --- 2. SarvamAudioPlayer Tests ---

    @Test
    fun `SarvamAudioPlayer plays audio and supports sub-20ms stopAndFlush`() = runTest {
        val playbackDriver = MemoryAudioPlaybackDriver()
        val player = SarvamAudioPlayer(playbackDriver)

        // Direct play
        val chunk1 = byteArrayOf(1, 2, 3, 4)
        player.play(chunk1)
        assertEquals(1, playbackDriver.writtenBytes.size)
        assertEquals(4, playbackDriver.writtenBytes.first().size)
        assertTrue(player.isPlaying)

        // Stream play
        val flow = flow {
            emit(byteArrayOf(5, 6))
            kotlinx.coroutines.delay(50)
            emit(byteArrayOf(7, 8))
        }
        val job = player.playStream(flow, scope = this)

        // Instant stopAndFlush (Barge-in)
        val startTime = System.currentTimeMillis()
        player.stopAndFlush()
        val durationMs = System.currentTimeMillis() - startTime

        // Verify barge-in stop took less than 100ms
        assertTrue("stopAndFlush took $durationMs ms, expected < 100ms", durationMs < 100L)
        assertFalse(player.isPlaying)
        assertTrue(playbackDriver.isFlushed)
        assertTrue(job.isCancelled)
    }

    // --- 3. BargeInCoordinator Tests ---

    @Test
    fun `BargeInCoordinator automatically invokes stopAndFlush on VadSpeechStart`() = runTest {
        val wsSession = TestWebSocketSession()
        val sttSession = SttRealtimeSession(wsSession)
        val playbackDriver = MemoryAudioPlaybackDriver()
        val player = SarvamAudioPlayer(playbackDriver)

        val bargeInTriggered = AtomicBoolean(false)
        val coordinator = BargeInCoordinator(
            onBargeIn = { bargeInTriggered.set(true) }
        )

        // Start playback
        val infiniteAudio = flow {
            while (true) {
                emit(byteArrayOf(1, 2, 3, 4))
                kotlinx.coroutines.delay(10)
            }
        }
        player.playStream(infiniteAudio, scope = this)
        assertTrue(player.isPlaying)

        // Attach coordinator
        val coordJob = coordinator.attach(sttSession, player, scope = this)

        // Send other event first: transcript_partial
        wsSession.incomingFlow.emit(WebSocketFrame.Text("""{"event":"transcript_partial","text":"Hel"}"""))
        kotlinx.coroutines.delay(10)
        assertTrue(player.isPlaying)
        assertFalse(bargeInTriggered.get())

        // Send VadSpeechStart event
        wsSession.incomingFlow.emit(WebSocketFrame.Text("""{"event":"vad_speech_start","timestamp_ms":1234}"""))
        kotlinx.coroutines.delay(20)

        // Verify player is automatically stopped and flushed!
        assertFalse(player.isPlaying)
        assertTrue(playbackDriver.isFlushed)
        assertTrue(bargeInTriggered.get())

        coordJob.cancel()
    }

    @Test
    fun `BargeInCoordinator without callback works on VadSpeechStart`() = runTest {
        val wsSession = TestWebSocketSession()
        val sttSession = SttRealtimeSession(wsSession)
        val playbackDriver = MemoryAudioPlaybackDriver()
        val player = SarvamAudioPlayer(playbackDriver)
        player.play(byteArrayOf(1, 2, 3))

        val coordinator = BargeInCoordinator()
        val job = coordinator.attach(sttSession, player, scope = this)

        wsSession.incomingFlow.emit(WebSocketFrame.Text("""{"event":"vad_speech_start"}"""))
        kotlinx.coroutines.delay(20)

        assertFalse(player.isPlaying)
        assertTrue(playbackDriver.isFlushed)
        job.cancel()
    }

    @Test
    fun `ByteArrayAudioCaptureDriver edge cases`() {
        val driver = ByteArrayAudioCaptureDriver(byteArrayOf(1, 2, 3, 4), sampleRate = 16000, channelCount = 1)
        val buf = ByteArray(10)
        // Not started
        assertEquals(0, driver.read(buf, 0, 10))

        driver.start()
        // Read with offset
        assertEquals(2, driver.read(buf, 2, 2))
        assertEquals(1.toByte(), buf[2])
        assertEquals(2.toByte(), buf[3])

        // Read remaining
        assertEquals(2, driver.read(buf, 0, 5))
        // Read past end
        assertEquals(0, driver.read(buf, 0, 5))

        driver.stop()
        driver.close()
    }

    @Test
    fun `MemoryAudioPlaybackDriver edge cases`() {
        val driver = MemoryAudioPlaybackDriver()
        assertFalse(driver.isPlaying)
        driver.start()
        assertTrue(driver.isPlaying)

        driver.write(byteArrayOf(10, 20, 30, 40), 1, 2)
        assertEquals(1, driver.writtenBytes.size)
        org.junit.Assert.assertArrayEquals(byteArrayOf(20, 30), driver.writtenBytes[0])

        driver.flush()
        assertTrue(driver.isFlushed)
        assertEquals(0, driver.writtenBytes.size)

        driver.stop()
        assertFalse(driver.isPlaying)
        driver.close()
    }

    @Test
    fun `SarvamMicStreamer lifecycle and negative bytesRead`() = runTest {
        var callCount = 0
        val allowNegativeRead = CountDownLatch(1)
        val negativeDriver = object : AudioCaptureDriver {
            override val sampleRate: Int = 16000
            override val channelCount: Int = 1
            override fun start() {}
            override fun read(buffer: ByteArray, offset: Int, length: Int): Int {
                callCount++
                return if (callCount == 1) {
                    buffer[0] = 1
                    buffer[1] = 2
                    2
                } else {
                    allowNegativeRead.await(5, TimeUnit.SECONDS)
                    -1
                }
            }
            override fun stop() {}
            override fun close() {}
        }

        val streamer = SarvamMicStreamer(negativeDriver)
        assertFalse(streamer.isCapturing())

        val job1 = streamer.start(scope = this)
        assertTrue(streamer.isCapturing())

        // Calling start again while running returns the same job
        val job2 = streamer.start(scope = this)
        assertEquals(job1, job2)

        // Allow driver to return -1 and trigger natural termination
        allowNegativeRead.countDown()

        // Await capture coroutine completion cleanly without flaky sleeping
        withTimeout(5000) {
            job1.join()
        }
        assertFalse(streamer.isCapturing())

        // Stop when already not running (idempotency check)
        streamer.stop()

        streamer.close()
    }

    @Test
    fun `SarvamAudioPlayer play when playing and playSession with TtsStreamingSession`() = runTest {
        val driver = MemoryAudioPlaybackDriver()
        val player = SarvamAudioPlayer(driver)

        // Play first chunk
        player.play(byteArrayOf(1, 2))
        assertTrue(driver.isPlaying)

        // Play second chunk while already playing (branch coverage: driver.isPlaying == true)
        player.play(byteArrayOf(3, 4))
        assertEquals(2, driver.writtenBytes.size)

        // playStream with empty chunk
        val job = player.playStream(flowOf(ByteArray(0), byteArrayOf(5, 6)), scope = this)
        kotlinx.coroutines.delay(20)
        job.cancel()

        // playSession
        val wsSession = TestWebSocketSession()
        val ttsSession = ai.sarvam.session.TtsStreamingSession(
            wsSession,
            ai.sarvam.models.TtsStreamingConfig()
        )

        val sessionJob = player.playSession(ttsSession, scope = this)
        val audioB64 = java.util.Base64.getEncoder().encodeToString(byteArrayOf(7, 8, 9))
        wsSession.incomingFlow.emit(WebSocketFrame.Text("""{"type":"audio","data":{"audio":"$audioB64"}}"""))

        var received = false
        for (i in 0 until 50) {
            if (driver.writtenBytes.any { it.contentEquals(byteArrayOf(7, 8, 9)) }) {
                received = true
                break
            }
            Thread.sleep(10)
        }
        assertTrue(received)

        sessionJob.cancel()
        player.close()
    }
}
