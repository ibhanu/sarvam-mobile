import 'dart:convert';
import 'dart:typed_data';

import 'package:sarvam/src/generated/sarvam_spec_generated.dart';
import '../core/auth_provider.dart';
import '../core/environment.dart';
import '../core/middleware/middleware.dart';
import '../core/request_options.dart';
import '../core/transport.dart';
import '../core/websocket_factory.dart';
import '../models/text_to_speech_models.dart';
import '../realtime/tts_streaming_session.dart';

/// Resource for text-to-speech synthesis, audio stream chunking, and realtime WebSocket speech generation.
class TextToSpeechResource {
  final HttpHandler _pipeline;
  final SarvamEnvironment _environment;
  final AuthProvider _authProvider;
  final WebSocketFactory _webSocketFactory;

  TextToSpeechResource(
    this._pipeline,
    this._environment,
    this._authProvider,
    this._webSocketFactory,
  );

  /// Synthesizes text into speech, returning a unary [TextToSpeechResponse] with decoded audio bytes.
  Future<TextToSpeechResponse> convert(
    TextToSpeechRequest request, {
    RequestOptions? options,
  }) async {
    final uri = Uri.parse('${_environment.apiBaseUrl}/text-to-speech');
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
    return TextToSpeechResponse.fromJson(json);
  }

  /// Synthesizes text into speech as a chunked HTTP binary stream.
  Stream<Uint8List> stream(
    TextToSpeechRequest request, {
    RequestOptions? options,
  }) async* {
    final uri = Uri.parse('${_environment.apiBaseUrl}/text-to-speech/stream');
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
    yield* response.stream;
  }

  /// Connects to the realtime text-to-speech streaming service over WebSocket,
  /// immediately sending the initial config frame.
  Future<TtsStreamingSession> connect(
    TtsStreamingConfig config, {
    RequestOptions? options,
  }) async {
    final queryParams = <String, String>{
      'model': config.model.value,
      'send_completion_event': 'true',
    };
    if (options?.queryParams != null) {
      options!.queryParams!.forEach((k, v) => queryParams[k] = v.toString());
    }

    final uri = Uri.parse('${_environment.wsBaseUrl}/text-to-speech/ws')
        .replace(queryParameters: queryParams);

    // 1. Resolve authentication credentials.
    final credentials = await _authProvider.getCredentials();
    final wsHeaders = <String, String>{};
    final wsProtocols = <String>[];

    credentials.applyToWebSocket(
      headers: wsHeaders,
      protocols: wsProtocols,
      useSubprotocolAuth: config.useSubprotocolAuth,
    );

    if (options?.headers != null) {
      wsHeaders.addAll(options!.headers!);
    }

    // 2. Establish WebSocket connection.
    final session = await _webSocketFactory.connect(
      uri,
      headers: wsHeaders,
      protocols: wsProtocols.isNotEmpty ? wsProtocols : null,
    );

    // 3. Immediately send initial config frame before caller sends text.
    TtsStreamingSession.sendInitialConfig(session, config);

    return TtsStreamingSession(session);
  }
}
