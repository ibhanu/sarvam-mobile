package ai.sarvam

import ai.sarvam.core.RequestOptions
import ai.sarvam.core.SarvamClientConfig
import ai.sarvam.core.SarvamEnvironment
import ai.sarvam.core.auth.ApiKeyAuth
import ai.sarvam.core.auth.AuthProvider
import ai.sarvam.core.auth.AuthToken
import ai.sarvam.core.auth.ProxyAuth
import ai.sarvam.core.auth.SarvamCredentials
import ai.sarvam.core.auth.TokenAuth
import ai.sarvam.core.error.SarvamException
import ai.sarvam.core.error.TimeoutPhase
import ai.sarvam.core.http.HttpBody
import ai.sarvam.core.http.HttpRequest
import ai.sarvam.core.http.HttpResponse
import ai.sarvam.core.http.HttpTransport
import ai.sarvam.core.http.MultipartPart
import ai.sarvam.core.io.FileInput
import ai.sarvam.core.middleware.ConsoleLogger
import ai.sarvam.core.middleware.LogLevel
import ai.sarvam.core.middleware.LoggerAdapter
import ai.sarvam.core.middleware.LoggingMiddleware
import ai.sarvam.core.middleware.RetryMiddleware
import ai.sarvam.core.sse.SseEvent
import ai.sarvam.core.sse.SseReader
import ai.sarvam.core.util.Clock
import ai.sarvam.core.util.DefaultRandomSource
import ai.sarvam.core.util.JsonHelper
import ai.sarvam.core.util.RandomSource
import ai.sarvam.core.util.SystemClock
import ai.sarvam.core.ws.WebSocketFactory
import ai.sarvam.core.ws.WebSocketFrame
import ai.sarvam.core.ws.WebSocketSession
import ai.sarvam.generated.OperationKind
import ai.sarvam.models.SttRealtimeEvent
import ai.sarvam.models.TtsStreamEvent
import ai.sarvam.models.TtsStreamingConfig
import ai.sarvam.session.SttRealtimeSession
import ai.sarvam.session.TtsStreamingSession
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.MutableSharedFlow
import kotlinx.coroutines.flow.flowOf
import kotlinx.coroutines.flow.take
import kotlinx.coroutines.flow.toList
import kotlinx.coroutines.launch
import kotlinx.coroutines.test.runTest
import org.junit.Assert.assertArrayEquals
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotEquals
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Assert.fail
import org.junit.Test
import java.io.ByteArrayInputStream
import java.io.File
import java.time.Instant
import java.time.format.DateTimeFormatter

class CoreInfrastructureTest {

    private class MockSession : WebSocketSession {
        val sent = mutableListOf<String>()
        val incomingFlow = MutableSharedFlow<WebSocketFrame>(replay = 10)
        override suspend fun send(text: String) { sent.add(text) }
        override suspend fun send(bytes: ByteArray) {}
        override fun close(code: Int, reason: String?) {}
        override val incoming: Flow<WebSocketFrame> = incomingFlow
    }

    private class MockTransport(private val responseHandler: (HttpRequest) -> HttpResponse) : HttpTransport {
        override suspend fun execute(request: HttpRequest): HttpResponse = responseHandler(request)
    }

    private class SimpleResponse(
        override val statusCode: Int = 200,
        override val headers: Map<String, List<String>> = emptyMap(),
        private val body: String = ""
    ) : HttpResponse {
        override suspend fun bodyAsString(): String = body
        override suspend fun bodyAsBytes(): ByteArray = body.toByteArray()
        override fun bodyByteStream(): Flow<ByteArray> = flowOf(body.toByteArray())
        override fun close() {}
    }

    // --- 1. SarvamClient.Builder and sarvamClient DSL ---

    @Test
    fun `SarvamClient Builder and DSL coverage`() {
        val client1 = SarvamClient("key-1")
        assertNotNull(client1)

        val client2 = SarvamClient(ApiKeyAuth("key-2"))
        assertNotNull(client2)

        val customLogger = object : LoggerAdapter {
            override fun log(level: String, message: String) {}
        }

        val client3 = sarvamClient {
            apiKey("key-3")
            apiBaseUrl("https://api.custom.com/")
            wsBaseUrl("wss://ws.custom.com/")
            logLevel(LogLevel.BODY)
            maxRetries(5)
            baseBackoffMs(100L)
            maxBackoffMs(5000L)
            clock(SystemClock)
            randomSource(DefaultRandomSource)
            addMiddleware(LoggingMiddleware(LogLevel.HEADERS, customLogger))
        }
        assertEquals("https://api.custom.com", client3.config.environment.apiBaseUrl)
        assertEquals("wss://ws.custom.com", client3.config.environment.wsBaseUrl)

        try {
            SarvamClient.builder().build()
            fail("Expected IllegalStateException when no auth configured")
        } catch (e: IllegalStateException) {
            assertTrue(e.message?.contains("AuthProvider or apiKey") == true)
        }
    }

    // --- 2. LoggingMiddleware ---

    @Test
    fun `LoggingMiddleware all log levels and sensitive header redaction`() = runTest {
        val logs = mutableListOf<String>()
        val testLogger = object : LoggerAdapter {
            override fun log(level: String, message: String) {
                logs.add("[$level] $message")
            }
        }

        // Test ConsoleLogger
        ConsoleLogger().log("INFO", "test message")

        // 1. LogLevel.NONE
        val mwNone = LoggingMiddleware(LogLevel.NONE, testLogger)
        val dummyReq = HttpRequest("GET", "https://api.sarvam.ai/v1")
        mwNone.intercept(dummyReq) { SimpleResponse(200) }
        assertEquals(0, logs.size)

        // 2. LogLevel.BASIC
        val mwBasic = LoggingMiddleware(LogLevel.BASIC, testLogger)
        mwBasic.intercept(dummyReq) { SimpleResponse(200) }
        assertTrue(logs.any { it.contains("--> GET https://api.sarvam.ai/v1") })
        assertTrue(logs.any { it.contains("<-- 200 https://api.sarvam.ai/v1") })

        // 3. LogLevel.HEADERS with sensitive redaction
        logs.clear()
        val mwHeaders = LoggingMiddleware(LogLevel.HEADERS, testLogger)
        val sensitiveReq = dummyReq
            .withHeader("api-subscription-key", "secret-key")
            .withHeader("authorization", "Bearer token")
            .withHeader("x-api-key", "top-secret")
            .withHeader("normal-header", "normal-val")

        mwHeaders.intercept(sensitiveReq) {
            SimpleResponse(
                200,
                headers = mapOf(
                    "authorization" to listOf("Bearer return-tok"),
                    "x-normal" to listOf("normal")
                )
            )
        }
        assertTrue(logs.any { it.contains("api-subscription-key: [REDACTED]") })
        assertTrue(logs.any { it.contains("authorization: [REDACTED]") })
        assertTrue(logs.any { it.contains("x-api-key: [REDACTED]") })
        assertTrue(logs.any { it.contains("normal-header: normal-val") })

        // 4. Exception in LoggingMiddleware
        logs.clear()
        try {
            mwBasic.intercept(dummyReq) { throw RuntimeException("network failure") }
            fail("Expected exception")
        } catch (e: RuntimeException) {
            assertTrue(logs.any { it.contains("<-- FAILED https://api.sarvam.ai/v1") })
        }
    }

    // --- 3. RetryMiddleware isRetryable and computeDelay branches ---

    @Test
    fun `RetryMiddleware isRetryable branches and backoff`() {
        val clock = object : Clock {
            var time = 1000L
            override fun currentTimeMillis(): Long = time
        }
        val random = object : RandomSource {
            override fun nextLong(until: Long): Long = until - 1
        }

        val retry = RetryMiddleware(
            maxRetries = 3,
            baseBackoffMs = 100L,
            maxBackoffMs = 1000L,
            clock = clock,
            randomSource = random
        )

        val nonRetryables = listOf(
            SarvamException.AuthenticationException(401, "unauth", null, "unauth"),
            SarvamException.PermissionDeniedException(403, "denied", null, "denied"),
            SarvamException.BadRequestException(400, "bad", null, null, "bad"),
            SarvamException.NotFoundException(404, "not_found", null, "not_found"),
            SarvamException.PayloadTooLargeException(413, "too_large", null, "too_large"),
            SarvamException.UnprocessableEntityException(422, "unprocessable", null, null, "unprocessable"),
            SarvamException.StreamException(null, "stream error"),
            SarvamException.RealtimeException(1006, "closed", "closed"),
            SarvamException.DecodingException(null, "decode")
        )

        val req = HttpRequest("POST", "https://api.sarvam.ai/v1", operationKind = OperationKind.STATELESS_POST)
        for (ex in nonRetryables) {
            assertFalse(retry.isRetryable(req, ex))
        }

        // RateLimitException
        val rateLimitEx = SarvamException.RateLimitException(500L, 429, "rate_limit", null, "limit")
        assertTrue(retry.isRetryable(req, rateLimitEx))

        val multipartNonReplayable = HttpRequest(
            "POST", "https://api.sarvam.ai/v1",
            operationKind = OperationKind.MULTIPART_COMPUTE,
            body = HttpBody.Multipart(listOf(MultipartPart.FilePart("f", FileInput.fromStream({ ByteArrayInputStream(byteArrayOf(1)) }, "a.wav", isReplayable = false))))
        )
        assertFalse(retry.isRetryable(multipartNonReplayable, rateLimitEx))

        // ServerException
        val server500 = SarvamException.ServerException(500, "internal", null, "internal")
        val server503 = SarvamException.ServerException(503, "unavailable", null, "unavailable")

        val reqIdempotent = HttpRequest("GET", "https://api.sarvam.ai/v1", operationKind = OperationKind.IDEMPOTENT)
        val reqStateless = HttpRequest("POST", "https://api.sarvam.ai/v1", operationKind = OperationKind.STATELESS_POST)
        val reqMultipartReplayable = HttpRequest("POST", "https://api.sarvam.ai/v1", operationKind = OperationKind.MULTIPART_COMPUTE, body = HttpBody.Json("{}"))
        val reqJobCreateNoKey = HttpRequest("POST", "https://api.sarvam.ai/v1", operationKind = OperationKind.JOB_CREATE)
        val reqJobCreateWithKey = HttpRequest("POST", "https://api.sarvam.ai/v1", operationKind = OperationKind.JOB_CREATE).withHeader("Idempotency-Key", "k1")

        assertTrue(retry.isRetryable(reqIdempotent, server500))
        assertTrue(retry.isRetryable(reqStateless, server500))
        assertFalse(retry.isRetryable(reqMultipartReplayable, server500)) // only 503 is retryable for MULTIPART_COMPUTE
        assertTrue(retry.isRetryable(reqMultipartReplayable, server503))
        assertFalse(retry.isRetryable(reqJobCreateNoKey, server500))
        assertTrue(retry.isRetryable(reqJobCreateWithKey, server500))

        // ConnectionException & TimeoutException
        val connEx = SarvamException.ConnectionException("conn")
        val timeoutEx = SarvamException.TimeoutException(TimeoutPhase.TOTAL, "timeout")

        assertTrue(retry.isRetryable(reqIdempotent, connEx))
        assertTrue(retry.isRetryable(reqMultipartReplayable, connEx))
        assertFalse(retry.isRetryable(reqJobCreateNoKey, connEx))
        assertTrue(retry.isRetryable(reqJobCreateWithKey, connEx))

        assertTrue(retry.isRetryable(reqIdempotent, timeoutEx))
        assertTrue(retry.isRetryable(reqMultipartReplayable, timeoutEx))
        assertFalse(retry.isRetryable(reqJobCreateNoKey, timeoutEx))
        assertTrue(retry.isRetryable(reqJobCreateWithKey, timeoutEx))
    }

    // --- 4. SarvamException factories and header parsing ---

    @Test
    fun `SarvamException fromHttpResponse full coverage`() {
        val clock = object : Clock {
            override fun currentTimeMillis(): Long = 1_000_000L
        }

        // 1. Detail error format
        val detailEx = SarvamException.fromHttpResponse(400, emptyMap(), """{"detail":"Invalid request body"}""", clock)
        assertEquals("Invalid request body", (detailEx as SarvamException.BadRequestException).message?.substringAfter("): "))

        // 2. Non-JSON raw body
        val rawEx = SarvamException.fromHttpResponse(404, emptyMap(), "Plain 404 error", clock)
        assertTrue(rawEx is SarvamException.NotFoundException)

        // 3. Blank body fallback
        val blankEx = SarvamException.fromHttpResponse(502, emptyMap(), "   ", clock)
        assertTrue(blankEx is SarvamException.ServerException)
        assertTrue(blankEx.message?.contains("HTTP 502 error") == true)

        // 4. Status code mappings: 413, 422, 504, 408, 409, 505, unknown 302
        val ex413 = SarvamException.fromHttpResponse(413, emptyMap(), "{}", clock)
        assertTrue(ex413 is SarvamException.PayloadTooLargeException)

        val ex422 = SarvamException.fromHttpResponse(422, emptyMap(), "{}", clock)
        assertTrue(ex422 is SarvamException.UnprocessableEntityException)

        val ex504 = SarvamException.fromHttpResponse(504, emptyMap(), "{}", clock)
        assertTrue(ex504 is SarvamException.ServerException)

        val ex408 = SarvamException.fromHttpResponse(408, emptyMap(), "{}", clock)
        assertTrue(ex408 is SarvamException.ServerException)

        val ex409 = SarvamException.fromHttpResponse(409, emptyMap(), "{}", clock)
        assertTrue(ex409 is SarvamException.ServerException)

        val ex505 = SarvamException.fromHttpResponse(505, emptyMap(), "{}", clock)
        assertTrue(ex505 is SarvamException.ServerException)

        val ex302 = SarvamException.fromHttpResponse(302, emptyMap(), "{}", clock)
        assertTrue(ex302 is SarvamException.BadRequestException)

        // 5. Retry-After header variations
        // a) retry-after-ms
        val exMs = SarvamException.fromHttpResponse(429, mapOf("retry-after-ms" to listOf("2500")), "{}", clock)
        assertEquals(2500L, (exMs as SarvamException.RateLimitException).retryAfterMs)

        // b) Retry-After seconds
        val exSec = SarvamException.fromHttpResponse(429, mapOf("Retry-After" to listOf("5")), "{}", clock)
        assertEquals(5000L, (exSec as SarvamException.RateLimitException).retryAfterMs)

        // c) Retry-After HTTP date
        val futureDateStr = DateTimeFormatter.RFC_1123_DATE_TIME.format(
            Instant.ofEpochMilli(clock.currentTimeMillis() + 10_000L).atZone(java.time.ZoneOffset.UTC)
        )
        val exDate = SarvamException.fromHttpResponse(429, mapOf("Retry-After" to listOf(futureDateStr)), "{}", clock)
        assertEquals(10_000L, (exDate as SarvamException.RateLimitException).retryAfterMs)

        // d) x-ratelimit-reset epoch seconds
        val resetSec = (clock.currentTimeMillis() + 8000L) / 1000L
        val exReset = SarvamException.fromHttpResponse(429, mapOf("x-ratelimit-reset" to listOf(resetSec.toString())), "{}", clock)
        assertEquals(8000L, (exReset as SarvamException.RateLimitException).retryAfterMs)
    }

    // --- 5. FileInput extensions and streams ---

    @Test
    fun `FileInput fromFile extensions and fromStream`() {
        val tempDir = File.createTempFile("test", "dir")
        tempDir.delete()
        tempDir.mkdir()

        val wavFile = File(tempDir, "audio.wav").apply { writeBytes(byteArrayOf(1, 2)) }
        val mp3File = File(tempDir, "audio.mp3").apply { writeBytes(byteArrayOf(3, 4)) }
        val opusFile = File(tempDir, "audio.opus").apply { writeBytes(byteArrayOf(5, 6)) }
        val flacFile = File(tempDir, "audio.flac").apply { writeBytes(byteArrayOf(7, 8)) }
        val aacFile = File(tempDir, "audio.aac").apply { writeBytes(byteArrayOf(9, 10)) }
        val pdfFile = File(tempDir, "doc.pdf").apply { writeBytes(byteArrayOf(11, 12)) }
        val otherFile = File(tempDir, "doc.xyz").apply { writeBytes(byteArrayOf(13, 14)) }

        assertEquals("audio/wav", FileInput.fromFile(wavFile).mimeType)
        assertEquals("audio/mpeg", FileInput.fromFile(mp3File).mimeType)
        assertEquals("audio/opus", FileInput.fromFile(opusFile).mimeType)
        assertEquals("audio/flac", FileInput.fromFile(flacFile).mimeType)
        assertEquals("audio/aac", FileInput.fromFile(aacFile).mimeType)
        assertEquals("application/pdf", FileInput.fromFile(pdfFile).mimeType)
        assertEquals("application/octet-stream", FileInput.fromFile(otherFile).mimeType)

        // fromStream
        val streamInput = FileInput.fromStream(
            inputStreamProvider = { ByteArrayInputStream(byteArrayOf(99, 100)) },
            filename = "stream.bin",
            mimeType = "application/bin",
            isReplayable = false
        )
        assertFalse(streamInput.isReplayable)
        assertArrayEquals(byteArrayOf(99, 100), streamInput.readBytes())
        assertNotNull(streamInput.openStream())

        wavFile.delete()
        mp3File.delete()
        opusFile.delete()
        flacFile.delete()
        aacFile.delete()
        pdfFile.delete()
        otherFile.delete()
        tempDir.delete()
    }

    // --- 6. HttpRequest and HttpBody ---

    @Test
    fun `HttpRequest withHeaders and HttpBody Binary equals hashCode`() {
        val bin1 = HttpBody.Binary(byteArrayOf(1, 2), "audio/wav")
        val bin2 = HttpBody.Binary(byteArrayOf(1, 2), "audio/wav")
        val bin3 = HttpBody.Binary(byteArrayOf(1, 3), "audio/wav")

        assertEquals(bin1, bin2)
        assertEquals(bin1.hashCode(), bin2.hashCode())
        assertNotEquals(bin1, bin3)

        val req = HttpRequest("GET", "https://test.com")
            .withHeaders(mapOf("A" to "1", "B" to "2"))
        assertEquals("1", req.header("A"))
        assertEquals("2", req.header("B"))
        assertTrue(req.isReplayable)
    }

    // --- 7. SseReader edge cases ---

    @Test
    fun `SseReader colon-less, unspaced values, comments, retry, and trailing events`() = runTest {
        val rawSse = """
            |: this is a comment
            |event: custom
            |data:first line
            |data: second line
            |id: 123
            |retry: 5000
            |
            |fieldwithoutcolon
            |data: trailing
            |
        """.trimMargin()

        val events = SseReader.parse(flowOf(rawSse.toByteArray())).toList()
        assertEquals(2, events.size)

        val e1 = events[0]
        assertEquals("custom", e1.event)
        assertEquals("first line\nsecond line", e1.data)
        assertEquals("123", e1.id)
        assertEquals(5000L, e1.retry)

        val e2 = events[1]
        assertEquals("trailing", e2.data)
    }

    // --- 8. SttRealtimeSession and TtsStreamingSession methods and events ---

    @Test
    fun `SttRealtimeSession methods and event parsing`() = runTest {
        val session = MockSession()
        val stt = SttRealtimeSession(session)

        stt.updateConfig(mode = "transcribe", keyterms = listOf("term"), threshold = 0.8, silenceDurationMs = 200)
        assertTrue(session.sent.any { it.contains("\"event\":\"config_update\"") })

        stt.flush()
        assertTrue(session.sent.any { it.contains("\"event\":\"flush\"") })

        stt.ping()
        assertTrue(session.sent.any { it.contains("\"event\":\"ping\"") })

        stt.end()
        assertTrue(session.sent.any { it.contains("\"event\":\"end\"") })

        stt.close(1000, "done")

        // Parse events
        session.incomingFlow.emit(WebSocketFrame.Text("""{"event":"session_begin","session_id":"s_1"}"""))
        session.incomingFlow.emit(WebSocketFrame.Text("""{"event":"vad_speech_end","timestamp_ms":2000}"""))
        session.incomingFlow.emit(WebSocketFrame.Text("""{"event":"transcript_final","utterance_idx":1,"text":"ok","language":"hi-IN","language_confidence":0.9,"start_s":0.1,"end_s":1.5}"""))
        session.incomingFlow.emit(WebSocketFrame.Text("""{"event":"session_end","duration_seconds":10.5}"""))
        session.incomingFlow.emit(WebSocketFrame.Text("""{"event":"error","code":"err_1","message":"err msg"}"""))
        session.incomingFlow.emit(WebSocketFrame.Text("""{"event":"custom_unknown"}"""))
        session.incomingFlow.emit(WebSocketFrame.Closed(1001, "going away"))
        session.incomingFlow.emit(WebSocketFrame.Failure(RuntimeException("fail")))

        val events = stt.events.take(8).toList()

        assertTrue(events.any { it is SttRealtimeEvent.SessionBegin && it.sessionId == "s_1" })
        assertTrue(events.any { it is SttRealtimeEvent.VadSpeechEnd && it.timestampMs == 2000L })
        assertTrue(events.any { it is SttRealtimeEvent.TranscriptFinal && it.text == "ok" && it.languageConfidence == 0.9 })
        assertTrue(events.any { it is SttRealtimeEvent.SessionEnd && it.durationSeconds == 10.5 })
        assertTrue(events.any { it is SttRealtimeEvent.Error && it.code == "err_1" })
        assertTrue(events.any { it is SttRealtimeEvent.Unknown })
        assertTrue(events.any { it is SttRealtimeEvent.Error && it.code == "ws_closed_1001" })
        assertTrue(events.any { it is SttRealtimeEvent.Error && it.code == "ws_failure" })
    }

    @Test
    fun `TtsStreamingSession methods and event parsing`() = runTest {
        val session = MockSession()
        val tts = TtsStreamingSession(
            session,
            TtsStreamingConfig(
                pitch = 0.5,
                pace = 1.0,
                loudness = 1.5,
                enablePreprocessing = true,
                voiceId = "v1"
            )
        )

        tts.initialize()
        assertTrue(session.sent.any { it.contains("\"type\":\"config\"") && it.contains("\"voice_id\":\"v1\"") })

        tts.sendText("Hello world \"quotes\" \n newline")
        assertTrue(session.sent.any { it.contains("\"type\":\"text\"") })

        tts.flush()
        assertTrue(session.sent.any { it.contains("\"type\":\"flush\"") })

        tts.ping()
        assertTrue(session.sent.any { it.contains("\"type\":\"ping\"") })

        tts.close(1000, "done")

        // Parse events
        session.incomingFlow.emit(WebSocketFrame.Text("""{"type":"event","data":{"event":"final"},"request_id":"r1"}"""))
        session.incomingFlow.emit(WebSocketFrame.Text("""{"type":"error","data":{"code":"e1","message":"msg"}}"""))
        session.incomingFlow.emit(WebSocketFrame.Text("""{"type":"unknown"}"""))
        session.incomingFlow.emit(WebSocketFrame.Closed(1002, "protocol error"))
        session.incomingFlow.emit(WebSocketFrame.Failure(RuntimeException("conn drop")))

        val events = tts.events.take(5).toList()

        assertTrue(events.any { it is TtsStreamEvent.Completed && it.requestId == "r1" })
        assertTrue(events.any { it is TtsStreamEvent.Error && it.code == "e1" })
        assertTrue(events.any { it is TtsStreamEvent.Unknown })
        assertTrue(events.any { it is TtsStreamEvent.Error && it.code == "ws_closed_1002" })
        assertTrue(events.any { it is TtsStreamEvent.Error && it.code == "ws_failure" })
    }
}
