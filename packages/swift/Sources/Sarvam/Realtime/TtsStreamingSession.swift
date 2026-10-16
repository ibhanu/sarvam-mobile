import Foundation

/// Real-time streaming session for Text-to-Speech synthesis.
public actor TtsStreamingSession {
    private let socketSession: any WebSocketSession

    /// Non-isolated stream of incoming events for convenient async-for iteration.
    public nonisolated let events: AsyncThrowingStream<TtsStreamEvent, Error>

    /// Connects to the Sarvam TTS Streaming WebSocket endpoint and transmits initial configuration.
    public static func connect(
        config: TtsStreamingConfig,
        environment: SarvamEnvironment,
        authProvider: AuthProvider,
        webSocketFactory: WebSocketFactory,
        endpointPath: String? = nil
    ) async throws -> TtsStreamingSession {
        let basePath = endpointPath ?? (config.voiceId != nil ? "/voices/clone/ws" : "/text-to-speech/ws")
        let isVoiceCloning = basePath.contains("clone") || config.voiceId != nil

        var queryItems: [URLQueryItem] = [
            URLQueryItem(name: "send_completion_event", value: "true")
        ]
        if !isVoiceCloning {
            queryItems.append(URLQueryItem(name: "model", value: config.model.rawValue))
        }

        var urlComponents = URLComponents(string: "\(environment.wsBaseUrl)\(basePath)")
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

        // Immediately transmit initial config frame
        var configData: [String: Any] = [:]
        if let lang = config.languageCode {
            configData["language_code"] = lang.rawValue
        }
        if let spk = config.speaker {
            configData["speaker"] = spk.rawValue
        }
        if let voiceId = config.voiceId {
            configData["voice_id"] = voiceId
        } else {
            configData["model"] = config.model.rawValue
        }
        if let rate = config.speechSampleRate {
            configData["speech_sample_rate"] = rate
        }
        if let codec = config.outputAudioCodec {
            configData["output_audio_codec"] = codec.rawValue
        }

        let configFrame: [String: Any] = [
            "type": "config",
            "data": configData
        ]
        let json = try JSONSerialization.data(withJSONObject: configFrame)
        if let text = String(data: json, encoding: .utf8) {
            try await socket.send(.text(text))
        }

        return TtsStreamingSession(socketSession: socket)
    }

    init(socketSession: any WebSocketSession) {
        self.socketSession = socketSession

        let socketEvents = socketSession.events
        self.events = AsyncThrowingStream<TtsStreamEvent, Error> { continuation in
            let task = Task {
                do {
                    for try await event in socketEvents {
                        switch event {
                        case .open:
                            break
                        case .message(.text(let text)):
                            let parsed = TtsStreamEvent.parse(jsonString: text)
                            continuation.yield(parsed)
                        case .message(.data(let data)):
                            if let text = String(data: data, encoding: .utf8) {
                                let parsed = TtsStreamEvent.parse(jsonString: text)
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

    // MARK: - Outbound Protocol Methods

    /// Transmits text chunk for speech synthesis.
    public func sendText(_ text: String) async throws {
        let payload: [String: Any] = [
            "type": "text",
            "data": ["text": text]
        ]
        let json = try JSONSerialization.data(withJSONObject: payload)
        guard let text = String(data: json, encoding: .utf8) else { return }
        try await socketSession.send(.text(text))
    }

    /// Flushes synthesis pipeline.
    public func flush() async throws {
        try await socketSession.send(.text("{\"type\":\"flush\"}"))
    }

    /// Sends a ping frame.
    public func ping() async throws {
        try await socketSession.send(.text("{\"type\":\"ping\"}"))
    }

    /// Cleanly closes the WebSocket connection.
    public func close() async throws {
        try await socketSession.close(code: 1000, reason: "Session closed by client")
    }
}
