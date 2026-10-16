import Foundation
@testable import Sarvam

public final class MockHTTPTransport: HTTPTransport, @unchecked Sendable {
    public typealias Handler = @Sendable (HTTPRequest) async throws -> HTTPResponse
    public typealias StreamHandler = @Sendable (HTTPRequest) async throws -> (HTTPResponse, AsyncThrowingStream<Data, Error>)

    private var handlers: [Handler] = []
    private var streamHandlers: [StreamHandler] = []
    private let lock = NSLock()

    private var _executedRequests: [HTTPRequest] = []
    public var executedRequests: [HTTPRequest] {
        lock.withLock { _executedRequests }
    }

    public init() {}

    public func queueResponse(_ response: HTTPResponse) {
        lock.withLock {
            handlers.append { _ in response }
        }
    }

    public func queueResponses(_ responses: [HTTPResponse]) {
        for res in responses {
            queueResponse(res)
        }
    }

    public func queueHandler(_ handler: @escaping Handler) {
        lock.withLock {
            handlers.append(handler)
        }
    }

    public func queueStreamHandler(_ handler: @escaping StreamHandler) {
        lock.withLock {
            streamHandlers.append(handler)
        }
    }

    public func queueStreamResponse(
        statusCode: Int = 200,
        headers: [String: String] = [:],
        chunks: [Data]
    ) {
        queueStreamHandler { _ in
            let response = HTTPResponse(statusCode: statusCode, headers: headers, body: Data())
            let stream = AsyncThrowingStream<Data, Error> { continuation in
                for chunk in chunks {
                    continuation.yield(chunk)
                }
                continuation.finish()
            }
            return (response, stream)
        }
    }

    public func execute(request: HTTPRequest) async throws -> HTTPResponse {
        let handler: Handler = lock.withLock {
            _executedRequests.append(request)
            if !handlers.isEmpty {
                return handlers.removeFirst()
            } else {
                return { _ in HTTPResponse(statusCode: 200, headers: [:], body: Data()) }
            }
        }

        return try await handler(request)
    }

    public func executeStream(request: HTTPRequest) async throws -> (HTTPResponse, AsyncThrowingStream<Data, Error>) {
        let streamHandler: StreamHandler = lock.withLock {
            _executedRequests.append(request)
            if !streamHandlers.isEmpty {
                return streamHandlers.removeFirst()
            } else {
                return { _ in
                    (
                        HTTPResponse(statusCode: 200, headers: [:], body: Data()),
                        AsyncThrowingStream { $0.finish() }
                    )
                }
            }
        }

        return try await streamHandler(request)
    }
}
