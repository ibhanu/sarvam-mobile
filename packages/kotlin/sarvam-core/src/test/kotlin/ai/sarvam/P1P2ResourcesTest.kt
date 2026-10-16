package ai.sarvam

import ai.sarvam.core.SarvamEnvironment
import ai.sarvam.core.error.SarvamException
import ai.sarvam.core.error.TimeoutPhase
import ai.sarvam.core.io.FileInput
import ai.sarvam.core.util.Clock
import ai.sarvam.generated.AudioCodec
import ai.sarvam.generated.LanguageCode
import ai.sarvam.generated.SttModel
import ai.sarvam.generated.TtsModel
import ai.sarvam.models.CreateDocumentJobRequest
import ai.sarvam.models.CreateDubbingJobRequest
import ai.sarvam.models.SpeechToTextJobInitRequest
import ai.sarvam.models.SpeechToTextJobParameters
import ai.sarvam.models.VoiceCloneRequest
import ai.sarvam.models.VoiceCloneResponse
import ai.sarvam.resources.JobPoller
import kotlinx.coroutines.flow.toList
import kotlinx.coroutines.test.runTest
import okhttp3.mockwebserver.MockResponse
import okhttp3.mockwebserver.MockWebServer
import org.junit.After
import org.junit.Assert.assertArrayEquals
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertTrue
import org.junit.Assert.fail
import org.junit.Before
import org.junit.Test
import java.util.Base64
import java.util.concurrent.atomic.AtomicInteger

class P1P2ResourcesTest {

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
            .apiKey("test-api-key")
            .environment(env)
            .build()
    }

    @After
    fun tearDown() {
        server.shutdown()
    }

    // --- 1. JobPoller Tests ---

    @Test
    fun `JobPoller polls until complete`() = runTest {
        val clock = object : Clock {
            var time = 0L
            override fun currentTimeMillis(): Long = time
        }
        val poller = JobPoller(clock = clock, sleeper = { clock.time += it })
        val count = AtomicInteger(0)

        val result = poller.waitUntilComplete(
            jobId = "job_123",
            pollIntervalMs = 1000L,
            timeoutMs = 10_000L,
            fetchStatus = { id ->
                val c = count.incrementAndGet()
                if (c < 3) "pending" else "completed"
            },
            isTerminal = { it == "completed" }
        )

        assertEquals("completed", result)
        assertEquals(3, count.get())
        assertEquals(2000L, clock.time)
    }

    @Test
    fun `JobPoller throws ServerException when isFailed matches`() = runTest {
        val clock = object : Clock {
            var time = 0L
            override fun currentTimeMillis(): Long = time
        }
        val poller = JobPoller(clock = clock, sleeper = { clock.time += it })

        try {
            poller.waitUntilComplete(
                jobId = "job_failed_1",
                pollIntervalMs = 1000L,
                timeoutMs = 10_000L,
                fetchStatus = { "failed" },
                isTerminal = { it == "completed" || it == "failed" },
                isFailed = { it == "failed" }
            )
            fail("Expected ServerException on failed job")
        } catch (e: SarvamException.ServerException) {
            assertEquals("job_failed", e.code)
            assertTrue(e.message?.contains("failed with terminal status") == true)
        }
    }

    @Test
    fun `JobPoller throws TimeoutException when timeout exceeded`() = runTest {
        val clock = object : Clock {
            var time = 0L
            override fun currentTimeMillis(): Long = time
        }
        val poller = JobPoller(clock = clock, sleeper = { clock.time += it })

        try {
            poller.waitUntilComplete(
                jobId = "job_timeout",
                pollIntervalMs = 1000L,
                timeoutMs = 2500L,
                fetchStatus = { "running" },
                isTerminal = { it == "completed" }
            )
            fail("Expected TimeoutException")
        } catch (e: SarvamException.TimeoutException) {
            assertEquals(TimeoutPhase.TOTAL, e.phase)
            assertTrue(e.message?.contains("timed out after 2500ms") == true)
        }
    }

    // --- 2. VoiceCloning Resource Tests ---

    @Test
    fun `VoiceCloning convert decodes audioBytes from root audio`() = runTest {
        val rawPcm = "hello-voice-clone".toByteArray()
        val b64 = Base64.getEncoder().encodeToString(rawPcm)
        server.enqueue(
            MockResponse()
                .setResponseCode(200)
                .setBody("""{"audio":"$b64","audio_b64":"$b64","request_id":"req_vc_1","audio_duration":2.5}""")
        )

        val response = client.voiceCloning.convert(
            VoiceCloneRequest(
                text = "Namaste",
                voiceId = "svc-1234",
                languageCode = LanguageCode.HI_IN,
                outputAudioCodec = AudioCodec.WAV
            )
        )

        val recorded = server.takeRequest()
        assertEquals("/voices/clone", recorded.path)
        assertEquals("POST", recorded.method)
        assertTrue(recorded.body.readUtf8().contains("Namaste"))
        assertEquals("req_vc_1", response.requestId)
        assertArrayEquals(rawPcm, response.audioBytes)
    }

    @Test
    fun `VoiceCloning stream returns Flow of ByteArray`() = runTest {
        val audioBytes = byteArrayOf(1, 2, 3, 4, 5)
        server.enqueue(
            MockResponse()
                .setResponseCode(200)
                .setHeader("Content-Type", "application/octet-stream")
                .setBody(okio.Buffer().write(audioBytes))
        )

        val flow = client.voiceCloning.stream(
            VoiceCloneRequest(text = "Streaming clone test")
        )
        val chunks = flow.toList()
        val combined = chunks.reduce { acc, bytes -> acc + bytes }
        assertArrayEquals(audioBytes, combined)

        val recorded = server.takeRequest()
        assertEquals("/voices/clone/stream", recorded.path)
    }

    @Test
    fun `VoiceCloning list, get, and delete voices`() = runTest {
        server.enqueue(
            MockResponse()
                .setResponseCode(200)
                .setBody("""{"status":"success","data":{"voices":[{"id":"v1","name":"Voice 1"}],"total":1}}""")
        )
        server.enqueue(
            MockResponse()
                .setResponseCode(200)
                .setBody("""{"status":"success","data":{"id":"v1","name":"Voice 1","status":"active"}}""")
        )
        server.enqueue(MockResponse().setResponseCode(204))

        val list = client.voiceCloning.listVoices()
        assertEquals(1, list.data?.voices?.size)
        assertEquals("v1", list.data?.voices?.first()?.id)

        val detail = client.voiceCloning.getVoice("v1")
        assertEquals("v1", detail.data?.id)

        client.voiceCloning.deleteVoice("v1")

        assertEquals("/voices", server.takeRequest().path)
        assertEquals("/voices/v1", server.takeRequest().path)
        val deleteReq = server.takeRequest()
        assertEquals("/voices/delete/v1", deleteReq.path)
        assertEquals("DELETE", deleteReq.method)
    }

    // --- 3. DocAI Resource Tests ---

    @Test
    fun `DocAi extract auto-serializes schema Map and JsonObject to JSON string field`() = runTest {
        server.enqueue(
            MockResponse()
                .setResponseCode(201)
                .setBody("""{"job_id":"doc_job_1","status":"pending","run_id":"run_1"}""")
        )

        val schemaMap = mapOf(
            "title" to "Invoice",
            "type" to "object",
            "properties" to mapOf(
                "total" to mapOf("type" to "number"),
                "vendor" to mapOf("type" to "string")
            )
        )

        val file = FileInput.fromBytes("sample invoice text".toByteArray(), "invoice.pdf", "application/pdf")
        val response = client.docAi.extract(
            file = file,
            schema = schemaMap
        )

        assertEquals("doc_job_1", response.jobId)

        val recorded = server.takeRequest()
        assertEquals("/doc-ai/v1/job/extract", recorded.path)
        val bodyStr = recorded.body.readUtf8()
        assertTrue(bodyStr.contains("name=\"schema\""))
        assertTrue(bodyStr.contains("\"title\":\"Invoice\""))
        assertTrue(bodyStr.contains("name=\"file\"; filename=\"invoice.pdf\""))
    }

    @Test
    fun `DocAi digitise sends multiple file parts and digitiseAndWait polls until terminal`() = runTest {
        server.enqueue(
            MockResponse()
                .setResponseCode(201)
                .setBody("""{"job_id":"doc_digitise_1","status":"pending"}""")
        )
        server.enqueue(
            MockResponse()
                .setResponseCode(200)
                .setBody("""{"job_id":"doc_digitise_1","status":"running"}""")
        )
        server.enqueue(
            MockResponse()
                .setResponseCode(200)
                .setBody("""{"job_id":"doc_digitise_1","status":"completed","usage":{"pages":2}}""")
        )

        val file1 = FileInput.fromBytes("page1".toByteArray(), "p1.pdf", "application/pdf")
        val file2 = FileInput.fromBytes("page2".toByteArray(), "p2.pdf", "application/pdf")

        val result = client.docAi.digitiseAndWait(
            files = listOf(file1, file2),
            pollIntervalMs = 50L,
            timeoutMs = 5000L
        )

        assertEquals("doc_digitise_1", result.jobId)
        assertEquals("completed", result.status)
        assertTrue(result.isTerminal)
        assertTrue(result.isSuccessful)

        val initReq = server.takeRequest()
        assertEquals("/doc-ai/v1/job/digitise", initReq.path)
        val bodyStr = initReq.body.readUtf8()
        assertTrue(bodyStr.contains("filename=\"p1.pdf\""))
        assertTrue(bodyStr.contains("filename=\"p2.pdf\""))

        assertEquals("/doc-ai/v1/job/doc_digitise_1/status", server.takeRequest().path)
        assertEquals("/doc-ai/v1/job/doc_digitise_1/status", server.takeRequest().path)
    }

    // --- 4. PronunciationDictionary Resource Tests ---

    @Test
    fun `PronunciationDictionary list, create, update, get, delete`() = runTest {
        server.enqueue(
            MockResponse()
                .setResponseCode(200)
                .setBody("""{"dictionary_count":1,"dictionaries":["p_123"]}""")
        )
        server.enqueue(
            MockResponse()
                .setResponseCode(200)
                .setBody("""{"dictionary_id":"p_123"}""")
        )
        server.enqueue(
            MockResponse()
                .setResponseCode(200)
                .setBody("""{"dictionary_id":"p_123","updated_pronunciations":{"hi-IN":{"word":"pron"}}}""")
        )
        server.enqueue(
            MockResponse()
                .setResponseCode(200)
                .setBody("""{"pronunciations":{"hi-IN":{"word":"pron"}}}""")
        )
        server.enqueue(
            MockResponse()
                .setResponseCode(200)
                .setBody("""{"success":true,"message":"Dictionary deleted"}""")
        )

        val list = client.pronunciationDictionary.list()
        assertEquals(1, list.dictionaryCount)

        val file = FileInput.fromBytes("word,pron".toByteArray(), "dict.csv", "text/csv")
        val created = client.pronunciationDictionary.create(file)
        assertEquals("p_123", created.dictionaryId)

        val updated = client.pronunciationDictionary.update("p_123", file)
        assertEquals("p_123", updated.dictionaryId)

        val fetched = client.pronunciationDictionary.get("p_123")
        assertTrue(fetched.pronunciations.containsKey("hi-IN"))

        val deleted = client.pronunciationDictionary.delete("p_123")
        assertTrue(deleted.success)

        assertEquals("/text-to-speech/pronunciation-dictionary", server.takeRequest().path)
        assertEquals("/text-to-speech/pronunciation-dictionary", server.takeRequest().path)
        val putReq = server.takeRequest()
        assertEquals("/text-to-speech/pronunciation-dictionary?dict_id=p_123", putReq.path)
        assertEquals("PUT", putReq.method)
        assertEquals("/text-to-speech/pronunciation-dictionary/p_123", server.takeRequest().path)
        val delReq = server.takeRequest()
        assertEquals("/text-to-speech/pronunciation-dictionary?dict_id=p_123", delReq.path)
        assertEquals("DELETE", delReq.method)
    }

    // --- 5. STT Job & STT Translate Job Tests ---

    @Test
    fun `SpeechToTextJob initialise, getUploadLinks, start, getStatus, getDownloadLinks, waitUntilComplete`() = runTest {
        server.enqueue(
            MockResponse()
                .setResponseCode(202)
                .setBody("""{"job_id":"stt_job_1","job_state":"Accepted"}""")
        )
        server.enqueue(
            MockResponse()
                .setResponseCode(200)
                .setBody("""{"job_id":"stt_job_1","job_state":"Accepted","upload_urls":{"f1.wav":{"file_url":"https://upload.url"}}}""")
        )
        server.enqueue(
            MockResponse()
                .setResponseCode(200)
                .setBody("""{"job_id":"stt_job_1","job_state":"Running"}""")
        )
        server.enqueue(
            MockResponse()
                .setResponseCode(200)
                .setBody("""{"job_id":"stt_job_1","job_state":"Running"}""")
        )
        server.enqueue(
            MockResponse()
                .setResponseCode(200)
                .setBody("""{"job_id":"stt_job_1","job_state":"Completed","total_files":1,"successful_files_count":1}""")
        )
        server.enqueue(
            MockResponse()
                .setResponseCode(200)
                .setBody("""{"job_id":"stt_job_1","job_state":"Completed","download_urls":{"f1.json":{"file_url":"https://download.url"}}}""")
        )

        val initRes = client.speechToTextJob.initialise(
            SpeechToTextJobInitRequest(
                jobParameters = SpeechToTextJobParameters(
                    model = SttModel.SAARAS_V4,
                    languageCode = LanguageCode.HI_IN
                )
            )
        )
        assertEquals("stt_job_1", initRes.jobId)

        val uploadRes = client.speechToTextJob.getUploadLinks("stt_job_1", listOf("f1.wav"))
        assertTrue(uploadRes.uploadUrls.containsKey("f1.wav"))

        val startRes = client.speechToTextJob.start("stt_job_1")
        assertEquals("Running", startRes.jobState)

        val completedStatus = client.speechToTextJob.waitUntilComplete(
            jobId = "stt_job_1",
            pollIntervalMs = 50L,
            timeoutMs = 5000L
        )
        assertEquals("Completed", completedStatus.jobState)

        val downloadRes = client.speechToTextJob.getDownloadLinks("stt_job_1", listOf("f1.json"))
        assertTrue(downloadRes.downloadUrls.containsKey("f1.json"))

        assertEquals("/speech-to-text/job/v1", server.takeRequest().path)
        assertEquals("/speech-to-text/job/v1/upload-files", server.takeRequest().path)
        assertEquals("/speech-to-text/job/v1/stt_job_1/start", server.takeRequest().path)
        assertEquals("/speech-to-text/job/v1/stt_job_1/status", server.takeRequest().path)
        assertEquals("/speech-to-text/job/v1/stt_job_1/status", server.takeRequest().path)
        assertEquals("/speech-to-text/job/v1/download-files", server.takeRequest().path)
    }

    // --- 6. DocumentTranslation Tests ---

    @Test
    fun `DocumentTranslation create, start, live-status, triggerExport, getExportStatus, waitUntilComplete`() = runTest {
        server.enqueue(
            MockResponse()
                .setResponseCode(201)
                .setBody("""{"job_id":"doc_trans_1","upload_url":"https://upload.url"}""")
        )
        server.enqueue(
            MockResponse()
                .setResponseCode(200)
                .setBody("""{"job_id":"doc_trans_1","message":"started"}""")
        )
        server.enqueue(
            MockResponse()
                .setResponseCode(200)
                .setBody("""{"job_id":"doc_trans_1","job_state":"Completed","progress":100}""")
        )
        server.enqueue(
            MockResponse()
                .setResponseCode(202)
                .setBody("""{"export_id":"exp_1","job_id":"doc_trans_1","export_state":"Pending"}""")
        )
        server.enqueue(
            MockResponse()
                .setResponseCode(200)
                .setBody("""{"export_id":"exp_1","job_id":"doc_trans_1","export_state":"Completed","download_url":"https://download.url"}""")
        )

        val created = client.documentTranslation.create(
            CreateDocumentJobRequest(
                originalFilename = "doc.pdf",
                sourceLanguageCode = LanguageCode.EN_IN,
                targetLanguageCodes = listOf(LanguageCode.HI_IN)
            )
        )
        assertEquals("doc_trans_1", created.jobId)

        val started = client.documentTranslation.start("doc_trans_1")
        assertEquals("doc_trans_1", started.jobId)

        val liveStatus = client.documentTranslation.waitUntilComplete(
            jobId = "doc_trans_1",
            pollIntervalMs = 50L,
            timeoutMs = 5000L
        )
        assertEquals("Completed", liveStatus.jobState)

        val triggerRes = client.documentTranslation.triggerExport("doc_trans_1", "hi-IN", "pdf")
        assertEquals("exp_1", triggerRes.exportId)

        val exportStatus = client.documentTranslation.getExportStatus("doc_trans_1", "hi-IN", "exp_1")
        assertEquals("Completed", exportStatus.exportState)

        assertEquals("/translate/document/jobs", server.takeRequest().path)
        assertEquals("/translate/document/jobs/doc_trans_1/start", server.takeRequest().path)
        assertEquals("/translate/document/jobs/doc_trans_1/live-status", server.takeRequest().path)
        assertEquals("/translate/document/jobs/doc_trans_1/export?lang=hi-IN&format=pdf", server.takeRequest().path)
        assertEquals("/translate/document/jobs/doc_trans_1/export/status?lang=hi-IN&export_id=exp_1", server.takeRequest().path)
    }

    // --- 7. Dubbing Resource Tests ---

    @Test
    fun `Dubbing routes to EnvironmentHost DUBBING and serializes wire field aliases src_lang and target_langs`() = runTest {
        server.enqueue(
            MockResponse()
                .setResponseCode(200)
                .setBody("""{"status":"success","data":{"job_id":"dub_1","upload_url":"https://upload.url"}}""")
        )
        server.enqueue(
            MockResponse()
                .setResponseCode(200)
                .setBody("""{"status":"success","data":{"job_id":"dub_1","status":"completed","progress":100}}""")
        )

        val created = client.dubbing.create(
            CreateDubbingJobRequest(
                sourceLanguageCode = LanguageCode.EN_IN,
                targetLanguageCodes = listOf(LanguageCode.HI_IN, LanguageCode.TE_IN),
                jobName = "Dubbing test"
            )
        )

        assertEquals("dub_1", created.data?.jobId)

        val recorded = server.takeRequest()
        // Dubbing base url is /dubbing, endpoint is /jobs -> path is /dubbing/jobs!
        assertEquals("/dubbing/jobs", recorded.path)
        assertEquals("POST", recorded.method)

        val body = recorded.body.readUtf8()
        // Check wire aliases
        assertTrue(body.contains("\"src_lang\":\"en-IN\""))
        assertTrue(body.contains("\"target_langs\":[\"hi-IN\",\"te-IN\"]"))
        assertTrue(body.contains("\"job_name\":\"Dubbing test\""))

        // Polling live status
        val liveStatus = client.dubbing.waitUntilComplete(
            jobId = "dub_1",
            pollIntervalMs = 50L,
            timeoutMs = 5000L
        )
        assertEquals("completed", liveStatus.data?.status)
        assertEquals("/dubbing/jobs/dub_1/live-status", server.takeRequest().path)
    }
}
