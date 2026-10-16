import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// Factory protocol for creating WebSocket connections.
public protocol WebSocketFactory: Sendable {
    func connect(
        url: URL,
        headers: [String: String],
        subprotocols: [String]
    ) async throws -> any WebSocketSession
}

/// Standard production WebSocketFactory using `URLSession`.
public final class URLSessionWebSocketFactory: WebSocketFactory, @unchecked Sendable {
    private let session: URLSession

    public init(session: URLSession = .shared) {
        self.session = session
    }

    public func connect(
        url: URL,
        headers: [String: String],
        subprotocols: [String]
    ) async throws -> any WebSocketSession {
        var urlRequest = URLRequest(url: url)
        for (k, v) in headers {
            urlRequest.setValue(v, forHTTPHeaderField: k)
        }

        if !subprotocols.isEmpty {
            urlRequest.setValue(subprotocols.joined(separator: ", "), forHTTPHeaderField: "Sec-WebSocket-Protocol")
        }

        let task = session.webSocketTask(with: urlRequest)

        return URLSessionWebSocketSession(task: task)
    }
}
