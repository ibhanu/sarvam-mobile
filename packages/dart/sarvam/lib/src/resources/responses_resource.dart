import 'dart:convert';

import 'package:sarvam/src/generated/sarvam_spec_generated.dart';
import '../core/environment.dart';
import '../core/middleware/middleware.dart';
import '../core/request_options.dart';
import '../core/sse/sse_transformer.dart';
import '../core/transport.dart';
import '../models/response_models.dart';

/// Resource for Sarvam's Responses API (`/v2/responses`).
class ResponsesResource {
  final HttpHandler _pipeline;
  final SarvamEnvironment _environment;

  ResponsesResource(this._pipeline, this._environment);

  /// Initiates an SSE stream on `/v2/responses`, emitting [ResponseEvent]s and cleanly
  /// completing upon receiving `response.completed` without hanging waiting for `data: [DONE]`.
  Stream<ResponseEvent> createStream(
    ResponseStreamRequest request, {
    RequestOptions? options,
  }) async* {
    final uri = Uri.parse('${_environment.apiBaseUrl}/v2/responses');
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
      isStreaming: true,
    );

    final response = await _pipeline(httpRequest);
    final sseStream = parseSseStream(response.stream, isResponsesApi: true);

    await for (final sse in sseStream) {
      yield ResponseEvent.fromSse(
        event: sse.event ?? '',
        data: sse.data,
      );
    }
  }
}
