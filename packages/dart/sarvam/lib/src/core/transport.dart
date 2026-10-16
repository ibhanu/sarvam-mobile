import 'dart:convert';
import 'dart:typed_data';

import 'package:sarvam/src/generated/sarvam_spec_generated.dart';
import 'file_input.dart';

/// Low-level HTTP request abstraction passed through the middleware pipeline.
class HttpRequest {
  final Uri url;
  final String method;
  final Map<String, String> headers;
  final Uint8List? bodyBytes;
  final List<SarvamFileInput>? files;
  final Map<String, String>? fields;
  final OperationKind operationKind;
  final Duration? timeout;
  final bool isStreaming;

  HttpRequest({
    required this.url,
    required this.method,
    Map<String, String>? headers,
    this.bodyBytes,
    this.files,
    this.fields,
    this.operationKind = OperationKind.statelessPost,
    this.timeout,
    this.isStreaming = false,
  }) : headers = headers != null
            ? Map<String, String>.of(headers)
            : <String, String>{};

  /// Decodes [bodyBytes] as a UTF-8 string, or returns an empty string if null.
  String get body =>
      bodyBytes != null ? utf8.decode(bodyBytes!, allowMalformed: true) : '';

  HttpRequest copyWith({
    Uri? url,
    String? method,
    Map<String, String>? headers,
    Uint8List? bodyBytes,
    List<SarvamFileInput>? files,
    Map<String, String>? fields,
    OperationKind? operationKind,
    Duration? timeout,
    bool? isStreaming,
  }) {
    return HttpRequest(
      url: url ?? this.url,
      method: method ?? this.method,
      headers: headers ?? Map<String, String>.of(this.headers),
      bodyBytes: bodyBytes ?? this.bodyBytes,
      files: files ?? this.files,
      fields: fields ?? this.fields,
      operationKind: operationKind ?? this.operationKind,
      timeout: timeout ?? this.timeout,
      isStreaming: isStreaming ?? this.isStreaming,
    );
  }

  /// Helper to check if this request has any attached files that cannot be replayed.
  bool get hasNonReplayableFiles {
    if (files == null || files!.isEmpty) return false;
    return files!.any((file) => !file.isReplayable);
  }
}

/// Low-level HTTP response abstraction returned from [HttpTransport].
class HttpResponse {
  final int statusCode;
  final Map<String, String> headers;
  final Uint8List bodyBytes;
  final Stream<Uint8List> stream;

  HttpResponse({
    required this.statusCode,
    required this.headers,
    required this.bodyBytes,
    Stream<Uint8List>? stream,
  }) : stream = stream ?? Stream<Uint8List>.value(bodyBytes);

  /// Decodes [bodyBytes] as a UTF-8 string.
  String get body => utf8.decode(bodyBytes, allowMalformed: true);
}

/// Abstract contract for sending HTTP requests.
abstract interface class HttpTransport {
  /// Sends an HTTP request and returns an [HttpResponse].
  Future<HttpResponse> send(HttpRequest request);

  /// Closes the transport and releases any pooled resources.
  void close();
}
