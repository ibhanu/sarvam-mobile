import 'dart:convert';

import 'package:sarvam/src/generated/sarvam_spec_generated.dart';
import '../core/environment.dart';
import '../core/middleware/middleware.dart';
import '../core/request_options.dart';
import '../core/transport.dart';
import '../models/text_models.dart';

/// Resource for text translation, transliteration, and language identification.
class TextResource {
  final HttpHandler _pipeline;
  final SarvamEnvironment _environment;

  TextResource(this._pipeline, this._environment);

  /// Translates text into an Indic language or English.
  Future<TranslateResponse> translate(
    TranslateRequest request, {
    RequestOptions? options,
  }) async {
    final uri = Uri.parse('${_environment.apiBaseUrl}/translate');
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
    return TranslateResponse.fromJson(json);
  }

  /// Transliterates text from one script into another.
  Future<TransliterateResponse> transliterate(
    TransliterateRequest request, {
    RequestOptions? options,
  }) async {
    final uri = Uri.parse('${_environment.apiBaseUrl}/transliterate');
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
    return TransliterateResponse.fromJson(json);
  }

  /// Identifies the spoken or written language of the given text.
  Future<TextLidResponse> identifyLanguage(
    IdentifyLanguageRequest request, {
    RequestOptions? options,
  }) async {
    final uri = Uri.parse('${_environment.apiBaseUrl}/text-lid');
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
    return TextLidResponse.fromJson(json);
  }
}
