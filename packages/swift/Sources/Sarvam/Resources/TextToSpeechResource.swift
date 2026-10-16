import Foundation

/// Stateless request builder and response decoder for Text-to-Speech endpoints.
public final class TextToSpeechResource: Sendable {
    private let config: SarvamClientConfig
    private let executor: RequestExecutor

    init(config: SarvamClientConfig) {
        self.config = config
        self.executor = RequestExecutor(config: config)
    }

    /// Converts text into speech audio bytes.
    public func convert(
        _ request: TextToSpeechRequest,
        options: RequestOptions? = nil
    ) async throws -> TextToSpeechResponse {
        let url = URL(string: "\(config.environment.apiBaseUrl)/text-to-speech")!
        let encoder = JSONEncoder()
        let body = try encoder.encode(request)

        var headers = options?.headers ?? [:]
        headers["content-type"] = "application/json"

        let httpRequest = HTTPRequest(
            method: .post,
            url: url,
            headers: headers,
            body: body,
            operationKind: .statelessPost,
            timeoutInterval: options?.timeoutInterval,
            idempotencyKey: options?.idempotencyKey
        )

        let response = try await executor.execute(request: httpRequest)
        let decoder = JSONDecoder()
        do {
            return try decoder.decode(TextToSpeechResponse.self, from: response.body)
        } catch {
            throw SarvamError.decodingError(
                rawBody: String(data: response.body, encoding: .utf8),
                message: "Failed to decode TextToSpeechResponse: \(error.localizedDescription)",
                cause: error.localizedDescription
            )
        }
    }

    /// Streams raw binary audio chunks via HTTP chunked transfer.
    public func stream(
        _ request: TextToSpeechRequest,
        options: RequestOptions? = nil
    ) -> AsyncThrowingStream<Data, Error> {
        let executor = self.executor
        let apiBaseUrl = config.environment.apiBaseUrl

        return AsyncThrowingStream<Data, Error> { continuation in
            let task = Task {
                do {
                    let url = URL(string: "\(apiBaseUrl)/text-to-speech/stream")!
                    let encoder = JSONEncoder()
                    let body = try encoder.encode(request)

                    var headers = options?.headers ?? [:]
                    headers["content-type"] = "application/json"

                    let httpRequest = HTTPRequest(
                        method: .post,
                        url: url,
                        headers: headers,
                        body: body,
                        operationKind: .statelessPost,
                        timeoutInterval: options?.timeoutInterval,
                        idempotencyKey: options?.idempotencyKey
                    )

                    let (_, dataStream) = try await executor.executeStream(request: httpRequest)

                    for try await chunk in dataStream {
                        continuation.yield(chunk)
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

    /// Connects to the real-time WebSocket TTS streaming session.
    public func connect(
        config: TtsStreamingConfig = TtsStreamingConfig(),
        options: RequestOptions? = nil
    ) async throws -> TtsStreamingSession {
        try await TtsStreamingSession.connect(
            config: config,
            environment: self.config.environment,
            authProvider: self.config.authProvider,
            webSocketFactory: self.config.webSocketFactory
        )
    }
}
