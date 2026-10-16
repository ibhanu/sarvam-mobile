import Foundation

/// Real-time bidirectional streaming session for Speech-to-Text.
public actor SttRealtimeSession {
    private let socketSession: any WebSocketSession
    private var heartbeatTask: Task<Void, Never>?

    /// Non-isolated stream of incoming events for convenient async-for iteration.
    public nonisolated let events: AsyncThrowingStream<SttRealtimeEvent, Error>

    /// Connects to the Sarvam STT Realtime WebSocket endpoint.
    public static func connect(
        config: SttRealtimeConfig,
        environment: SarvamEnvironment,
        authProvider: AuthProvider,
        webSocketFactory: WebSocketFactory
    ) async throws -> SttRealtimeSession {
        // Client-side sample rate validation (throws immediately before connecting)
        guard config.sampleRate == 16000 || config.sampleRate == 8000 else {
            throw SarvamError.badRequestError(
                statusCode: 400,
                code: "invalid_sample_rate",
                requestId: nil,
                message: "sampleRate must be 16000 or 8000, got \(config.sampleRate)"
            )
        }

        // Build URL query parameters
        var queryItems: [URLQueryItem] = []
        if let lang = config.languageCode {
            queryItems.append(URLQueryItem(name: "language_code", value: lang.rawValue))
        }
        if let model = config.model {
            queryItems.append(URLQueryItem(name: "model", value: model.rawValue))
        }
        queryItems.append(URLQueryItem(name: "sample_rate", value: String(config.sampleRate)))
        if let streamType = config.streamType {
            queryItems.append(URLQueryItem(name: "stream_type", value: streamType))
        }
        if let mode = config.mode {
            queryItems.append(URLQueryItem(name: "mode", value: mode.rawValue))
        }
        if let encoding = config.encoding {
            queryItems.append(URLQueryItem(name: "encoding", value: encoding))
        }
        if let returnTimestamps = config.returnTimestamps {
            queryItems.append(URLQueryItem(name: "return_timestamps", value: String(returnTimestamps)))
        }
        if let endpointing = config.endpointing {
            queryItems.append(URLQueryItem(name: "endpointing", value: String(endpointing)))
        }
        if let threshold = config.threshold {
            queryItems.append(URLQueryItem(name: "threshold", value: String(threshold)))
        }
        if let prefix = config.prefixPaddingMs {
            queryItems.append(URLQueryItem(name: "prefix_padding_ms", value: String(prefix)))
        }
        if let silence = config.silenceDurationMs {
            queryItems.append(URLQueryItem(name: "silence_duration_ms", value: String(silence)))
        }
        if let minSpeech = config.minSpeechDurationMs {
            queryItems.append(URLQueryItem(name: "min_speech_duration_ms", value: String(minSpeech)))
        }
        if let prompt = config.prompt {
            queryItems.append(URLQueryItem(name: "prompt", value: prompt))
        }
        if let keyterms = config.keyterms {
            queryItems.append(URLQueryItem(name: "keyterms", value: keyterms.joined(separator: ",")))
        }

        var urlComponents = URLComponents(string: "\(environment.wsBaseUrl)/speech-to-text-realtime/ws")
        urlComponents?.queryItems = queryItems
        guard let url = urlComponents?.url else {
            throw SarvamError.badRequestError(statusCode: 400, code: "invalid_url", requestId: nil, message: "Invalid WebSocket URL")
        }

        // Obtain credentials
        var headers: [String: String] = [:]
        var subprotocols: [String] = config.subprotocols ?? []

        let credentials = try await authProvider.getCredentials()
        switch credentials {
        case .subscriptionKey(let key):
            if config.useSubprotocolAuth {
                subprotocols.append("api-subscription-key.\(key)")
            } else {
                headers["Api-Subscription-Key"] = key
            }
        case .bearerToken(let token, _):
            if config.useSubprotocolAuth {
                subprotocols.append("bearer.\(token)")
            } else {
                headers["Authorization"] = "Bearer \(token)"
            }
        case .customHeaders(let h):
            for (k, v) in h {
                headers[k] = v
            }
        }

        let socket = try await webSocketFactory.connect(
            url: url,
            headers: headers,
            subprotocols: subprotocols
        )

        let session = SttRealtimeSession(socketSession: socket)
        await session.startHeartbeat()
        return session
    }

    init(socketSession: any WebSocketSession) {
        self.socketSession = socketSession
        self.heartbeatTask = nil

        let socketEvents = socketSession.events
        self.events = AsyncThrowingStream<SttRealtimeEvent, Error> { continuation in
            let task = Task {
                do {
                    for try await event in socketEvents {
                        switch event {
                        case .open:
                            break
                        case .message(.text(let text)):
                            let parsed = SttRealtimeEvent.parse(jsonString: text)
                            continuation.yield(parsed)
                        case .message(.data(let data)):
                            if let text = String(data: data, encoding: .utf8) {
                                let parsed = SttRealtimeEvent.parse(jsonString: text)
                                continuation.yield(parsed)
                            }
                        case .close(let code, let reason):
                            if code != 1000 && code != 1001 {
                                continuation.finish(throwing: SarvamError.realtimeError(
                                    closeCode: code,
                                    code: "socket_closed",
                                    message: reason ?? "WebSocket closed with code \(code)"
                                ))
                            } else {
                                continuation.finish()
                            }
                        case .error(let err):
                            continuation.finish(throwing: err)
                        }
                    }
                    continuation.finish()
                } catch is CancellationError {
                    continuation.finish(throwing: CancellationError())
                } catch {
                    continuation.finish(throwing: error)
                }
            }

            continuation.onTermination = { @Sendable _ in
                task.cancel()
            }
        }
    }

    private func startHeartbeat() {
        self.heartbeatTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 20_000_000_000)
                guard let self = self else { break }
                try? await self.ping()
            }
        }
    }

    deinit {
        heartbeatTask?.cancel()
    }

    // MARK: - Outbound Protocol Methods

    /// Streams linear PCM 16-bit audio bytes to the session.
    public func sendAudio(_ pcmData: Data) async throws {
        let b64 = pcmData.base64EncodedString()
        let payload: [String: Any] = [
            "event": "audio_input",
            "audio": b64
        ]
        let json = try JSONSerialization.data(withJSONObject: payload)
        guard let text = String(data: json, encoding: .utf8) else { return }
        try await socketSession.send(.text(text))
    }

    /// Dynamically updates configuration parameters on the active stream.
    public func updateConfig(
        mode: SttMode? = nil,
        keyterms: [String]? = nil,
        threshold: Double? = nil,
        silenceDurationMs: Int? = nil
    ) async throws {
        var payload: [String: Any] = ["event": "config_update"]
        if let mode = mode {
            payload["mode"] = mode.rawValue
        }
        if let keyterms = keyterms {
            payload["keyterms"] = keyterms
        }
        if let threshold = threshold {
            payload["threshold"] = threshold
        }
        if let silence = silenceDurationMs {
            payload["silence_duration_ms"] = silence
        }
        let json = try JSONSerialization.data(withJSONObject: payload)
        guard let text = String(data: json, encoding: .utf8) else { return }
        try await socketSession.send(.text(text))
    }

    /// Flushes any pending audio buffers through inference.
    public func flush() async throws {
        try await socketSession.send(.text("{\"event\":\"flush\"}"))
    }

    /// Sends a ping heartbeat frame.
    public func ping() async throws {
        try await socketSession.send(.text("{\"event\":\"ping\"}"))
    }

    /// Signals end of input audio stream to the server.
    public func end() async throws {
        try await socketSession.send(.text("{\"event\":\"end\"}"))
    }

    /// Cleanly closes the WebSocket connection.
    public func close() async throws {
        heartbeatTask?.cancel()
        try await socketSession.close(code: 1000, reason: "Session closed by client")
    }
}
