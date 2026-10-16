/// Request parameters for initialising a batch Speech-to-Text or STT-Translate job.
class SpeechToTextJobInitRequest {
  final Map<String, dynamic> jobParameters;
  final Map<String, dynamic>? callback;

  const SpeechToTextJobInitRequest({
    required this.jobParameters,
    this.callback,
  });

  Map<String, dynamic> toJson() {
    final map = <String, dynamic>{
      'job_parameters': jobParameters,
    };
    if (callback != null) map['callback'] = callback;
    return map;
  }
}

/// Status of a Speech-to-Text bulk job.
class SpeechToTextJobStatus {
  final String jobId;
  final String jobState;
  final String? createdAt;
  final String? updatedAt;
  final int? totalFiles;
  final int? successfulFilesCount;
  final int? failedFilesCount;
  final String? errorMessage;
  final List<dynamic>? jobDetails;
  final Map<String, dynamic> raw;

  const SpeechToTextJobStatus({
    required this.jobId,
    required this.jobState,
    this.createdAt,
    this.updatedAt,
    this.totalFiles,
    this.successfulFilesCount,
    this.failedFilesCount,
    this.errorMessage,
    this.jobDetails,
    this.raw = const <String, dynamic>{},
  });

  factory SpeechToTextJobStatus.fromJson(Map<String, dynamic> json) {
    return SpeechToTextJobStatus(
      jobId: (json['job_id'] ?? '').toString(),
      jobState: (json['job_state'] ?? json['status'] ?? '').toString(),
      createdAt: json['created_at'] as String?,
      updatedAt: json['updated_at'] as String?,
      totalFiles: json['total_files'] as int?,
      successfulFilesCount: json['successful_files_count'] as int?,
      failedFilesCount: json['failed_files_count'] as int?,
      errorMessage: json['error_message'] as String?,
      jobDetails: json['job_details'] as List<dynamic>?,
      raw: json,
    );
  }

  bool get isCompleted => jobState.toLowerCase() == 'completed';

  bool get isFailed => jobState.toLowerCase() == 'failed';

  @override
  String toString() =>
      'SpeechToTextJobStatus(jobId: $jobId, state: $jobState, success: $successfulFilesCount, failed: $failedFilesCount)';
}

/// Response returned when requesting upload links for a bulk job.
class SpeechToTextJobUploadLinksResponse {
  final String jobId;
  final String jobState;
  final Map<String, dynamic> uploadUrls;
  final String? storageContainerType;
  final Map<String, dynamic> raw;

  const SpeechToTextJobUploadLinksResponse({
    required this.jobId,
    required this.jobState,
    required this.uploadUrls,
    this.storageContainerType,
    this.raw = const <String, dynamic>{},
  });

  factory SpeechToTextJobUploadLinksResponse.fromJson(Map<String, dynamic> json) {
    return SpeechToTextJobUploadLinksResponse(
      jobId: (json['job_id'] ?? '').toString(),
      jobState: (json['job_state'] ?? '').toString(),
      uploadUrls: (json['upload_urls'] as Map<String, dynamic>?) ??
          const <String, dynamic>{},
      storageContainerType: json['storage_container_type'] as String?,
      raw: json,
    );
  }
}

/// Response returned when requesting download links for a completed bulk job.
class SpeechToTextJobDownloadLinksResponse {
  final String jobId;
  final String jobState;
  final Map<String, dynamic> downloadUrls;
  final String? storageContainerType;
  final Map<String, dynamic> raw;

  const SpeechToTextJobDownloadLinksResponse({
    required this.jobId,
    required this.jobState,
    required this.downloadUrls,
    this.storageContainerType,
    this.raw = const <String, dynamic>{},
  });

  factory SpeechToTextJobDownloadLinksResponse.fromJson(Map<String, dynamic> json) {
    return SpeechToTextJobDownloadLinksResponse(
      jobId: (json['job_id'] ?? '').toString(),
      jobState: (json['job_state'] ?? '').toString(),
      downloadUrls: (json['download_urls'] as Map<String, dynamic>?) ??
          const <String, dynamic>{},
      storageContainerType: json['storage_container_type'] as String?,
      raw: json,
    );
  }
}
