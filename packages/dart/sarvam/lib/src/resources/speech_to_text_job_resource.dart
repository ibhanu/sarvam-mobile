import 'dart:convert';

import 'package:sarvam/src/generated/sarvam_spec_generated.dart';
import '../core/environment.dart';
import '../core/job_poller.dart';
import '../core/middleware/middleware.dart';
import '../core/request_options.dart';
import '../core/transport.dart';
import '../models/speech_to_text_job_models.dart';

/// Base resource providing batch Speech-to-Text job operations.
abstract class BaseSpeechToTextJobResource {
  final HttpHandler _pipeline;
  final SarvamEnvironment _environment;
  final JobPoller _jobPoller;
  final String _basePath;

  BaseSpeechToTextJobResource(
    this._pipeline,
    this._environment,
    this._basePath, {
    JobPoller? jobPoller,
  }) : _jobPoller = jobPoller ?? const JobPoller();

  /// Initialises a new bulk STT job.
  Future<SpeechToTextJobStatus> initialise(
    SpeechToTextJobInitRequest request, {
    RequestOptions? options,
  }) async {
    final uri = Uri.parse('${_environment.apiBaseUrl}$_basePath');
    final headers = <String, String>{
      'content-type': 'application/json',
    };
    if (options?.headers != null) {
      headers.addAll(options!.headers!);
    }

    final httpRequest = HttpRequest(
      url: uri,
      method: 'POST',
      headers: headers,
      bodyBytes: utf8.encode(jsonEncode(request.toJson())),
      operationKind: OperationKind.jobCreate,
      timeout: options?.timeout,
    );

    final response = await _pipeline(httpRequest);
    final json = jsonDecode(response.body) as Map<String, dynamic>;
    return SpeechToTextJobStatus.fromJson(json);
  }

  /// Obtains presigned Azure SAS upload links for audio files to be processed.
  Future<SpeechToTextJobUploadLinksResponse> getUploadLinks(
    String jobId,
    List<String> files, {
    RequestOptions? options,
  }) async {
    final uri = Uri.parse('${_environment.apiBaseUrl}$_basePath/upload-files');
    final headers = <String, String>{
      'content-type': 'application/json',
    };
    if (options?.headers != null) {
      headers.addAll(options!.headers!);
    }

    final body = <String, dynamic>{
      'job_id': jobId,
      'files': files,
    };

    final httpRequest = HttpRequest(
      url: uri,
      method: 'POST',
      headers: headers,
      bodyBytes: utf8.encode(jsonEncode(body)),
      operationKind: OperationKind.statelessPost,
      timeout: options?.timeout,
    );

    final response = await _pipeline(httpRequest);
    final json = jsonDecode(response.body) as Map<String, dynamic>;
    return SpeechToTextJobUploadLinksResponse.fromJson(json);
  }

  /// Starts processing for the uploaded files in [jobId].
  Future<SpeechToTextJobStatus> start(
    String jobId, {
    String? ptuId,
    RequestOptions? options,
  }) async {
    final queryParams = <String, String>{};
    if (ptuId != null) queryParams['ptu_id'] = ptuId;
    if (options?.queryParams != null) {
      options!.queryParams!.forEach((k, v) => queryParams[k] = v.toString());
    }

    final uri = Uri.parse(
            '${_environment.apiBaseUrl}$_basePath/${Uri.encodeComponent(jobId)}/start')
        .replace(queryParameters: queryParams.isNotEmpty ? queryParams : null);

    final headers = <String, String>{};
    if (options?.headers != null) {
      headers.addAll(options!.headers!);
    }

    final httpRequest = HttpRequest(
      url: uri,
      method: 'POST',
      headers: headers,
      operationKind: OperationKind.statelessPost,
      timeout: options?.timeout,
    );

    final response = await _pipeline(httpRequest);
    final json = jsonDecode(response.body) as Map<String, dynamic>;
    return SpeechToTextJobStatus.fromJson(json);
  }

  /// Retrieves the current status and per-file progress of [jobId].
  Future<SpeechToTextJobStatus> getStatus(
    String jobId, {
    RequestOptions? options,
  }) async {
    final uri = Uri.parse(
        '${_environment.apiBaseUrl}$_basePath/${Uri.encodeComponent(jobId)}/status');
    final headers = <String, String>{};
    if (options?.headers != null) {
      headers.addAll(options!.headers!);
    }

    final httpRequest = HttpRequest(
      url: uri,
      method: 'GET',
      headers: headers,
      operationKind: OperationKind.idempotent,
      timeout: options?.timeout,
    );

    final response = await _pipeline(httpRequest);
    final json = jsonDecode(response.body) as Map<String, dynamic>;
    return SpeechToTextJobStatus.fromJson(json);
  }

  /// Obtains presigned Azure SAS download links for completed output transcript files.
  Future<SpeechToTextJobDownloadLinksResponse> getDownloadLinks(
    String jobId,
    List<String> files, {
    RequestOptions? options,
  }) async {
    final uri =
        Uri.parse('${_environment.apiBaseUrl}$_basePath/download-files');
    final headers = <String, String>{
      'content-type': 'application/json',
    };
    if (options?.headers != null) {
      headers.addAll(options!.headers!);
    }

    final body = <String, dynamic>{
      'job_id': jobId,
      'files': files,
    };

    final httpRequest = HttpRequest(
      url: uri,
      method: 'POST',
      headers: headers,
      bodyBytes: utf8.encode(jsonEncode(body)),
      operationKind: OperationKind.statelessPost,
      timeout: options?.timeout,
    );

    final response = await _pipeline(httpRequest);
    final json = jsonDecode(response.body) as Map<String, dynamic>;
    return SpeechToTextJobDownloadLinksResponse.fromJson(json);
  }

  /// Polls [getStatus] until the job enters a terminal state (`Completed` or `Failed`).
  Future<SpeechToTextJobStatus> waitUntilComplete(
    String jobId, {
    Duration pollInterval = const Duration(seconds: 2),
    Duration timeout = const Duration(minutes: 5),
    CancellationToken? cancellationToken,
    RequestOptions? options,
  }) async {
    return _jobPoller.waitUntilComplete<SpeechToTextJobStatus>(
      pollFn: () => getStatus(jobId, options: options),
      isComplete: (status) => status.isCompleted,
      isFailed: (status) => status.isFailed,
      failureMessage: (status) =>
          'STT job $jobId failed with state: ${status.jobState}. Error: ${status.errorMessage}',
      pollInterval: pollInterval,
      timeout: timeout,
      cancellationToken: cancellationToken,
    );
  }
}

/// Resource for batch Speech-to-Text jobs (`/speech-to-text/job/v1`).
class SpeechToTextJobResource extends BaseSpeechToTextJobResource {
  SpeechToTextJobResource(
    HttpHandler pipeline,
    SarvamEnvironment environment, {
    JobPoller? jobPoller,
  }) : super(
          pipeline,
          environment,
          '/speech-to-text/job/v1',
          jobPoller: jobPoller,
        );
}

/// Resource for batch Speech-to-Text Translation jobs (`/speech-to-text-translate/job/v1`).
class SpeechToTextTranslateJobResource extends BaseSpeechToTextJobResource {
  SpeechToTextTranslateJobResource(
    HttpHandler pipeline,
    SarvamEnvironment environment, {
    JobPoller? jobPoller,
  }) : super(
          pipeline,
          environment,
          '/speech-to-text-translate/job/v1',
          jobPoller: jobPoller,
        );
}
