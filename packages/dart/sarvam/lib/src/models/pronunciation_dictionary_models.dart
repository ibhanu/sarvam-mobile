/// Represents a pronunciation dictionary item.
class PronunciationDictionary {
  final String dictId;
  final String? name;
  final String? languageCode;
  final String? status;
  final String? createdAt;
  final String? updatedAt;
  final Map<String, dynamic> raw;

  const PronunciationDictionary({
    required this.dictId,
    this.name,
    this.languageCode,
    this.status,
    this.createdAt,
    this.updatedAt,
    this.raw = const <String, dynamic>{},
  });

  factory PronunciationDictionary.fromJson(Map<String, dynamic> json) {
    return PronunciationDictionary(
      dictId: (json['dict_id'] ?? json['id'] ?? '').toString(),
      name: json['name'] as String?,
      languageCode: json['language_code'] as String?,
      status: json['status'] as String?,
      createdAt: json['created_at'] as String?,
      updatedAt: json['updated_at'] as String?,
      raw: json,
    );
  }

  @override
  String toString() =>
      'PronunciationDictionary(dictId: $dictId, name: $name, status: $status)';
}

/// Response returned by [PronunciationDictionaryResource.list].
class PronunciationDictionaryListResponse {
  final List<PronunciationDictionary> dictionaries;
  final Map<String, dynamic> raw;

  const PronunciationDictionaryListResponse({
    required this.dictionaries,
    this.raw = const <String, dynamic>{},
  });

  factory PronunciationDictionaryListResponse.fromJson(dynamic json) {
    if (json is List<dynamic>) {
      final list = json
          .whereType<Map<String, dynamic>>()
          .map(PronunciationDictionary.fromJson)
          .toList();
      return PronunciationDictionaryListResponse(dictionaries: list);
    }
    if (json is Map<String, dynamic>) {
      final dicts = json['dictionaries'] ?? json['data'] ?? const <dynamic>[];
      if (dicts is List<dynamic>) {
        final list = dicts
            .whereType<Map<String, dynamic>>()
            .map(PronunciationDictionary.fromJson)
            .toList();
        return PronunciationDictionaryListResponse(
          dictionaries: list,
          raw: json,
        );
      }
      return PronunciationDictionaryListResponse(dictionaries: const [], raw: json);
    }
    return const PronunciationDictionaryListResponse(dictionaries: []);
  }
}

/// Response returned by create, update, or delete operations on pronunciation dictionary.
class PronunciationDictionaryResponse {
  final String dictId;
  final String? status;
  final String? message;
  final Map<String, dynamic> raw;

  const PronunciationDictionaryResponse({
    required this.dictId,
    this.status,
    this.message,
    this.raw = const <String, dynamic>{},
  });

  factory PronunciationDictionaryResponse.fromJson(Map<String, dynamic> json) {
    return PronunciationDictionaryResponse(
      dictId: (json['dict_id'] ?? json['id'] ?? '').toString(),
      status: json['status'] as String?,
      message: json['message'] as String?,
      raw: json,
    );
  }

  @override
  String toString() =>
      'PronunciationDictionaryResponse(dictId: $dictId, status: $status)';
}
