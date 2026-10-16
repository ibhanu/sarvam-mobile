import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:sarvam/sarvam.dart';
import 'package:sarvam/src/core/websocket_channel_io.dart';
import 'package:test/test.dart';

void main() {
  group('PackageHttpTransport Unit Tests', () {
    test('standard GET and POST requests with headers and body', () async {
      late http.BaseRequest capturedRequest;
      final mockClient = MockClient((request) async {
        capturedRequest = request;
        return http.Response('{"status":"ok"}', 200, headers: {
          'content-type': 'application/json',
          'x-test': 'value',
        });
      });

      final transport = PackageHttpTransport(client: mockClient);

      // GET request
      final getReq = HttpRequest(
        url: Uri.parse('https://api.sarvam.ai/v1/test'),
        method: 'GET',
        headers: {'Authorization': 'Bearer test-token'},
      );
      final getResp = await transport.send(getReq);
      expect(getResp.statusCode, 200);
      expect(getResp.headers['x-test'], 'value');
      expect(getResp.body, '{"status":"ok"}');
      expect(capturedRequest.method, 'GET');
      expect(capturedRequest.headers['authorization'], 'Bearer test-token');

      // POST request with body bytes
      final postReq = HttpRequest(
        url: Uri.parse('https://api.sarvam.ai/v1/test'),
        method: 'POST',
        headers: {'Content-Type': 'application/json'},
        bodyBytes: Uint8List.fromList(utf8.encode('{"hello":"world"}')),
      );
      final postResp = await transport.send(postReq);
      expect(postResp.statusCode, 200);
      expect(capturedRequest.method, 'POST');
      expect(capturedRequest, isA<http.Request>());
      expect((capturedRequest as http.Request).body, '{"hello":"world"}');

      // close() should not close client since ownsClient is false
      transport.close();
    });

    test('multipart request with fromBytes and fromStream and fields', () async {
      late http.BaseRequest capturedRequest;
      final mockClient = MockClient.streaming((request, bodyStream) async {
        capturedRequest = request;
        return http.StreamedResponse(
          Stream<List<int>>.value(utf8.encode('{"uploaded":true}')),
          200,
        );
      });

      final transport = PackageHttpTransport(client: mockClient);

      final fileBytes = SarvamFileInput.fromBytes(
        'audio_bytes',
        Uint8List.fromList([1, 2, 3, 4]),
        filename: 'test.wav',
        contentType: 'audio/wav',
      );

      final fileStream = SarvamFileInput.fromStream(
        'audio_stream',
        () => Stream<List<int>>.value([5, 6, 7, 8]),
        4,
        filename: 'stream.wav',
        contentType: 'audio/wav',
      );

      final request = HttpRequest(
        url: Uri.parse('https://api.sarvam.ai/upload'),
        method: 'POST',
        files: [fileBytes, fileStream],
        fields: {'key': 'val', 'language': 'hi-IN'},
        headers: {'x-custom': '123'},
      );

      final response = await transport.send(request);
      expect(response.statusCode, 200);
      expect(capturedRequest, isA<http.MultipartRequest>());

      final multipart = capturedRequest as http.MultipartRequest;
      expect(multipart.fields['key'], 'val');
      expect(multipart.fields['language'], 'hi-IN');
      expect(multipart.headers['x-custom'], '123');
      expect(multipart.files.length, 2);
      expect(multipart.files[0].field, 'audio_bytes');
      expect(multipart.files[0].filename, 'test.wav');
      expect(multipart.files[1].field, 'audio_stream');
      expect(multipart.files[1].filename, 'stream.wav');
    });

    test('streaming response returns byte stream', () async {
      final mockClient = MockClient.streaming((request, bodyStream) async {
        final stream = Stream<List<int>>.fromIterable([
          [1, 2],
          [3, 4],
        ]);
        return http.StreamedResponse(stream, 200, headers: {'x-stream': 'true'});
      });

      final transport = PackageHttpTransport(client: mockClient);
      final request = HttpRequest(
        url: Uri.parse('https://api.sarvam.ai/stream'),
        method: 'GET',
        isStreaming: true,
      );

      final response = await transport.send(request);
      expect(response.statusCode, 200);
      expect(response.headers['x-stream'], 'true');
      expect(response.bodyBytes, isEmpty);

      final collectedChunks = <Uint8List>[];
      await for (final chunk in response.stream) {
        collectedChunks.add(chunk);
      }
      expect(collectedChunks.length, 2);
      expect(collectedChunks[0], [1, 2]);
      expect(collectedChunks[1], [3, 4]);
    });

    test('timeout handling maps to TimeoutException', () async {
      final mockClient = MockClient((request) async {
        await Future<void>.delayed(const Duration(milliseconds: 100));
        return http.Response('ok', 200);
      });

      final transport = PackageHttpTransport(client: mockClient);
      final request = HttpRequest(
        url: Uri.parse('https://api.sarvam.ai/timeout'),
        method: 'GET',
        timeout: const Duration(milliseconds: 10),
      );

      await expectLater(
        () => transport.send(request),
        throwsA(isA<TimeoutException>().having(
          (e) => e.phase,
          'phase',
          TimeoutPhase.total,
        )),
      );
    });

    test('connection exception handling maps to ConnectionException', () async {
      final mockClient = MockClient((request) async {
        throw const SocketException('Connection refused');
      });

      final transport = PackageHttpTransport(client: mockClient);
      final request = HttpRequest(
        url: Uri.parse('https://api.sarvam.ai/fail'),
        method: 'GET',
      );

      await expectLater(
        () => transport.send(request),
        throwsA(isA<ConnectionException>().having(
          (e) => e.cause,
          'cause',
          isA<SocketException>(),
        )),
      );
    });

    test('ownsClient = true closes http client on close()', () {
      final transport = PackageHttpTransport();
      // Should not throw
      transport.close();
    });
  });

  group('DefaultWebSocketFactory & ChannelWebSocketSession Unit Tests', () {
    late HttpServer server;
    late Uri serverUri;
    String? lastProtocolReceived;
    HttpHeaders? lastHeadersReceived;

    setUp(() async {
      server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      serverUri = Uri.parse('ws://127.0.0.1:${server.port}/ws');

      server.listen((ioRequest) async {
        lastHeadersReceived = ioRequest.headers;
        lastProtocolReceived = ioRequest.headers.value('sec-websocket-protocol');

        if (WebSocketTransformer.isUpgradeRequest(ioRequest)) {
          final ws = await WebSocketTransformer.upgrade(
            ioRequest,
            protocolSelector: (protocols) {
              if (protocols.isNotEmpty) return protocols.first;
              return null;
            },
          );

          ws.listen(
            (message) {
              // Echo message back with prefix
              if (message is String) {
                ws.add('echo:$message');
              } else if (message is List<int>) {
                ws.add(message);
              }
            },
            onDone: () {
              ws.close();
            },
          );
        } else {
          ioRequest.response.statusCode = HttpStatus.badRequest;
          await ioRequest.response.close();
        }
      });
    });

    tearDown(() async {
      await server.close(force: true);
    });

    test('connects with native headers, sends and receives text and binary, closes cleanly', () async {
      const factory = DefaultWebSocketFactory();
      final session = await factory.connect(
        serverUri,
        headers: {'api-subscription-key': 'test-sub-key'},
      );

      expect(lastHeadersReceived?.value('api-subscription-key'), 'test-sub-key');

      final incomingEvents = <dynamic>[];
      final sub = session.incoming.listen(incomingEvents.add);

      session.send('hello world');
      await Future<void>.delayed(const Duration(milliseconds: 50));

      expect(incomingEvents, contains('echo:hello world'));

      session.send(Uint8List.fromList([10, 20, 30]));
      await Future<void>.delayed(const Duration(milliseconds: 50));

      expect(incomingEvents.any((e) => e is List<int> && e.length == 3), isTrue);

      await session.close(1000, 'normal closure');
      await sub.cancel();
    });

    test('connects with subprotocol authentication', () async {
      const factory = DefaultWebSocketFactory();
      final session = await factory.connect(
        serverUri,
        protocols: ['api-subscription-key.secret-key-123'],
      );

      expect(lastProtocolReceived, 'api-subscription-key.secret-key-123');

      final completer = Completer<String>();
      final sub = session.incoming.listen((data) {
        if (!completer.isCompleted) completer.complete(data as String);
      });

      session.send('ping');
      final result = await completer.future.timeout(const Duration(seconds: 2));
      expect(result, 'echo:ping');

      await session.close();
      await sub.cancel();
    });

    test('connect throws RealtimeException on connection error', () async {
      const factory = DefaultWebSocketFactory();
      // Unopened port on loopback
      final deadUri = Uri.parse('ws://127.0.0.1:54321/ws');

      await expectLater(
        () => factory.connect(deadUri),
        throwsA(isA<RealtimeException>()),
      );
    });
  });
}
