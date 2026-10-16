import Foundation

/// Incoming or outgoing WebSocket message frame.
public enum WebSocketMessage: Sendable, Equatable {
    case text(String)
    case data(Data)
}

/// Normalized WebSocket events emitted by a `WebSocketSession`.
public enum WebSocketEvent: Sendable {
    case open
    case message(WebSocketMessage)
    case close(code: Int, reason: String?)
    case error(SarvamError)
}
