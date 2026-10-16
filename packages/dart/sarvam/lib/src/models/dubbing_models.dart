import 'package:sarvam/src/generated/sarvam_spec_generated.dart';

/// Request parameters for creating a dubbing job.
/// Automatically maps `sourceLanguageCode` to `src_lang` and `targetLanguageCodes` to `target_langs`.
class DubbingCreateRequest {
  final LanguageCode sourceLanguageCode;
  final List<LanguageCode> targetLanguageCodes;
  final bool? voiceCloning;
  final String? voiceId;
  final int? numSpeakers;
  final bool? disableWatermark;
  final String? jobName;
  final bool? editorFlow;
  final List<String>? exportOptions;
  final String? pacePreset;
  final String? register;
  final Map<String, dynamic>? extraParameters;

  const DubbingCreateRequest({
    required this.sourceLanguageCode,
    required this.targetLanguageCodes,
    this.voiceCloning = true,
    this.voiceId,
    this.numSpeakers = 1,
    this.disableWatermark = false,
    this.jobName,
    this.editorFlow = false,
    this.exportOptions,
    this.pacePreset,
    this.register,
    this.extraParameters,
  });

  Map<String, dynamic> toJson() {
    final map = <String, dynamic>{
      'src_lang': sourceLanguageCode.value,
      'target_langs': targetLanguageCodes.map((l) => l.value).toList(),
    };
    if (voiceCloning != null) map['voice_cloning'] = voiceCloning;
    if (voiceId != null) map['voice_id'] = voiceId;
    if (numSpeakers != null) map['num_speakers'] = numSpeakers;
    if (disableWatermark != null) {
      map['disable_watermark'] = disableWatermark;
    }
    if (jobName != null) map['job_name'] = jobName;
    if (editorFlow != null) map['editor_flow'] = editorFlow;
    if (exportOptions != null) map['export_options'] = exportOptions;
    if (pacePreset != null) map['pace_preset'] = pacePreset;
    if (register != null) map['register'] = register;
    if (extraParameters != null) {
      map.addAll(extraParameters!);
    }
    return map;
  }
}

/// Response returned when creating a dubbing job.
class DubbingJobResponse {
  final String jobId;
  final String? status;
  final String? message;
  final Map<String, dynamic> raw;

  const DubbingJobResponse({
    required this.jobId,
    this.status,
    this.message,
    this.raw = const <String, dynamic>{},
  });

  factory DubbingJobResponse.fromJson(Map<String, dynamic> json) {
    final data = json['data'] is Map<String, dynamic>
        ? json['data'] as Map<String, dynamic>
        : json;
    return DubbingJobResponse(
      jobId: (data['job_id'] ?? json['job_id'] ?? '').toString(),
      status: (data['status'] ?? json['status'])?.toString(),
      message: json['message'] as String?,
      raw: json,
    );
  }

  @override
  String toString() => 'DubbingJobResponse(jobId: $jobId, status: $status)';
}

/// Live status of a dubbing job.
class DubbingLiveStatus {
  final String jobId;
  final String status;
  final int progress;
  final String? currentStep;
  final String? currentStepLabel;
  final String? errorMessage;
  final Map<String, dynamic> raw;

  const DubbingLiveStatus({
    required this.jobId,
    required this.status,
    this.progress = 0,
    this.currentStep,
    this.currentStepLabel,
    this.errorMessage,
    this.raw = const <String, dynamic>{},
  });

  factory DubbingLiveStatus.fromJson(Map<String, dynamic> json) {
    final data = json['data'] is Map<String, dynamic>
        ? json['data'] as Map<String, dynamic>
        : json;
    return DubbingLiveStatus(
      jobId: (data['job_id'] ?? json['job_id'] ?? '').toString(),
      status: (data['status'] ?? json['status'] ?? '').toString(),
      progress: (data['progress'] as num?)?.toInt() ?? 0,
      currentStep: data['current_step'] as String?,
      currentStepLabel: data['current_step_label'] as String?,
      errorMessage: data['error_message'] as String?,
      raw: json,
    );
  }

  bool get isCompleted =>
      status.toLowerCase() == 'completed' ||
      status.toLowerCase() == 'partial_failure';

  bool get isFailed => status.toLowerCase() == 'failed';

  @override
  String toString() =>
      'DubbingLiveStatus(jobId: $jobId, status: $status, progress: $progress%)';
}

/// Export status response for dubbing jobs.
class DubbingExportStatus {
  final String status;
  final String? message;
  final Map<String, dynamic> data;
  final Map<String, dynamic> raw;

  const DubbingExportStatus({
    required this.status,
    this.message,
    required this.data,
    this.raw = const <String, dynamic>{},
  });

  factory DubbingExportStatus.fromJson(Map<String, dynamic> json) {
    return DubbingExportStatus(
      status: (json['status'] ?? '').toString(),
      message: json['message'] as String?,
      data: (json['data'] as Map<String, dynamic>?) ?? const <String, dynamic>{},
      raw: json,
    );
  }

  @override
  String toString() => 'DubbingExportStatus(status: $status)';
}
