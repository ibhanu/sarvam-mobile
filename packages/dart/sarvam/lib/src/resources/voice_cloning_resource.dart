import 'dart:convert';
import 'dart:typed_data';

import 'package:sarvam/src/generated/sarvam_spec_generated.dart';
import '../core/auth_provider.dart';
import '../core/environment.dart';
import '../core/file_input.dart';
import '../core/middleware/middleware.dart';
import '../core/request_options.dart';
import '../core/transport.dart';
import '../core/websocket_factory.dart';
import '../models/voice_cloning_models.dart';
import '../realtime/tts_streaming_session.dart';

/// Resource for instant voice cloning, voice library management, and real-time speech cloning.
class VoiceCloningResource {
  final HttpHandler _pipeline;
  final SarvamEnvironment _environment;
  final AuthProvider _authProvider;
  final WebSocketFactory _webSocketFactory;

  VoiceCloningResource(
    this._pipeline,
    this._environment,
    this._authProvider,
    this._webSocketFactory,
  );

  /// Lists all registered cloned voices in the user's voice library.
  Future<VoiceListResponse> listVoices({RequestOptions? options}) async {
    final uri = Uri.parse('${_environment.apiBaseUrl}/voices');
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
    final json = jsonDecode(response.body);
    return VoiceListResponse.fromJson(json);
  }

  /// Creates and registers a new cloned voice from a reference audio file.
  Future<VoiceCreateResponse> createVoice(
    VoiceCreateRequest request, {
    RequestOptions? options,
  }) async {
    final uri = Uri.parse('${_environment.apiBaseUrl}/voices/create');
    final headers = <String, String>{};
    if (options?.headers != null) {
      headers.addAll(options!.headers!);
    }

    final file = request.file.field == 'file'
        ? request.file
        : (request.file.bytes != null
            ? SarvamFileInput.fromBytes(
                'file',
                request.file.bytes!,
                filename: request.file.filename,
                contentType: request.file.contentType,
              )
            : SarvamFileInput.fromStream(
                'file',
                request.file.streamFactory,
                request.file.length,
                filename: request.file.filename,
                contentType: request.file.contentType,
                isReplayable: request.file.isReplayable,
              ));

    final httpRequest = HttpRequest(
      url: uri,
      method: 'POST',
      headers: headers,
      files: <SarvamFileInput>[file],
      fields: request.toFields(),
      operationKind: OperationKind.jobCreate,
      timeout: options?.timeout,
    );

    final response = await _pipeline(httpRequest);
    final json = jsonDecode(response.body) as Map<String, dynamic>;
    return VoiceCreateResponse.fromJson(json);
  }

  /// Retrieves details of a specific cloned voice by its [voiceId].
  Future<Voice> getVoice(String voiceId, {RequestOptions? options}) async {
    final uri = Uri.parse(
        '${_environment.apiBaseUrl}/voices/${Uri.encodeComponent(voiceId)}');
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
    final data = json['data'] is Map<String, dynamic>
        ? json['data'] as Map<String, dynamic>
        : json;
    return Voice.fromJson(data);
  }

  /// Deletes a cloned voice by its [voiceId].
  Future<Map<String, dynamic>> deleteVoice(
    String voiceId, {
    RequestOptions? options,
  }) async {
    final uri = Uri.parse(
        '${_environment.apiBaseUrl}/voices/delete/${Uri.encodeComponent(voiceId)}');
    final headers = <String, String>{};
    if (options?.headers != null) {
      headers.addAll(options!.headers!);
    }

    final httpRequest = HttpRequest(
      url: uri,
      method: 'DELETE',
      headers: headers,
      operationKind: OperationKind.idempotent,
      timeout: options?.timeout,
    );

    final response = await _pipeline(httpRequest);
    if (response.body.trim().isEmpty) return const <String, dynamic>{};
    return jsonDecode(response.body) as Map<String, dynamic>;
  }

  /// Synthesizes text in a cloned voice, returning [VoiceCloneResponse] with decoded audio bytes.
  Future<VoiceCloneResponse> convert(
    VoiceCloneRequest request, {
    RequestOptions? options,
  }) async {
    final uri = Uri.parse('${_environment.apiBaseUrl}/voices/clone');
    final headers = <String, String>{};
    if (options?.headers != null) {
      headers.addAll(options!.headers!);
    }

    final files = <SarvamFileInput>[];
    if (request.refAudio != null) {
      final ref = request.refAudio!;
      files.add(
        ref.field == 'ref_audio'
            ? ref
            : (ref.bytes != null
                ? SarvamFileInput.fromBytes(
                    'ref_audio',
                    ref.bytes!,
                    filename: ref.filename,
                    contentType: ref.contentType,
                  )
                : SarvamFileInput.fromStream(
                    'ref_audio',
                    ref.streamFactory,
                    ref.length,
                    filename: ref.filename,
                    contentType: ref.contentType,
                    isReplayable: ref.isReplayable,
                  )),
      );
    }

    final httpRequest = HttpRequest(
      url: uri,
      method: 'POST',
      headers: headers,
      files: files.isNotEmpty ? files : null,
      fields: request.toFields(),
      operationKind: OperationKind.multipartCompute,
      timeout: options?.timeout,
    );

    final response = await _pipeline(httpRequest);
    final json = jsonDecode(response.body) as Map<String, dynamic>;
    return VoiceCloneResponse.fromJson(json);
  }

  /// Synthesizes text into a cloned voice as a chunked HTTP binary stream.
  Stream<Uint8List> stream(
    VoiceCloneRequest request, {
    RequestOptions? options,
  }) async* {
    final uri = Uri.parse('${_environment.apiBaseUrl}/voices/clone/stream');
    final headers = <String, String>{};
    if (options?.headers != null) {
      headers.addAll(options!.headers!);
    }

    final files = <SarvamFileInput>[];
    if (request.refAudio != null) {
      final ref = request.refAudio!;
      files.add(
        ref.field == 'ref_audio'
            ? ref
            : (ref.bytes != null
                ? SarvamFileInput.fromBytes(
                    'ref_audio',
                    ref.bytes!,
                    filename: ref.filename,
                    contentType: ref.contentType,
                  )
                : SarvamFileInput.fromStream(
                    'ref_audio',
                    ref.streamFactory,
                    ref.length,
                    filename: ref.filename,
                    contentType: ref.contentType,
                    isReplayable: ref.isReplayable,
                  )),
      );
    }

    final httpRequest = HttpRequest(
      url: uri,
      method: 'POST',
      headers: headers,
      files: files.isNotEmpty ? files : null,
      fields: request.toFields(),
      operationKind: OperationKind.multipartCompute,
      timeout: options?.timeout,
      isStreaming: true,
    );

    final response = await _pipeline(httpRequest);
    yield* response.stream;
  }

  /// Connects to the voice cloning realtime WebSocket session,
  /// immediately sending the initial config frame.
  Future<TtsStreamingSession> connect(
    VoiceCloningStreamingConfig config, {
    RequestOptions? options,
  }) async {
    final queryParams = <String, String>{
      'send_completion_event': 'true',
    };
    if (options?.queryParams != null) {
      options!.queryParams!.forEach((k, v) => queryParams[k] = v.toString());
    }

    final uri = Uri.parse('${_environment.wsBaseUrl}/voices/clone/ws')
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
    session.send(jsonEncode(config.toConfigPayload()));

    return TtsStreamingSession(session);
  }
}
