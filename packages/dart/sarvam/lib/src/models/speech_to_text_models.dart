import 'package:sarvam/src/generated/sarvam_spec_generated.dart';

/// Response returned by [SpeechToTextResource.transcribe].
class SpeechToTextResponse {
  final String transcript;
  final LanguageCode? languageCode;
  final Map<String, dynamic> raw;

  const SpeechToTextResponse({
    required this.transcript,
    this.languageCode,
    this.raw = const <String, dynamic>{},
  });

  factory SpeechToTextResponse.fromJson(Map<String, dynamic> json) {
    return SpeechToTextResponse(
      transcript: json['transcript'] as String? ?? '',
      languageCode: json['language_code'] != null
          ? LanguageCode(json['language_code'] as String)
          : null,
      raw: json,
    );
  }

  @override
  String toString() => 'SpeechToTextResponse(transcript: $transcript)';
}

/// Response returned by [SpeechToTextResource.translate].
class SpeechToTextTranslateResponse {
  final String transcript;
  final String? translatedTranscript;
  final LanguageCode? sourceLanguageCode;
  final LanguageCode? targetLanguageCode;
  final Map<String, dynamic> raw;

  const SpeechToTextTranslateResponse({
    required this.transcript,
    this.translatedTranscript,
    this.sourceLanguageCode,
    this.targetLanguageCode,
    this.raw = const <String, dynamic>{},
  });

  factory SpeechToTextTranslateResponse.fromJson(Map<String, dynamic> json) {
    return SpeechToTextTranslateResponse(
      transcript: json['transcript'] as String? ?? '',
      translatedTranscript: json['translated_transcript'] as String?,
      sourceLanguageCode: json['source_language_code'] != null
          ? LanguageCode(json['source_language_code'] as String)
          : null,
      targetLanguageCode: json['target_language_code'] != null
          ? LanguageCode(json['target_language_code'] as String)
          : null,
      raw: json,
    );
  }

  @override
  String toString() =>
      'SpeechToTextTranslateResponse(transcript: $transcript, translated: $translatedTranscript)';
}

/// Configuration options for opening an [SttRealtimeSession].
class SttRealtimeConfig {
  final LanguageCode languageCode;
  final SttModel model;
  final int sampleRate;
  final String? streamType;
  final SttMode? mode;
  final String? encoding;
  final bool? returnTimestamps;
  final bool? endpointing;
  final double? threshold;
  final int? prefixPaddingMs;
  final int? silenceDurationMs;
  final int? minSpeechDurationMs;
  final String? prompt;
  final List<String>? keyterms;
  final bool useSubprotocolAuth;

  const SttRealtimeConfig({
    this.languageCode = LanguageCode.hiIn,
    this.model = SttModel.saarasV3Realtime,
    this.sampleRate = 16000,
    this.streamType,
    this.mode,
    this.encoding,
    this.returnTimestamps,
    this.endpointing,
    this.threshold,
    this.prefixPaddingMs,
    this.silenceDurationMs,
    this.minSpeechDurationMs,
    this.prompt,
    this.keyterms,
    this.useSubprotocolAuth = false,
  });

  Map<String, String> toQueryParams() {
    final params = <String, String>{
      'language_code': languageCode.value,
      'model': model.value,
      'sample_rate': sampleRate.toString(),
    };
    if (streamType != null) params['stream_type'] = streamType!;
    if (mode != null) params['mode'] = mode!.value;
    if (encoding != null) params['encoding'] = encoding!;
    if (returnTimestamps != null) {
      params['return_timestamps'] = returnTimestamps.toString();
    }
    if (endpointing != null) params['endpointing'] = endpointing.toString();
    if (threshold != null) params['threshold'] = threshold.toString();
    if (prefixPaddingMs != null) {
      params['prefix_padding_ms'] = prefixPaddingMs.toString();
    }
    if (silenceDurationMs != null) {
      params['silence_duration_ms'] = silenceDurationMs.toString();
    }
    if (minSpeechDurationMs != null) {
      params['min_speech_duration_ms'] = minSpeechDurationMs.toString();
    }
    if (prompt != null) params['prompt'] = prompt!;
    if (keyterms != null && keyterms!.isNotEmpty) {
      params['keyterms'] = keyterms!.join(',');
    }
    return params;
  }
}
