import 'dart:convert';
import 'dart:typed_data';

import 'package:sarvam/src/generated/sarvam_spec_generated.dart';
import '../core/file_input.dart';

/// Representation of a registered voice in the voice cloning library.
class Voice {
  final String voiceId;
  final String? name;
  final String? language;
  final String? gender;
  final String? style;
  final String? status;
  final String? referenceText;
  final String? createdAt;
  final String? updatedAt;
  final Map<String, dynamic> raw;

  const Voice({
    required this.voiceId,
    this.name,
    this.language,
    this.gender,
    this.style,
    this.status,
    this.referenceText,
    this.createdAt,
    this.updatedAt,
    this.raw = const <String, dynamic>{},
  });

  factory Voice.fromJson(Map<String, dynamic> json) {
    return Voice(
      voiceId: (json['voice_id'] ?? json['id'] ?? '').toString(),
      name: json['name'] as String?,
      language: json['language'] as String?,
      gender: json['gender'] as String?,
      style: json['style'] as String?,
      status: json['status'] as String?,
      referenceText: json['reference_text'] as String?,
      createdAt: json['created_at'] as String?,
      updatedAt: json['updated_at'] as String?,
      raw: json,
    );
  }

  @override
  String toString() => 'Voice(id: $voiceId, name: $name, status: $status)';
}

/// Response returned by [VoiceCloningResource.listVoices].
class VoiceListResponse {
  final List<Voice> voices;
  final Map<String, dynamic> raw;

  const VoiceListResponse({
    required this.voices,
    this.raw = const <String, dynamic>{},
  });

  factory VoiceListResponse.fromJson(dynamic json) {
    if (json is List<dynamic>) {
      final list = json
          .whereType<Map<String, dynamic>>()
          .map(Voice.fromJson)
          .toList();
      return VoiceListResponse(voices: list);
    }
    if (json is Map<String, dynamic>) {
      final voicesData = json['voices'] ?? json['data'] ?? const <dynamic>[];
      if (voicesData is List<dynamic>) {
        final list = voicesData
            .whereType<Map<String, dynamic>>()
            .map(Voice.fromJson)
            .toList();
        return VoiceListResponse(voices: list, raw: json);
      }
      return VoiceListResponse(voices: const [], raw: json);
    }
    return const VoiceListResponse(voices: []);
  }
}

/// Request parameters for creating a new voice in [VoiceCloningResource.createVoice].
class VoiceCreateRequest {
  final SarvamFileInput file;
  final String name;
  final LanguageCode language;
  final String? gender;
  final String? style;

  const VoiceCreateRequest({
    required this.file,
    required this.name,
    required this.language,
    this.gender,
    this.style,
  });

  Map<String, String> toFields() {
    final fields = <String, String>{
      'name': name,
      'language': language.value,
    };
    if (gender != null) fields['gender'] = gender!;
    if (style != null) fields['style'] = style!;
    return fields;
  }
}

/// Response returned by [VoiceCloningResource.createVoice].
class VoiceCreateResponse {
  final String voiceId;
  final String status;
  final String? referenceText;
  final Map<String, dynamic> raw;

  const VoiceCreateResponse({
    required this.voiceId,
    required this.status,
    this.referenceText,
    this.raw = const <String, dynamic>{},
  });

  factory VoiceCreateResponse.fromJson(Map<String, dynamic> json) {
    final data = json['data'] is Map<String, dynamic>
        ? json['data'] as Map<String, dynamic>
        : json;
    return VoiceCreateResponse(
      voiceId: (data['voice_id'] ?? '').toString(),
      status: (data['status'] ?? json['status'] ?? '').toString(),
      referenceText: data['reference_text'] as String?,
      raw: json,
    );
  }

  @override
  String toString() =>
      'VoiceCreateResponse(voiceId: $voiceId, status: $status)';
}

/// Request parameters for [VoiceCloningResource.convert] and [VoiceCloningResource.stream].
class VoiceCloneRequest {
  final String text;
  final LanguageCode languageCode;
  final String? voiceId;
  final SarvamFileInput? refAudio;
  final String? refText;
  final double? pace;
  final AudioCodec? outputAudioCodec;
  final String? outputAudioBitrate;
  final int? speechSampleRate;
  final bool? enableTextNormalization;

  const VoiceCloneRequest({
    required this.text,
    required this.languageCode,
    this.voiceId,
    this.refAudio,
    this.refText,
    this.pace,
    this.outputAudioCodec,
    this.outputAudioBitrate,
    this.speechSampleRate,
    this.enableTextNormalization,
  });

  Map<String, String> toFields() {
    final fields = <String, String>{
      'text': text,
      'language_code': languageCode.value,
    };
    if (voiceId != null) fields['voice_id'] = voiceId!;
    if (refText != null) fields['ref_text'] = refText!;
    if (pace != null) fields['pace'] = pace!.toString();
    if (outputAudioCodec != null) {
      fields['output_audio_codec'] = outputAudioCodec!.value;
    }
    if (outputAudioBitrate != null) {
      fields['output_audio_bitrate'] = outputAudioBitrate!;
    }
    if (speechSampleRate != null) {
      fields['speech_sample_rate'] = speechSampleRate!.toString();
    }
    if (enableTextNormalization != null) {
      fields['enable_text_normalization'] =
          enableTextNormalization!.toString();
    }
    return fields;
  }
}

/// Response returned by [VoiceCloningResource.convert].
class VoiceCloneResponse {
  final String audio;
  final String audioB64;
  final String requestId;
  final double? audioDuration;
  final Map<String, dynamic> raw;

  const VoiceCloneResponse({
    required this.audio,
    required this.audioB64,
    required this.requestId,
    this.audioDuration,
    this.raw = const <String, dynamic>{},
  });

  factory VoiceCloneResponse.fromJson(Map<String, dynamic> json) {
    final audioVal = json['audio'] as String? ?? json['audio_b64'] as String? ?? '';
    final audioB64Val = json['audio_b64'] as String? ?? audioVal;
    final reqId = json['request_id'] as String? ?? '';
    final duration = (json['audio_duration'] as num?)?.toDouble();

    return VoiceCloneResponse(
      audio: audioVal,
      audioB64: audioB64Val,
      requestId: reqId,
      audioDuration: duration,
      raw: json,
    );
  }

  /// Binary bytes decoded from the root Base64 audio field.
  Uint8List get audioBytes {
    if (audio.isNotEmpty) {
      return base64Decode(audio);
    }
    if (audioB64.isNotEmpty) {
      return base64Decode(audioB64);
    }
    return Uint8List(0);
  }

  @override
  String toString() =>
      'VoiceCloneResponse(requestId: $requestId, duration: $audioDuration, byteLength: ${audioBytes.length})';
}

/// Configuration options for opening a voice-cloning realtime WebSocket session.
class VoiceCloningStreamingConfig {
  final LanguageCode targetLanguageCode;
  final String? voiceId;
  final String? refAudio;
  final String? refText;
  final double? pace;
  final int? speechSampleRate;
  final AudioCodec? outputAudioCodec;
  final String? outputAudioBitrate;
  final int? minBufferSize;
  final int? maxChunkLength;
  final bool? enablePretts;
  final bool useSubprotocolAuth;

  const VoiceCloningStreamingConfig({
    required this.targetLanguageCode,
    this.voiceId,
    this.refAudio,
    this.refText,
    this.pace,
    this.speechSampleRate,
    this.outputAudioCodec,
    this.outputAudioBitrate,
    this.minBufferSize,
    this.maxChunkLength,
    this.enablePretts,
    this.useSubprotocolAuth = false,
  });

  Map<String, dynamic> toConfigPayload() {
    final data = <String, dynamic>{
      'target_language_code': targetLanguageCode.value,
    };
    if (voiceId != null) data['voice_id'] = voiceId;
    if (refAudio != null) data['ref_audio'] = refAudio;
    if (refText != null) data['ref_text'] = refText;
    if (pace != null) data['pace'] = pace;
    if (speechSampleRate != null) {
      data['speech_sample_rate'] = speechSampleRate;
    }
    if (outputAudioCodec != null) {
      data['output_audio_codec'] = outputAudioCodec!.value;
    }
    if (outputAudioBitrate != null) {
      data['output_audio_bitrate'] = outputAudioBitrate;
    }
    if (minBufferSize != null) data['min_buffer_size'] = minBufferSize;
    if (maxChunkLength != null) data['max_chunk_length'] = maxChunkLength;
    if (enablePretts != null) data['enable_pretts'] = enablePretts;

    return <String, dynamic>{
      'type': 'config',
      'data': data,
    };
  }
}
