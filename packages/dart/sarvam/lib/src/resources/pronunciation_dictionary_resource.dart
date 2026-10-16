import 'dart:convert';

import 'package:sarvam/src/generated/sarvam_spec_generated.dart';
import '../core/environment.dart';
import '../core/file_input.dart';
import '../core/middleware/middleware.dart';
import '../core/request_options.dart';
import '../core/transport.dart';
import '../models/pronunciation_dictionary_models.dart';

/// Resource for managing custom pronunciation dictionaries for Text-to-Speech synthesis.
class PronunciationDictionaryResource {
  final HttpHandler _pipeline;
  final SarvamEnvironment _environment;

  PronunciationDictionaryResource(this._pipeline, this._environment);

  /// Lists all pronunciation dictionaries associated with the account.
  Future<PronunciationDictionaryListResponse> list({
    RequestOptions? options,
  }) async {
    final uri =
        Uri.parse('${_environment.apiBaseUrl}/text-to-speech/pronunciation-dictionary');
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
    return PronunciationDictionaryListResponse.fromJson(json);
  }

  /// Creates a new pronunciation dictionary from a file upload (e.g. `.pls` XML).
  Future<PronunciationDictionaryResponse> create(
    SarvamFileInput file, {
    RequestOptions? options,
  }) async {
    final uri =
        Uri.parse('${_environment.apiBaseUrl}/text-to-speech/pronunciation-dictionary');
    final headers = <String, String>{};
    if (options?.headers != null) {
      headers.addAll(options!.headers!);
    }

    final normalizedFile = file.field == 'file'
        ? file
        : (file.bytes != null
            ? SarvamFileInput.fromBytes(
                'file',
                file.bytes!,
                filename: file.filename,
                contentType: file.contentType,
              )
            : SarvamFileInput.fromStream(
                'file',
                file.streamFactory,
                file.length,
                filename: file.filename,
                contentType: file.contentType,
                isReplayable: file.isReplayable,
              ));

    final httpRequest = HttpRequest(
      url: uri,
      method: 'POST',
      headers: headers,
      files: <SarvamFileInput>[normalizedFile],
      operationKind: OperationKind.multipartCompute,
      timeout: options?.timeout,
    );

    final response = await _pipeline(httpRequest);
    final json = jsonDecode(response.body) as Map<String, dynamic>;
    return PronunciationDictionaryResponse.fromJson(json);
  }

  /// Updates an existing pronunciation dictionary by [dictId].
  Future<PronunciationDictionaryResponse> update(
    String dictId,
    SarvamFileInput file, {
    RequestOptions? options,
  }) async {
    final uri = Uri.parse(
            '${_environment.apiBaseUrl}/text-to-speech/pronunciation-dictionary')
        .replace(queryParameters: <String, String>{'dict_id': dictId});
    final headers = <String, String>{};
    if (options?.headers != null) {
      headers.addAll(options!.headers!);
    }

    final normalizedFile = file.field == 'file'
        ? file
        : (file.bytes != null
            ? SarvamFileInput.fromBytes(
                'file',
                file.bytes!,
                filename: file.filename,
                contentType: file.contentType,
              )
            : SarvamFileInput.fromStream(
                'file',
                file.streamFactory,
                file.length,
                filename: file.filename,
                contentType: file.contentType,
                isReplayable: file.isReplayable,
              ));

    final httpRequest = HttpRequest(
      url: uri,
      method: 'PUT',
      headers: headers,
      files: <SarvamFileInput>[normalizedFile],
      operationKind: OperationKind.idempotent,
      timeout: options?.timeout,
    );

    final response = await _pipeline(httpRequest);
    final json = jsonDecode(response.body) as Map<String, dynamic>;
    return PronunciationDictionaryResponse.fromJson(json);
  }

  /// Retrieves a pronunciation dictionary by its [dictId].
  Future<PronunciationDictionary> get(
    String dictId, {
    RequestOptions? options,
  }) async {
    final uri = Uri.parse(
        '${_environment.apiBaseUrl}/text-to-speech/pronunciation-dictionary/${Uri.encodeComponent(dictId)}');
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
    return PronunciationDictionary.fromJson(data);
  }

  /// Deletes a pronunciation dictionary by [dictId].
  Future<Map<String, dynamic>> delete(
    String dictId, {
    RequestOptions? options,
  }) async {
    final uri = Uri.parse(
            '${_environment.apiBaseUrl}/text-to-speech/pronunciation-dictionary')
        .replace(queryParameters: <String, String>{'dict_id': dictId});
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
}
