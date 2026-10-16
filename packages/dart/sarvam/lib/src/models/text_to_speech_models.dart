import 'dart:convert';
import 'dart:typed_data';

import 'package:sarvam/src/generated/sarvam_spec_generated.dart';

/// Request parameters for [TextToSpeechResource.convert] and [TextToSpeechResource.stream].
class TextToSpeechRequest {
  final String text;
  final LanguageCode targetLanguageCode;
  final Speaker? speaker;
  final TtsModel? model;
  final double? pitch;
  final double? pace;
  final double? loudness;
  final int? speechSampleRate;
  final bool? enablePreprocessing;
  final AudioCodec? outputAudioCodec;

  const TextToSpeechRequest({
    required this.text,
    required this.targetLanguageCode,
    this.speaker,
    this.model,
    this.pitch,
    this.pace,
    this.loudness,
    this.speechSampleRate,
    this.enablePreprocessing,
    this.outputAudioCodec,
  });

  Map<String, dynamic> toJson() {
    final map = <String, dynamic>{
      'text': text,
      'target_language_code': targetLanguageCode.value,
    };
    if (speaker != null) map['speaker'] = speaker!.value;
    if (model != null) map['model'] = model!.value;
    if (pitch != null) map['pitch'] = pitch;
    if (pace != null) map['pace'] = pace;
    if (loudness != null) map['loudness'] = loudness;
    if (speechSampleRate != null) {
      map['speech_sample_rate'] = speechSampleRate;
    }
    if (enablePreprocessing != null) {
      map['enable_preprocessing'] = enablePreprocessing;
    }
    if (outputAudioCodec != null) {
      map['output_audio_codec'] = outputAudioCodec!.value;
    }
    return map;
  }
}

/// Single audio item containing Base64 encoded audio.
class TtsAudioItem {
  final String audio;

  const TtsAudioItem({required this.audio});

  factory TtsAudioItem.fromJson(dynamic json) {
    if (json is String) {
      return TtsAudioItem(audio: json);
    }
    if (json is Map<String, dynamic>) {
      return TtsAudioItem(audio: json['audio'] as String? ?? '');
    }
    return TtsAudioItem(audio: json.toString());
  }

  Uint8List get bytes => base64Decode(audio);
}

/// Response returned by [TextToSpeechResource.convert].
class TextToSpeechResponse {
  final List<TtsAudioItem> audios;
  final Map<String, dynamic> raw;

  const TextToSpeechResponse({
    required this.audios,
    this.raw = const <String, dynamic>{},
  });

  factory TextToSpeechResponse.fromJson(Map<String, dynamic> json) {
    final audiosJson = json['audios'] as List<dynamic>? ?? const [];
    final audiosList = audiosJson.map(TtsAudioItem.fromJson).toList();
    return TextToSpeechResponse(
      audios: audiosList,
      raw: json,
    );
  }

  /// Total number of generated audio items.
  int get audioCount => audios.length;

  /// Base64 payload of the primary/first audio item, or null if empty.
  String? get firstAudioBase64 => audios.isNotEmpty ? audios.first.audio : null;

  /// Binary bytes decoded from the first audio item's Base64 payload.
  Uint8List get audioBytes {
    if (audios.isEmpty) {
      return Uint8List(0);
    }
    return audios.first.bytes;
  }

  /// Byte length of the first decoded audio item.
  int get firstAudioByteLength => audioBytes.length;

  @override
  String toString() =>
      'TextToSpeechResponse(audioCount: $audioCount, firstAudioByteLength: $firstAudioByteLength)';
}

/// Configuration options for opening a [TtsStreamingSession].
class TtsStreamingConfig {
  final LanguageCode languageCode;
  final Speaker speaker;
  final TtsModel model;
  final int? speechSampleRate;
  final AudioCodec? outputAudioCodec;
  final bool useSubprotocolAuth;

  const TtsStreamingConfig({
    required this.languageCode,
    required this.speaker,
    this.model = TtsModel.bulbulV4Flash,
    this.speechSampleRate,
    this.outputAudioCodec,
    this.useSubprotocolAuth = false,
  });

  Map<String, dynamic> toConfigPayload() {
    final data = <String, dynamic>{
      'language_code': languageCode.value,
      'speaker': speaker.value,
      'model': model.value,
    };
    if (speechSampleRate != null) {
      data['speech_sample_rate'] = speechSampleRate;
    }
    if (outputAudioCodec != null) {
      data['output_audio_codec'] = outputAudioCodec!.value;
    }
    return <String, dynamic>{
      'type': 'config',
      'data': data,
    };
  }
}
