package ai.sarvam

import ai.sarvam.core.RequestOptions
import ai.sarvam.core.SarvamEnvironment
import ai.sarvam.core.auth.ApiKeyAuth
import ai.sarvam.core.auth.AuthToken
import ai.sarvam.core.auth.TokenAuth
import ai.sarvam.core.error.SarvamException
import ai.sarvam.core.io.FileInput
import ai.sarvam.generated.AudioCodec
import ai.sarvam.generated.ChatModel
import ai.sarvam.generated.LanguageCode
import ai.sarvam.generated.Speaker
import ai.sarvam.generated.SttModel
import ai.sarvam.generated.TtsModel
import ai.sarvam.models.ChatCompletionRequest
import ai.sarvam.models.ChatMessage
import ai.sarvam.models.CreateDocumentJobRequest
import ai.sarvam.models.CreateDubbingJobRequest
import ai.sarvam.models.ResponsesRequest
import ai.sarvam.models.SpeechToTextJobInitRequest
import ai.sarvam.models.SpeechToTextJobParameters
import ai.sarvam.models.SttRealtimeConfig
import ai.sarvam.models.TextLidRequest
import ai.sarvam.models.TextToSpeechRequest
import ai.sarvam.models.TranslateRequest
import ai.sarvam.models.TransliterateRequest
import ai.sarvam.models.TtsStreamingConfig
import ai.sarvam.models.VoiceCloneRequest
import kotlinx.coroutines.flow.toList
import kotlinx.coroutines.test.runTest
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.buildJsonObject
import kotlinx.serialization.json.put
import okhttp3.WebSocket
import okhttp3.WebSocketListener
import okhttp3.mockwebserver.MockResponse
import okhttp3.mockwebserver.MockWebServer
import org.junit.After
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertTrue
import org.junit.Assert.fail
import org.junit.Before
import org.junit.Test

class AllResourcesComprehensiveTest {

    private lateinit var server: MockWebServer
    private lateinit var env: SarvamEnvironment
    private lateinit var client: SarvamClient

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
        client = SarvamClient.builder()
            .apiKey("test-key")
            .environment(env)
            .build()
    }

    @After
    fun tearDown() {
        server.shutdown()
    }

    // --- DocAiResource Tests ---

    @Test
    fun `DocAi digitise single and multi with all parameters and options`() = runTest {
        server.enqueue(MockResponse().setResponseCode(200).setBody("""{"job_id":"d1","status":"pending"}"""))
        server.enqueue(MockResponse().setResponseCode(200).setBody("""{"job_id":"d2","status":"pending"}"""))

        val file = FileInput.fromBytes("abc".toByteArray(), "a.pdf", "application/pdf")
        val opts = RequestOptions(headers = mapOf("X-Opt" to "val"), timeoutMillis = 5000L)

        // Multiple files
        val res1 = client.docAi.digitise(
            files = listOf(file),
            uploadIds = listOf("up1"),
            language = "hi",
            contentType = "application/pdf",
            model = "doc-v1",
            options = opts
        )
        assertEquals("d1", res1.jobId)
        val req1 = server.takeRequest()
        assertEquals("val", req1.getHeader("X-Opt"))
        val b1 = req1.body.readUtf8()
        assertTrue(b1.contains("upload_ids"))
        assertTrue(b1.contains("language"))
        assertTrue(b1.contains("content_type"))
        assertTrue(b1.contains("model"))

        // Single file convenience overload
        val res2 = client.docAi.digitise(
            file = file,
            uploadIds = listOf("up2"),
            language = "en",
            contentType = "application/pdf",
            model = "doc-v2",
            options = opts
        )
        assertEquals("d2", res2.jobId)
        server.takeRequest()
    }

    @Test
    fun `DocAi extract with different schema structures and options`() = runTest {
        server.enqueue(MockResponse().setResponseCode(200).setBody("""{"job_id":"e1","status":"pending"}"""))
        server.enqueue(MockResponse().setResponseCode(200).setBody("""{"job_id":"e2","status":"pending"}"""))
        server.enqueue(MockResponse().setResponseCode(200).setBody("""{"job_id":"e3","status":"pending"}"""))
        server.enqueue(MockResponse().setResponseCode(200).setBody("""{"job_id":"e4","status":"pending"}"""))

        val file = FileInput.fromBytes("abc".toByteArray(), "a.pdf", "application/pdf")
        val opts = RequestOptions(headers = mapOf("X-Opt" to "val"))

        // 1. String schema
        client.docAi.extract(
            file = file,
            schema = """{"type":"object"}""",
            uploadIds = listOf("u1"),
            configId = "c1",
            outputFormat = "json",
            classification = "invoice",
            model = "extract-v1",
            options = opts
        )
        val req1 = server.takeRequest()
        val b1 = req1.body.readUtf8()
        assertTrue(b1.contains("name=\"config_id\""))
        assertTrue(b1.contains("name=\"output_format\""))
        assertTrue(b1.contains("name=\"classification\""))
        assertTrue(b1.contains("name=\"model\""))

        // 2. JsonElement schema
        val jsonSchema = buildJsonObject { put("field", "value") }
        client.docAi.extract(files = listOf(file), schema = jsonSchema)
        server.takeRequest()

        // 3. Map with nested primitives, lists, arrays, maps, and nulls
        val complexMap = mapOf(
            "str" to "hello",
            "bool" to true,
            "num" to 123,
            "nil" to null,
            "list" to listOf("a", 1),
            "arr" to arrayOf("b", 2),
            "nested" to mapOf("k" to "v")
        )
        client.docAi.extract(file = file, schema = complexMap)
        server.takeRequest()

        // 4. Other object schema (uses toString)
        client.docAi.extract(file = file, schema = 999)
        server.takeRequest()
    }

    @Test
    fun `DocAi createUploadUrl, getStatus, getResults, getDownloadUrl, digitiseAndWait, extractAndWait`() = runTest {
        server.enqueue(MockResponse().setResponseCode(200).setBody("""{"upload_id":"up_1","url":"https://up.url"}"""))
        server.enqueue(MockResponse().setResponseCode(200).setBody("""{"job_id":"j1","status":"running"}"""))
        server.enqueue(MockResponse().setResponseCode(200).setBody("""{"result":"raw_text"}"""))
        server.enqueue(MockResponse().setResponseCode(200).setBody("""{"url":"https://down.url"}"""))

        val opts = RequestOptions(headers = mapOf("X-Opt" to "1"))

        val upRes = client.docAi.createUploadUrl("application/pdf", opts)
        assertEquals("https://up.url", upRes.url)
        assertEquals("/doc-ai/v1/job/upload", server.takeRequest().path)

        val statusRes = client.docAi.getStatus("j1", opts)
        assertEquals("j1", statusRes.jobId)
        assertEquals("/doc-ai/v1/job/j1/status", server.takeRequest().path)

        val resultsRes = client.docAi.getResults("j1", format = "json", options = opts)
        assertEquals("""{"result":"raw_text"}""", resultsRes)
        assertEquals("/doc-ai/v1/job/j1/results?format=json", server.takeRequest().path)

        val downRes = client.docAi.getDownloadUrl("j1", opts)
        assertEquals("https://down.url", downRes.url)
        assertEquals("/doc-ai/v1/job/j1/download-url", server.takeRequest().path)

        // digitiseAndWait with single file
        server.enqueue(MockResponse().setResponseCode(200).setBody("""{"job_id":"d_wait","status":"pending"}"""))
        server.enqueue(MockResponse().setResponseCode(200).setBody("""{"job_id":"d_wait","status":"completed"}"""))
        val file = FileInput.fromBytes("abc".toByteArray(), "a.pdf")
        val dWait = client.docAi.digitiseAndWait(file = file, pollIntervalMs = 20L, timeoutMs = 2000L)
        assertEquals("completed", dWait.status)
        server.takeRequest() // digitise
        server.takeRequest() // status

        // extractAndWait with single file
        server.enqueue(MockResponse().setResponseCode(200).setBody("""{"job_id":"e_wait","status":"pending"}"""))
        server.enqueue(MockResponse().setResponseCode(200).setBody("""{"job_id":"e_wait","status":"completed"}"""))
        val eWait = client.docAi.extractAndWait(file = file, schema = "{}", pollIntervalMs = 20L, timeoutMs = 2000L)
        assertEquals("completed", eWait.status)
        server.takeRequest() // extract
        server.takeRequest() // status
    }

    // --- SpeechToTextTranslateJobResource Tests ---

    @Test
    fun `SpeechToTextTranslateJob initialise, uploadLinks, start, status, downloadLinks, waitUntilComplete`() = runTest {
        server.enqueue(MockResponse().setResponseCode(202).setBody("""{"job_id":"stt_tr_1","job_state":"Accepted"}"""))
        server.enqueue(MockResponse().setResponseCode(200).setBody("""{"job_id":"stt_tr_1","upload_urls":{"f1":{"file_url":"https://u"}}}"""))
        server.enqueue(MockResponse().setResponseCode(200).setBody("""{"job_id":"stt_tr_1","job_state":"Running"}"""))
        server.enqueue(MockResponse().setResponseCode(200).setBody("""{"job_id":"stt_tr_1","job_state":"Running"}"""))
        server.enqueue(MockResponse().setResponseCode(200).setBody("""{"job_id":"stt_tr_1","job_state":"Completed"}"""))
        server.enqueue(MockResponse().setResponseCode(200).setBody("""{"job_id":"stt_tr_1","download_urls":{"f1":{"file_url":"https://d"}}}"""))

        val opts = RequestOptions(headers = mapOf("X-Custom" to "val"))

        val initRes = client.speechToTextTranslateJob.initialise(
            SpeechToTextJobInitRequest(SpeechToTextJobParameters(model = SttModel.SAARAS_V4)),
            opts
        )
        assertEquals("stt_tr_1", initRes.jobId)

        val upRes = client.speechToTextTranslateJob.getUploadLinks("stt_tr_1", listOf("f1"), opts)
        assertTrue(upRes.uploadUrls.containsKey("f1"))

        val startRes = client.speechToTextTranslateJob.start("stt_tr_1", opts)
        assertEquals("Running", startRes.jobState)

        val statusRes = client.speechToTextTranslateJob.waitUntilComplete("stt_tr_1", pollIntervalMs = 20L, timeoutMs = 2000L, options = opts)
        assertEquals("Completed", statusRes.jobState)

        val downRes = client.speechToTextTranslateJob.getDownloadLinks("stt_tr_1", listOf("f1"), opts)
        assertTrue(downRes.downloadUrls.containsKey("f1"))

        assertEquals("/speech-to-text-translate/job/v1", server.takeRequest().path)
        assertEquals("/speech-to-text-translate/job/v1/upload-files", server.takeRequest().path)
        assertEquals("/speech-to-text-translate/job/v1/stt_tr_1/start", server.takeRequest().path)
        assertEquals("/speech-to-text-translate/job/v1/stt_tr_1/status", server.takeRequest().path)
        assertEquals("/speech-to-text-translate/job/v1/stt_tr_1/status", server.takeRequest().path)
        assertEquals("/speech-to-text-translate/job/v1/download-files", server.takeRequest().path)
    }

    @Test
    fun `SpeechToTextTranslateJob waitUntilComplete throws on failed status`() = runTest {
        server.enqueue(MockResponse().setResponseCode(200).setBody("""{"job_id":"stt_fail","job_state":"Failed"}"""))

        try {
            client.speechToTextTranslateJob.waitUntilComplete("stt_fail", pollIntervalMs = 20L, timeoutMs = 2000L)
            fail("Expected ServerException")
        } catch (e: SarvamException.ServerException) {
            assertEquals("job_failed", e.code)
        }
        server.takeRequest()
    }

    // --- SpeechToTextResource Tests ---

    @Test
    fun `SpeechToText transcribe and translate with full parameters`() = runTest {
        server.enqueue(MockResponse().setResponseCode(200).setBody("""{"transcript":"Hello"}"""))
        server.enqueue(MockResponse().setResponseCode(200).setBody("""{"transcript":"Translated"}"""))

        val file = FileInput.fromBytes("pcm".toByteArray(), "audio.wav", "audio/wav")
        val opts = RequestOptions(headers = mapOf("X-Opt" to "1"))

        val res1 = client.speechToText.transcribe(
            file = file,
            model = SttModel.SAARAS_V4,
            languageCode = LanguageCode.HI_IN,
            prompt = "context prompt",
            withDiarization = true,
            withTimestamps = true,
            options = opts
        )
        assertEquals("Hello", res1.transcript)
        val r1 = server.takeRequest()
        assertEquals("1", r1.getHeader("X-Opt"))
        val b1 = r1.body.readUtf8()
        assertTrue(b1.contains("name=\"with_diarization\""))
        assertTrue(b1.contains("name=\"with_timestamps\""))

        val res2 = client.speechToText.translate(
            file = file,
            model = SttModel.SAARAS_V4,
            prompt = "translate prompt",
            options = opts
        )
        assertEquals("Translated", res2.transcript)
        server.takeRequest()
    }

    @Test
    fun `SpeechToText connect client validation and options`() = runTest {
        // Invalid sample rate
        try {
            client.speechToText.connect(SttRealtimeConfig(sampleRate = 44100))
            fail("Expected BadRequestException for sampleRate 44100")
        } catch (e: SarvamException.BadRequestException) {
            assertEquals("invalid_sample_rate", e.code)
        }

        // Connect with subprotocol auth & Bearer token
        val bearerClient = SarvamClient.builder()
            .authProvider(TokenAuth({ AuthToken("my-jwt-token") }))
            .environment(env)
            .build()

        server.enqueue(MockResponse().withWebSocketUpgrade(object : WebSocketListener() {
            override fun onClosing(webSocket: WebSocket, code: Int, reason: String) {
                webSocket.close(code, reason)
            }
        }))

        val session = bearerClient.speechToText.connect(
            SttRealtimeConfig(
                sampleRate = 8000,
                streamType = "raw",
                useSubprotocolAuth = true,
                threshold = 0.5,
                prompt = "test",
                keyterms = listOf("term1", "term2")
            )
        )
        assertNotNull(session)
        session.close()

        val req = server.takeRequest()
        assertTrue(req.path?.contains("sample_rate=8000") == true)
        assertTrue(req.path?.contains("stream_type=raw") == true)
        assertTrue(req.path?.contains("threshold=0.5") == true)
        assertTrue(req.getHeader("Sec-WebSocket-Protocol")?.contains("bearer.my-jwt-token") == true)
    }

    // --- ChatResource and ChatSession Tests ---

    @Test
    fun `Chat completionsStream, completionsV2, completionsV2Stream, listModels, getModel, ChatSession`() = runTest {
        val ssePayload = "data: {\"id\":\"c1\",\"choices\":[{\"delta\":{\"content\":\"Hello\"}}]}\n\ndata: [DONE]\n\n"
        server.enqueue(MockResponse().setResponseCode(200).setBody(ssePayload))
        server.enqueue(MockResponse().setResponseCode(200).setBody("""{"id":"v2","choices":[{"message":{"role":"assistant","content":"V2 done"}}]}"""))
        server.enqueue(MockResponse().setResponseCode(200).setBody(ssePayload))
        server.enqueue(MockResponse().setResponseCode(200).setBody("""{"models":[{"id":"m1","owned_by":"sarvam"}]}"""))
        server.enqueue(MockResponse().setResponseCode(200).setBody("""{"id":"m1","owned_by":"sarvam"}"""))

        val chatReq = ChatCompletionRequest(
            model = "sarvam-2b",
            messages = listOf(ChatMessage(role = "user", content = "hi"))
        )

        // 1. completionsStream
        val chunks = client.chat.completionsStream(chatReq).toList()
        assertEquals(1, chunks.size)
        assertEquals("Hello", chunks[0].choices.firstOrNull()?.delta?.content)
        assertEquals("/v1/chat/completions", server.takeRequest().path)

        // 2. completionsV2
        val v2Res = client.chat.completionsV2(chatReq)
        assertEquals("V2 done", v2Res.choices.firstOrNull()?.message?.content)
        assertEquals("/v2/chat/completions", server.takeRequest().path)

        // 3. completionsV2Stream
        val v2Chunks = client.chat.completionsV2Stream(chatReq).toList()
        assertEquals(1, v2Chunks.size)
        assertEquals("/v2/chat/completions", server.takeRequest().path)

        // 4. listModels & getModel
        val listRes = client.chat.listModels()
        assertEquals(1, listRes.models.size)
        assertEquals("/v2/models", server.takeRequest().path)

        val modelInfo = client.chat.getModel("m1")
        assertEquals("m1", modelInfo.id)
        assertEquals("/v2/models/m1", server.takeRequest().path)

        // 5. ChatSession with session affinity
        server.enqueue(MockResponse().setResponseCode(200).setBody("""{"id":"s1","choices":[{"message":{"role":"assistant","content":"Session ok"}}]}"""))
        val session = client.chat.createSession("custom-session-123")
        val sessRes = session.completions(chatReq)
        assertEquals("Session ok", sessRes.choices.firstOrNull()?.message?.content)
        val sessReq = server.takeRequest()
        assertEquals("custom-session-123", sessReq.getHeader("x-session-affinity"))

        // ChatSession stream
        server.enqueue(MockResponse().setResponseCode(200).setBody(ssePayload))
        session.completionsStream(chatReq).toList()
        assertEquals("custom-session-123", server.takeRequest().getHeader("x-session-affinity"))

        // ChatSession v2
        server.enqueue(MockResponse().setResponseCode(200).setBody("""{"id":"s2"}"""))
        session.completionsV2(chatReq)
        assertEquals("custom-session-123", server.takeRequest().getHeader("x-session-affinity"))

        // ChatSession v2 stream
        server.enqueue(MockResponse().setResponseCode(200).setBody(ssePayload))
        session.completionsV2Stream(chatReq).toList()
        assertEquals("custom-session-123", server.takeRequest().getHeader("x-session-affinity"))
    }

    // --- VoiceCloningResource Tests ---

    @Test
    fun `VoiceCloning listVoices with filters, createVoice with style, convert with all fields, connect`() = runTest {
        server.enqueue(MockResponse().setResponseCode(200).setBody("""{"status":"success","data":{"voices":[],"total":0}}"""))
        server.enqueue(MockResponse().setResponseCode(200).setBody("""{"status":"success","data":{"voice_id":"v_new"}}"""))
        server.enqueue(MockResponse().setResponseCode(200).setBody("""{"audio":"aGVsbG8=","request_id":"r1"}"""))
        server.enqueue(MockResponse().withWebSocketUpgrade(object : WebSocketListener() {
            override fun onClosing(webSocket: WebSocket, code: Int, reason: String) {
                webSocket.close(code, reason)
            }
        }))

        // listVoices with query params
        client.voiceCloning.listVoices(search = "priya", gender = "female", accent = "indian", limit = 10, offset = 0)
        val r1 = server.takeRequest()
        assertTrue(r1.path?.contains("search=priya") == true)
        assertTrue(r1.path?.contains("gender=female") == true)

        // createVoice with all options
        val file = FileInput.fromBytes("voice".toByteArray(), "sample.wav")
        client.voiceCloning.createVoice(file = file, name = "Priya", language = "hi", style = "neutral", gender = "female")
        val r2 = server.takeRequest()
        val b2 = r2.body.readUtf8()
        assertTrue(b2.contains("name=\"style\""))

        // convert with all optional fields
        client.voiceCloning.convert(
            VoiceCloneRequest(
                text = "Voice clone full test",
                voiceId = "v1",
                pace = 1.1,
                speechSampleRate = 22050,
                enableQc = true,
                enableCachedResponses = false,
                enableVad = true,
                enableTextNormalization = true,
                minAudioDuration = 1.0,
                maxAudioDuration = 5.0,
                refAudioDuration = 3.0,
                refText = "reference text"
            )
        )
        val r3 = server.takeRequest()
        val b3 = r3.body.readUtf8()
        assertTrue(b3.contains("name=\"enable_qc\""))
        assertTrue(b3.contains("name=\"ref_text\""))

        // connect
        val ttsSession = client.voiceCloning.connect("v1")
        assertNotNull(ttsSession)
        ttsSession.close()
        val r4 = server.takeRequest()
        assertTrue(r4.path?.contains("voice_id=v1") == true)
    }

    // --- TextResource Tests ---

    @Test
    fun `TextResource convenience overloads`() = runTest {
        server.enqueue(MockResponse().setResponseCode(200).setBody("""{"translated_text":"नमस्ते"}"""))
        server.enqueue(MockResponse().setResponseCode(200).setBody("""{"transliterated_text":"namaste"}"""))
        server.enqueue(MockResponse().setResponseCode(200).setBody("""{"detected_language":"hi-IN","confidence":0.95}"""))

        val transRes = client.text.translate(
            input = "Hello",
            targetLanguageCode = LanguageCode.HI_IN,
            sourceLanguageCode = LanguageCode.EN_IN
        )
        assertEquals("नमस्ते", transRes.translatedText)
        server.takeRequest()

        val translitRes = client.text.transliterate(
            input = "नमस्ते",
            sourceLanguageCode = LanguageCode.HI_IN,
            targetLanguageCode = LanguageCode.EN_IN
        )
        assertEquals("namaste", translitRes.transliteratedText)
        server.takeRequest()

        val lidRes = client.text.identifyLanguage("नमस्ते दुनिया")
        assertEquals("hi-IN", lidRes.detectedLanguage)
        server.takeRequest()
    }

    // --- TextToSpeechResource Tests ---

    @Test
    fun `TextToSpeech connect WebSocket with options`() = runTest {
        server.enqueue(MockResponse().withWebSocketUpgrade(object : WebSocketListener() {
            override fun onClosing(webSocket: WebSocket, code: Int, reason: String) {
                webSocket.close(code, reason)
            }
        }))

        val session = client.textToSpeech.connect(
            TtsStreamingConfig(model = TtsModel.BULBUL_V2),
            RequestOptions(headers = mapOf("X-TTS-Header" to "true"))
        )
        assertNotNull(session)
        session.close()

        val req = server.takeRequest()
        assertEquals("true", req.getHeader("X-TTS-Header"))
        assertTrue(req.path?.contains("model=bulbul:v2") == true)
    }

    // --- DubbingResource Tests ---

    @Test
    fun `Dubbing start and getExportStatus with limit`() = runTest {
        server.enqueue(MockResponse().setResponseCode(200).setBody("""{"message":"started"}"""))
        server.enqueue(MockResponse().setResponseCode(200).setBody("""{"status":"success","data":{"exports":[]}}"""))

        val startRes = client.dubbing.start("dub_job_1")
        assertEquals("started", startRes.message)
        assertEquals("/dubbing/jobs/dub_job_1/start", server.takeRequest().path)

        val exportRes = client.dubbing.getExportStatus("dub_job_1", limit = 5)
        assertEquals("success", exportRes.status)
        assertEquals("/dubbing/jobs/dub_job_1/export-status?limit=5", server.takeRequest().path)
    }

    // --- ResponsesResource Tests ---

    @Test
    fun `ResponsesResource handles response failed and incomplete stream events`() = runTest {
        val sseFailed = "data: {\"type\":\"response.failed\",\"id\":\"rf1\",\"error\":\"Server overloaded\"}\n\n"
        server.enqueue(MockResponse().setResponseCode(200).setBody(sseFailed))

        val events1 = client.responses.createStream(ResponsesRequest(model = "sarvam-2b", input = "hi")).toList()
        assertEquals(1, events1.size)
        assertTrue(events1[0] is ai.sarvam.models.ResponseStreamEvent.ResponseFailed)
        assertEquals("Server overloaded", (events1[0] as ai.sarvam.models.ResponseStreamEvent.ResponseFailed).error)
        server.takeRequest()

        val sseIncomplete = "data: {\"type\":\"response.incomplete\",\"id\":\"ri1\",\"reason\":\"max_tokens\"}\n\n"
        server.enqueue(MockResponse().setResponseCode(200).setBody(sseIncomplete))

        val events2 = client.responses.createStream(ResponsesRequest(model = "sarvam-2b", input = "hi")).toList()
        assertEquals(1, events2.size)
        assertTrue(events2[0] is ai.sarvam.models.ResponseStreamEvent.ResponseIncomplete)
        assertEquals("max_tokens", (events2[0] as ai.sarvam.models.ResponseStreamEvent.ResponseIncomplete).reason)
        server.takeRequest()
    }

    // --- Additional Resource Tests for Full Coverage ---

    @Test
    fun `DocAi digitiseAndWait and extractAndWait with multi files and direct jobId`() = runTest {
        val file1 = FileInput.fromBytes("abc".toByteArray(), "a.pdf")
        val file2 = FileInput.fromBytes("def".toByteArray(), "b.pdf")

        // 1. digitiseAndWait(files = ...)
        server.enqueue(MockResponse().setResponseCode(200).setBody("""{"job_id":"d_multi","status":"pending"}"""))
        server.enqueue(MockResponse().setResponseCode(200).setBody("""{"job_id":"d_multi","status":"running"}"""))
        server.enqueue(MockResponse().setResponseCode(200).setBody("""{"job_id":"d_multi","status":"completed"}"""))

        val dRes = client.docAi.digitiseAndWait(
            files = listOf(file1, file2),
            uploadIds = listOf("u1"),
            pollIntervalMs = 20L,
            timeoutMs = 2000L
        )
        assertEquals("completed", dRes.status)
        server.takeRequest() // POST digitise
        server.takeRequest() // GET status running
        server.takeRequest() // GET status completed

        // 2. extractAndWait(files = ...)
        server.enqueue(MockResponse().setResponseCode(200).setBody("""{"job_id":"e_multi","status":"pending"}"""))
        server.enqueue(MockResponse().setResponseCode(200).setBody("""{"job_id":"e_multi","status":"completed"}"""))

        val eRes = client.docAi.extractAndWait(
            files = listOf(file1, file2),
            schema = mapOf("key" to "value"),
            pollIntervalMs = 20L,
            timeoutMs = 2000L
        )
        assertEquals("completed", eRes.status)
        server.takeRequest() // POST extract
        server.takeRequest() // GET status completed

        // 3. direct digitiseAndWait(jobId = ...)
        server.enqueue(MockResponse().setResponseCode(200).setBody("""{"job_id":"d_direct","status":"partially_completed"}"""))
        val dDirect = client.docAi.digitiseAndWait("d_direct", pollIntervalMs = 20L, timeoutMs = 2000L)
        assertEquals("partially_completed", dDirect.status)
        server.takeRequest()

        // 4. direct extractAndWait(jobId = ...)
        server.enqueue(MockResponse().setResponseCode(200).setBody("""{"job_id":"e_direct","status":"completed"}"""))
        val eDirect = client.docAi.extractAndWait("e_direct", pollIntervalMs = 20L, timeoutMs = 2000L)
        assertEquals("completed", eDirect.status)
        server.takeRequest()
    }

    @Test
    fun `DocumentTranslation triggerExport, getExportStatus variations, and waitUntilComplete`() = runTest {
        val opts = RequestOptions(headers = mapOf("X-H" to "V"))

        // triggerExport
        server.enqueue(MockResponse().setResponseCode(200).setBody("""{"export_id":"exp_1","job_id":"dj_1"}"""))
        val expRes = client.documentTranslation.triggerExport("dj_1", lang = "hi", format = "docx", options = opts)
        assertEquals("exp_1", expRes.exportId)
        val r1 = server.takeRequest()
        assertTrue(r1.path?.contains("lang=hi") == true)
        assertTrue(r1.path?.contains("format=docx") == true)
        assertEquals("V", r1.getHeader("X-H"))

        // getExportStatus without params
        server.enqueue(MockResponse().setResponseCode(200).setBody("""{"export_id":"exp_1","job_id":"dj_1"}"""))
        val expStatus1 = client.documentTranslation.getExportStatus("dj_1")
        assertEquals("exp_1", expStatus1.exportId)
        assertEquals("/translate/document/jobs/dj_1/export/status", server.takeRequest().path)

        // getExportStatus with lang and exportId
        server.enqueue(MockResponse().setResponseCode(200).setBody("""{"export_id":"exp_2","job_id":"dj_1"}"""))
        val expStatus2 = client.documentTranslation.getExportStatus("dj_1", lang = "hi", exportId = "exp_2", options = opts)
        assertEquals("exp_2", expStatus2.exportId)
        val r2 = server.takeRequest()
        assertTrue(r2.path?.contains("lang=hi") == true)
        assertTrue(r2.path?.contains("export_id=exp_2") == true)

        // waitUntilComplete with PartiallyCompleted
        server.enqueue(MockResponse().setResponseCode(200).setBody("""{"job_id":"dj_1","job_state":"PartiallyCompleted"}"""))
        val liveStatus = client.documentTranslation.waitUntilComplete("dj_1", pollIntervalMs = 20L, timeoutMs = 2000L)
        assertEquals("PartiallyCompleted", liveStatus.jobState)
        server.takeRequest()

        // waitUntilComplete with Failed
        server.enqueue(MockResponse().setResponseCode(200).setBody("""{"job_id":"dj_1","job_state":"Failed"}"""))
        try {
            client.documentTranslation.waitUntilComplete("dj_1", pollIntervalMs = 20L, timeoutMs = 2000L)
            fail("Expected ServerException on Failed")
        } catch (e: SarvamException.ServerException) {
            assertEquals("job_failed", e.code)
        }
        server.takeRequest()
    }

    @Test
    fun `Dubbing waitUntilComplete with success and failures`() = runTest {
        // Success after poll
        server.enqueue(MockResponse().setResponseCode(200).setBody("""{"status":"success","data":{"job_id":"d1","status":"processing"}}"""))
        server.enqueue(MockResponse().setResponseCode(200).setBody("""{"status":"success","data":{"job_id":"d1","status":"completed"}}"""))
        val liveRes = client.dubbing.waitUntilComplete("d1", pollIntervalMs = 20L, timeoutMs = 2000L)
        assertEquals("completed", liveRes.data?.status)
        server.takeRequest()
        server.takeRequest()

        // Failure: partial_failure
        server.enqueue(MockResponse().setResponseCode(200).setBody("""{"status":"success","data":{"job_id":"d1","status":"partial_failure"}}"""))
        try {
            client.dubbing.waitUntilComplete("d1", pollIntervalMs = 20L, timeoutMs = 2000L)
            fail("Expected ServerException on partial_failure")
        } catch (e: SarvamException.ServerException) {
            assertEquals("job_failed", e.code)
        }
        server.takeRequest()

        // Failure: deleted
        server.enqueue(MockResponse().setResponseCode(200).setBody("""{"status":"success","data":{"job_id":"d1","status":"deleted"}}"""))
        try {
            client.dubbing.waitUntilComplete("d1", pollIntervalMs = 20L, timeoutMs = 2000L)
            fail("Expected ServerException on deleted")
        } catch (e: SarvamException.ServerException) {
            assertEquals("job_failed", e.code)
        }
        server.takeRequest()
    }

    @Test
    fun `SpeechToTextJob start with ptuId, getStatus, getDownloadLinks, waitUntilComplete failure`() = runTest {
        val opts = RequestOptions(headers = mapOf("X-Test" to "1"))

        // start with ptuId
        server.enqueue(MockResponse().setResponseCode(200).setBody("""{"job_id":"stt_j1","job_state":"Running"}"""))
        val startRes = client.speechToTextJob.start("stt_j1", ptuId = "ptu_123", options = opts)
        assertEquals("Running", startRes.jobState)
        val r1 = server.takeRequest()
        assertTrue(r1.path?.contains("ptu_id=ptu_123") == true)
        assertEquals("1", r1.getHeader("X-Test"))

        // getStatus
        server.enqueue(MockResponse().setResponseCode(200).setBody("""{"job_id":"stt_j1","job_state":"Running"}"""))
        val statusRes = client.speechToTextJob.getStatus("stt_j1", opts)
        assertEquals("Running", statusRes.jobState)
        assertEquals("/speech-to-text/job/v1/stt_j1/status", server.takeRequest().path)

        // getDownloadLinks
        server.enqueue(MockResponse().setResponseCode(200).setBody("""{"job_id":"stt_j1","download_urls":{"f1":{"file_url":"https://d"}}}"""))
        val downRes = client.speechToTextJob.getDownloadLinks("stt_j1", listOf("f1"), opts)
        assertEquals("https://d", downRes.downloadUrls["f1"]?.fileUrl)
        server.takeRequest()

        // waitUntilComplete with Failed
        server.enqueue(MockResponse().setResponseCode(200).setBody("""{"job_id":"stt_j1","job_state":"Failed"}"""))
        try {
            client.speechToTextJob.waitUntilComplete("stt_j1", pollIntervalMs = 20L, timeoutMs = 2000L)
            fail("Expected ServerException on Failed")
        } catch (e: SarvamException.ServerException) {
            assertEquals("job_failed", e.code)
        }
        server.takeRequest()
    }

    @Test
    fun `PronunciationDictionary list, create, update, delete`() = runTest {
        val opts = RequestOptions(headers = mapOf("X-Dict" to "true"))
        val file = FileInput.fromBytes("dict data".toByteArray(), "dict.json")

        // list
        server.enqueue(MockResponse().setResponseCode(200).setBody("""{"dictionary_count":1,"dictionaries":["d1"]}"""))
        val listRes = client.pronunciationDictionary.list(opts)
        assertEquals(1, listRes.dictionaryCount)
        assertEquals("true", server.takeRequest().getHeader("X-Dict"))

        // create
        server.enqueue(MockResponse().setResponseCode(200).setBody("""{"dictionary_id":"dict_new"}"""))
        val createRes = client.pronunciationDictionary.create(file, opts)
        assertEquals("dict_new", createRes.dictionaryId)
        val r2 = server.takeRequest()
        assertEquals("POST", r2.method)
        assertEquals("true", r2.getHeader("X-Dict"))

        // update
        server.enqueue(MockResponse().setResponseCode(200).setBody("""{"dictionary_id":"dict_new","updated_pronunciations":{}}"""))
        val updateRes = client.pronunciationDictionary.update("dict_new", file, opts)
        assertEquals("dict_new", updateRes.dictionaryId)
        val r3 = server.takeRequest()
        assertEquals("PUT", r3.method)
        assertTrue(r3.path?.contains("dict_id=dict_new") == true)

        // delete
        server.enqueue(MockResponse().setResponseCode(200).setBody("""{"success":true,"message":"deleted"}"""))
        val delRes = client.pronunciationDictionary.delete("dict_new", opts)
        assertTrue(delRes.success)
        val r4 = server.takeRequest()
        assertEquals("DELETE", r4.method)
        assertTrue(r4.path?.contains("dict_id=dict_new") == true)
    }

    @Test
    fun `VoiceCloning getVoice, deleteVoice, and stream`() = runTest {
        val opts = RequestOptions(headers = mapOf("X-VC" to "1"))

        // getVoice
        server.enqueue(MockResponse().setResponseCode(200).setBody("""{"status":"ok","data":{"id":"v1","name":"Priya"}}"""))
        val vDetail = client.voiceCloning.getVoice("v1", opts)
        assertEquals("Priya", vDetail.data?.name)
        val r1 = server.takeRequest()
        assertEquals("/voices/v1", r1.path)
        assertEquals("1", r1.getHeader("X-VC"))

        // deleteVoice
        server.enqueue(MockResponse().setResponseCode(200).setBody("{}"))
        client.voiceCloning.deleteVoice("v1", opts)
        val r2 = server.takeRequest()
        assertEquals("DELETE", r2.method)
        assertEquals("/voices/delete/v1", r2.path)

        // stream
        server.enqueue(MockResponse().setResponseCode(200).setBody("audiochunk1audiochunk2"))
        val req = VoiceCloneRequest(text = "streaming test")
        val chunks = client.voiceCloning.stream(req, opts).toList()
        assertTrue(chunks.isNotEmpty())
        val combined = chunks.fold(ByteArray(0)) { acc, bytes -> acc + bytes }
        assertEquals("audiochunk1audiochunk2", String(combined))
        server.takeRequest()
    }

    @Test
    fun `SpeechToText transcribe and translate minimal, and connect with query params`() = runTest {
        val file = FileInput.fromBytes("abc".toByteArray(), "test.wav")

        // transcribe minimal
        server.enqueue(MockResponse().setResponseCode(200).setBody("""{"transcript":"min transcribe"}"""))
        val tRes = client.speechToText.transcribe(file)
        assertEquals("min transcribe", tRes.transcript)
        server.takeRequest()

        // translate minimal
        server.enqueue(MockResponse().setResponseCode(200).setBody("""{"transcript":"min translate"}"""))
        val trRes = client.speechToText.translate(file)
        assertEquals("min translate", trRes.transcript)
        server.takeRequest()

        // connect with custom credentials & all query params
        val customAuthClient = SarvamClient.builder()
            .authProvider(object : ai.sarvam.core.auth.AuthProvider {
                override suspend fun getCredentials(): ai.sarvam.core.auth.SarvamCredentials =
                    ai.sarvam.core.auth.SarvamCredentials.CustomHeaders(mapOf("X-Custom-Auth" to "custom-val"))
            })
            .environment(env)
            .build()

        server.enqueue(MockResponse().withWebSocketUpgrade(object : WebSocketListener() {
            override fun onClosing(webSocket: WebSocket, code: Int, reason: String) {
                webSocket.close(code, reason)
            }
        }))

        val session = customAuthClient.speechToText.connect(
            SttRealtimeConfig(
                languageCode = LanguageCode.HI_IN,
                model = SttModel.SAARAS_V4,
                sampleRate = 16000,
                mode = ai.sarvam.generated.SttMode.TRANSCRIBE,
                encoding = "linear16",
                returnTimestamps = true,
                endpointing = false,
                prefixPaddingMs = 150,
                silenceDurationMs = 400,
                minSpeechDurationMs = 250,
                useSubprotocolAuth = false
            ),
            RequestOptions(headers = mapOf("X-Extra" to "val"))
        )
        assertNotNull(session)
        session.close()

        val req = server.takeRequest()
        assertEquals("custom-val", req.getHeader("X-Custom-Auth"))
        assertEquals("val", req.getHeader("X-Extra"))
        assertTrue(req.path?.contains("mode=transcribe") == true)
        assertTrue(req.path?.contains("encoding=linear16") == true)
        assertTrue(req.path?.contains("return_timestamps=true") == true)
        assertTrue(req.path?.contains("endpointing=false") == true)
        assertTrue(req.path?.contains("prefix_padding_ms=150") == true)
        assertTrue(req.path?.contains("silence_duration_ms=400") == true)
        assertTrue(req.path?.contains("min_speech_duration_ms=250") == true)
    }

    @Test
    fun `SarvamClient Builder and Companion full coverage`() {
        val clientFromApiKey = SarvamClient("my-api-key")
        assertNotNull(clientFromApiKey.text)

        val clientFromAuth = SarvamClient(ApiKeyAuth("my-api-key"))
        assertNotNull(clientFromAuth.speechToText)

        val customClient = SarvamClient.builder()
            .apiKey("key")
            .apiBaseUrl("http://localhost:8080/v1/")
            .wsBaseUrl("ws://localhost:8080/ws/")
            .maxRetries(3)
            .baseBackoffMs(200L)
            .maxBackoffMs(4000L)
            .logLevel(ai.sarvam.core.middleware.LogLevel.HEADERS)
            .clock(ai.sarvam.core.util.SystemClock)
            .randomSource(ai.sarvam.core.util.DefaultRandomSource)
            .build()

        assertNotNull(customClient.chat)
        assertNotNull(customClient.documentTranslation)
        assertNotNull(customClient.dubbing)
        assertNotNull(customClient.jobs)
        assertNotNull(customClient.pronunciationDictionary)
        assertNotNull(customClient.responses)
        assertNotNull(customClient.speechToTextJob)
        assertNotNull(customClient.speechToTextTranslateJob)
        assertNotNull(customClient.textToSpeech)
        assertNotNull(customClient.voiceCloning)
        assertNotNull(customClient.docAi)
    }
}

