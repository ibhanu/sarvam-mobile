import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:sarvam/src/generated/sarvam_spec_generated.dart';
import '../core/exceptions.dart';
import '../core/websocket_factory.dart';
import 'stt_realtime_events.dart';

/// Realtime bi-directional streaming speech-to-text session over WebSocket.
class SttRealtimeSession {
  final WebSocketSession _session;
  final Stream<SttRealtimeEvent> _events;

  SttRealtimeSession(this._session)
      : _events = _session.incoming
            .map<SttRealtimeEvent>(SttRealtimeEvent.fromJson)
            .asBroadcastStream();

  /// Stream of events emitted by the server.
  Stream<SttRealtimeEvent> get events => _events;

  /// Sends raw PCM audio bytes to the server as Base64.
  void sendAudio(Uint8List pcmBytes) {
    final payload = <String, dynamic>{
      'event': 'audio_input',
      'audio': base64Encode(pcmBytes),
    };
    _session.send(jsonEncode(payload));
  }

  /// Sends a configuration update mid-session.
  void updateConfig({
    SttMode? mode,
    List<String>? keyterms,
    double? threshold,
    int? silenceDurationMs,
  }) {
    final payload = <String, dynamic>{
      'event': 'config_update',
    };
    if (mode != null) payload['mode'] = mode.value;
    if (keyterms != null) payload['keyterms'] = keyterms;
    if (threshold != null) payload['threshold'] = threshold;
    if (silenceDurationMs != null) {
      payload['silence_duration_ms'] = silenceDurationMs;
    }
    _session.send(jsonEncode(payload));
  }

  /// Flushes any pending audio buffers.
  void flush() {
    _session.send(jsonEncode(<String, dynamic>{'event': 'flush'}));
  }

  /// Sends an application-level ping frame.
  void ping() {
    _session.send(jsonEncode(<String, dynamic>{'event': 'ping'}));
  }

  /// Notifies the server that audio stream input has finished.
  void end() {
    _session.send(jsonEncode(<String, dynamic>{'event': 'end'}));
  }

  /// Closes the underlying WebSocket connection cleanly.
  Future<void> close([int? code = 1000, String? reason]) {
    return _session.close(code, reason);
  }

  /// Validates [sampleRate] before establishing the WebSocket connection.
  /// Throws [BadRequestException] if not 16000 or 8000.
  static void validateSampleRate(int sampleRate) {
    if (sampleRate != 16000 && sampleRate != 8000) {
      throw const BadRequestException(
        statusCode: 400,
        code: 'bad_request',
        message: 'sampleRate must be 16000 or 8000',
      );
    }
  }
}
