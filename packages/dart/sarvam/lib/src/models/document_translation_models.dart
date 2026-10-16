import 'package:sarvam/src/generated/sarvam_spec_generated.dart';

/// Request parameters for creating a document translation job.
class DocumentTranslationCreateRequest {
  final LanguageCode sourceLanguageCode;
  final List<LanguageCode> targetLanguageCodes;
  final String? fileUrl;
  final String? jobName;
  final Map<String, dynamic>? extraParameters;

  const DocumentTranslationCreateRequest({
    required this.sourceLanguageCode,
    required this.targetLanguageCodes,
    this.fileUrl,
    this.jobName,
    this.extraParameters,
  });

  Map<String, dynamic> toJson() {
    final map = <String, dynamic>{
      'source_language_code': sourceLanguageCode.value,
      'target_language_codes':
          targetLanguageCodes.map((l) => l.value).toList(),
    };
    if (fileUrl != null) map['file_url'] = fileUrl;
    if (jobName != null) map['job_name'] = jobName;
    if (extraParameters != null) {
      map.addAll(extraParameters!);
    }
    return map;
  }
}

/// Response returned when creating a document translation job.
class DocumentTranslationJobResponse {
  final String jobId;
  final String? jobName;
  final String? jobState;
  final Map<String, dynamic> raw;

  const DocumentTranslationJobResponse({
    required this.jobId,
    this.jobName,
    this.jobState,
    this.raw = const <String, dynamic>{},
  });

  factory DocumentTranslationJobResponse.fromJson(Map<String, dynamic> json) {
    return DocumentTranslationJobResponse(
      jobId: (json['job_id'] ?? '').toString(),
      jobName: json['job_name'] as String?,
      jobState: (json['job_state'] ?? json['status'])?.toString(),
      raw: json,
    );
  }

  @override
  String toString() =>
      'DocumentTranslationJobResponse(jobId: $jobId, state: $jobState)';
}

/// Live status of an active document translation job.
class DocumentTranslationLiveStatus {
  final String jobId;
  final String? jobName;
  final String jobState;
  final String? sourceLanguageCode;
  final int progress;
  final List<dynamic>? translations;
  final String? errorMessage;
  final String? createdAt;
  final String? updatedAt;
  final Map<String, dynamic> raw;

  const DocumentTranslationLiveStatus({
    required this.jobId,
    this.jobName,
    required this.jobState,
    this.sourceLanguageCode,
    this.progress = 0,
    this.translations,
    this.errorMessage,
    this.createdAt,
    this.updatedAt,
    this.raw = const <String, dynamic>{},
  });

  factory DocumentTranslationLiveStatus.fromJson(Map<String, dynamic> json) {
    return DocumentTranslationLiveStatus(
      jobId: (json['job_id'] ?? '').toString(),
      jobName: json['job_name'] as String?,
      jobState: (json['job_state'] ?? json['status'] ?? '').toString(),
      sourceLanguageCode: json['source_language_code'] as String?,
      progress: (json['progress'] as num?)?.toInt() ?? 0,
      translations: json['translations'] as List<dynamic>?,
      errorMessage: json['error_message'] as String?,
      createdAt: json['created_at'] as String?,
      updatedAt: json['updated_at'] as String?,
      raw: json,
    );
  }

  bool get isCompleted =>
      jobState.toLowerCase() == 'completed' ||
      jobState.toLowerCase() == 'partiallycompleted';

  bool get isFailed => jobState.toLowerCase() == 'failed';

  @override
  String toString() =>
      'DocumentTranslationLiveStatus(jobId: $jobId, state: $jobState, progress: $progress%)';
}

/// Response returned when triggering an export for a document translation job.
class DocumentTranslationExportResponse {
  final String? exportId;
  final String? status;
  final Map<String, dynamic> raw;

  const DocumentTranslationExportResponse({
    this.exportId,
    this.status,
    this.raw = const <String, dynamic>{},
  });

  factory DocumentTranslationExportResponse.fromJson(Map<String, dynamic> json) {
    return DocumentTranslationExportResponse(
      exportId: json['export_id']?.toString(),
      status: json['status']?.toString(),
      raw: json,
    );
  }
}

/// Export status of a translated document format.
class DocumentTranslationExportStatus {
  final String exportId;
  final String jobId;
  final String targetLanguageCode;
  final String format;
  final String exportState;
  final String? downloadUrl;
  final String? filename;
  final int? fileSize;
  final int? progress;
  final String? errorMessage;
  final Map<String, dynamic> raw;

  const DocumentTranslationExportStatus({
    required this.exportId,
    required this.jobId,
    required this.targetLanguageCode,
    required this.format,
    required this.exportState,
    this.downloadUrl,
    this.filename,
    this.fileSize,
    this.progress,
    this.errorMessage,
    this.raw = const <String, dynamic>{},
  });

  factory DocumentTranslationExportStatus.fromJson(Map<String, dynamic> json) {
    return DocumentTranslationExportStatus(
      exportId: (json['export_id'] ?? '').toString(),
      jobId: (json['job_id'] ?? '').toString(),
      targetLanguageCode: (json['target_language_code'] ?? '').toString(),
      format: (json['format'] ?? '').toString(),
      exportState: (json['export_state'] ?? json['status'] ?? '').toString(),
      downloadUrl: json['download_url'] as String?,
      filename: json['filename'] as String?,
      fileSize: (json['file_size'] as num?)?.toInt(),
      progress: (json['progress'] as num?)?.toInt(),
      errorMessage: json['error_message'] as String?,
      raw: json,
    );
  }

  bool get isCompleted => exportState.toLowerCase() == 'completed';

  bool get isFailed => exportState.toLowerCase() == 'failed';

  @override
  String toString() =>
      'DocumentTranslationExportStatus(exportId: $exportId, state: $exportState, url: $downloadUrl)';
}
