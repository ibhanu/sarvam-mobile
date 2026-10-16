import 'package:sarvam/src/generated/sarvam_spec_generated.dart';

/// Request parameters for [TextResource.translate].
class TranslateRequest {
  final String input;
  final LanguageCode? sourceLanguageCode;
  final LanguageCode targetLanguageCode;
  final String? speakerGender;
  final String? mode;
  final String? model;

  const TranslateRequest({
    required this.input,
    this.sourceLanguageCode,
    required this.targetLanguageCode,
    this.speakerGender,
    this.mode,
    this.model,
  });

  Map<String, dynamic> toJson() {
    final map = <String, dynamic>{
      'input': input,
      'target_language_code': targetLanguageCode.value,
    };
    if (sourceLanguageCode != null) {
      map['source_language_code'] = sourceLanguageCode!.value;
    }
    if (speakerGender != null) {
      map['speaker_gender'] = speakerGender;
    }
    if (mode != null) {
      map['mode'] = mode;
    }
    if (model != null) {
      map['model'] = model;
    }
    return map;
  }
}

/// Response returned by [TextResource.translate].
class TranslateResponse {
  final String translatedText;
  final Map<String, dynamic> raw;

  const TranslateResponse({
    required this.translatedText,
    this.raw = const <String, dynamic>{},
  });

  factory TranslateResponse.fromJson(Map<String, dynamic> json) {
    return TranslateResponse(
      translatedText: json['translated_text'] as String? ?? '',
      raw: json,
    );
  }

  @override
  String toString() => 'TranslateResponse(translatedText: $translatedText)';
}

/// Request parameters for [TextResource.transliterate].
class TransliterateRequest {
  final String input;
  final LanguageCode? sourceLanguageCode;
  final LanguageCode targetLanguageCode;

  const TransliterateRequest({
    required this.input,
    this.sourceLanguageCode,
    required this.targetLanguageCode,
  });

  Map<String, dynamic> toJson() {
    final map = <String, dynamic>{
      'input': input,
      'target_language_code': targetLanguageCode.value,
    };
    if (sourceLanguageCode != null) {
      map['source_language_code'] = sourceLanguageCode!.value;
    }
    return map;
  }
}

/// Response returned by [TextResource.transliterate].
class TransliterateResponse {
  final String transliteratedText;
  final Map<String, dynamic> raw;

  const TransliterateResponse({
    required this.transliteratedText,
    this.raw = const <String, dynamic>{},
  });

  factory TransliterateResponse.fromJson(Map<String, dynamic> json) {
    return TransliterateResponse(
      transliteratedText: json['transliterated_text'] as String? ?? '',
      raw: json,
    );
  }

  @override
  String toString() =>
      'TransliterateResponse(transliteratedText: $transliteratedText)';
}

/// Request parameters for [TextResource.identifyLanguage].
class IdentifyLanguageRequest {
  final String input;

  const IdentifyLanguageRequest({required this.input});

  Map<String, dynamic> toJson() => <String, dynamic>{
        'input': input,
      };
}

/// Response returned by [TextResource.identifyLanguage].
class TextLidResponse {
  final LanguageCode detectedLanguage;
  final double? confidence;
  final Map<String, dynamic> raw;

  const TextLidResponse({
    required this.detectedLanguage,
    this.confidence,
    this.raw = const <String, dynamic>{},
  });

  factory TextLidResponse.fromJson(Map<String, dynamic> json) {
    final langStr = json['detected_language'] as String? ?? 'unknown';
    return TextLidResponse(
      detectedLanguage: LanguageCode(langStr),
      confidence: (json['confidence'] as num?)?.toDouble(),
      raw: json,
    );
  }

  @override
  String toString() =>
      'TextLidResponse(detectedLanguage: ${detectedLanguage.value}, confidence: $confidence)';
}
