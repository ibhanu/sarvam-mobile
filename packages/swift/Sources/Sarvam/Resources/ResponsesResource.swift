import Foundation

/// Stateless request builder for Responses API streaming.
public final class ResponsesResource: Sendable {
    private let config: SarvamClientConfig
    private let executor: RequestExecutor

    init(config: SarvamClientConfig) {
        self.config = config
        self.executor = RequestExecutor(config: config)
    }

    /// Creates a streaming session on `/v2/responses`.
    ///
    /// Terminates cleanly when `response.completed`, `response.failed`, or `response.incomplete`
    /// is encountered, without expecting a `[DONE]` sentinel line.
    public func createStream(
        _ request: ResponsesRequest,
        options: RequestOptions? = nil
    ) -> AsyncThrowingStream<SSEEvent, Error> {
        let executor = self.executor
        let apiBaseUrl = config.environment.apiBaseUrl

        return AsyncThrowingStream<SSEEvent, Error> { continuation in
            let task = Task {
                do {
                    let url = URL(string: "\(apiBaseUrl)/v2/responses")!
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

                    let sseStream = SSEParser.parse(
                        byteStream: dataStream,
                        terminateOnDoneSentinel: false,
                        customTermination: { event in
                            let evt = event.event ?? ""
                            if evt == "response.completed" || evt == "response.failed" || evt == "response.incomplete" {
                                return true
                            }
                            if event.data.contains("\"response.completed\"") ||
                                event.data.contains("\"response.failed\"") ||
                                event.data.contains("\"response.incomplete\"") {
                                return true
                            }
                            return false
                        }
                    )

                    for try await event in sseStream {
                        continuation.yield(event)
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
