import 'dart:convert';

import 'package:sarvam/src/generated/sarvam_spec_generated.dart';

/// Sealed union representing events received from an [SttRealtimeSession].
sealed class SttRealtimeEvent {
  const SttRealtimeEvent();

  factory SttRealtimeEvent.fromJson(dynamic rawData) {
    if (rawData is! String) {
      if (rawData is Map<String, dynamic>) {
        return _fromMap(rawData, jsonEncode(rawData));
      }
      return UnknownSttEvent(rawJson: rawData.toString(), data: const {});
    }

    try {
      final decoded = jsonDecode(rawData);
      if (decoded is Map<String, dynamic>) {
        return _fromMap(decoded, rawData);
      }
      return UnknownSttEvent(rawJson: rawData, data: const {});
    } catch (_) {
      return UnknownSttEvent(rawJson: rawData, data: const {});
    }
  }

  static SttRealtimeEvent _fromMap(Map<String, dynamic> json, String rawJson) {
    final eventName = json['event'] as String? ?? '';

    switch (eventName) {
      case 'session_begin':
        return SessionBegin(
          sessionId: json['session_id'] as String? ?? '',
        );

      case 'vad_speech_start':
      case 'speech_start':
        return VadSpeechStart(
          timestampMs: json['timestamp_ms'] as int?,
        );

      case 'vad_speech_end':
      case 'speech_end':
        return VadSpeechEnd(
          timestampMs: json['timestamp_ms'] as int?,
        );

      case 'transcript_partial':
        return TranscriptPartial(
          utteranceIdx: json['utterance_idx'] as int?,
          text: json['text'] as String? ?? '',
          language: json['language'] != null
              ? LanguageCode(json['language'] as String)
              : null,
        );

      case 'transcript_final':
      case 'transcript':
        return TranscriptFinal(
          utteranceIdx: json['utterance_idx'] as int?,
          text: json['text'] as String? ?? '',
          language: json['language'] != null
              ? LanguageCode(json['language'] as String)
              : null,
          languageConfidence: (json['language_confidence'] as num?)?.toDouble(),
          startS: (json['start_s'] as num?)?.toDouble(),
          endS: (json['end_s'] as num?)?.toDouble(),
        );

      case 'session_end':
        return SessionEnd(
          durationSeconds: (json['duration_seconds'] as num?)?.toDouble(),
        );

      case 'error':
        return SttError(
          code: json['code'] as String?,
          message: json['message'] as String? ?? 'STT Realtime Error',
        );

      default:
        return UnknownSttEvent(
          rawJson: rawJson,
          data: json,
        );
    }
  }
}

final class SessionBegin extends SttRealtimeEvent {
  final String sessionId;
  const SessionBegin({required this.sessionId});

  @override
  String toString() => 'SessionBegin(sessionId: $sessionId)';
}

final class VadSpeechStart extends SttRealtimeEvent {
  final int? timestampMs;
  const VadSpeechStart({this.timestampMs});

  @override
  String toString() => 'VadSpeechStart(timestampMs: $timestampMs)';
}

/// Convenience alias for [VadSpeechStart].
typedef SttVadSpeechStart = VadSpeechStart;

final class VadSpeechEnd extends SttRealtimeEvent {
  final int? timestampMs;
  const VadSpeechEnd({this.timestampMs});

  @override
  String toString() => 'VadSpeechEnd(timestampMs: $timestampMs)';
}

final class TranscriptPartial extends SttRealtimeEvent {
  final int? utteranceIdx;
  final String text;
  final LanguageCode? language;

  const TranscriptPartial({
    this.utteranceIdx,
    required this.text,
    this.language,
  });

  @override
  String toString() =>
      'TranscriptPartial(idx: $utteranceIdx, text: $text, lang: ${language?.value})';
}

final class TranscriptFinal extends SttRealtimeEvent {
  final int? utteranceIdx;
  final String text;
  final LanguageCode? language;
  final double? languageConfidence;
  final double? startS;
  final double? endS;

  const TranscriptFinal({
    this.utteranceIdx,
    required this.text,
    this.language,
    this.languageConfidence,
    this.startS,
    this.endS,
  });

  @override
  String toString() =>
      'TranscriptFinal(idx: $utteranceIdx, text: $text, lang: ${language?.value}, conf: $languageConfidence, start: $startS, end: $endS)';
}

final class SessionEnd extends SttRealtimeEvent {
  final double? durationSeconds;
  const SessionEnd({this.durationSeconds});

  @override
  String toString() => 'SessionEnd(durationSeconds: $durationSeconds)';
}

final class SttError extends SttRealtimeEvent {
  final String? code;
  final String message;

  const SttError({this.code, required this.message});

  @override
  String toString() => 'SttError(code: $code, message: $message)';
}

final class UnknownSttEvent extends SttRealtimeEvent {
  final String rawJson;
  final Map<String, dynamic> data;

  const UnknownSttEvent({
    required this.rawJson,
    required this.data,
  });

  @override
  String toString() => 'UnknownSttEvent($rawJson)';
}
