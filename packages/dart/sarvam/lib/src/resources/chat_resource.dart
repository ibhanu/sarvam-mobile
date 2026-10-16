import 'dart:convert';
import 'dart:math';

import 'package:sarvam/src/generated/sarvam_spec_generated.dart';
import '../core/environment.dart';
import '../core/middleware/middleware.dart';
import '../core/request_options.dart';
import '../core/sse/sse_transformer.dart';
import '../core/transport.dart';
import '../models/chat_models.dart';

/// Resource for chat completions (V1 & V2), streaming deltas, model discovery, and affinity sessions.
class ChatResource {
  final HttpHandler _pipeline;
  final SarvamEnvironment _environment;

  ChatResource(this._pipeline, this._environment);

  /// Executes a unary OpenAI-compatible chat completion request (V1).
  Future<ChatCompletionResponse> completions(
    ChatCompletionRequest request, {
    RequestOptions? options,
  }) async {
    final uri = Uri.parse('${_environment.apiBaseUrl}/v1/chat/completions');
    final headers = <String, String>{
      'content-type': 'application/json',
    };
    if (options?.headers != null) {
      headers.addAll(options!.headers!);
    }

    final bodyMap = request.toJson()..['stream'] = false;
    final httpRequest = HttpRequest(
      url: uri,
      method: 'POST',
      headers: headers,
      bodyBytes: utf8.encode(jsonEncode(bodyMap)),
      operationKind: OperationKind.statelessPost,
      timeout: options?.timeout,
    );

    final response = await _pipeline(httpRequest);
    final json = jsonDecode(response.body) as Map<String, dynamic>;
    return ChatCompletionResponse.fromJson(json);
  }

  /// Streams OpenAI-compatible chat completion delta chunks via SSE (V1), terminating on `data: [DONE]`.
  Stream<ChatCompletionChunk> completionsStream(
    ChatCompletionRequest request, {
    RequestOptions? options,
  }) async* {
    final uri = Uri.parse('${_environment.apiBaseUrl}/v1/chat/completions');
    final headers = <String, String>{
      'content-type': 'application/json',
    };
    if (options?.headers != null) {
      headers.addAll(options!.headers!);
    }

    final bodyMap = request.toJson()..['stream'] = true;
    final httpRequest = HttpRequest(
      url: uri,
      method: 'POST',
      headers: headers,
      bodyBytes: utf8.encode(jsonEncode(bodyMap)),
      operationKind: OperationKind.statelessPost,
      timeout: options?.timeout,
      isStreaming: true,
    );

    final response = await _pipeline(httpRequest);
    final sseStream = parseSseStream(response.stream, isResponsesApi: false);

    await for (final sse in sseStream) {
      if (sse.data.trim() == '[DONE]') {
        break;
      }
      try {
        final json = jsonDecode(sse.data) as Map<String, dynamic>;
        yield ChatCompletionChunk.fromJson(json);
      } catch (_) {
        // Skip unparseable non-data chunks.
      }
    }
  }

  /// Executes a unary Sarvam chat completion request (V2).
  Future<ChatCompletionV2Response> completionsV2(
    ChatCompletionV2Request request, {
    RequestOptions? options,
  }) async {
    final uri = Uri.parse('${_environment.apiBaseUrl}/v2/chat/completions');
    final headers = <String, String>{
      'content-type': 'application/json',
    };
    if (options?.headers != null) {
      headers.addAll(options!.headers!);
    }

    final bodyMap = request.toJson()..['stream'] = false;
    final httpRequest = HttpRequest(
      url: uri,
      method: 'POST',
      headers: headers,
      bodyBytes: utf8.encode(jsonEncode(bodyMap)),
      operationKind: OperationKind.statelessPost,
      timeout: options?.timeout,
    );

    final response = await _pipeline(httpRequest);
    final json = jsonDecode(response.body) as Map<String, dynamic>;
    return ChatCompletionV2Response.fromJson(json);
  }

  /// Streams Sarvam chat completion delta chunks via SSE (V2),
  /// safely guarding terminal chunks with `choices: []` without throwing index exceptions.
  Stream<ChatCompletionChunk> completionsV2Stream(
    ChatCompletionV2Request request, {
    RequestOptions? options,
  }) async* {
    final uri = Uri.parse('${_environment.apiBaseUrl}/v2/chat/completions');
    final headers = <String, String>{
      'content-type': 'application/json',
    };
    if (options?.headers != null) {
      headers.addAll(options!.headers!);
    }

    final bodyMap = request.toJson()..['stream'] = true;
    final httpRequest = HttpRequest(
      url: uri,
      method: 'POST',
      headers: headers,
      bodyBytes: utf8.encode(jsonEncode(bodyMap)),
      operationKind: OperationKind.statelessPost,
      timeout: options?.timeout,
      isStreaming: true,
    );

    final response = await _pipeline(httpRequest);
    final sseStream = parseSseStream(response.stream, isResponsesApi: false);

    await for (final sse in sseStream) {
      if (sse.data.trim() == '[DONE]') {
        break;
      }
      try {
        final json = jsonDecode(sse.data) as Map<String, dynamic>;
        yield ChatCompletionChunk.fromJson(json);
      } catch (_) {
        // Skip unparseable non-data chunks.
      }
    }
  }

  /// Lists available chat and language models.
  Future<ModelListResponse> listModels({
    RequestOptions? options,
  }) async {
    final uri = Uri.parse('${_environment.apiBaseUrl}/v2/models');
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
    return ModelListResponse.fromJson(json);
  }

  /// Retrieves details for a specific model by [modelId].
  Future<ModelResponse> getModel(
    String modelId, {
    RequestOptions? options,
  }) async {
    final uri = Uri.parse('${_environment.apiBaseUrl}/v2/models/$modelId');
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
    return ModelResponse.fromJson(json);
  }

  /// Creates a stateful [ChatSession] managing `x-session-affinity` across multiple turns.
  ChatSession createSession({String? sessionId}) {
    return ChatSession(
      this,
      sessionId: sessionId ?? _generateUuidV4(),
    );
  }

  static String _generateUuidV4() {
    final rand = Random();
    final bytes = List<int>.generate(16, (i) => rand.nextInt(256));
    bytes[6] = (bytes[6] & 0x0f) | 0x40; // Version 4
    bytes[8] = (bytes[8] & 0x3f) | 0x80; // Variant 10
    final hex = bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
    return '${hex.substring(0, 8)}-${hex.substring(8, 12)}-${hex.substring(12, 16)}-${hex.substring(16, 20)}-${hex.substring(20, 32)}';
  }
}

/// Stateful wrapper around [ChatResource] maintaining session affinity.
class ChatSession {
  final ChatResource _chat;
  final String sessionId;

  ChatSession(this._chat, {required this.sessionId});

  RequestOptions _withAffinity(RequestOptions? options) {
    final mergedHeaders = <String, String>{
      'x-session-affinity': sessionId,
    };
    if (options?.headers != null) {
      mergedHeaders.addAll(options!.headers!);
    }
    return (options ?? const RequestOptions()).copyWith(headers: mergedHeaders);
  }

  Future<ChatCompletionResponse> completions(
    ChatCompletionRequest request, {
    RequestOptions? options,
  }) {
    return _chat.completions(request, options: _withAffinity(options));
  }

  Stream<ChatCompletionChunk> completionsStream(
    ChatCompletionRequest request, {
    RequestOptions? options,
  }) {
    return _chat.completionsStream(request, options: _withAffinity(options));
  }

  Future<ChatCompletionV2Response> completionsV2(
    ChatCompletionV2Request request, {
    RequestOptions? options,
  }) {
    return _chat.completionsV2(request, options: _withAffinity(options));
  }

  Stream<ChatCompletionChunk> completionsV2Stream(
    ChatCompletionV2Request request, {
    RequestOptions? options,
  }) {
    return _chat.completionsV2Stream(request, options: _withAffinity(options));
  }
}
