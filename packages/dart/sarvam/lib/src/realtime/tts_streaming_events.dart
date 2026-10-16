import 'dart:convert';
import 'dart:typed_data';

/// Sealed union representing events received from a [TtsStreamingSession].
sealed class TtsStreamEvent {
  const TtsStreamEvent();

  factory TtsStreamEvent.fromJson(dynamic rawData) {
    if (rawData is! String) {
      if (rawData is Map<String, dynamic>) {
        return _fromMap(rawData, jsonEncode(rawData));
      }
      return UnknownTtsEvent(rawJson: rawData.toString(), data: const {});
    }

    try {
      final decoded = jsonDecode(rawData);
      if (decoded is Map<String, dynamic>) {
        return _fromMap(decoded, rawData);
      }
      return UnknownTtsEvent(rawJson: rawData, data: const {});
    } catch (_) {
      return UnknownTtsEvent(rawJson: rawData, data: const {});
    }
  }

  static TtsStreamEvent _fromMap(Map<String, dynamic> json, String rawJson) {
    final type = json['type'] as String? ?? '';
    final data = json['data'] is Map<String, dynamic>
        ? json['data'] as Map<String, dynamic>
        : const <String, dynamic>{};

    switch (type) {
      case 'audio':
        final b64 = data['audio'] as String? ?? json['audio'] as String? ?? '';
        final bytes = b64.isNotEmpty ? base64Decode(b64) : Uint8List(0);
        return TtsAudioChunk(
          audioBytes: bytes,
          contentType: data['content_type'] as String?,
          requestId: data['request_id'] as String?,
        );

      case 'event':
        final eventName =
            data['event'] as String? ?? data['event_type'] as String?;
        if (eventName == 'final' || eventName == 'completion') {
          return TtsCompleted(
            requestId: data['request_id'] as String?,
          );
        }
        return UnknownTtsEvent(rawJson: rawJson, data: json);

      case 'error':
        final msg = json['message'] as String? ??
            data['message'] as String? ??
            'TTS Streaming Error';
        final code = json['code'] as String? ?? data['code'] as String?;
        return TtsError(
          message: msg,
          code: code,
        );

      default:
        return UnknownTtsEvent(rawJson: rawJson, data: json);
    }
  }
}

final class TtsAudioChunk extends TtsStreamEvent {
  final Uint8List audioBytes;
  final String? contentType;
  final String? requestId;

  const TtsAudioChunk({
    required this.audioBytes,
    this.contentType,
    this.requestId,
  });

  @override
  String toString() =>
      'TtsAudioChunk(byteLength: ${audioBytes.length}, contentType: $contentType)';
}

final class TtsCompleted extends TtsStreamEvent {
  final String? requestId;

  const TtsCompleted({this.requestId});

  @override
  String toString() => 'TtsCompleted(requestId: $requestId)';
}

final class TtsError extends TtsStreamEvent {
  final String message;
  final String? code;

  const TtsError({
    required this.message,
    this.code,
  });

  @override
  String toString() => 'TtsError(message: $message, code: $code)';
}

final class UnknownTtsEvent extends TtsStreamEvent {
  final String rawJson;
  final Map<String, dynamic> data;

  const UnknownTtsEvent({
    required this.rawJson,
    required this.data,
  });

  @override
  String toString() => 'UnknownTtsEvent($rawJson)';
}
