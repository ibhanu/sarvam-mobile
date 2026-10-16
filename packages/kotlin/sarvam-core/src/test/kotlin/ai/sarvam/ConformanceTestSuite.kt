package ai.sarvam

import ai.sarvam.core.SarvamEnvironment
import ai.sarvam.core.auth.AuthToken
import ai.sarvam.core.auth.TokenAuth
import ai.sarvam.core.error.SarvamException
import ai.sarvam.core.http.HttpBody
import ai.sarvam.core.http.HttpRequest
import ai.sarvam.core.io.FileInput
import ai.sarvam.generated.ChatModel
import ai.sarvam.generated.LanguageCode
import ai.sarvam.generated.OperationKind
import ai.sarvam.generated.Speaker
import ai.sarvam.generated.SttModel
import ai.sarvam.generated.TtsModel
import ai.sarvam.models.ChatCompletionRequest
import ai.sarvam.models.ChatMessage
import ai.sarvam.models.ResponseStreamEvent
import ai.sarvam.models.ResponsesRequest
import ai.sarvam.models.SttRealtimeConfig
import ai.sarvam.models.SttRealtimeEvent
import ai.sarvam.models.TextToSpeechRequest
import ai.sarvam.models.TranslateRequest
import ai.sarvam.models.TtsStreamEvent
import ai.sarvam.models.TtsStreamingConfig
import kotlinx.coroutines.flow.take
import kotlinx.coroutines.flow.toList
import kotlinx.coroutines.test.runTest
import okhttp3.Response
import okhttp3.WebSocket
import okhttp3.WebSocketListener
import okhttp3.mockwebserver.MockResponse
import okhttp3.mockwebserver.MockWebServer
import okio.Buffer
import okio.ByteString.Companion.decodeHex
import org.junit.After
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Assert.fail
import org.junit.Before
import org.junit.Test
import java.util.concurrent.atomic.AtomicInteger

class ConformanceTestSuite {

    private lateinit var server: MockWebServer
    private lateinit var env: SarvamEnvironment

    @Before
    fun setUp() {
        server = MockWebServer()
        server.start()
        val url = server.url("/").toString().trimEnd('/')
        val wsUrl = url.replace("http://", "ws://").replace("https://", "wss://")
        env = SarvamEnvironment(
            apiBaseUrl = url,
            dubbingBaseUrl = "$url/dubbing",
            wsBaseUrl = wsUrl
        )
    }

    @After
    fun tearDown() {
        server.shutdown()
    }

    private fun createClient(apiKey: String = "test-api-key", baseBackoffMs: Long = 1L): SarvamClient {
        return SarvamClient.builder()
            .apiKey(apiKey)
            .environment(env)
            .baseBackoffMs(baseBackoffMs)
            .build()
    }

    // 1. rest-auth-error-quirk
    @Test
    fun `case 1 - rest-auth-error-quirk`() = runTest {
        server.enqueue(
            MockResponse()
                .setResponseCode(403)
                .setHeader("content-type", "application/json")
                .setBody("""{"error":{"code":"invalid_api_key_error","message":"Invalid API key","request_id":"req_auth_403"}}""")
        )

        val client = createClient(apiKey = "invalid-key")

        try {
            client.text.translate(
                TranslateRequest(
                    input = "Hello world",
                    sourceLanguageCode = LanguageCode.EN_IN,
                    targetLanguageCode = LanguageCode.HI_IN
                )
            )
            fail("Expected AuthenticationException")
        } catch (e: SarvamException.AuthenticationException) {
            assertEquals(403, e.statusCode)
            assertEquals("invalid_api_key_error", e.code)
            assertEquals("req_auth_403", e.requestId)
            assertEquals("Invalid API key", e.message?.substringAfterLast(": "))
        }

        val recorded = server.takeRequest()
        assertEquals("/translate", recorded.path)
        assertEquals("invalid-key", recorded.getHeader("api-subscription-key"))
    }

    // 2. rest-idempotent-retry-500
    @Test
    fun `case 2 - rest-idempotent-retry-500`() = runTest {
        server.enqueue(
            MockResponse()
                .setResponseCode(500)
                .setHeader("content-type", "application/json")
                .setBody("""{"error":{"code":"internal_server_error","message":"Transient inference service failure","request_id":"req_glitch_500"}}""")
        )
        server.enqueue(
            MockResponse()
                .setResponseCode(200)
                .setHeader("content-type", "application/json")
                .setBody("""{"models":[{"id":"sarvam-2b"},{"id":"saaras:v3"}]}""")
        )

        val client = createClient()
        val response = client.chat.listModels()

        assertEquals(2, response.models.size)
        assertEquals("sarvam-2b", response.models[0].id)
        assertEquals("saaras:v3", response.models[1].id)
        assertEquals(2, server.requestCount)
    }

    // 3. rest-job-creation-safety-500
    @Test
    fun `case 3 - rest-job-creation-safety-500`() = runTest {
        server.enqueue(
            MockResponse()
                .setResponseCode(500)
                .setHeader("content-type", "application/json")
                .setBody("""{"error":{"code":"internal_server_error","message":"Internal server error","request_id":"req_job_500"}}""")
        )

        val client = createClient()
        val request = HttpRequest(
            method = "POST",
            url = "${env.apiBaseUrl}/doc-ai/v1/job/digitise",
            body = HttpBody.Json("""{"language":"hi","output_format":"md"}"""),
            operationKind = OperationKind.JOB_CREATE
        )

        try {
            client.config.execute(request)
            fail("Expected ServerException with 0 retries")
        } catch (e: SarvamException.ServerException) {
            assertEquals(500, e.statusCode)
            assertEquals("internal_server_error", e.code)
            assertEquals("req_job_500", e.requestId)
            assertEquals(1, server.requestCount) // Zero retries!
        }
    }

    // 4. rest-permission-denied
    @Test
    fun `case 4 - rest-permission-denied`() = runTest {
        server.enqueue(
            MockResponse()
                .setResponseCode(403)
                .setHeader("content-type", "application/json")
                .setBody("""{"error":{"code":"authentication_error","message":"Tier locked","request_id":"req_perm_403"}}""")
        )

        val client = createClient(apiKey = "tier-locked-key")

        try {
            client.text.translate(
                input = "Hello world",
                sourceLanguageCode = LanguageCode.EN_IN,
                targetLanguageCode = LanguageCode.HI_IN
            )
            fail("Expected PermissionDeniedException")
        } catch (e: SarvamException.PermissionDeniedException) {
            assertEquals(403, e.statusCode)
            assertEquals("authentication_error", e.code)
            assertEquals("req_perm_403", e.requestId)
            assertEquals(1, server.requestCount)
        }
    }

    // 5. rest-rate-limit-retry
    @Test
    fun `case 5 - rest-rate-limit-retry`() = runTest {
        server.enqueue(
            MockResponse()
                .setResponseCode(429)
                .setHeader("retry-after-ms", "10")
                .setHeader("content-type", "application/json")
                .setBody("""{"error":{"code":"rate_limit_exceeded_error","message":"Rate limit exceeded","request_id":"req_rl_1"}}""")
        )
        server.enqueue(
            MockResponse()
                .setResponseCode(200)
                .setHeader("content-type", "application/json")
                .setBody("""{"translated_text":"नमस्ते पुनः प्रयास"}""")
        )

        val client = createClient()
        val response = client.text.translate(
            input = "Hello retry",
            sourceLanguageCode = LanguageCode.EN_IN,
            targetLanguageCode = LanguageCode.HI_IN
        )

        assertEquals("नमस्ते पुनः प्रयास", response.translatedText)
        assertEquals(2, server.requestCount)
    }

    // 6. rest-sas-blob-upload
    @Test
    fun `case 6 - rest-sas-blob-upload`() = runTest {
        server.enqueue(
            MockResponse()
                .setResponseCode(201)
                .setHeader("x-ms-request-id", "mock-azure-req-1")
        )

        val client = createClient()
        val fileInput = FileInput.fromBytes("mock-audio-binary-data".toByteArray(), "upload.wav", "application/octet-stream")
        client.jobs.uploadToSignedUrl("${env.apiBaseUrl}/mock-sas-upload", fileInput)

        val recorded = server.takeRequest()
        assertEquals("PUT", recorded.method)
        assertEquals("/mock-sas-upload", recorded.path)
        assertEquals("BlockBlob", recorded.getHeader("x-ms-blob-type"))
        assertEquals("mock-audio-binary-data", recorded.body.readUtf8())
    }

    // 7. rest-text-identify-language-success
    @Test
    fun `case 7 - rest-text-identify-language-success`() = runTest {
        server.enqueue(
            MockResponse()
                .setResponseCode(200)
                .setHeader("content-type", "application/json")
                .setBody("""{"detected_language":"hi-IN","confidence":0.99}""")
        )

        val client = createClient()
        val response = client.text.identifyLanguage("नमस्ते दुनिया")

        assertEquals("hi-IN", response.detectedLanguage)
        assertEquals(0.99, response.confidence, 0.001)

        val recorded = server.takeRequest()
        assertEquals("/text-lid", recorded.path)
        assertEquals("test-api-key", recorded.getHeader("api-subscription-key"))
    }

    // 8. rest-text-translate-success
    @Test
    fun `case 8 - rest-text-translate-success`() = runTest {
        server.enqueue(
            MockResponse()
                .setResponseCode(200)
                .setHeader("content-type", "application/json")
                .setBody("""{"translated_text":"नमस्ते दुनिया"}""")
        )

        val client = createClient()
        val response = client.text.translate(
            TranslateRequest(
                input = "Hello world",
                sourceLanguageCode = LanguageCode.EN_IN,
                targetLanguageCode = LanguageCode.HI_IN,
                speakerGender = "Male",
                mode = "formal",
                model = "mayura:v1"
            )
        )

        assertEquals("नमस्ते दुनिया", response.translatedText)
        val recorded = server.takeRequest()
        assertEquals("/translate", recorded.path)
        assertEquals("test-api-key", recorded.getHeader("api-subscription-key"))
    }

    // 9. rest-text-transliterate-success
    @Test
    fun `case 9 - rest-text-transliterate-success`() = runTest {
        server.enqueue(
            MockResponse()
                .setResponseCode(200)
                .setHeader("content-type", "application/json")
                .setBody("""{"transliterated_text":"नमस्ते"}""")
        )

        val client = createClient()
        val response = client.text.transliterate(
            input = "namaste",
            sourceLanguageCode = LanguageCode.EN_IN,
            targetLanguageCode = LanguageCode.HI_IN
        )

        assertEquals("नमस्ते", response.transliteratedText)
        val recorded = server.takeRequest()
        assertEquals("/transliterate", recorded.path)
        assertEquals("test-api-key", recorded.getHeader("api-subscription-key"))
    }

    // 10. rest-token-auth-refresh
    @Test
    fun `case 10 - rest-token-auth-refresh`() = runTest {
        server.enqueue(
            MockResponse()
                .setResponseCode(403)
                .setHeader("content-type", "application/json")
                .setBody("""{"error":{"code":"invalid_api_key_error","message":"Bearer token expired","request_id":"req_token_expired"}}""")
        )
        server.enqueue(
            MockResponse()
                .setResponseCode(200)
                .setHeader("content-type", "application/json")
                .setBody("""{"translated_text":"नमस्ते दुनिया"}""")
        )

        val tokenAttempts = AtomicInteger(0)
        val tokenAuth = TokenAuth(
            tokenProvider = {
                val attempt = tokenAttempts.incrementAndGet()
                if (attempt == 1) AuthToken("expired-token") else AuthToken("refreshed-token")
            }
        )

        val client = SarvamClient.builder()
            .authProvider(tokenAuth)
            .environment(env)
            .build()

        val response = client.text.translate(
            input = "Hello world",
            sourceLanguageCode = LanguageCode.EN_IN,
            targetLanguageCode = LanguageCode.HI_IN
        )

        assertEquals("नमस्ते दुनिया", response.translatedText)
        assertEquals(2, server.requestCount)

        val req1 = server.takeRequest()
        assertEquals("Bearer expired-token", req1.getHeader("Authorization"))

        val req2 = server.takeRequest()
        assertEquals("Bearer refreshed-token", req2.getHeader("Authorization"))
    }

    // 11. rest-tts-chunked-stream
    @Test
    fun `case 11 - rest-tts-chunked-stream`() = runTest {
        val chunk0 = "0102030405060708090a0b0c0d0e0f10".decodeHex().toByteArray()
        val chunk1 = "1112131415161718191a1b1c1d1e1f20".decodeHex().toByteArray()
        val chunk2 = "2122232425262728292a2b2c2d2e2f30".decodeHex().toByteArray()

        val buffer = Buffer()
        buffer.write(chunk0)
        buffer.write(chunk1)
        buffer.write(chunk2)

        server.enqueue(
            MockResponse()
                .setResponseCode(200)
                .setHeader("content-type", "application/octet-stream")
                .setChunkedBody(buffer, 16)
        )

        val client = createClient()
        val chunks = client.textToSpeech.stream(
            TextToSpeechRequest(
                text = "नमस्ते भारत",
                targetLanguageCode = LanguageCode.HI_IN,
                speaker = Speaker("meera")
            )
        ).toList()

        val totalLength = chunks.sumOf { it.size }
        assertEquals(48, totalLength)

        val concatenated = Buffer()
        chunks.forEach { concatenated.write(it) }
        val expectedHex = "0102030405060708090a0b0c0d0e0f101112131415161718191a1b1c1d1e1f202122232425262728292a2b2c2d2e2f30"
        assertEquals(expectedHex, concatenated.readByteString().hex())
    }

    // 12. rest-tts-base64-decoding
    @Test
    fun `case 12 - rest-tts-base64-decoding`() = runTest {
        val base64Payload = "UklGRiQAAABXQVZFZm10IBAAAAABAAEAQB8AAEAfAAABAAgAZGF0YQAAAAA="
        server.enqueue(
            MockResponse()
                .setResponseCode(200)
                .setHeader("content-type", "application/json")
                .setBody("""{"audios":[{"audio":"$base64Payload"}]}""")
        )

        val client = createClient()
        val response = client.textToSpeech.convert(
            TextToSpeechRequest(
                text = "नमस्ते दुनिया",
                targetLanguageCode = LanguageCode.HI_IN,
                speaker = Speaker("meera"),
                model = TtsModel.BULBUL_V3
            )
        )

        assertEquals(1, response.audioCount)
        assertEquals(base64Payload, response.firstAudioBase64)
        assertEquals(44, response.firstAudioByteLength)
        assertEquals(44, response.audioBytes.size)

        // Magic bytes RIFF (0x52, 0x49, 0x46, 0x46)
        assertEquals('R'.code.toByte(), response.audioBytes[0])
        assertEquals('I'.code.toByte(), response.audioBytes[1])
        assertEquals('F'.code.toByte(), response.audioBytes[2])
        assertEquals('F'.code.toByte(), response.audioBytes[3])
    }

    // 13. sse-chat-v1-stream
    @Test
    fun `case 13 - sse-chat-v1-stream`() = runTest {
        val ssePayload = "data: {\"id\":\"chatcmpl-v1-1\",\"choices\":[{\"index\":0,\"delta\":{\"content\":\"Hi\"}}]}\n\n" +
                "data: {\"id\":\"chatcmpl-v1-1\",\"choices\":[{\"index\":0,\"delta\":{\"content\":\" there!\"}}]}\n\n" +
                "data: [DONE]\n\n"

        server.enqueue(
            MockResponse()
                .setResponseCode(200)
                .setHeader("content-type", "text/event-stream")
                .setBody(ssePayload)
        )

        val client = createClient()
        val chunks = client.chat.completionsStream(
            ChatCompletionRequest(
                model = "sarvam-2b",
                messages = listOf(ChatMessage("user", "Hi"))
            )
        ).toList()

        assertEquals(2, chunks.size)
        val accumulated = chunks.mapNotNull { it.firstDeltaContent }.joinToString("")
        assertEquals("Hi there!", accumulated)
    }

    // 14. sse-chat-v2-empty-choices
    @Test
    fun `case 14 - sse-chat-v2-empty-choices`() = runTest {
        val ssePayload = "data: {\"id\":\"chatcmpl-1\",\"choices\":[{\"index\":0,\"delta\":{\"content\":\"Namaste\"}}]}\n\n" +
                "data: {\"id\":\"chatcmpl-1\",\"choices\":[{\"index\":0,\"delta\":{\"content\":\" world\"}}]}\n\n" +
                "data: {\"id\":\"chatcmpl-1\",\"choices\":[],\"usage\":{\"prompt_tokens\":8,\"completion_tokens\":2,\"total_tokens\":10}}\n\n" +
                "data: [DONE]\n\n"

        server.enqueue(
            MockResponse()
                .setResponseCode(200)
                .setHeader("content-type", "text/event-stream")
                .setBody(ssePayload)
        )

        val client = createClient()
        val chunks = client.chat.completionsV2Stream(
            ChatCompletionRequest(
                model = "sarvam-2b",
                messages = listOf(ChatMessage("user", "Hello"))
            )
        ).toList()

        assertEquals(3, chunks.size)
        val accumulated = chunks.mapNotNull { it.firstDeltaContent }.joinToString("")
        assertEquals("Namaste world", accumulated)

        val usageChunk = chunks[2]
        assertTrue(usageChunk.choices.isEmpty())
        assertNull(usageChunk.firstDeltaContent)
        assertNotNull(usageChunk.usage)
        assertEquals(8, usageChunk.usage?.promptTokens)
        assertEquals(2, usageChunk.usage?.completionTokens)
        assertEquals(10, usageChunk.usage?.totalTokens)
    }

    // 15. sse-responses-api-no-done
    @Test
    fun `case 15 - sse-responses-api-no-done`() = runTest {
        val ssePayload = "event: response.created\n" +
                "data: {\"id\":\"resp_001\",\"type\":\"response.created\"}\n\n" +
                "event: response.output_item.added\n" +
                "data: {\"id\":\"resp_001\",\"type\":\"response.output_item.added\",\"item\":{\"id\":\"item_001\",\"type\":\"message\",\"role\":\"assistant\"}}\n\n" +
                "event: response.content_part.added\n" +
                "data: {\"id\":\"resp_001\",\"type\":\"response.content_part.added\",\"item_id\":\"item_001\",\"part\":{\"type\":\"text\",\"text\":\"Quantum computers use qubits.\"}}\n\n" +
                "event: response.completed\n" +
                "data: {\"id\":\"resp_001\",\"type\":\"response.completed\",\"response\":{\"status\":\"completed\"}}\n\n"

        server.enqueue(
            MockResponse()
                .setResponseCode(200)
                .setHeader("content-type", "text/event-stream")
                .setBody(ssePayload)
        )

        val client = createClient()
        val events = client.responses.createStream(
            ResponsesRequest(
                model = "glm-5.3",
                input = "Explain quantum computing briefly"
            )
        ).toList()

        assertEquals(4, events.size)
        assertTrue(events[0] is ResponseStreamEvent.ResponseCreated)
        assertTrue(events[1] is ResponseStreamEvent.ResponseOutputItemAdded)
        assertTrue(events[2] is ResponseStreamEvent.ResponseContentPartAdded)
        assertTrue(events[3] is ResponseStreamEvent.ResponseCompleted)

        val finalEvent = events[3] as ResponseStreamEvent.ResponseCompleted
        assertEquals("completed", finalEvent.status)
    }

    // 16. ws-stt-invalid-sample-rate
    @Test
    fun `case 16 - ws-stt-invalid-sample-rate`() = runTest {
        val client = createClient()
        try {
            client.speechToText.connect(
                SttRealtimeConfig(
                    languageCode = LanguageCode.HI_IN,
                    sampleRate = 44100
                )
            )
            fail("Expected BadRequestException for invalid sample rate")
        } catch (e: SarvamException.BadRequestException) {
            assertEquals(400, e.statusCode)
            assertTrue(e.message?.contains("sampleRate must be 16000 or 8000") == true)
        }
    }

    // 17. ws-stt-realtime
    @Test
    fun `case 17 - ws-stt-realtime`() = runTest {
        server.enqueue(
            MockResponse().withWebSocketUpgrade(object : WebSocketListener() {
                override fun onMessage(webSocket: WebSocket, text: String) {
                    if (text.contains(""""event":"audio_input"""")) {
                        webSocket.send("""{"event":"session_begin","session_id":"sess_stt_001"}""")
                        webSocket.send("""{"event":"vad_speech_start","timestamp_ms":100}""")
                        webSocket.send("""{"event":"transcript_partial","utterance_idx":0,"text":"नमस्ते","language":"hi-IN"}""")
                        webSocket.send("""{"event":"transcript_final","utterance_idx":0,"text":"नमस्ते!","language":"hi-IN","language_confidence":0.99,"start_s":0.1,"end_s":1.5}""")
                    } else if (text.contains(""""event":"end"""")) {
                        webSocket.send("""{"event":"session_end"}""")
                        webSocket.close(1000, "Normal closure")
                    }
                }
            })
        )

        val client = createClient()
        val session = client.speechToText.connect(
            SttRealtimeConfig(
                languageCode = LanguageCode.HI_IN,
                model = SttModel.SAARAS_V3_REALTIME,
                sampleRate = 16000
            )
        )

        session.sendAudio(byteArrayOf(0, 0, 0, 0))
        session.end()

        val events = session.events.take(5).toList()
        assertEquals(5, events.size)

        assertTrue(events[0] is SttRealtimeEvent.SessionBegin)
        assertEquals("sess_stt_001", (events[0] as SttRealtimeEvent.SessionBegin).sessionId)

        assertTrue(events[1] is SttRealtimeEvent.VadSpeechStart)
        assertEquals(100L, (events[1] as SttRealtimeEvent.VadSpeechStart).timestampMs)

        assertTrue(events[2] is SttRealtimeEvent.TranscriptPartial)
        assertEquals("नमस्ते", (events[2] as SttRealtimeEvent.TranscriptPartial).text)

        assertTrue(events[3] is SttRealtimeEvent.TranscriptFinal)
        val finalTranscript = events[3] as SttRealtimeEvent.TranscriptFinal
        assertEquals("नमस्ते!", finalTranscript.text)
        assertEquals(LanguageCode.HI_IN, finalTranscript.language)
        assertEquals(0.99, finalTranscript.languageConfidence ?: 0.0, 0.001)

        assertTrue(events[4] is SttRealtimeEvent.SessionEnd)

        val recorded = server.takeRequest()
        assertEquals("test-api-key", recorded.getHeader("Api-Subscription-Key"))
        assertTrue(recorded.path?.contains("/speech-to-text-realtime/ws") == true)
        assertTrue(recorded.path?.contains("sample_rate=16000") == true)
    }

    // 18. ws-stt-subprotocol-auth
    @Test
    fun `case 18 - ws-stt-subprotocol-auth`() = runTest {
        server.enqueue(
            MockResponse().withWebSocketUpgrade(object : WebSocketListener() {
                override fun onMessage(webSocket: WebSocket, text: String) {
                    if (text.contains(""""event":"audio_input"""")) {
                        webSocket.send("""{"event":"session_begin","session_id":"sess_subprotocol_001"}""")
                        webSocket.send("""{"event":"transcript_final","utterance_idx":0,"text":"नमस्ते!","language":"hi-IN"}""")
                        webSocket.send("""{"event":"session_end"}""")
                        webSocket.close(1000, "Done")
                    }
                }
            })
        )

        val client = createClient()
        val session = client.speechToText.connect(
            SttRealtimeConfig(
                languageCode = LanguageCode.HI_IN,
                model = SttModel.SAARAS_V3_REALTIME,
                sampleRate = 16000,
                useSubprotocolAuth = true
            )
        )

        session.sendAudio(byteArrayOf(0, 0, 0, 0))

        val events = session.events.take(3).toList()
        assertEquals(3, events.size)
        assertTrue(events[0] is SttRealtimeEvent.SessionBegin)
        assertTrue(events[1] is SttRealtimeEvent.TranscriptFinal)
        assertEquals("नमस्ते!", (events[1] as SttRealtimeEvent.TranscriptFinal).text)
        assertTrue(events[2] is SttRealtimeEvent.SessionEnd)

        val recorded = server.takeRequest()
        assertEquals("api-subscription-key.test-api-key", recorded.getHeader("Sec-WebSocket-Protocol"))
    }

    // 19. ws-tts-streaming
    @Test
    fun `case 19 - ws-tts-streaming`() = runTest {
        server.enqueue(
            MockResponse().withWebSocketUpgrade(object : WebSocketListener() {
                override fun onMessage(webSocket: WebSocket, text: String) {
                    if (text.contains(""""type":"flush"""")) {
                        webSocket.send("""{"type":"audio","data":{"audio":"UklGRiQAAABXQVZFZm10IBAAAAABAAEAQB8AAEAfAAABAAgAZGF0YQAAAAA="}}""")
                        webSocket.send("""{"type":"audio","data":{"audio":"UklGRiQAAABXQVZFZm10IBAAAAABAAEAQB8AAEAfAAABAAgAZGF0YQAAAAA="}}""")
                        webSocket.send("""{"type":"event","data":{"event":"final"}}""")
                        webSocket.close(1000, "Completed")
                    }
                }
            })
        )

        val client = createClient()
        val session = client.textToSpeech.connect(
            TtsStreamingConfig(
                languageCode = LanguageCode.HI_IN,
                speaker = Speaker("simran_en_customer"),
                model = TtsModel.BULBUL_V4_FLASH,
                speechSampleRate = 22050
            )
        )

        session.sendText("नमस्ते भारत")
        session.flush()

        val events = session.events.take(3).toList()
        assertEquals(3, events.size)

        assertTrue(events[0] is TtsStreamEvent.AudioChunk)
        val chunk1 = events[0] as TtsStreamEvent.AudioChunk
        assertEquals(44, chunk1.audioBytes.size)

        assertTrue(events[1] is TtsStreamEvent.AudioChunk)
        val chunk2 = events[1] as TtsStreamEvent.AudioChunk
        assertEquals(44, chunk2.audioBytes.size)

        assertTrue(events[2] is TtsStreamEvent.Completed)

        val recorded = server.takeRequest()
        assertEquals("test-api-key", recorded.getHeader("Api-Subscription-Key"))
        assertTrue(recorded.path?.contains("/text-to-speech/ws") == true)
        assertTrue(recorded.path?.contains("model=bulbul%3Av4-flash") == true || recorded.path?.contains("model=bulbul:v4-flash") == true)
    }
}
