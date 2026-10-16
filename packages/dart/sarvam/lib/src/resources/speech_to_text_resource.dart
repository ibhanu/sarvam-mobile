import 'dart:convert';

import 'package:sarvam/src/generated/sarvam_spec_generated.dart';
import '../core/auth_provider.dart';
import '../core/environment.dart';
import '../core/file_input.dart';
import '../core/middleware/middleware.dart';
import '../core/request_options.dart';
import '../core/transport.dart';
import '../core/websocket_factory.dart';
import '../models/speech_to_text_models.dart';
import '../realtime/stt_realtime_session.dart';

/// Resource for speech recognition, audio translation, and realtime bi-directional STT streaming.
class SpeechToTextResource {
  final HttpHandler _pipeline;
  final SarvamEnvironment _environment;
  final AuthProvider _authProvider;
  final WebSocketFactory _webSocketFactory;

  SpeechToTextResource(
    this._pipeline,
    this._environment,
    this._authProvider,
    this._webSocketFactory,
  );

  /// Transcribes speech from an audio file into text.
  Future<SpeechToTextResponse> transcribe({
    required SarvamFileInput file,
    LanguageCode? languageCode,
    SttModel? model,
    SttMode? mode,
    RequestOptions? options,
  }) async {
    final uri = Uri.parse('${_environment.apiBaseUrl}/speech-to-text');
    final fields = <String, String>{};
    if (languageCode != null) fields['language_code'] = languageCode.value;
    if (model != null) fields['model'] = model.value;
    if (mode != null) fields['mode'] = mode.value;

    final headers = <String, String>{};
    if (options?.headers != null) {
      headers.addAll(options!.headers!);
    }

    final httpRequest = HttpRequest(
      url: uri,
      method: 'POST',
      headers: headers,
      files: <SarvamFileInput>[file],
      fields: fields,
      operationKind: OperationKind.multipartCompute,
      timeout: options?.timeout,
    );

    final response = await _pipeline(httpRequest);
    final json = jsonDecode(response.body) as Map<String, dynamic>;
    return SpeechToTextResponse.fromJson(json);
  }

  /// Transcribes speech from an audio file and translates it into another language.
  Future<SpeechToTextTranslateResponse> translate({
    required SarvamFileInput file,
    LanguageCode? sourceLanguageCode,
    LanguageCode? targetLanguageCode,
    SttModel? model,
    SttMode? mode,
    RequestOptions? options,
  }) async {
    final uri =
        Uri.parse('${_environment.apiBaseUrl}/speech-to-text-translate');
    final fields = <String, String>{};
    if (sourceLanguageCode != null) {
      fields['source_language_code'] = sourceLanguageCode.value;
    }
    if (targetLanguageCode != null) {
      fields['target_language_code'] = targetLanguageCode.value;
    }
    if (model != null) fields['model'] = model.value;
    if (mode != null) fields['mode'] = mode.value;

    final headers = <String, String>{};
    if (options?.headers != null) {
      headers.addAll(options!.headers!);
    }

    final httpRequest = HttpRequest(
      url: uri,
      method: 'POST',
      headers: headers,
      files: <SarvamFileInput>[file],
      fields: fields,
      operationKind: OperationKind.multipartCompute,
      timeout: options?.timeout,
    );

    final response = await _pipeline(httpRequest);
    final json = jsonDecode(response.body) as Map<String, dynamic>;
    return SpeechToTextTranslateResponse.fromJson(json);
  }

  /// Connects to the realtime bi-directional streaming speech recognition service over WebSocket.
  Future<SttRealtimeSession> connect(
    SttRealtimeConfig config, {
    RequestOptions? options,
  }) async {
    // 1. Client-side sample rate validation (throws BadRequestException if not 16000 or 8000).
    SttRealtimeSession.validateSampleRate(config.sampleRate);

    // 2. Prepare query parameters and handshake URI.
    final queryParams = config.toQueryParams();
    if (options?.queryParams != null) {
      options!.queryParams!.forEach((k, v) => queryParams[k] = v.toString());
    }

    final uri =
        Uri.parse('${_environment.wsBaseUrl}/speech-to-text-realtime/ws')
            .replace(queryParameters: queryParams);

    // 3. Resolve authentication credentials.
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

    // 4. Establish WebSocket connection.
    final session = await _webSocketFactory.connect(
      uri,
      headers: wsHeaders,
      protocols: wsProtocols.isNotEmpty ? wsProtocols : null,
    );

    return SttRealtimeSession(session);
  }
}
