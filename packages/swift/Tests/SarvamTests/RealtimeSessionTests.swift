import Foundation
import Testing
@testable import Sarvam

@Suite("STT Realtime & TTS Streaming Sessions Tests")
struct RealtimeSessionTests {
    // MARK: - SttRealtimeEvent Parsing Tests
    @Test("SttRealtimeEvent parse all event types")
    func testSttRealtimeEventParsing() {
        // session_begin
        let begin = SttRealtimeEvent.parse(jsonString: "{\"event\":\"session_begin\",\"session_id\":\"sess-1\"}")
        #expect(begin == .sessionBegin(sessionId: "sess-1"))

        // vad_speech_start / speech_start
        let vStart1 = SttRealtimeEvent.parse(jsonString: "{\"event\":\"vad_speech_start\",\"timestamp_ms\":150}")
        #expect(vStart1 == .vadSpeechStart(timestampMs: 150))
        let vStart2 = SttRealtimeEvent.parse(jsonString: "{\"event\":\"speech_start\",\"timestamp_ms\":200}")
        #expect(vStart2 == .vadSpeechStart(timestampMs: 200))

        // vad_speech_end / speech_end
        let vEnd1 = SttRealtimeEvent.parse(jsonString: "{\"event\":\"vad_speech_end\",\"timestamp_ms\":350}")
        #expect(vEnd1 == .vadSpeechEnd(timestampMs: 350))
        let vEnd2 = SttRealtimeEvent.parse(jsonString: "{\"event\":\"speech_end\",\"timestamp_ms\":400}")
        #expect(vEnd2 == .vadSpeechEnd(timestampMs: 400))

        // transcript_partial
        let partial = SttRealtimeEvent.parse(jsonString: "{\"event\":\"transcript_partial\",\"utterance_idx\":1,\"text\":\"Nam\",\"language\":\"hi-IN\"}")
        #expect(partial == .transcriptPartial(utteranceIdx: 1, text: "Nam", language: .hiIn))

        // transcript_final / transcript
        let final1 = SttRealtimeEvent.parse(jsonString: "{\"event\":\"transcript_final\",\"utterance_idx\":1,\"text\":\"Namaste\",\"language\":\"hi-IN\",\"language_confidence\":0.95,\"start_s\":0.1,\"end_s\":0.8}")
        #expect(final1 == .transcriptFinal(utteranceIdx: 1, text: "Namaste", language: .hiIn, languageConfidence: 0.95, startS: 0.1, endS: 0.8))

        let final2 = SttRealtimeEvent.parse(jsonString: "{\"event\":\"transcript\",\"text\":\"Hello\"}")
        #expect(final2 == .transcriptFinal(utteranceIdx: nil, text: "Hello", language: nil))

        // session_end
        let end = SttRealtimeEvent.parse(jsonString: "{\"event\":\"session_end\",\"duration_seconds\":12.5}")
        #expect(end == .sessionEnd(durationSeconds: 12.5))

        // error
        let err = SttRealtimeEvent.parse(jsonString: "{\"event\":\"error\",\"code\":\"stt_err\",\"message\":\"bad audio\"}")
        #expect(err == .error(code: "stt_err", message: "bad audio"))

        // unknown & invalid JSON
        let unk = SttRealtimeEvent.parse(jsonString: "{\"event\":\"custom_event\"}")
        #expect(unk == .unknown(rawJson: "{\"event\":\"custom_event\"}"))
        let inv = SttRealtimeEvent.parse(jsonString: "invalid-json")
        #expect(inv == .unknown(rawJson: "invalid-json"))
    }

    // MARK: - SttRealtimeSession Connection, Events & Outbound Tests
    @Test("SttRealtimeSession connection query params, auth, events, and outbound commands")
    func testSttRealtimeSessionFull() async throws {
        let wsFactory = MockWebSocketFactory()
        let wsSession = MockWebSocketSession()
        wsFactory.queueSession(wsSession)

        let config = SttRealtimeConfig(
            languageCode: .hiIn,
            model: "saaras:v2",
            sampleRate: 16000,
            streamType: "raw",
            mode: "conversational",
            encoding: "pcm_s16le",
            returnTimestamps: true,
            endpointing: true,
            threshold: 0.5,
            prefixPaddingMs: 100,
            silenceDurationMs: 300,
            minSpeechDurationMs: 150,
            prompt: "Test context",
            keyterms: ["term1", "term2"],
            useSubprotocolAuth: false
        )

        let env = SarvamEnvironment.production
        let auth = ApiKeyAuth(apiKey: "stt-key")

        let session = try await SttRealtimeSession.connect(
            config: config,
            environment: env,
            authProvider: auth,
            webSocketFactory: wsFactory
        )

        // Verify connection parameters
        let conn = wsFactory.connections.last!
        #expect(conn.url.query?.contains("sample_rate=16000") == true)
        #expect(conn.url.query?.contains("language_code=hi-IN") == true)
        #expect(conn.url.query?.contains("model=saaras%3Av2") == true || conn.url.query?.contains("model=saaras:v2") == true)
        #expect(conn.url.query?.contains("keyterms=term1%2Cterm2") == true || conn.url.query?.contains("keyterms=term1,term2") == true)
        #expect(conn.headers["Api-Subscription-Key"] == "stt-key")

        // Inbound event handling
        let eventTask = Task {
            var received: [SttRealtimeEvent] = []
            for try await ev in session.events {
                received.append(ev)
            }
            return received
        }

        wsSession.emitServerMessage("{\"event\":\"session_begin\",\"session_id\":\"s-1\"}")
        wsSession.emitServerData(Data("{\"event\":\"transcript_partial\",\"text\":\"Nam\"}".utf8))
        wsSession.emitClose(code: 1000)

        let events = try await eventTask.value
        #expect(events.count == 2)
        #expect(events[0] == SttRealtimeEvent.sessionBegin(sessionId: "s-1"))
        #expect(events[1] == SttRealtimeEvent.transcriptPartial(utteranceIdx: nil, text: "Nam", language: nil))

        // Outbound methods
        try await session.sendAudio(Data([0, 1, 2, 3]))
        try await session.updateConfig(mode: .transcribe, keyterms: ["newterm"], threshold: 0.7, silenceDurationMs: 400)
        try await session.flush()
        try await session.ping()
        try await session.end()
        try await session.close()

        #expect(wsSession.sentMessages.count >= 5)
        #expect(wsSession.isClosed)
    }

    @Test("SttRealtimeSession connection subprotocol auth and sample rate rejection")
    func testSttRealtimeSessionAuthVariations() async throws {
        let wsFactory = MockWebSocketFactory()

        // 1. Invalid sample rate rejection
        let invalidConfig = SttRealtimeConfig(sampleRate: 44100)
        await #expect(throws: SarvamError.self) {
            _ = try await SttRealtimeSession.connect(
                config: invalidConfig,
                environment: .production,
                authProvider: ApiKeyAuth(apiKey: "k"),
                webSocketFactory: wsFactory
            )
        }

        // 2. TokenAuth with subprotocol auth
        let tokenWsSession = MockWebSocketSession()
        wsFactory.queueSession(tokenWsSession)
        let tokenAuth = TokenAuth(tokenProvider: { AuthToken(token: "my-bearer-token") })
        let tokenConfig = SttRealtimeConfig(sampleRate: 8000, useSubprotocolAuth: true)
        let tokenSession = try await SttRealtimeSession.connect(
            config: tokenConfig,
            environment: .production,
            authProvider: tokenAuth,
            webSocketFactory: wsFactory
        )
        let tokenConn = wsFactory.connections.last!
        #expect(tokenConn.subprotocols.contains("bearer.my-bearer-token"))
        try await tokenSession.close()

        // 3. ProxyAuth (custom headers)
        let proxyWsSession = MockWebSocketSession()
        wsFactory.queueSession(proxyWsSession)
        let proxyAuth = ProxyAuth(proxyBaseUrl: "https://proxy.com", headersProvider: { ["X-Custom": "val"] })
        let proxyConfig = SttRealtimeConfig(sampleRate: 16000)
        let proxySession = try await SttRealtimeSession.connect(
            config: proxyConfig,
            environment: .production,
            authProvider: proxyAuth,
            webSocketFactory: wsFactory
        )
        let proxyConn = wsFactory.connections.last!
        #expect(proxyConn.headers["X-Custom"] == "val")
        try await proxySession.close()
    }

    @Test("SttRealtimeSession abnormal close code throws realtimeError")
    func testSttRealtimeSessionAbnormalClose() async throws {
        let wsFactory = MockWebSocketFactory()
        let wsSession = MockWebSocketSession()
        wsFactory.queueSession(wsSession)

        let session = try await SttRealtimeSession.connect(
            config: SttRealtimeConfig(sampleRate: 16000),
            environment: .production,
            authProvider: ApiKeyAuth(apiKey: "k"),
            webSocketFactory: wsFactory
        )

        let eventTask = Task {
            for try await _ in session.events {}
        }

        wsSession.emitClose(code: 1006, reason: "Connection dropped abnormally")

        await #expect(throws: SarvamError.self) {
            try await eventTask.value
        }
    }

    // MARK: - TtsStreamEvent Parsing Tests
    @Test("TtsStreamEvent parse all event types")
    func testTtsStreamEventParsing() {
        // audio with data dict
        let audio1 = TtsStreamEvent.parse(jsonString: "{\"type\":\"audio\",\"data\":{\"audio\":\"AQIDBA==\",\"content_type\":\"audio/wav\",\"request_id\":\"req-1\"}}")
        #expect(audio1 == .audioChunk(audioBytes: Data([1, 2, 3, 4]), contentType: "audio/wav", requestId: "req-1"))

        // audio with root fields
        let audio2 = TtsStreamEvent.parse(jsonString: "{\"type\":\"audio\",\"audio\":\"AQIDBA==\",\"request_id\":\"req-2\"}")
        #expect(audio2 == .audioChunk(audioBytes: Data([1, 2, 3, 4]), contentType: nil, requestId: "req-2"))

        // audio with invalid base64
        let badAudio = TtsStreamEvent.parse(jsonString: "{\"type\":\"audio\",\"audio\":\"not-base-64!!\"}")
        #expect(badAudio == .unknown(rawJson: "{\"type\":\"audio\",\"audio\":\"not-base-64!!\"}"))

        // event final / completion / unknown event name
        let finalEv = TtsStreamEvent.parse(jsonString: "{\"type\":\"event\",\"data\":{\"event\":\"final\",\"request_id\":\"req-1\"}}")
        #expect(finalEv == .completed(requestId: "req-1"))
        let compEv = TtsStreamEvent.parse(jsonString: "{\"type\":\"event\",\"data\":{\"event_type\":\"completion\",\"request_id\":\"req-2\"}}")
        #expect(compEv == .completed(requestId: "req-2"))
        let otherEv = TtsStreamEvent.parse(jsonString: "{\"type\":\"event\",\"data\":{\"event\":\"progress\"}}")
        #expect(otherEv == .unknown(rawJson: "{\"type\":\"event\",\"data\":{\"event\":\"progress\"}}"))

        // error with and without code
        let errEv = TtsStreamEvent.parse(jsonString: "{\"type\":\"error\",\"data\":{\"message\":\"TTS failed\",\"code\":\"tts_err\"}}")
        #expect(errEv == .error(message: "TTS failed", code: "tts_err"))
        let errEvNoCode = TtsStreamEvent.parse(jsonString: "{\"type\":\"error\"}")
        #expect(errEvNoCode == .error(message: "Unknown TTS error"))

        // unknown & invalid JSON
        let unk = TtsStreamEvent.parse(jsonString: "{\"type\":\"ping\"}")
        #expect(unk == .unknown(rawJson: "{\"type\":\"ping\"}"))
        let inv = TtsStreamEvent.parse(jsonString: "not-json")
        #expect(inv == .unknown(rawJson: "not-json"))
        #expect(SttRealtimeEvent.sessionEnd() == .sessionEnd(durationSeconds: nil))
    }

    // MARK: - TtsStreamingSession Connection, Events & Outbound Tests
    @Test("TtsStreamingSession connection, initial config frame, events, and outbound commands")
    func testTtsStreamingSessionFull() async throws {
        let wsFactory = MockWebSocketFactory()
        let wsSession = MockWebSocketSession()
        wsFactory.queueSession(wsSession)

        let config = TtsStreamingConfig(
            languageCode: .hiIn,
            speaker: .anushka,
            model: .bulbulV2,
            speechSampleRate: 22050,
            outputAudioCodec: .wav
        )

        let session = try await TtsStreamingSession.connect(
            config: config,
            environment: .production,
            authProvider: ApiKeyAuth(apiKey: "tts-key"),
            webSocketFactory: wsFactory
        )

        // Verify initial config frame sent
        #expect(wsSession.sentMessages.count == 1)
        if case let .text(txt) = wsSession.sentMessages.first {
            #expect(txt.contains("config"))
            #expect(txt.contains("anushka"))
            #expect(txt.contains("hi-IN"))
            #expect(txt.contains("22050"))
        } else {
            #expect(Bool(false), "Expected initial config message")
        }

        // Inbound event handling
        let eventTask = Task {
            var received: [TtsStreamEvent] = []
            for try await ev in session.events {
                received.append(ev)
            }
            return received
        }

        wsSession.emitServerMessage("{\"type\":\"audio\",\"data\":{\"audio\":\"AQIDBA==\"}}")
        wsSession.emitServerData(Data("{\"type\":\"event\",\"data\":{\"event\":\"final\"}}".utf8))
        wsSession.emitClose(code: 1000)

        let events = try await eventTask.value
        #expect(events.count == 2)
        #expect(events[0] == TtsStreamEvent.audioChunk(audioBytes: Data([1, 2, 3, 4])))
        #expect(events[1] == TtsStreamEvent.completed())

        // Outbound methods
        try await session.sendText("Hello world")
        try await session.flush()
        try await session.ping()
        try await session.close()

        #expect(wsSession.sentMessages.count >= 4)
        #expect(wsSession.isClosed)
    }

    @Test("TtsStreamingSession voiceId routing and abnormal close")
    func testTtsStreamingSessionVoiceIdAndClose() async throws {
        let wsFactory = MockWebSocketFactory()
        let wsSession = MockWebSocketSession()
        wsFactory.queueSession(wsSession)

        let config = TtsStreamingConfig(
            languageCode: .hiIn,
            voiceId: "cloned-voice-1"
        )

        let session = try await TtsStreamingSession.connect(
            config: config,
            environment: .production,
            authProvider: ApiKeyAuth(apiKey: "key"),
            webSocketFactory: wsFactory
        )

        let conn = wsFactory.connections.last!
        #expect(conn.url.path.contains("voices/clone/ws"))

        let eventTask = Task {
            for try await _ in session.events {}
        }
        wsSession.emitClose(code: 1006, reason: "Socket dropped")
        await #expect(throws: SarvamError.self) {
            try await eventTask.value
        }

        // Subprotocol auth with ApiKeyAuth and TokenAuth + ProxyAuth + error event
        let wsSession2 = MockWebSocketSession()
        wsFactory.queueSession(wsSession2)
        let subConfig = TtsStreamingConfig(useSubprotocolAuth: true)
        let session2 = try await TtsStreamingSession.connect(
            config: subConfig,
            environment: .production,
            authProvider: ApiKeyAuth(apiKey: "sub-key"),
            webSocketFactory: wsFactory
        )
        #expect(wsFactory.connections.last?.subprotocols.contains("api-subscription-key.sub-key") == true)
        try await session2.close()

        let wsSession3 = MockWebSocketSession()
        wsFactory.queueSession(wsSession3)
        let session3 = try await TtsStreamingSession.connect(
            config: TtsStreamingConfig(useSubprotocolAuth: true),
            environment: .production,
            authProvider: TokenAuth(tokenProvider: { AuthToken(token: "tok-1") }),
            webSocketFactory: wsFactory
        )
        #expect(wsFactory.connections.last?.subprotocols.contains("bearer.tok-1") == true)
        try await session3.close()

        let wsSession4 = MockWebSocketSession()
        wsFactory.queueSession(wsSession4)
        let session4 = try await TtsStreamingSession.connect(
            config: TtsStreamingConfig(useSubprotocolAuth: false),
            environment: .production,
            authProvider: TokenAuth(tokenProvider: { AuthToken(token: "tok-2") }),
            webSocketFactory: wsFactory
        )
        #expect(wsFactory.connections.last?.headers["Authorization"] == "Bearer tok-2")
        try await session4.close()

        let wsSession5 = MockWebSocketSession()
        wsFactory.queueSession(wsSession5)
        let session5 = try await TtsStreamingSession.connect(
            config: TtsStreamingConfig(),
            environment: .production,
            authProvider: ProxyAuth(proxyBaseUrl: "https://proxy.com", headersProvider: { ["X-Tts-Proxy": "yes"] }),
            webSocketFactory: wsFactory
        )
        #expect(wsFactory.connections.last?.headers["X-Tts-Proxy"] == "yes")
        let errTask = Task {
            for try await _ in session5.events {}
        }
        wsSession5.emitError(SarvamError.connectionError(message: "ws failed"))
        await #expect(throws: SarvamError.self) {
            try await errTask.value
        }
    }
}
