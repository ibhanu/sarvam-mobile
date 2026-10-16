import 'dart:convert';

import 'package:sarvam/src/generated/sarvam_spec_generated.dart';
import '../core/file_input.dart';

/// Request parameters for [DocAiResource.digitise].
class DocAiDigitiseRequest {
  /// File or files to digitise. Accepts a single [SarvamFileInput] or a `List<SarvamFileInput>`.
  final dynamic file;

  /// Comma-separated upload IDs returned by [DocAiResource.createUploadUrl].
  final String? uploadIds;

  /// Language code (e.g. `hi-IN`, `en-IN`).
  final LanguageCode? language;

  /// Content type of the document (e.g. `printed`, `handwritten`).
  final String? contentType;

  /// Vision model identifier (default: `sarvam-vision-v1`).
  final String? model;

  const DocAiDigitiseRequest({
    this.file,
    this.uploadIds,
    this.language,
    this.contentType,
    this.model,
  });

  /// Extracts the file attachments normalized to a [List<SarvamFileInput>].
  List<SarvamFileInput> getFiles() {
    if (file is SarvamFileInput) {
      final f = file as SarvamFileInput;
      return [
        if (f.field == 'file') f else _withFileField(f),
      ];
    } else if (file is List<SarvamFileInput>) {
      final list = file as List<SarvamFileInput>;
      return list.map((f) => f.field == 'file' ? f : _withFileField(f)).toList();
    } else if (file is List) {
      return (file as List)
          .whereType<SarvamFileInput>()
          .map((f) => f.field == 'file' ? f : _withFileField(f))
          .toList();
    }
    return const [];
  }

  Map<String, String> toFields() {
    final fields = <String, String>{};
    if (uploadIds != null) fields['upload_ids'] = uploadIds!;
    if (language != null) fields['language'] = language!.value;
    if (contentType != null) fields['content_type'] = contentType!;
    if (model != null) fields['model'] = model!;
    return fields;
  }
}

/// Request parameters for [DocAiResource.extract].
class DocAiExtractRequest {
  /// File or files to extract from. Accepts a single [SarvamFileInput] or a `List<SarvamFileInput>`.
  final dynamic file;

  /// Comma-separated upload IDs returned by [DocAiResource.createUploadUrl].
  final String? uploadIds;

  /// Extraction schema. Can be passed as a [Map<String, dynamic>] or a raw JSON [String].
  /// Automatically serialized to a JSON string multipart field.
  final dynamic schema;

  /// Saved extraction configuration ID.
  final String? configId;

  /// Output format (e.g. `json`, `csv`).
  final String? outputFormat;

  /// Enable document classification.
  final bool? classification;

  /// Vision model identifier.
  final String? model;

  const DocAiExtractRequest({
    this.file,
    this.uploadIds,
    this.schema,
    this.configId,
    this.outputFormat,
    this.classification,
    this.model,
  });

  /// Extracts the file attachments normalized to a [List<SarvamFileInput>].
  List<SarvamFileInput> getFiles() {
    if (file is SarvamFileInput) {
      final f = file as SarvamFileInput;
      return [
        if (f.field == 'file') f else _withFileField(f),
      ];
    } else if (file is List<SarvamFileInput>) {
      final list = file as List<SarvamFileInput>;
      return list.map((f) => f.field == 'file' ? f : _withFileField(f)).toList();
    } else if (file is List) {
      return (file as List)
          .whereType<SarvamFileInput>()
          .map((f) => f.field == 'file' ? f : _withFileField(f))
          .toList();
    }
    return const [];
  }

  Map<String, String> toFields() {
    final fields = <String, String>{};
    if (uploadIds != null) fields['upload_ids'] = uploadIds!;
    if (configId != null) fields['config_id'] = configId!;
    if (outputFormat != null) fields['output_format'] = outputFormat!;
    if (classification != null) {
      fields['classification'] = classification!.toString();
    }
    if (model != null) fields['model'] = model!;

    // Auto-serialize schema into JSON string if provided.
    if (schema != null) {
      if (schema is String) {
        fields['schema'] = schema as String;
      } else if (schema is Map) {
        fields['schema'] = jsonEncode(schema);
      } else {
        fields['schema'] = jsonEncode(schema);
      }
    }

    return fields;
  }
}

SarvamFileInput _withFileField(SarvamFileInput file) {
  if (file.bytes != null) {
    return SarvamFileInput.fromBytes(
      'file',
      file.bytes!,
      filename: file.filename,
      contentType: file.contentType,
    );
  }
  return SarvamFileInput.fromStream(
    'file',
    file.streamFactory,
    file.length,
    filename: file.filename,
    contentType: file.contentType,
    isReplayable: file.isReplayable,
  );
}

/// Request parameters for [DocAiResource.createUploadUrl].
class DocAiPresignUploadRequest {
  final String fileName;
  final String? contentType;

  const DocAiPresignUploadRequest({
    required this.fileName,
    this.contentType,
  });

  Map<String, dynamic> toJson() {
    final map = <String, dynamic>{'file_name': fileName};
    if (contentType != null) map['content_type'] = contentType;
    return map;
  }
}

/// Response returned by [DocAiResource.createUploadUrl].
class DocAiPresignUploadResponse {
  final String uploadId;
  final String method;
  final String url;
  final Map<String, String> headers;
  final String expiresAt;
  final Map<String, dynamic> raw;

  const DocAiPresignUploadResponse({
    required this.uploadId,
    required this.method,
    required this.url,
    this.headers = const <String, String>{},
    required this.expiresAt,
    this.raw = const <String, dynamic>{},
  });

  factory DocAiPresignUploadResponse.fromJson(Map<String, dynamic> json) {
    final rawHeaders = json['headers'] as Map<String, dynamic>? ?? const {};
    final headers = rawHeaders.map((k, v) => MapEntry(k, v.toString()));
    return DocAiPresignUploadResponse(
      uploadId: (json['upload_id'] ?? '').toString(),
      method: (json['method'] ?? 'PUT').toString(),
      url: (json['url'] ?? '').toString(),
      headers: headers,
      expiresAt: (json['expires_at'] ?? '').toString(),
      raw: json,
    );
  }
}

/// Response returned when starting a DocAI digitisation or extraction job.
class DocAiStartJobResponse {
  final String jobId;
  final String status;
  final String? runId;
  final Map<String, dynamic> raw;

  const DocAiStartJobResponse({
    required this.jobId,
    required this.status,
    this.runId,
    this.raw = const <String, dynamic>{},
  });

  factory DocAiStartJobResponse.fromJson(Map<String, dynamic> json) {
    return DocAiStartJobResponse(
      jobId: (json['job_id'] ?? '').toString(),
      status: (json['status'] ?? '').toString(),
      runId: json['run_id']?.toString(),
      raw: json,
    );
  }

  @override
  String toString() => 'DocAiStartJobResponse(jobId: $jobId, status: $status)';
}

/// Status of a DocAI job.
class DocAiJobStatus {
  final String jobId;
  final String status;
  final String? pipeline;
  final Map<String, dynamic>? usage;
  final String? createdAt;
  final String? updatedAt;
  final Map<String, dynamic> raw;

  const DocAiJobStatus({
    required this.jobId,
    required this.status,
    this.pipeline,
    this.usage,
    this.createdAt,
    this.updatedAt,
    this.raw = const <String, dynamic>{},
  });

  factory DocAiJobStatus.fromJson(Map<String, dynamic> json) {
    return DocAiJobStatus(
      jobId: (json['job_id'] ?? '').toString(),
      status: (json['status'] ?? '').toString(),
      pipeline: json['pipeline'] as String?,
      usage: json['usage'] as Map<String, dynamic>?,
      createdAt: json['created_at'] as String?,
      updatedAt: json['updated_at'] as String?,
      raw: json,
    );
  }

  bool get isCompleted =>
      status == 'completed' || status == 'partially_completed';

  bool get isFailed => status == 'failed' || status == 'rejected';

  @override
  String toString() => 'DocAiJobStatus(jobId: $jobId, status: $status)';
}

/// Structured results of a completed DocAI job.
class DocAiResultsResponse {
  final String type;
  final String jobId;
  final String status;
  final Map<String, dynamic>? usage;
  final dynamic result;
  final dynamic annotations;
  final List<dynamic>? documents;
  final int? version;
  final Map<String, dynamic> raw;

  const DocAiResultsResponse({
    required this.type,
    required this.jobId,
    required this.status,
    this.usage,
    this.result,
    this.annotations,
    this.documents,
    this.version,
    this.raw = const <String, dynamic>{},
  });

  factory DocAiResultsResponse.fromJson(Map<String, dynamic> json) {
    return DocAiResultsResponse(
      type: (json['type'] ?? '').toString(),
      jobId: (json['job_id'] ?? '').toString(),
      status: (json['status'] ?? '').toString(),
      usage: json['usage'] as Map<String, dynamic>?,
      result: json['result'],
      annotations: json['annotations'],
      documents: json['documents'] as List<dynamic>?,
      version: json['version'] as int?,
      raw: json,
    );
  }

  @override
  String toString() =>
      'DocAiResultsResponse(type: $type, jobId: $jobId, status: $status)';
}

/// Download URL details for a DocAI job.
class DocAiDownloadUrlResponse {
  final String method;
  final String url;
  final Map<String, String> headers;
  final String? expiresAt;
  final Map<String, dynamic> raw;

  const DocAiDownloadUrlResponse({
    required this.method,
    required this.url,
    this.headers = const <String, String>{},
    this.expiresAt,
    this.raw = const <String, dynamic>{},
  });

  factory DocAiDownloadUrlResponse.fromJson(Map<String, dynamic> json) {
    final rawHeaders = json['headers'] as Map<String, dynamic>? ?? const {};
    final headers = rawHeaders.map((k, v) => MapEntry(k, v.toString()));
    return DocAiDownloadUrlResponse(
      method: (json['method'] ?? 'GET').toString(),
      url: (json['url'] ?? '').toString(),
      headers: headers,
      expiresAt: json['expires_at'] as String?,
      raw: json,
    );
  }
}
