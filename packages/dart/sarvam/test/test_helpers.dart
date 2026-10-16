import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:sarvam/sarvam.dart';

/// In-memory mock HTTP transport for simulating server responses and recording requests.
class MockHttpTransport implements HttpTransport {
  final Future<HttpResponse> Function(HttpRequest request) handler;
  final List<HttpRequest> recordedRequests = <HttpRequest>[];
  bool isClosed = false;

  MockHttpTransport(this.handler);

  @override
  Future<HttpResponse> send(HttpRequest request) {
    recordedRequests.add(request);
    return handler(request);
  }

  @override
  void close() {
    isClosed = true;
  }
}

/// Helper to create an [HttpResponse] easily in tests.
HttpResponse jsonResponse({
  int statusCode = 200,
  required Object data,
  Map<String, String>? headers,
}) {
  final body = jsonEncode(data);
  final bodyBytes = Uint8List.fromList(utf8.encode(body));
  final responseHeaders = <String, String>{
    'content-type': 'application/json',
    if (headers != null) ...headers,
  };
  return HttpResponse(
    statusCode: statusCode,
    headers: responseHeaders,
    bodyBytes: bodyBytes,
    stream: Stream<Uint8List>.value(bodyBytes),
  );
}

/// Helper to create a binary stream [HttpResponse].
HttpResponse chunkedBinaryResponse({
  int statusCode = 200,
  required List<Uint8List> chunks,
  Map<String, String>? headers,
}) {
  final responseHeaders = <String, String>{
    'content-type': 'application/octet-stream',
    'transfer-encoding': 'chunked',
    if (headers != null) ...headers,
  };
  return HttpResponse(
    statusCode: statusCode,
    headers: responseHeaders,
    bodyBytes: Uint8List(0),
    stream: Stream<Uint8List>.fromIterable(chunks),
  );
}

/// Helper to create an SSE text stream [HttpResponse].
HttpResponse sseResponse({
  int statusCode = 200,
  required String ssePayload,
  Map<String, String>? headers,
}) {
  final bytes = Uint8List.fromList(utf8.encode(ssePayload));
  final responseHeaders = <String, String>{
    'content-type': 'text/event-stream',
    if (headers != null) ...headers,
  };
  return HttpResponse(
    statusCode: statusCode,
    headers: responseHeaders,
    bodyBytes: bytes,
    stream: Stream<Uint8List>.value(bytes),
  );
}

/// Mock WebSocket session for recording outbound messages and injecting inbound frames.
class MockWebSocketSession implements WebSocketSession {
  final StreamController<dynamic> _incomingController =
      StreamController<dynamic>.broadcast();
  final List<dynamic> sentFrames = <dynamic>[];
  bool isClosed = false;
  int? closeCode;
  String? closeReason;

  @override
  Stream<dynamic> get incoming => _incomingController.stream;

  @override
  void send(dynamic data) {
    sentFrames.add(data);
  }

  void pushIncoming(dynamic frame) {
    _incomingController.add(frame);
  }

  void pushError(Object error) {
    _incomingController.addError(error);
  }

  @override
  Future<void> close([int? code, String? reason]) async {
    isClosed = true;
    closeCode = code;
    closeReason = reason;
    await _incomingController.close();
  }
}

/// Mock WebSocket factory for capturing connection parameters and supplying [MockWebSocketSession].
class MockWebSocketFactory implements WebSocketFactory {
  Uri? lastUri;
  Map<String, String>? lastHeaders;
  List<String>? lastProtocols;
  final MockWebSocketSession session;

  MockWebSocketFactory({MockWebSocketSession? session})
      : session = session ?? MockWebSocketSession();

  @override
  Future<WebSocketSession> connect(
    Uri uri, {
    Map<String, String>? headers,
    Iterable<String>? protocols,
  }) async {
    lastUri = uri;
    lastHeaders = headers != null ? Map<String, String>.of(headers) : null;
    lastProtocols = protocols != null ? List<String>.of(protocols) : null;
    return session;
  }
}
