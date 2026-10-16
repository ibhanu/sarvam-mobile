import 'dart:convert';

import 'package:sarvam/src/generated/sarvam_spec_generated.dart';
import '../core/environment.dart';
import '../core/job_poller.dart';
import '../core/middleware/middleware.dart';
import '../core/request_options.dart';
import '../core/transport.dart';
import '../models/dubbing_models.dart';

/// Resource for AI video and audio dubbing jobs, routed to the dedicated Dubbing host.
class DubbingResource {
  final HttpHandler _pipeline;
  final SarvamEnvironment _environment;
  final JobPoller _jobPoller;

  DubbingResource(
    this._pipeline,
    this._environment, {
    JobPoller? jobPoller,
  }) : _jobPoller = jobPoller ?? const JobPoller();

  /// Creates a new dubbing job, mapping `sourceLanguageCode` to `src_lang` and
  /// `targetLanguageCodes` to `target_langs`.
  Future<DubbingJobResponse> create(
    DubbingCreateRequest request, {
    RequestOptions? options,
  }) async {
    final uri = Uri.parse('${_environment.dubbingBaseUrl}/jobs');
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
    return DubbingJobResponse.fromJson(json);
  }

  /// Starts processing for the dubbing job [jobId].
  Future<DubbingJobResponse> start(
    String jobId, {
    RequestOptions? options,
  }) async {
    final uri = Uri.parse(
        '${_environment.dubbingBaseUrl}/jobs/${Uri.encodeComponent(jobId)}/start');
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
    return DubbingJobResponse.fromJson(json);
  }

  /// Retrieves the live status and progress of the dubbing job [jobId].
  Future<DubbingLiveStatus> getLiveStatus(
    String jobId, {
    RequestOptions? options,
  }) async {
    final uri = Uri.parse(
        '${_environment.dubbingBaseUrl}/jobs/${Uri.encodeComponent(jobId)}/live-status');
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
    return DubbingLiveStatus.fromJson(json);
  }

  /// Retrieves the export status and download URLs of completed dubbing tracks.
  Future<DubbingExportStatus> getExportStatus(
    String jobId, {
    int? limit,
    RequestOptions? options,
  }) async {
    final queryParams = <String, String>{};
    if (limit != null) queryParams['limit'] = limit.toString();
    if (options?.queryParams != null) {
      options!.queryParams!.forEach((k, v) => queryParams[k] = v.toString());
    }

    final uri = Uri.parse(
            '${_environment.dubbingBaseUrl}/jobs/${Uri.encodeComponent(jobId)}/export-status')
        .replace(queryParameters: queryParams.isNotEmpty ? queryParams : null);

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
    return DubbingExportStatus.fromJson(json);
  }

  /// Polls [getLiveStatus] until the dubbing job enters a terminal state (`completed` or `failed`).
  Future<DubbingLiveStatus> waitUntilComplete(
    String jobId, {
    Duration pollInterval = const Duration(seconds: 2),
    Duration timeout = const Duration(minutes: 5),
    CancellationToken? cancellationToken,
    RequestOptions? options,
  }) async {
    return _jobPoller.waitUntilComplete<DubbingLiveStatus>(
      pollFn: () => getLiveStatus(jobId, options: options),
      isComplete: (status) => status.isCompleted,
      isFailed: (status) => status.isFailed,
      failureMessage: (status) =>
          'Dubbing job $jobId failed with status: ${status.status}. Error: ${status.errorMessage}',
      pollInterval: pollInterval,
      timeout: timeout,
      cancellationToken: cancellationToken,
    );
  }
}
