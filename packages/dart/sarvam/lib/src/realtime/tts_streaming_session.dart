import 'dart:async';
import 'dart:convert';

import '../core/websocket_factory.dart';
import '../models/text_to_speech_models.dart';
import 'tts_streaming_events.dart';

/// Realtime text-to-speech streaming session over WebSocket.
class TtsStreamingSession {
  final WebSocketSession _session;
  final Stream<TtsStreamEvent> _events;

  TtsStreamingSession(this._session)
      : _events = _session.incoming
            .map<TtsStreamEvent>(TtsStreamEvent.fromJson)
            .asBroadcastStream();

  /// Stream of events emitted by the TTS server.
  Stream<TtsStreamEvent> get events => _events;

  /// Sends the initial configuration frame to the server upon session establishment.
  static void sendInitialConfig(
    WebSocketSession session,
    TtsStreamingConfig config,
  ) {
    session.send(jsonEncode(config.toConfigPayload()));
  }

  /// Sends a text fragment to be synthesized.
  void sendText(String text) {
    final payload = <String, dynamic>{
      'type': 'text',
      'data': <String, dynamic>{'text': text},
    };
    _session.send(jsonEncode(payload));
  }

  /// Flushes the audio synthesis queue.
  void flush() {
    _session.send(jsonEncode(<String, dynamic>{'type': 'flush'}));
  }

  /// Sends an application-level ping frame.
  void ping() {
    _session.send(jsonEncode(<String, dynamic>{'type': 'ping'}));
  }

  /// Closes the underlying WebSocket connection cleanly.
  Future<void> close([int? code = 1000, String? reason]) {
    return _session.close(code, reason);
  }
}
