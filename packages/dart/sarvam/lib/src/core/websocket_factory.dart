import 'dart:async';

/// Abstract session representing an open bidirectional WebSocket connection.
abstract interface class WebSocketSession {
  /// Stream emitting incoming raw WebSocket text or binary frames.
  Stream<dynamic> get incoming;

  /// Sends a text or binary frame across the socket.
  void send(dynamic data);

  /// Closes the socket connection cleanly with an optional close code and reason.
  Future<void> close([int? code, String? reason]);
}

/// Abstract factory for opening WebSocket connections across native and web platforms.
abstract interface class WebSocketFactory {
  /// Establishes a WebSocket connection to [uri].
  ///
  /// [headers] are sent during the handshake on native platforms.
  /// [protocols] defines the subprotocols (e.g. `['api-subscription-key.<key>']`).
  Future<WebSocketSession> connect(
    Uri uri, {
    Map<String, String>? headers,
    Iterable<String>? protocols,
  });
}
