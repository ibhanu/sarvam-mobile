import Foundation

/// Stateless request builder and response decoder for Chat completions endpoints.
public final class ChatResource: Sendable {
    private let config: SarvamClientConfig
    private let executor: RequestExecutor

    init(config: SarvamClientConfig) {
        self.config = config
        self.executor = RequestExecutor(config: config)
    }

    /// Creates a stateful session that maintains affinity via `x-session-affinity` header.
    public func createSession(affinityId: String? = nil) -> ChatSession {
        ChatSession(chatResource: self, affinityId: affinityId ?? UUID().uuidString)
    }

    /// Unary Chat completions (V1 OpenAI-compatible endpoint).
    public func completions(
        _ request: ChatCompletionRequest,
        options: RequestOptions? = nil
    ) async throws -> ChatCompletionResponse {
        var req = request
        req.stream = false
        return try await performCompletion(path: "/v1/chat/completions", request: req, options: options)
    }

    /// Streaming Chat completions (V1 OpenAI-compatible endpoint).
    public func completionsStream(
        _ request: ChatCompletionRequest,
        options: RequestOptions? = nil
    ) -> AsyncThrowingStream<ChatCompletionChunk, Error> {
        var req = request
        req.stream = true
        return performStreamingCompletion(path: "/v1/chat/completions", request: req, options: options)
    }

    /// Unary Chat completions (V2 Sarvam endpoint).
    public func completionsV2(
        _ request: ChatCompletionRequest,
        options: RequestOptions? = nil
    ) async throws -> ChatCompletionResponse {
        var req = request
        req.stream = false
        return try await performCompletion(path: "/v2/chat/completions", request: req, options: options)
    }

    /// Streaming Chat completions (V2 Sarvam endpoint).
    public func completionsV2Stream(
        _ request: ChatCompletionRequest,
        options: RequestOptions? = nil
    ) -> AsyncThrowingStream<ChatCompletionChunk, Error> {
        var req = request
        req.stream = true
        return performStreamingCompletion(path: "/v2/chat/completions", request: req, options: options)
    }

    /// Lists available chat models.
    public func listModels(options: RequestOptions? = nil) async throws -> ChatModelListResponse {
        let url = URL(string: "\(config.environment.apiBaseUrl)/v2/models")!
        let httpRequest = HTTPRequest(
            method: .get,
            url: url,
            headers: options?.headers ?? [:],
            operationKind: .idempotent,
            timeoutInterval: options?.timeoutInterval,
            idempotencyKey: options?.idempotencyKey
        )

        let response = try await executor.execute(request: httpRequest)
        let decoder = JSONDecoder()
        do {
            return try decoder.decode(ChatModelListResponse.self, from: response.body)
        } catch {
            throw SarvamError.decodingError(
                rawBody: String(data: response.body, encoding: .utf8),
                message: "Failed to decode ChatModelListResponse: \(error.localizedDescription)",
                cause: error.localizedDescription
            )
        }
    }

    /// Retrieves metadata for a specific chat model.
    public func getModel(
        _ modelId: String,
        options: RequestOptions? = nil
    ) async throws -> ChatModelInfo {
        let url = URL(string: "\(config.environment.apiBaseUrl)/v2/models/\(modelId)")!
        let httpRequest = HTTPRequest(
            method: .get,
            url: url,
            headers: options?.headers ?? [:],
            operationKind: .idempotent,
            timeoutInterval: options?.timeoutInterval,
            idempotencyKey: options?.idempotencyKey
        )

        let response = try await executor.execute(request: httpRequest)
        let decoder = JSONDecoder()
        do {
            return try decoder.decode(ChatModelInfo.self, from: response.body)
        } catch {
            throw SarvamError.decodingError(
                rawBody: String(data: response.body, encoding: .utf8),
                message: "Failed to decode ChatModelInfo: \(error.localizedDescription)",
                cause: error.localizedDescription
            )
        }
    }

    // MARK: - Internal Helpers

    private func performCompletion(
        path: String,
        request: ChatCompletionRequest,
        options: RequestOptions?
    ) async throws -> ChatCompletionResponse {
        let url = URL(string: "\(config.environment.apiBaseUrl)\(path)")!
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
            return try decoder.decode(ChatCompletionResponse.self, from: response.body)
        } catch {
            throw SarvamError.decodingError(
                rawBody: String(data: response.body, encoding: .utf8),
                message: "Failed to decode ChatCompletionResponse: \(error.localizedDescription)",
                cause: error.localizedDescription
            )
        }
    }

    private func performStreamingCompletion(
        path: String,
        request: ChatCompletionRequest,
        options: RequestOptions?
    ) -> AsyncThrowingStream<ChatCompletionChunk, Error> {
        let executor = self.executor
        let apiBaseUrl = config.environment.apiBaseUrl

        return AsyncThrowingStream<ChatCompletionChunk, Error> { continuation in
            let task = Task {
                do {
                    let url = URL(string: "\(apiBaseUrl)\(path)")!
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
                    let sseStream = SSEParser.parse(byteStream: dataStream, terminateOnDoneSentinel: true)
                    let decoder = JSONDecoder()

                    for try await event in sseStream {
                        guard let eventData = event.data.data(using: .utf8) else { continue }
                        do {
                            let chunk = try decoder.decode(ChatCompletionChunk.self, from: eventData)
                            continuation.yield(chunk)
                        } catch {
                            continuation.finish(throwing: SarvamError.decodingError(
                                rawBody: event.data,
                                message: "Failed to decode ChatCompletionChunk: \(error.localizedDescription)",
                                cause: error.localizedDescription
                            ))
                            return
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
}
