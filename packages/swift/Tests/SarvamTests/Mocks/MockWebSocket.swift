import Foundation
@testable import Sarvam

public final class MockWebSocketSession: WebSocketSession, @unchecked Sendable {
    private var _sentMessages: [WebSocketMessage] = []
    public var sentMessages: [WebSocketMessage] {
        lock.withLock { _sentMessages }
    }

    private var _isClosed = false
    public var isClosed: Bool {
        lock.withLock { _isClosed }
    }

    private var _closeCode: Int?
    public var closeCode: Int? {
        lock.withLock { _closeCode }
    }

    private var _closeReason: String?
    public var closeReason: String? {
        lock.withLock { _closeReason }
    }

    public let events: AsyncThrowingStream<WebSocketEvent, Error>
    private let continuation: AsyncThrowingStream<WebSocketEvent, Error>.Continuation
    private let lock = NSLock()

    public init() {
        var cont: AsyncThrowingStream<WebSocketEvent, Error>.Continuation!
        self.events = AsyncThrowingStream { continuation in
            cont = continuation
        }
        self.continuation = cont
    }

    public func send(_ message: WebSocketMessage) async throws {
        lock.withLock {
            _sentMessages.append(message)
        }
    }

    public func close(code: Int = 1000, reason: String? = nil) async throws {
        lock.withLock {
            _isClosed = true
            _closeCode = code
            _closeReason = reason
        }
        continuation.finish()
    }

    public func emitServerMessage(_ text: String) {
        continuation.yield(.message(.text(text)))
    }

    public func emitServerData(_ data: Data) {
        continuation.yield(.message(.data(data)))
    }

    public func emitClose(code: Int, reason: String? = nil) {
        continuation.yield(.close(code: code, reason: reason))
        continuation.finish()
    }

    public func emitOpen() {
        continuation.yield(.open)
    }

    public func emitError(_ error: SarvamError) {
        continuation.yield(.error(error))
        continuation.finish()
    }

    public func finish() {
        continuation.finish()
    }
}

public final class MockWebSocketFactory: WebSocketFactory, @unchecked Sendable {
    public struct ConnectionRecord: Sendable {
        public let url: URL
        public let headers: [String: String]
        public let subprotocols: [String]
    }

    private var _connections: [ConnectionRecord] = []
    public var connections: [ConnectionRecord] {
        lock.withLock { _connections }
    }

    private var queuedSessions: [MockWebSocketSession] = []
    private var onConnectHandler: (@Sendable (ConnectionRecord, MockWebSocketSession) -> Void)?
    private let lock = NSLock()

    public init() {}

    public func queueSession(_ session: MockWebSocketSession) {
        lock.withLock {
            queuedSessions.append(session)
        }
    }

    public func onConnect(_ handler: @escaping @Sendable (ConnectionRecord, MockWebSocketSession) -> Void) {
        lock.withLock {
            self.onConnectHandler = handler
        }
    }

    public func connect(
        url: URL,
        headers: [String: String],
        subprotocols: [String]
    ) async throws -> any WebSocketSession {
        let record = ConnectionRecord(url: url, headers: headers, subprotocols: subprotocols)
        let (session, handler): (MockWebSocketSession, (@Sendable (ConnectionRecord, MockWebSocketSession) -> Void)?) = lock.withLock {
            _connections.append(record)
            let s: MockWebSocketSession
            if !queuedSessions.isEmpty {
                s = queuedSessions.removeFirst()
            } else {
                s = MockWebSocketSession()
            }
            return (s, onConnectHandler)
        }

        handler?(record, session)
        return session
    }
}
