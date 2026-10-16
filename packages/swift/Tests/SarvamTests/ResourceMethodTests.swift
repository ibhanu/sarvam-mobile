import Foundation
import Testing
@testable import Sarvam

@Suite("All Resource Methods Comprehensive Tests")
struct ResourceMethodTests {
    private func makeClient(transport: MockHTTPTransport, clock: MockClockProvider = MockClockProvider()) -> SarvamClient {
        SarvamClient(
            authProvider: ApiKeyAuth(apiKey: "test-api-key"),
            transport: transport,
            clock: clock
        )
    }

    // MARK: - SpeechToTextTranslateJobResource Tests (All 6 Methods + Decoding Errors)
    @Test("SpeechToTextTranslateJobResource all 6 methods and decoding error handling")
    func testSpeechToTextTranslateJobAllMethods() async throws {
        let transport = MockHTTPTransport()
        let clock = MockClockProvider()
        let client = makeClient(transport: transport, clock: clock)

        // 1. initialise
        transport.queueResponse(HTTPResponse(statusCode: 200, headers: [:], body: Data("{\"job_id\":\"tr-1\",\"job_state\":\"created\"}".utf8)))
        let initResp = try await client.speechToTextTranslateJob.initialise(
            SpeechToTextTranslateJobInitRequest(jobParameters: SpeechToTextTranslateJobParameters()),
            options: RequestOptions(headers: ["X-Test": "1"], timeoutInterval: 10, idempotencyKey: "k1")
        )
        #expect(initResp.jobId == "tr-1")

        // 2. getUploadLinks
        transport.queueResponse(HTTPResponse(statusCode: 200, headers: [:], body: Data("{\"job_id\":\"tr-1\",\"job_state\":\"pending\",\"upload_urls\":{}}".utf8)))
        let uploadResp = try await client.speechToTextTranslateJob.getUploadLinks(
            FilesRequest(jobId: "tr-1", files: ["f1.wav"]),
            options: RequestOptions(idempotencyKey: "k2")
        )
        #expect(uploadResp.jobId == "tr-1")

        // 3. start
        transport.queueResponse(HTTPResponse(statusCode: 200, headers: [:], body: Data("{\"job_id\":\"tr-1\",\"job_state\":\"in_progress\"}".utf8)))
        let startResp = try await client.speechToTextTranslateJob.start(
            jobId: "tr-1",
            options: RequestOptions(idempotencyKey: "k3")
        )
        #expect(startResp.jobState == "in_progress")

        // 4. getStatus
        transport.queueResponse(HTTPResponse(statusCode: 200, headers: [:], body: Data("{\"job_id\":\"tr-1\",\"job_state\":\"completed\"}".utf8)))
        let statusResp = try await client.speechToTextTranslateJob.getStatus(jobId: "tr-1")
        #expect(statusResp.jobState == "completed")

        // 5. getDownloadLinks
        transport.queueResponse(HTTPResponse(statusCode: 200, headers: [:], body: Data("{\"job_id\":\"tr-1\",\"job_state\":\"completed\",\"download_urls\":{}}".utf8)))
        let downloadResp = try await client.speechToTextTranslateJob.getDownloadLinks(FilesRequest(jobId: "tr-1", files: ["f1.json"]))
        #expect(downloadResp.jobId == "tr-1")

        // 6. waitUntilComplete
        transport.queueResponse(HTTPResponse(statusCode: 200, headers: [:], body: Data("{\"job_id\":\"tr-1\",\"job_state\":\"in_progress\"}".utf8)))
        transport.queueResponse(HTTPResponse(statusCode: 200, headers: [:], body: Data("{\"job_id\":\"tr-1\",\"job_state\":\"completed\"}".utf8)))
        let completeResp = try await client.speechToTextTranslateJob.waitUntilComplete(
            jobId: "tr-1",
            pollingOptions: PollingOptions(pollInterval: 0.05, timeoutInterval: 5.0)
        )
        #expect(completeResp.jobState == "completed")

        // Decoding errors
        transport.queueResponse(HTTPResponse(statusCode: 200, headers: [:], body: Data("invalid-json".utf8)))
        await #expect(throws: SarvamError.self) {
            _ = try await client.speechToTextTranslateJob.initialise(SpeechToTextTranslateJobInitRequest(jobParameters: SpeechToTextTranslateJobParameters()))
        }

        transport.queueResponse(HTTPResponse(statusCode: 200, headers: [:], body: Data("invalid-json".utf8)))
        await #expect(throws: SarvamError.self) {
            _ = try await client.speechToTextTranslateJob.getUploadLinks(FilesRequest(jobId: "tr-1", files: []))
        }

        transport.queueResponse(HTTPResponse(statusCode: 200, headers: [:], body: Data("invalid-json".utf8)))
        await #expect(throws: SarvamError.self) {
            _ = try await client.speechToTextTranslateJob.start(jobId: "tr-1")
        }

        transport.queueResponse(HTTPResponse(statusCode: 200, headers: [:], body: Data("invalid-json".utf8)))
        await #expect(throws: SarvamError.self) {
            _ = try await client.speechToTextTranslateJob.getStatus(jobId: "tr-1")
        }

        transport.queueResponse(HTTPResponse(statusCode: 200, headers: [:], body: Data("invalid-json".utf8)))
        await #expect(throws: SarvamError.self) {
            _ = try await client.speechToTextTranslateJob.getDownloadLinks(FilesRequest(jobId: "tr-1", files: []))
        }
    }

    // MARK: - SpeechToTextJobResource Decoding Errors
    @Test("SpeechToTextJobResource decoding errors")
    func testSpeechToTextJobDecodingErrors() async throws {
        let transport = MockHTTPTransport()
        let client = makeClient(transport: transport)

        transport.queueResponse(HTTPResponse(statusCode: 200, headers: [:], body: Data("invalid".utf8)))
        await #expect(throws: SarvamError.self) {
            _ = try await client.speechToTextJob.initialise(SpeechToTextJobInitRequest(jobParameters: SpeechToTextJobParameters()))
        }

        transport.queueResponse(HTTPResponse(statusCode: 200, headers: [:], body: Data("invalid".utf8)))
        await #expect(throws: SarvamError.self) {
            _ = try await client.speechToTextJob.getUploadLinks(FilesRequest(jobId: "stt-1", files: []))
        }

        transport.queueResponse(HTTPResponse(statusCode: 200, headers: [:], body: Data("invalid".utf8)))
        await #expect(throws: SarvamError.self) {
            _ = try await client.speechToTextJob.start(jobId: "stt-1")
        }

        transport.queueResponse(HTTPResponse(statusCode: 200, headers: [:], body: Data("invalid".utf8)))
        await #expect(throws: SarvamError.self) {
            _ = try await client.speechToTextJob.getStatus(jobId: "stt-1")
        }

        transport.queueResponse(HTTPResponse(statusCode: 200, headers: [:], body: Data("invalid".utf8)))
        await #expect(throws: SarvamError.self) {
            _ = try await client.speechToTextJob.getDownloadLinks(FilesRequest(jobId: "stt-1", files: []))
        }
    }

    // MARK: - SpeechToTextResource Tests
    @Test("SpeechToTextResource transcribe, translate, connect, and decoding errors")
    func testSpeechToTextResource() async throws {
        let transport = MockHTTPTransport()
        let client = makeClient(transport: transport)
        let file = FileInput(data: Data([1, 2, 3]), fileName: "audio.wav")

        let opts = SpeechToTextOptions(
            model: .saarasV4,
            languageCode: .hiIn,
            prompt: "speech prompt",
            withTimestamps: true,
            withDiarization: true,
            numSpeakers: 2
        )

        // transcribe
        transport.queueResponse(HTTPResponse(statusCode: 200, headers: [:], body: Data("{\"transcript\":\"Namaste\"}".utf8)))
        let transcribeResp = try await client.speechToText.transcribe(file: file, options: opts)
        #expect(transcribeResp.transcript == "Namaste")

        // translate
        transport.queueResponse(HTTPResponse(statusCode: 200, headers: [:], body: Data("{\"transcript\":\"Hello\"}".utf8)))
        let translateResp = try await client.speechToText.translate(file: file, options: opts)
        #expect(translateResp.transcript == "Hello")

        // decoding error
        transport.queueResponse(HTTPResponse(statusCode: 200, headers: [:], body: Data("corrupt".utf8)))
        await #expect(throws: SarvamError.self) {
            _ = try await client.speechToText.transcribe(file: file)
        }

        // connect
        let wsFactory = MockWebSocketFactory()
        let wsSession = MockWebSocketSession()
        wsFactory.queueSession(wsSession)
        let customClient = SarvamClient(
            authProvider: ApiKeyAuth(apiKey: "key"),
            transport: transport,
            webSocketFactory: wsFactory
        )
        let realtimeSession = try await customClient.speechToText.connect(config: SttRealtimeConfig(sampleRate: 16000))
        try await realtimeSession.close()
    }

    // MARK: - ChatResource & ChatSession Tests
    @Test("ChatResource and ChatSession all methods and decoding errors")
    func testChatResourceAndSession() async throws {
        let transport = MockHTTPTransport()
        let client = makeClient(transport: transport)
        let req = ChatCompletionRequest(model: .sarvam105b, messages: [ChatMessage(role: "user", content: "Hi")])

        // listModels
        transport.queueResponse(HTTPResponse(statusCode: 200, headers: [:], body: Data("{\"models\":[{\"id\":\"sarvam-2b\"}]}".utf8)))
        let modelsResp = try await client.chat.listModels()
        #expect(modelsResp.models.count == 1)

        // getModel
        transport.queueResponse(HTTPResponse(statusCode: 200, headers: [:], body: Data("{\"id\":\"sarvam-2b\"}".utf8)))
        let modelResp = try await client.chat.getModel("sarvam-2b")
        #expect(modelResp.id == "sarvam-2b")

        // completions (V1)
        transport.queueResponse(HTTPResponse(statusCode: 200, headers: [:], body: Data("{\"id\":\"c1\",\"choices\":[]}".utf8)))
        let compV1 = try await client.chat.completions(req)
        #expect(compV1.id == "c1")

        // completionsV2
        transport.queueResponse(HTTPResponse(statusCode: 200, headers: [:], body: Data("{\"id\":\"c2\",\"choices\":[]}".utf8)))
        let compV2 = try await client.chat.completionsV2(req)
        #expect(compV2.id == "c2")

        // completionsStream
        let chunkJson = "{\"id\":\"c1\",\"choices\":[{\"delta\":{\"content\":\"Hello\"}}]}"
        let sseData = "data: \(chunkJson)\n\ndata: [DONE]\n\n"
        transport.queueStreamResponse(chunks: [Data(sseData.utf8)])
        let streamV1 = client.chat.completionsStream(req)
        var receivedV1 = ""
        for try await c in streamV1 {
            receivedV1 += c.firstDeltaContent ?? ""
        }
        #expect(receivedV1 == "Hello")

        // completionsV2Stream
        transport.queueStreamResponse(chunks: [Data(sseData.utf8)])
        let streamV2 = client.chat.completionsV2Stream(req)
        var receivedV2 = ""
        for try await c in streamV2 {
            receivedV2 += c.firstDeltaContent ?? ""
        }
        #expect(receivedV2 == "Hello")

        // ChatSession methods
        let session = client.chat.createSession(affinityId: "test-affinity")
        #expect(session.affinityId == "test-affinity")

        transport.queueResponse(HTTPResponse(statusCode: 200, headers: [:], body: Data("{\"id\":\"s1\",\"choices\":[]}".utf8)))
        let sessV1 = try await session.completions(req)
        #expect(sessV1.id == "s1")
        #expect(transport.executedRequests.last?.headers["x-session-affinity"] == "test-affinity")

        transport.queueResponse(HTTPResponse(statusCode: 200, headers: [:], body: Data("{\"id\":\"s2\",\"choices\":[]}".utf8)))
        let sessV2 = try await session.completionsV2(req)
        #expect(sessV2.id == "s2")
        #expect(transport.executedRequests.last?.headers["x-session-affinity"] == "test-affinity")

        transport.queueStreamResponse(chunks: [Data(sseData.utf8)])
        let sessStreamV1 = await session.completionsStream(req)
        for try await _ in sessStreamV1 {}
        #expect(transport.executedRequests.last?.headers["x-session-affinity"] == "test-affinity")

        transport.queueStreamResponse(chunks: [Data(sseData.utf8)])
        let sessStreamV2 = await session.completionsV2Stream(req)
        for try await _ in sessStreamV2 {}
        #expect(transport.executedRequests.last?.headers["x-session-affinity"] == "test-affinity")

        // Decoding errors
        transport.queueResponse(HTTPResponse(statusCode: 200, headers: [:], body: Data("bad".utf8)))
        await #expect(throws: SarvamError.self) {
            _ = try await client.chat.listModels()
        }

        transport.queueResponse(HTTPResponse(statusCode: 200, headers: [:], body: Data("bad".utf8)))
        await #expect(throws: SarvamError.self) {
            _ = try await client.chat.getModel("bad")
        }

        transport.queueResponse(HTTPResponse(statusCode: 200, headers: [:], body: Data("bad".utf8)))
        await #expect(throws: SarvamError.self) {
            _ = try await client.chat.completions(req)
        }

        // Stream decoding error
        transport.queueStreamResponse(chunks: [Data("data: corrupt-json\n\n".utf8)])
        let badStream = client.chat.completionsStream(req)
        await #expect(throws: SarvamError.self) {
            for try await _ in badStream {}
        }
    }

    // MARK: - DocAiResource Tests
    @Test("DocAiResource methods and edge cases")
    func testDocAiResource() async throws {
        let transport = MockHTTPTransport()
        let clock = MockClockProvider()
        let client = makeClient(transport: transport, clock: clock)
        let file = FileInput(data: Data([1, 2, 3]), fileName: "doc.pdf")

        // createUploadUrl
        transport.queueResponse(HTTPResponse(statusCode: 200, headers: [:], body: Data("{\"upload_id\":\"u1\",\"method\":\"PUT\",\"url\":\"https://up.url\",\"expires_at\":\"2026\"}".utf8)))
        let upResp = try await client.docAi.createUploadUrl()
        #expect(upResp.uploadId == "u1")

        // getResults with format
        transport.queueResponse(HTTPResponse(statusCode: 200, headers: [:], body: Data("{\"extracted\":\"text\"}".utf8)))
        let resWithFmt = try await client.docAi.getResults(jobId: "j1", format: "json")
        #expect(resWithFmt.rawBody.contains("extracted"))

        // getDownloadUrl
        transport.queueResponse(HTTPResponse(statusCode: 200, headers: [:], body: Data("{\"method\":\"GET\",\"url\":\"https://dl.url\",\"expires_at\":\"2026\"}".utf8)))
        let dlResp = try await client.docAi.getDownloadUrl(jobId: "j1")
        #expect(dlResp.url == "https://dl.url")

        // digitise (single file convenience)
        transport.queueResponse(HTTPResponse(statusCode: 200, headers: [:], body: Data("{\"job_id\":\"d1\",\"status\":\"running\",\"run_id\":\"r1\"}".utf8)))
        let digResp = try await client.docAi.digitise(file: file, language: "en", contentType: "pdf", model: "v1", uploadIds: "u1")
        #expect(digResp.jobId == "d1")

        // extract (single file convenience with schema string)
        transport.queueResponse(HTTPResponse(statusCode: 200, headers: [:], body: Data("{\"job_id\":\"e1\",\"status\":\"running\",\"run_id\":\"r2\"}".utf8)))
        let extResp = try await client.docAi.extract(
            file: file,
            schema: "{\"type\":\"object\"}",
            configId: "cfg1",
            outputFormat: "json",
            classification: "invoice",
            model: "v1",
            uploadIds: "u1"
        )
        #expect(extResp.jobId == "e1")

        // digitiseAndWait (single file)
        transport.queueResponse(HTTPResponse(statusCode: 200, headers: [:], body: Data("{\"job_id\":\"d2\",\"status\":\"running\",\"run_id\":\"r3\"}".utf8)))
        transport.queueResponse(HTTPResponse(statusCode: 200, headers: [:], body: Data("{\"job_id\":\"d2\",\"status\":\"completed\",\"pipeline\":\"digitise\",\"created_at\":\"\",\"updated_at\":\"\"}".utf8)))
        let digWaitResp = try await client.docAi.digitiseAndWait(file: file, pollingOptions: PollingOptions(pollInterval: 0.05, timeoutInterval: 5))
        #expect(digWaitResp.status == "completed")

        // extractAndWait (single file)
        transport.queueResponse(HTTPResponse(statusCode: 200, headers: [:], body: Data("{\"job_id\":\"e2\",\"status\":\"running\",\"run_id\":\"r4\"}".utf8)))
        transport.queueResponse(HTTPResponse(statusCode: 200, headers: [:], body: Data("{\"job_id\":\"e2\",\"status\":\"completed\",\"pipeline\":\"extract\",\"created_at\":\"\",\"updated_at\":\"\"}".utf8)))
        let extWaitResp = try await client.docAi.extractAndWait(file: file, pollingOptions: PollingOptions(pollInterval: 0.05, timeoutInterval: 5))
        #expect(extWaitResp.status == "completed")

        // Decoding errors
        transport.queueResponse(HTTPResponse(statusCode: 200, headers: [:], body: Data("corrupt".utf8)))
        await #expect(throws: SarvamError.self) {
            _ = try await client.docAi.createUploadUrl()
        }

        transport.queueResponse(HTTPResponse(statusCode: 200, headers: [:], body: Data("corrupt".utf8)))
        await #expect(throws: SarvamError.self) {
            _ = try await client.docAi.getStatus(jobId: "j1")
        }

        transport.queueResponse(HTTPResponse(statusCode: 200, headers: [:], body: Data("corrupt".utf8)))
        await #expect(throws: SarvamError.self) {
            _ = try await client.docAi.getDownloadUrl(jobId: "j1")
        }

        transport.queueResponse(HTTPResponse(statusCode: 200, headers: [:], body: Data("corrupt".utf8)))
        await #expect(throws: SarvamError.self) {
            _ = try await client.docAi.digitise(files: [file])
        }

        transport.queueResponse(HTTPResponse(statusCode: 200, headers: [:], body: Data("corrupt".utf8)))
        await #expect(throws: SarvamError.self) {
            _ = try await client.docAi.extract(files: [file])
        }
    }

    // MARK: - DocumentTranslationResource Decoding Errors
    @Test("DocumentTranslationResource decoding errors")
    func testDocumentTranslationDecodingErrors() async throws {
        let transport = MockHTTPTransport()
        let client = makeClient(transport: transport)

        transport.queueResponse(HTTPResponse(statusCode: 200, headers: [:], body: Data("bad".utf8)))
        await #expect(throws: SarvamError.self) {
            _ = try await client.documentTranslation.create(DocumentTranslationCreateRequest(sourceLanguageCode: .hiIn, targetLanguageCodes: [.enIn], originalFilename: "d.pdf"))
        }

        transport.queueResponse(HTTPResponse(statusCode: 200, headers: [:], body: Data("bad".utf8)))
        await #expect(throws: SarvamError.self) {
            _ = try await client.documentTranslation.start(jobId: "dt1")
        }

        transport.queueResponse(HTTPResponse(statusCode: 200, headers: [:], body: Data("bad".utf8)))
        await #expect(throws: SarvamError.self) {
            _ = try await client.documentTranslation.getLiveStatus(jobId: "dt1")
        }

        transport.queueResponse(HTTPResponse(statusCode: 200, headers: [:], body: Data("bad".utf8)))
        await #expect(throws: SarvamError.self) {
            _ = try await client.documentTranslation.triggerExport(jobId: "dt1", request: DocumentTranslationExportRequest(lang: .enIn))
        }

        transport.queueResponse(HTTPResponse(statusCode: 200, headers: [:], body: Data("bad".utf8)))
        await #expect(throws: SarvamError.self) {
            _ = try await client.documentTranslation.getExportStatus(jobId: "dt1", exportId: "e1")
        }
    }

    // MARK: - DubbingResource Decoding Errors
    @Test("DubbingResource decoding errors")
    func testDubbingDecodingErrors() async throws {
        let transport = MockHTTPTransport()
        let client = makeClient(transport: transport)

        transport.queueResponse(HTTPResponse(statusCode: 200, headers: [:], body: Data("bad".utf8)))
        await #expect(throws: SarvamError.self) {
            _ = try await client.dubbing.create(DubbingCreateRequest(sourceLanguageCode: .hiIn, targetLanguageCodes: [.enIn]))
        }

        transport.queueResponse(HTTPResponse(statusCode: 200, headers: [:], body: Data("bad".utf8)))
        await #expect(throws: SarvamError.self) {
            _ = try await client.dubbing.start(jobId: "dub1")
        }

        transport.queueResponse(HTTPResponse(statusCode: 200, headers: [:], body: Data("bad".utf8)))
        await #expect(throws: SarvamError.self) {
            _ = try await client.dubbing.getLiveStatus(jobId: "dub1")
        }

        transport.queueResponse(HTTPResponse(statusCode: 200, headers: [:], body: Data("bad".utf8)))
        await #expect(throws: SarvamError.self) {
            _ = try await client.dubbing.getExportStatus(jobId: "dub1")
        }
    }

    // MARK: - PronunciationDictionaryResource Decoding Errors
    @Test("PronunciationDictionaryResource decoding errors")
    func testPronunciationDictionaryDecodingErrors() async throws {
        let transport = MockHTTPTransport()
        let client = makeClient(transport: transport)

        transport.queueResponse(HTTPResponse(statusCode: 200, headers: [:], body: Data("bad".utf8)))
        await #expect(throws: SarvamError.self) {
            _ = try await client.pronunciationDictionary.create(file: FileInput(data: Data([1])))
        }

        transport.queueResponse(HTTPResponse(statusCode: 200, headers: [:], body: Data("bad".utf8)))
        await #expect(throws: SarvamError.self) {
            _ = try await client.pronunciationDictionary.get(dictId: "d1")
        }

        transport.queueResponse(HTTPResponse(statusCode: 200, headers: [:], body: Data("bad".utf8)))
        await #expect(throws: SarvamError.self) {
            _ = try await client.pronunciationDictionary.list()
        }

        transport.queueResponse(HTTPResponse(statusCode: 200, headers: [:], body: Data("bad".utf8)))
        await #expect(throws: SarvamError.self) {
            _ = try await client.pronunciationDictionary.update(dictId: "d1", file: FileInput(data: Data([1])))
        }

        transport.queueResponse(HTTPResponse(statusCode: 200, headers: [:], body: Data("bad".utf8)))
        await #expect(throws: SarvamError.self) {
            _ = try await client.pronunciationDictionary.delete(dictId: "d1")
        }
    }

    // MARK: - VoiceCloningResource Tests
    @Test("VoiceCloningResource decoding errors and options")
    func testVoiceCloningResource() async throws {
        let transport = MockHTTPTransport()
        let client = makeClient(transport: transport)

        // createVoice with all options
        transport.queueResponse(HTTPResponse(statusCode: 200, headers: [:], body: Data("{\"status\":\"success\",\"data\":{\"voice_id\":\"v1\",\"status\":\"created\"}}".utf8)))
        let createResp = try await client.voiceCloning.createVoice(
            file: FileInput(data: Data([1])),
            name: "Voice",
            language: "hi-IN",
            style: "cheerful",
            gender: "female"
        )
        #expect(createResp.data.voiceId == "v1")

        // convert with all options
        let cloneReq = VoiceCloneRequest(
            text: "Hello",
            languageCode: .hiIn,
            voiceId: "v1",
            refAudio: FileInput(data: Data([1])),
            refText: "Sample",
            pace: 1.0,
            outputAudioCodec: .wav,
            speechSampleRate: 16000,
            enableQc: false,
            enableVad: true,
            enableTextNormalization: true,
            minAudioDuration: 0.5,
            maxAudioDuration: 5.0,
            refAudioDuration: 2.0
        )
        transport.queueResponse(HTTPResponse(statusCode: 200, headers: [:], body: Data("{\"audio\":\"AQIDBA==\"}".utf8)))
        let convResp = try await client.voiceCloning.convert(cloneReq)
        #expect(convResp.audioBytes == Data([1, 2, 3, 4]))

        // stream with all options
        transport.queueStreamResponse(chunks: [Data([1, 2]), Data([3, 4])])
        let stream = client.voiceCloning.stream(cloneReq)
        var received = Data()
        for try await chunk in stream {
            received.append(chunk)
        }
        #expect(received == Data([1, 2, 3, 4]))

        // Decoding errors
        transport.queueResponse(HTTPResponse(statusCode: 200, headers: [:], body: Data("bad".utf8)))
        await #expect(throws: SarvamError.self) {
            _ = try await client.voiceCloning.listVoices()
        }

        transport.queueResponse(HTTPResponse(statusCode: 200, headers: [:], body: Data("bad".utf8)))
        await #expect(throws: SarvamError.self) {
            _ = try await client.voiceCloning.createVoice(file: FileInput(data: Data([1])), name: "n", language: "hi")
        }

        transport.queueResponse(HTTPResponse(statusCode: 200, headers: [:], body: Data("bad".utf8)))
        await #expect(throws: SarvamError.self) {
            _ = try await client.voiceCloning.getVoice(voiceId: "v1")
        }

        transport.queueResponse(HTTPResponse(statusCode: 200, headers: [:], body: Data("bad".utf8)))
        await #expect(throws: SarvamError.self) {
            _ = try await client.voiceCloning.convert(cloneReq)
        }
    }

    // MARK: - JobsResource Tests
    @Test("JobsResource uploadToSignedUrl success, custom header, invalid URL, and error response")
    func testJobsResource() async throws {
        let transport = MockHTTPTransport()
        let client = makeClient(transport: transport)
        let file = FileInput(data: Data([1, 2, 3]), mimeType: "audio/wav")

        // Success
        transport.queueResponse(HTTPResponse(statusCode: 201, headers: [:], body: Data()))
        try await client.jobs.uploadToSignedUrl(uploadUrl: "https://blob.storage.azure.com/upload", fileInput: file)
        #expect(transport.executedRequests.last?.headers["x-ms-blob-type"] == "BlockBlob")
        #expect(transport.executedRequests.last?.headers["content-type"] == "audio/wav")

        // Custom content-type header
        transport.queueResponse(HTTPResponse(statusCode: 200, headers: [:], body: Data()))
        try await client.jobs.uploadToSignedUrl(
            uploadUrl: "https://blob.storage.azure.com/upload",
            fileInput: file,
            options: RequestOptions(headers: ["Content-Type": "custom/binary"])
        )
        #expect(transport.executedRequests.last?.headers["Content-Type"] == "custom/binary")

        // HTTP error >= 400
        transport.queueResponse(HTTPResponse(statusCode: 403, headers: [:], body: Data("{\"code\":\"forbidden\"}".utf8)))
        await #expect(throws: SarvamError.self) {
            try await client.jobs.uploadToSignedUrl(uploadUrl: "https://blob.storage.azure.com/upload", fileInput: file)
        }

        // Invalid URL
        await #expect(throws: SarvamError.self) {
            try await client.jobs.uploadToSignedUrl(uploadUrl: "", fileInput: file)
        }
    }

    // MARK: - TextResource Tests
    @Test("TextResource decoding error handling")
    func testTextResourceDecodingErrors() async throws {
        let transport = MockHTTPTransport()
        let client = makeClient(transport: transport)

        transport.queueResponse(HTTPResponse(statusCode: 200, headers: [:], body: Data("bad".utf8)))
        await #expect(throws: SarvamError.self) {
            _ = try await client.text.translate(TranslateRequest(input: "hello", sourceLanguageCode: .enIn, targetLanguageCode: .hiIn))
        }

        transport.queueResponse(HTTPResponse(statusCode: 200, headers: [:], body: Data("bad".utf8)))
        await #expect(throws: SarvamError.self) {
            _ = try await client.text.transliterate(TransliterateRequest(input: "hello", sourceLanguageCode: .enIn, targetLanguageCode: .hiIn))
        }

        transport.queueResponse(HTTPResponse(statusCode: 200, headers: [:], body: Data("bad".utf8)))
        await #expect(throws: SarvamError.self) {
            _ = try await client.text.identifyLanguage(TextLidRequest(input: "hello"))
        }
    }

    // MARK: - TextToSpeechResource Tests
    @Test("TextToSpeechResource decoding error handling and connect")
    func testTextToSpeechResource() async throws {
        let transport = MockHTTPTransport()
        let wsFactory = MockWebSocketFactory()
        let wsSession = MockWebSocketSession()
        wsFactory.queueSession(wsSession)

        let client = SarvamClient(
            authProvider: ApiKeyAuth(apiKey: "key"),
            transport: transport,
            webSocketFactory: wsFactory
        )

        transport.queueResponse(HTTPResponse(statusCode: 200, headers: [:], body: Data("bad".utf8)))
        await #expect(throws: SarvamError.self) {
            _ = try await client.textToSpeech.convert(TextToSpeechRequest(text: "hi", targetLanguageCode: .hiIn))
        }

        let streamingSession = try await client.textToSpeech.connect(config: TtsStreamingConfig())
        try await streamingSession.close()
    }
}
