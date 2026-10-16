import 'dart:convert';

import 'package:sarvam/src/generated/sarvam_spec_generated.dart';
import '../core/environment.dart';
import '../core/file_input.dart';
import '../core/job_poller.dart';
import '../core/middleware/middleware.dart';
import '../core/request_options.dart';
import '../core/transport.dart';
import '../models/doc_ai_models.dart';

/// Resource for Sarvam Document Intelligence (Doc AI) — digitization, structured extraction, and status polling.
class DocAiResource {
  final HttpHandler _pipeline;
  final SarvamEnvironment _environment;
  final JobPoller _jobPoller;

  DocAiResource(
    this._pipeline,
    this._environment, {
    JobPoller? jobPoller,
  }) : _jobPoller = jobPoller ?? const JobPoller();

  /// Starts an asynchronous document digitization job.
  /// Accepts a single [SarvamFileInput] or a list of files sent under the `file` multipart array.
  Future<DocAiStartJobResponse> digitise(
    DocAiDigitiseRequest request, {
    RequestOptions? options,
  }) async {
    final uri = Uri.parse('${_environment.apiBaseUrl}/doc-ai/v1/job/digitise');
    final headers = <String, String>{};
    if (options?.headers != null) {
      headers.addAll(options!.headers!);
    }

    final files = request.getFiles();

    final httpRequest = HttpRequest(
      url: uri,
      method: 'POST',
      headers: headers,
      files: files.isNotEmpty ? files : null,
      fields: request.toFields(),
      operationKind: OperationKind.jobCreate,
      timeout: options?.timeout,
    );

    final response = await _pipeline(httpRequest);
    final json = jsonDecode(response.body) as Map<String, dynamic>;
    return DocAiStartJobResponse.fromJson(json);
  }

  /// Starts an asynchronous structured data extraction job.
  /// Automatically serializes [request.schema] into a JSON string multipart field if a [Map] is passed.
  Future<DocAiStartJobResponse> extract(
    DocAiExtractRequest request, {
    RequestOptions? options,
  }) async {
    final uri = Uri.parse('${_environment.apiBaseUrl}/doc-ai/v1/job/extract');
    final headers = <String, String>{};
    if (options?.headers != null) {
      headers.addAll(options!.headers!);
    }

    final files = request.getFiles();

    final httpRequest = HttpRequest(
      url: uri,
      method: 'POST',
      headers: headers,
      files: files.isNotEmpty ? files : null,
      fields: request.toFields(),
      operationKind: OperationKind.jobCreate,
      timeout: options?.timeout,
    );

    final response = await _pipeline(httpRequest);
    final json = jsonDecode(response.body) as Map<String, dynamic>;
    return DocAiStartJobResponse.fromJson(json);
  }

  /// Generates a presigned URL to upload documents directly for later DocAI processing.
  Future<DocAiPresignUploadResponse> createUploadUrl(
    DocAiPresignUploadRequest request, {
    RequestOptions? options,
  }) async {
    final uri = Uri.parse('${_environment.apiBaseUrl}/doc-ai/v1/job/upload');
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
      operationKind: OperationKind.statelessPost,
      timeout: options?.timeout,
    );

    final response = await _pipeline(httpRequest);
    final json = jsonDecode(response.body) as Map<String, dynamic>;
    return DocAiPresignUploadResponse.fromJson(json);
  }

  /// Retrieves the current status of a DocAI job.
  Future<DocAiJobStatus> getStatus(
    String jobId, {
    RequestOptions? options,
  }) async {
    final uri = Uri.parse(
        '${_environment.apiBaseUrl}/doc-ai/v1/job/${Uri.encodeComponent(jobId)}/status');
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
    return DocAiJobStatus.fromJson(json);
  }

  /// Retrieves the completed results of a DocAI job.
  Future<DocAiResultsResponse> getResults(
    String jobId, {
    String? format,
    RequestOptions? options,
  }) async {
    final queryParams = <String, String>{};
    if (format != null) queryParams['format'] = format;
    if (options?.queryParams != null) {
      options!.queryParams!.forEach((k, v) => queryParams[k] = v.toString());
    }

    final uri = Uri.parse(
            '${_environment.apiBaseUrl}/doc-ai/v1/job/${Uri.encodeComponent(jobId)}/results')
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
    return DocAiResultsResponse.fromJson(json);
  }

  /// Retrieves a presigned download URL for a completed DocAI job.
  Future<DocAiDownloadUrlResponse> getDownloadUrl(
    String jobId, {
    RequestOptions? options,
  }) async {
    final uri = Uri.parse(
        '${_environment.apiBaseUrl}/doc-ai/v1/job/${Uri.encodeComponent(jobId)}/download-url');
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
    return DocAiDownloadUrlResponse.fromJson(json);
  }

  /// Starts a digitization job and polls until completion, returning final results.
  Future<DocAiResultsResponse> digitiseAndWait(
    DocAiDigitiseRequest request, {
    Duration pollInterval = const Duration(seconds: 2),
    Duration timeout = const Duration(minutes: 5),
    CancellationToken? cancellationToken,
    RequestOptions? options,
  }) async {
    final init = await digitise(request, options: options);
    await _jobPoller.waitUntilComplete<DocAiJobStatus>(
      pollFn: () => getStatus(init.jobId, options: options),
      isComplete: (status) => status.isCompleted,
      isFailed: (status) => status.isFailed,
      failureMessage: (status) =>
          'DocAI digitisation job ${init.jobId} failed with status: ${status.status}',
      pollInterval: pollInterval,
      timeout: timeout,
      cancellationToken: cancellationToken,
    );
    return getResults(init.jobId, options: options);
  }

  /// Starts an extraction job and polls until completion, returning final results.
  Future<DocAiResultsResponse> extractAndWait(
    DocAiExtractRequest request, {
    Duration pollInterval = const Duration(seconds: 2),
    Duration timeout = const Duration(minutes: 5),
    CancellationToken? cancellationToken,
    RequestOptions? options,
  }) async {
    final init = await extract(request, options: options);
    await _jobPoller.waitUntilComplete<DocAiJobStatus>(
      pollFn: () => getStatus(init.jobId, options: options),
      isComplete: (status) => status.isCompleted,
      isFailed: (status) => status.isFailed,
      failureMessage: (status) =>
          'DocAI extraction job ${init.jobId} failed with status: ${status.status}',
      pollInterval: pollInterval,
      timeout: timeout,
      cancellationToken: cancellationToken,
    );
    return getResults(init.jobId, options: options);
  }
}
