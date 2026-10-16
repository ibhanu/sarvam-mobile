import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// Abstract WebSocket session interface for realtime streaming.
public protocol WebSocketSession: Sendable {
    /// Sends a WebSocket message.
    func send(_ message: WebSocketMessage) async throws

    /// Cleanly closes the WebSocket connection.
    func close(code: Int, reason: String?) async throws

    /// Stream of incoming events.
    var events: AsyncThrowingStream<WebSocketEvent, Error> { get }
}

/// URLSessionWebSocketTask-backed WebSocketSession.
public final class URLSessionWebSocketSession: WebSocketSession, @unchecked Sendable {
    private let task: URLSessionWebSocketTask
    public let events: AsyncThrowingStream<WebSocketEvent, Error>
    private let continuation: AsyncThrowingStream<WebSocketEvent, Error>.Continuation

    public init(task: URLSessionWebSocketTask) {
        self.task = task
        var cont: AsyncThrowingStream<WebSocketEvent, Error>.Continuation!
        self.events = AsyncThrowingStream { continuation in
            cont = continuation
        }
        self.continuation = cont

        continuation.onTermination = { [weak task] _ in
            task?.cancel(with: .goingAway, reason: nil)
        }

        task.resume()
        startReceiveLoop()
    }

    public func send(_ message: WebSocketMessage) async throws {
        let wsMessage: URLSessionWebSocketTask.Message
        switch message {
        case .text(let string):
            wsMessage = .string(string)
        case .data(let data):
            wsMessage = .data(data)
        }

        do {
            try await task.send(wsMessage)
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            throw SarvamError.realtimeError(
                closeCode: nil,
                code: "send_error",
                message: "Failed to send WebSocket frame: \(error.localizedDescription)"
            )
        }
    }

    public func close(code: Int = 1000, reason: String? = nil) async throws {
        let reasonData = reason?.data(using: .utf8)
        let closeCode = URLSessionWebSocketTask.CloseCode(rawValue: code) ?? .normalClosure
        task.cancel(with: closeCode, reason: reasonData)
        continuation.finish()
    }

    private func startReceiveLoop() {
        Task { [weak self] in
            guard let self = self else { return }
            while !Task.isCancelled {
                do {
                    let message = try await self.task.receive()
                    switch message {
                    case .string(let text):
                        self.continuation.yield(.message(.text(text)))
                    case .data(let data):
                        self.continuation.yield(.message(.data(data)))
                    @unknown default:
                        break
                    }
                } catch is CancellationError {
                    self.continuation.finish(throwing: CancellationError())
                    break
                } catch {
                    let nsError = error as NSError
                    let closeCode = self.task.closeCode.rawValue
                    let reason = self.task.closeReason.flatMap { String(data: $0, encoding: .utf8) }

                    if closeCode != 0 && closeCode != URLSessionWebSocketTask.CloseCode.invalid.rawValue {
                        self.continuation.yield(.close(code: closeCode, reason: reason))
                    } else if nsError.domain == NSPOSIXErrorDomain || nsError.domain == NSURLErrorDomain {
                        self.continuation.yield(.close(code: 1006, reason: error.localizedDescription))
                    } else {
                        self.continuation.yield(.error(SarvamError.realtimeError(
                            closeCode: closeCode != 0 ? closeCode : nil,
                            code: "receive_error",
                            message: error.localizedDescription
                        )))
                    }
                    self.continuation.finish()
                    break
                }
            }
        }
    }
}
