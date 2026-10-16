import 'dart:convert';

import 'package:sarvam/src/generated/sarvam_spec_generated.dart';
import '../core/environment.dart';
import '../core/job_poller.dart';
import '../core/middleware/middleware.dart';
import '../core/request_options.dart';
import '../core/transport.dart';
import '../models/document_translation_models.dart';

/// Resource for document translation jobs, live progress tracking, and format export.
class DocumentTranslationResource {
  final HttpHandler _pipeline;
  final SarvamEnvironment _environment;
  final JobPoller _jobPoller;

  DocumentTranslationResource(
    this._pipeline,
    this._environment, {
    JobPoller? jobPoller,
  }) : _jobPoller = jobPoller ?? const JobPoller();

  /// Creates a new document translation job.
  Future<DocumentTranslationJobResponse> create(
    DocumentTranslationCreateRequest request, {
    RequestOptions? options,
  }) async {
    final uri =
        Uri.parse('${_environment.apiBaseUrl}/translate/document/jobs');
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
    return DocumentTranslationJobResponse.fromJson(json);
  }

  /// Starts processing for the document translation job [jobId].
  Future<DocumentTranslationJobResponse> start(
    String jobId, {
    RequestOptions? options,
  }) async {
    final uri = Uri.parse(
        '${_environment.apiBaseUrl}/translate/document/jobs/${Uri.encodeComponent(jobId)}/start');
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
    return DocumentTranslationJobResponse.fromJson(json);
  }

  /// Retrieves the live translation status and per-page / per-language progress of [jobId].
  Future<DocumentTranslationLiveStatus> getLiveStatus(
    String jobId, {
    RequestOptions? options,
  }) async {
    final uri = Uri.parse(
        '${_environment.apiBaseUrl}/translate/document/jobs/${Uri.encodeComponent(jobId)}/live-status');
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
    return DocumentTranslationLiveStatus.fromJson(json);
  }

  /// Triggers an export for the completed translation in a specific language and format.
  Future<DocumentTranslationExportResponse> triggerExport(
    String jobId, {
    String? lang,
    String? format,
    bool? fitLineHeight,
    bool? fitFontShrink,
    RequestOptions? options,
  }) async {
    final queryParams = <String, String>{};
    if (lang != null) queryParams['lang'] = lang;
    if (format != null) queryParams['format'] = format;
    if (fitLineHeight != null) {
      queryParams['fit_line_height'] = fitLineHeight.toString();
    }
    if (fitFontShrink != null) {
      queryParams['fit_font_shrink'] = fitFontShrink.toString();
    }
    if (options?.queryParams != null) {
      options!.queryParams!.forEach((k, v) => queryParams[k] = v.toString());
    }

    final uri = Uri.parse(
            '${_environment.apiBaseUrl}/translate/document/jobs/${Uri.encodeComponent(jobId)}/export')
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
    return DocumentTranslationExportResponse.fromJson(json);
  }

  /// Retrieves the export status and signed download URL for an exported document.
  Future<DocumentTranslationExportStatus> getExportStatus(
    String jobId, {
    String? lang,
    String? exportId,
    RequestOptions? options,
  }) async {
    final queryParams = <String, String>{};
    if (lang != null) queryParams['lang'] = lang;
    if (exportId != null) queryParams['export_id'] = exportId;
    if (options?.queryParams != null) {
      options!.queryParams!.forEach((k, v) => queryParams[k] = v.toString());
    }

    final uri = Uri.parse(
            '${_environment.apiBaseUrl}/translate/document/jobs/${Uri.encodeComponent(jobId)}/export/status')
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
    return DocumentTranslationExportStatus.fromJson(json);
  }

  /// Polls [getLiveStatus] until the job enters a terminal state (`Completed`, `PartiallyCompleted`, or `Failed`).
  Future<DocumentTranslationLiveStatus> waitUntilComplete(
    String jobId, {
    Duration pollInterval = const Duration(seconds: 2),
    Duration timeout = const Duration(minutes: 5),
    CancellationToken? cancellationToken,
    RequestOptions? options,
  }) async {
    return _jobPoller.waitUntilComplete<DocumentTranslationLiveStatus>(
      pollFn: () => getLiveStatus(jobId, options: options),
      isComplete: (status) => status.isCompleted,
      isFailed: (status) => status.isFailed,
      failureMessage: (status) =>
          'Document translation job $jobId failed with state: ${status.jobState}. Error: ${status.errorMessage}',
      pollInterval: pollInterval,
      timeout: timeout,
      cancellationToken: cancellationToken,
    );
  }
}
