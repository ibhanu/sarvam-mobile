import Foundation
import Testing
@testable import Sarvam

@Suite("Sarvam Conformance Test Suite (19 Scenarios)")
struct ConformanceTests {

    // MARK: - Case 1: rest-auth-error-quirk
    @Test("Case 1: rest-auth-error-quirk (HTTP 403 with invalid_api_key_error)")
    func testAuthErrorQuirk() async throws {
        let mock = MockHTTPTransport()
        let errorJson = """
        {"error": {"code": "invalid_api_key_error", "message": "Invalid API key", "request_id": "req_auth_403"}}
        """
        mock.queueResponse(HTTPResponse(statusCode: 403, headers: ["content-type": "application/json"], body: errorJson.data(using: .utf8)!))

        let client = SarvamClient(
            apiKey: "invalid-key",
            transport: mock
        )

        do {
            _ = try await client.text.translate(
                TranslateRequest(input: "Hello world", sourceLanguageCode: .enIn, targetLanguageCode: .hiIn)
            )
            Issue.record("Expected AuthenticationError to be thrown")
        } catch let error as SarvamError {
            guard case let .authenticationError(status, code, reqId, message) = error else {
                Issue.record("Expected .authenticationError, got \(error)")
                return
            }
            #expect(status == 403)
            #expect(code == "invalid_api_key_error")
            #expect(reqId == "req_auth_403")
            #expect(message == "Invalid API key")
        }
    }

    // MARK: - Case 2: rest-idempotent-retry-500
    @Test("Case 2: rest-idempotent-retry-500 (GET /v2/models retries on 500)")
    func testIdempotentRetry500() async throws {
        let mock = MockHTTPTransport()
        let clock = MockClockProvider()
        let random = MockRandomProvider(fixedInt: 10)

        let errorJson = """
        {"error": {"code": "internal_server_error", "message": "Transient inference service failure", "request_id": "req_glitch_500"}}
        """
        let successJson = """
        {"models": [{"id": "sarvam-2b"}, {"id": "saaras:v3"}]}
        """
        mock.queueResponse(HTTPResponse(statusCode: 500, headers: ["content-type": "application/json"], body: errorJson.data(using: .utf8)!))
        mock.queueResponse(HTTPResponse(statusCode: 200, headers: ["content-type": "application/json"], body: successJson.data(using: .utf8)!))

        let client = SarvamClient(
            apiKey: "test-api-key",
            transport: mock,
            clock: clock,
            random: random
        )

        let models = try await client.chat.listModels()
        #expect(models.models.count == 2)
        #expect(models.models[0].id == "sarvam-2b")
        #expect(models.models[1].id == "saaras:v3")
        #expect(mock.executedRequests.count == 2)
    }

    // MARK: - Case 3: rest-job-creation-safety-500
    @Test("Case 3: rest-job-creation-safety-500 (JOB_CREATE never retries on 500)")
    func testJobCreationSafety500() async throws {
        let mock = MockHTTPTransport()
        let errorJson = """
        {"error": {"code": "internal_server_error", "message": "Internal server error", "request_id": "req_job_500"}}
        """
        mock.queueResponse(HTTPResponse(statusCode: 500, headers: ["content-type": "application/json"], body: errorJson.data(using: .utf8)!))

        let client = SarvamClient(
            apiKey: "test-api-key",
            transport: mock
        )

        let executor = RequestExecutor(config: client.config)
        let request = HTTPRequest(
            method: .post,
            url: URL(string: "https://api.sarvam.ai/doc-ai/v1/job/digitise")!,
            headers: ["content-type": "application/json"],
            body: "{\"language\":\"hi\",\"output_format\":\"md\"}".data(using: .utf8)!,
            operationKind: .jobCreate
        )

        do {
            _ = try await executor.execute(request: request)
            Issue.record("Expected ServerError to be thrown")
        } catch let error as SarvamError {
            guard case let .serverError(status, code, reqId, message) = error else {
                Issue.record("Expected .serverError, got \(error)")
                return
            }
            #expect(status == 500)
            #expect(code == "internal_server_error")
            #expect(reqId == "req_job_500")
            #expect(message == "Internal server error")
            #expect(mock.executedRequests.count == 1) // 0 retries performed!
        }
    }

    // MARK: - Case 4: rest-permission-denied
    @Test("Case 4: rest-permission-denied (HTTP 403 with authentication_error)")
    func testPermissionDenied() async throws {
        let mock = MockHTTPTransport()
        let errorJson = """
        {"error": {"code": "authentication_error", "message": "Tier locked", "request_id": "req_perm_403"}}
        """
        mock.queueResponse(HTTPResponse(statusCode: 403, headers: ["content-type": "application/json"], body: errorJson.data(using: .utf8)!))

        let client = SarvamClient(
            apiKey: "tier-locked-key",
            transport: mock
        )

        do {
            _ = try await client.text.translate(
                TranslateRequest(input: "Hello world", sourceLanguageCode: .enIn, targetLanguageCode: .hiIn)
            )
            Issue.record("Expected PermissionDeniedError")
        } catch let error as SarvamError {
            guard case let .permissionDeniedError(status, code, reqId, message) = error else {
                Issue.record("Expected .permissionDeniedError, got \(error)")
                return
            }
            #expect(status == 403)
            #expect(code == "authentication_error")
            #expect(reqId == "req_perm_403")
            #expect(message == "Tier locked")
            #expect(mock.executedRequests.count == 1)
        }
    }

    // MARK: - Case 5: rest-rate-limit-retry
    @Test("Case 5: rest-rate-limit-retry (Rate Limit 429 Retry with retry-after-ms)")
    func testRateLimitRetry() async throws {
        let mock = MockHTTPTransport()
        let clock = MockClockProvider()

        let rlJson = """
        {"error": {"code": "rate_limit_exceeded_error", "message": "Rate limit exceeded", "request_id": "req_rl_1"}}
        """
        let okJson = """
        {"translated_text": "नमस्ते दुनिया"}
        """
        mock.queueResponse(HTTPResponse(statusCode: 429, headers: ["content-type": "application/json", "retry-after-ms": "50"], body: rlJson.data(using: .utf8)!))
        mock.queueResponse(HTTPResponse(statusCode: 200, headers: ["content-type": "application/json"], body: okJson.data(using: .utf8)!))

        let client = SarvamClient(
            apiKey: "test-api-key",
            transport: mock,
            clock: clock
        )

        let response = try await client.text.translate(
            TranslateRequest(input: "Hello retry", sourceLanguageCode: .enIn, targetLanguageCode: .hiIn)
        )
        #expect(response.translatedText == "नमस्ते दुनिया")
        #expect(mock.executedRequests.count == 2)
        #expect(clock.sleepCalls == [50])
    }

    // MARK: - Case 6: rest-sas-blob-upload
    @Test("Case 6: rest-sas-blob-upload (Azure SAS Blob Upload Header Validation)")
    func testSasBlobUpload() async throws {
        let mock = MockHTTPTransport()
        mock.queueHandler { req in
            #expect(req.headers["x-ms-blob-type"] == "BlockBlob")
            #expect(req.headers["content-type"] == "application/octet-stream")
            return HTTPResponse(statusCode: 201, headers: ["x-ms-request-id": "mock-azure-req-1"], body: Data())
        }

        let client = SarvamClient(
            apiKey: "test-api-key",
            transport: mock
        )

        let audioData = "mock-audio-binary-data".data(using: .utf8)!
        try await client.jobs.uploadToSignedUrl(
            uploadUrl: "https://mockstorage.blob.core.windows.net/mock-sas-upload",
            fileInput: FileInput(data: audioData)
        )
        #expect(mock.executedRequests.count == 1)
    }

    // MARK: - Case 7: rest-text-identify-language-success
    @Test("Case 7: rest-text-identify-language-success")
    func testTextIdentifyLanguageSuccess() async throws {
        let mock = MockHTTPTransport()
        let json = """
        {"detected_language": "hi-IN", "confidence": 0.99}
        """
        mock.queueResponse(HTTPResponse(statusCode: 200, headers: ["content-type": "application/json"], body: json.data(using: .utf8)!))

        let client = SarvamClient(
            apiKey: "test-api-key",
            transport: mock
        )

        let result = try await client.text.identifyLanguage(TextLidRequest(input: "नमस्ते दुनिया"))
        #expect(result.detectedLanguage == "hi-IN")
        #expect(result.confidence == 0.99)
        #expect(mock.executedRequests[0].url.path == "/text-lid")
        #expect(mock.executedRequests[0].headers["api-subscription-key"] == "test-api-key")
    }

    // MARK: - Case 8: rest-text-translate-success
    @Test("Case 8: rest-text-translate-success")
    func testTextTranslateSuccess() async throws {
        let mock = MockHTTPTransport()
        let json = """
        {"translated_text": "नमस्ते दुनिया"}
        """
        mock.queueResponse(HTTPResponse(statusCode: 200, headers: ["content-type": "application/json"], body: json.data(using: .utf8)!))

        let client = SarvamClient(
            apiKey: "test-api-key",
            transport: mock
        )

        let request = TranslateRequest(
            input: "Hello world",
            sourceLanguageCode: .enIn,
            targetLanguageCode: .hiIn,
            speakerGender: "Male",
            mode: "formal",
            model: "mayura:v1"
        )
        let result = try await client.text.translate(request)
        #expect(result.translatedText == "नमस्ते दुनिया")
        #expect(mock.executedRequests[0].url.path == "/translate")
        #expect(mock.executedRequests[0].headers["api-subscription-key"] == "test-api-key")
    }

    // MARK: - Case 9: rest-text-transliterate-success
    @Test("Case 9: rest-text-transliterate-success")
    func testTextTransliterateSuccess() async throws {
        let mock = MockHTTPTransport()
        let json = """
        {"transliterated_text": "नमस्ते"}
        """
        mock.queueResponse(HTTPResponse(statusCode: 200, headers: ["content-type": "application/json"], body: json.data(using: .utf8)!))

        let client = SarvamClient(
            apiKey: "test-api-key",
            transport: mock
        )

        let request = TransliterateRequest(input: "namaste", sourceLanguageCode: .enIn, targetLanguageCode: .hiIn)
        let result = try await client.text.transliterate(request)
        #expect(result.transliteratedText == "नमस्ते")
        #expect(mock.executedRequests[0].url.path == "/transliterate")
        #expect(mock.executedRequests[0].headers["api-subscription-key"] == "test-api-key")
    }

    // MARK: - Case 10: rest-token-auth-refresh
    @Test("Case 10: rest-token-auth-refresh (TokenAuth Invalidation and Single Retry on 403)")
    func testTokenAuthRefresh() async throws {
        let mock = MockHTTPTransport()

        let err403 = """
        {"error": {"code": "invalid_api_key_error", "message": "Expired token", "request_id": "req_tok_1"}}
        """
        let ok200 = """
        {"translated_text": "नमस्ते दुनिया"}
        """
        mock.queueResponse(HTTPResponse(statusCode: 403, headers: ["content-type": "application/json"], body: err403.data(using: .utf8)!))
        mock.queueResponse(HTTPResponse(statusCode: 200, headers: ["content-type": "application/json"], body: ok200.data(using: .utf8)!))

        actor TokenState {
            var counter = 0
            func next() -> String {
                counter += 1
                return counter == 1 ? "token_initial" : "token_refreshed"
            }
        }
        let state = TokenState()
        let tokenAuth = TokenAuth(tokenProvider: {
            let t = await state.next()
            return AuthToken(token: t)
        })

        let client = SarvamClient(
            authProvider: tokenAuth,
            transport: mock
        )

        let result = try await client.text.translate(
            TranslateRequest(input: "Hello world", sourceLanguageCode: .enIn, targetLanguageCode: .hiIn)
        )
        #expect(result.translatedText == "नमस्ते दुनिया")
        #expect(mock.executedRequests.count == 2)
        #expect(mock.executedRequests[0].headers["Authorization"] == "Bearer token_initial")
        #expect(mock.executedRequests[1].headers["Authorization"] == "Bearer token_refreshed")
    }

    // MARK: - Case 11: rest-tts-chunked-stream
    @Test("Case 11: rest-tts-chunked-stream (TTS HTTP Chunked Binary Audio Stream)")
    func testTtsChunkedStream() async throws {
        let mock = MockHTTPTransport()
        let chunk0 = Data([0x01, 0x02, 0x03, 0x04, 0x05, 0x06, 0x07, 0x08, 0x09, 0x0a, 0x0b, 0x0c, 0x0d, 0x0e, 0x0f, 0x10])
        let chunk1 = Data([0x11, 0x12, 0x13, 0x14, 0x15, 0x16, 0x17, 0x18, 0x19, 0x1a, 0x1b, 0x1c, 0x1d, 0x1e, 0x1f, 0x20])
        let chunk2 = Data([0x21, 0x22, 0x23, 0x24, 0x25, 0x26, 0x27, 0x28, 0x29, 0x2a, 0x2b, 0x2c, 0x2d, 0x2e, 0x2f, 0x30])

        mock.queueStreamResponse(
            statusCode: 200,
            headers: ["content-type": "application/octet-stream", "transfer-encoding": "chunked"],
            chunks: [chunk0, chunk1, chunk2]
        )

        let client = SarvamClient(
            apiKey: "test-api-key",
            transport: mock
        )

        let req = TextToSpeechRequest(
            text: "नमस्ते भारत",
            targetLanguageCode: .hiIn,
            speaker: Speaker(rawValue: "meera")
        )

        var collected = Data()
        var chunkCount = 0
        for try await chunk in client.textToSpeech.stream(req) {
            collected.append(chunk)
            chunkCount += 1
        }

        #expect(chunkCount == 3)
        #expect(collected.count == 48)
        let hex = collected.map { String(format: "%02x", $0) }.joined()
        #expect(hex == "0102030405060708090a0b0c0d0e0f101112131415161718191a1b1c1d1e1f202122232425262728292a2b2c2d2e2f30")
    }

    // MARK: - Case 12: rest-tts-base64-decoding
    @Test("Case 12: rest-tts-base64-decoding (TTS REST Base64 Audio Decoding)")
    func testTtsBase64Decoding() async throws {
        let mock = MockHTTPTransport()
        let b64 = "UklGRiQAAABXQVZFZm10IBAAAAABAAEAQB8AAEAfAAABAAgAZGF0YQAAAAA="
        let json = """
        {"audios": [{"audio": "\(b64)"}]}
        """
        mock.queueResponse(HTTPResponse(statusCode: 200, headers: ["content-type": "application/json"], body: json.data(using: .utf8)!))

        let client = SarvamClient(
            apiKey: "test-api-key",
            transport: mock
        )

        let req = TextToSpeechRequest(
            text: "नमस्ते दुनिया",
            targetLanguageCode: .hiIn,
            speaker: Speaker(rawValue: "meera"),
            model: .bulbulV3
        )
        let response = try await client.textToSpeech.convert(req)
        #expect(response.audioCount == 1)
        #expect(response.firstAudioBase64 == b64)

        guard let bytes = response.audioBytes else {
            Issue.record("Expected non-nil audioBytes")
            return
        }
        #expect(bytes.count == 44)
        // Verify WAV RIFF header
        let prefix = String(data: bytes[0..<4], encoding: .ascii)
        #expect(prefix == "RIFF")
    }

    // MARK: - Case 13: sse-chat-v1-stream
    @Test("Case 13: sse-chat-v1-stream (Chat V1 Standard SSE Streaming)")
    func testChatV1Stream() async throws {
        let mock = MockHTTPTransport()
        let ssePayload = "data: {\"id\":\"chatcmpl-v1-1\",\"choices\":[{\"index\":0,\"delta\":{\"content\":\"Hi\"}}]}\n\ndata: {\"id\":\"chatcmpl-v1-1\",\"choices\":[{\"index\":0,\"delta\":{\"content\":\" there!\"}}]}\n\ndata: [DONE]\n"

        mock.queueStreamResponse(
            statusCode: 200,
            headers: ["content-type": "text/event-stream"],
            chunks: [ssePayload.data(using: .utf8)!]
        )

        let client = SarvamClient(
            apiKey: "test-api-key",
            transport: mock
        )

        let req = ChatCompletionRequest(
            model: ChatModel(rawValue: "sarvam-2b"),
            messages: [ChatMessage(role: "user", content: "Hi")]
        )

        var accumulated = ""
        for try await chunk in client.chat.completionsStream(req) {
            if let content = chunk.firstDeltaContent {
                accumulated += content
            }
        }

        #expect(accumulated == "Hi there!")
    }

    // MARK: - Case 14: sse-chat-v2-empty-choices
    @Test("Case 14: sse-chat-v2-empty-choices (Chat V2 SSE Stream with Empty Choices Usage Chunk)")
    func testChatV2EmptyChoices() async throws {
        let mock = MockHTTPTransport()
        let ssePayload = "data: {\"id\":\"chatcmpl-1\",\"choices\":[{\"index\":0,\"delta\":{\"content\":\"Namaste\"}}]}\n\ndata: {\"id\":\"chatcmpl-1\",\"choices\":[{\"index\":0,\"delta\":{\"content\":\" world\"}}]}\n\ndata: {\"id\":\"chatcmpl-1\",\"choices\":[],\"usage\":{\"prompt_tokens\":8,\"completion_tokens\":2,\"total_tokens\":10}}\n\ndata: [DONE]\n"

        mock.queueStreamResponse(
            statusCode: 200,
            headers: ["content-type": "text/event-stream"],
            chunks: [ssePayload.data(using: .utf8)!]
        )

        let client = SarvamClient(
            apiKey: "test-api-key",
            transport: mock
        )

        let req = ChatCompletionRequest(
            model: ChatModel(rawValue: "sarvam-2b"),
            messages: [ChatMessage(role: "user", content: "Hello")]
        )

        var accumulated = ""
        var finalUsage: ChatUsage?

        for try await chunk in client.chat.completionsV2Stream(req) {
            // firstDeltaContent must NOT crash when choices is []
            if let content = chunk.firstDeltaContent {
                accumulated += content
            }
            if let usage = chunk.usage {
                finalUsage = usage
            }
        }

        #expect(accumulated == "Namaste world")
        #expect(finalUsage?.promptTokens == 8)
        #expect(finalUsage?.completionTokens == 2)
        #expect(finalUsage?.totalTokens == 10)
    }

    // MARK: - Case 15: sse-responses-api-no-done
    @Test("Case 15: sse-responses-api-no-done (Responses API Stream terminates on response.completed)")
    func testResponsesApiNoDone() async throws {
        let mock = MockHTTPTransport()
        let ssePayload = "event: response.created\ndata: {\"id\":\"resp_001\",\"type\":\"response.created\"}\n\nevent: response.output_item.added\ndata: {\"id\":\"resp_001\",\"type\":\"response.output_item.added\",\"item\":{\"id\":\"item_001\",\"type\":\"message\",\"role\":\"assistant\"}}\n\nevent: response.content_part.added\ndata: {\"id\":\"resp_001\",\"type\":\"response.content_part.added\",\"item_id\":\"item_001\",\"part\":{\"type\":\"text\",\"text\":\"Quantum computers use qubits.\"}}\n\nevent: response.completed\ndata: {\"id\":\"resp_001\",\"type\":\"response.completed\",\"response\":{\"status\":\"completed\"}}\n"

        mock.queueStreamResponse(
            statusCode: 200,
            headers: ["content-type": "text/event-stream"],
            chunks: [ssePayload.data(using: .utf8)!]
        )

        let client = SarvamClient(
            apiKey: "test-api-key",
            transport: mock
        )

        var eventNames: [String] = []
        for try await event in client.responses.createStream(ResponsesRequest(model: "glm-5.3", input: "Explain quantum computing briefly")) {
            if let name = event.event {
                eventNames.append(name)
            }
        }

        #expect(eventNames == ["response.created", "response.output_item.added", "response.content_part.added", "response.completed"])
    }

    // MARK: - Case 16: ws-stt-invalid-sample-rate
    @Test("Case 16: ws-stt-invalid-sample-rate (Rejection of invalid sample rate)")
    func testWsSttInvalidSampleRate() async throws {
        let client = SarvamClient(apiKey: "test-api-key")

        do {
            _ = try await client.speechToText.connect(
                config: SttRealtimeConfig(sampleRate: 44100)
            )
            Issue.record("Expected BadRequestError for sampleRate 44100")
        } catch let error as SarvamError {
            guard case let .badRequestError(status, code, _, message, _) = error else {
                Issue.record("Expected badRequestError, got \(error)")
                return
            }
            #expect(status == 400)
            #expect(code == "invalid_sample_rate")
            #expect(message.contains("sampleRate must be 16000 or 8000"))
        }
    }

    // MARK: - Case 17: ws-stt-realtime
    @Test("Case 17: ws-stt-realtime (WebSocket STT Realtime Full Turn)")
    func testWsSttRealtime() async throws {
        let wsFactory = MockWebSocketFactory()
        let session = MockWebSocketSession()
        wsFactory.queueSession(session)

        let client = SarvamClient(
            apiKey: "test-api-key",
            webSocketFactory: wsFactory
        )

        let sttSession = try await client.speechToText.connect(
            config: SttRealtimeConfig(
                languageCode: .hiIn,
                model: .saarasV3Realtime,
                sampleRate: 16000
            )
        )

        #expect(wsFactory.connections.count == 1)
        #expect(wsFactory.connections[0].headers["Api-Subscription-Key"] == "test-api-key")

        // Client streams audio and ends
        try await sttSession.sendAudio("AAAA".data(using: .utf8)!)
        try await sttSession.end()

        #expect(session.sentMessages.count == 2)

        // Server emits frames
        session.emitServerMessage("{\"event\":\"session_begin\",\"session_id\":\"sess_stt_001\"}")
        session.emitServerMessage("{\"event\":\"vad_speech_start\",\"timestamp_ms\":100}")
        session.emitServerMessage("{\"event\":\"transcript_partial\",\"utterance_idx\":0,\"text\":\"नमस्ते\",\"language\":\"hi-IN\"}")
        session.emitServerMessage("{\"event\":\"transcript_final\",\"utterance_idx\":0,\"text\":\"नमस्ते!\",\"language\":\"hi-IN\",\"language_confidence\":0.99,\"start_s\":0.1,\"end_s\":1.5}")
        session.emitServerMessage("{\"event\":\"session_end\"}")
        session.finish()

        var receivedEvents: [SttRealtimeEvent] = []
        for try await evt in sttSession.events {
            receivedEvents.append(evt)
        }

        #expect(receivedEvents.count == 5)
        #expect(receivedEvents[0] == .sessionBegin(sessionId: "sess_stt_001"))
        #expect(receivedEvents[1] == .vadSpeechStart(timestampMs: 100))
        #expect(receivedEvents[2] == .transcriptPartial(utteranceIdx: 0, text: "नमस्ते", language: .hiIn))
        #expect(receivedEvents[3] == .transcriptFinal(utteranceIdx: 0, text: "नमस्ते!", language: .hiIn, languageConfidence: 0.99, startS: 0.1, endS: 1.5))
        #expect(receivedEvents[4] == .sessionEnd(durationSeconds: nil))
    }

    // MARK: - Case 18: ws-stt-subprotocol-auth
    @Test("Case 18: ws-stt-subprotocol-auth (WebSocket STT Subprotocol Authentication)")
    func testWsSttSubprotocolAuth() async throws {
        let wsFactory = MockWebSocketFactory()
        let session = MockWebSocketSession()
        wsFactory.queueSession(session)

        let client = SarvamClient(
            apiKey: "test-api-key",
            webSocketFactory: wsFactory
        )

        let sttSession = try await client.speechToText.connect(
            config: SttRealtimeConfig(
                languageCode: .hiIn,
                model: .saarasV3Realtime,
                sampleRate: 16000,
                useSubprotocolAuth: true
            )
        )

        #expect(wsFactory.connections.count == 1)
        #expect(wsFactory.connections[0].subprotocols.contains("api-subscription-key.test-api-key"))
        #expect(wsFactory.connections[0].headers["Api-Subscription-Key"] == nil)

        try await sttSession.sendAudio("AAAA".data(using: .utf8)!)
        try await sttSession.end()

        session.emitServerMessage("{\"event\":\"session_begin\",\"session_id\":\"sess_subprotocol_001\"}")
        session.emitServerMessage("{\"event\":\"transcript_final\",\"utterance_idx\":0,\"text\":\"नमस्ते!\",\"language\":\"hi-IN\"}")
        session.emitServerMessage("{\"event\":\"session_end\"}")
        session.finish()

        var events: [SttRealtimeEvent] = []
        for try await evt in sttSession.events {
            events.append(evt)
        }

        #expect(events.count == 3)
        #expect(events[1] == .transcriptFinal(utteranceIdx: 0, text: "नमस्ते!", language: .hiIn))
    }

    // MARK: - Case 19: ws-tts-streaming
    @Test("Case 19: ws-tts-streaming (WebSocket TTS Streaming Full Conversational Turn)")
    func testWsTtsStreaming() async throws {
        let wsFactory = MockWebSocketFactory()
        let session = MockWebSocketSession()
        wsFactory.queueSession(session)

        let client = SarvamClient(
            apiKey: "test-api-key",
            webSocketFactory: wsFactory
        )

        let ttsSession = try await client.textToSpeech.connect(
            config: TtsStreamingConfig(
                languageCode: .hiIn,
                speaker: Speaker(rawValue: "simran_en_customer"),
                model: .bulbulV4Flash,
                speechSampleRate: 22050,
                outputAudioCodec: .mp3
            )
        )

        // Verify config frame was sent immediately upon connection
        #expect(!session.sentMessages.isEmpty)
        if case .text(let firstMessage) = session.sentMessages[0] {
            #expect(firstMessage.contains("\"type\":\"config\""))
            #expect(firstMessage.contains("\"language_code\":\"hi-IN\""))
            #expect(firstMessage.contains("\"speaker\":\"simran_en_customer\""))
        } else {
            Issue.record("Expected first frame to be text config frame")
        }

        // Send text and flush
        try await ttsSession.sendText("नमस्ते भारत")
        try await ttsSession.flush()

        #expect(session.sentMessages.count == 3)

        // Server sends 2 audio chunks and final event
        let audioB64 = "UklGRiQAAABXQVZFZm10IBAAAAABAAEAQB8AAEAfAAABAAgAZGF0YQAAAAA="
        session.emitServerMessage("{\"type\":\"audio\",\"data\":{\"audio\":\"\(audioB64)\"}}")
        session.emitServerMessage("{\"type\":\"audio\",\"data\":{\"audio\":\"\(audioB64)\"}}")
        session.emitServerMessage("{\"type\":\"event\",\"data\":{\"event\":\"final\"}}")
        session.finish()

        var received: [TtsStreamEvent] = []
        for try await evt in ttsSession.events {
            received.append(evt)
        }

        #expect(received.count == 3)
        guard case let .audioChunk(bytes1, _, _) = received[0],
              case let .audioChunk(bytes2, _, _) = received[1],
              case .completed = received[2] else {
            Issue.record("Unexpected events: \(received)")
            return
        }

        #expect(bytes1.count == 44)
        #expect(bytes2.count == 44)
    }
}
