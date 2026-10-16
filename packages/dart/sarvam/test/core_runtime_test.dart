import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:sarvam/sarvam.dart';
import 'package:test/test.dart';

import 'test_helpers.dart';

void main() {
  group('Core Runtime Unit Tests', () {
    test('SarvamEnvironment production and proxy behavior', () {
      const prod = SarvamEnvironment.production;
      expect(prod.apiBaseUrl, 'https://api.sarvam.ai');
      expect(prod.dubbingBaseUrl, 'https://api.sarvam.ai/dubbing');
      expect(prod.wsBaseUrl, 'wss://api.sarvam.ai');

      final proxyHttps =
          SarvamEnvironment.proxy('https://proxy.example.com/sarvam/');
      expect(proxyHttps.apiBaseUrl, 'https://proxy.example.com/sarvam');
      expect(proxyHttps.dubbingBaseUrl,
          'https://proxy.example.com/sarvam/dubbing');
      expect(proxyHttps.wsBaseUrl, 'wss://proxy.example.com/sarvam');

      final proxyHttp = SarvamEnvironment.proxy('http://localhost:8080');
      expect(proxyHttp.apiBaseUrl, 'http://localhost:8080');
      expect(proxyHttp.dubbingBaseUrl, 'http://localhost:8080/dubbing');
      expect(proxyHttp.wsBaseUrl, 'ws://localhost:8080');
    });

    test('SarvamCredentials header and websocket application', () {
      const sub = SubscriptionKey('my-key');
      final restHeaders = <String, String>{};
      sub.applyToHttpHeaders(restHeaders);
      expect(restHeaders['api-subscription-key'], 'my-key');

      final nativeWsHeaders = <String, String>{};
      final nativeProtocols = <String>[];
      sub.applyToWebSocket(
        headers: nativeWsHeaders,
        protocols: nativeProtocols,
        useSubprotocolAuth: false,
      );
      expect(nativeWsHeaders['Api-Subscription-Key'], 'my-key');
      expect(nativeProtocols.isEmpty, isTrue);

      final webWsHeaders = <String, String>{};
      final webProtocols = <String>[];
      sub.applyToWebSocket(
        headers: webWsHeaders,
        protocols: webProtocols,
        useSubprotocolAuth: true,
      );
      expect(webProtocols, contains('api-subscription-key.my-key'));

      const bearer = BearerToken('my-token');
      final bearerHeaders = <String, String>{};
      bearer.applyToHttpHeaders(bearerHeaders);
      expect(bearerHeaders['Authorization'], 'Bearer my-token');

      const custom = CustomHeaders({'x-app-user': 'user_123'});
      final customHeaders = <String, String>{};
      custom.applyToHttpHeaders(customHeaders);
      expect(customHeaders['x-app-user'], 'user_123');
    });

    test('TokenAuth caching, single-flight deduplication and proactive refresh',
        () async {
      final clock = MockClock(
          initialTime: DateTime.fromMillisecondsSinceEpoch(1000000000));
      var callCount = 0;

      final completer = Completer<AuthToken>();
      Future<AuthToken> tokenProvider() async {
        callCount++;
        if (callCount == 1) {
          return completer.future;
        }
        return AuthToken(
          token: 'token_$callCount',
          expiresAtEpochMs:
              clock.now().millisecondsSinceEpoch + 120000, // 2 minutes from now
        );
      }

      final auth = TokenAuth(tokenProvider, clock: clock);

      // Concurrent calls sharing in-flight refresh (single-flight deduplication)
      final future1 = auth.getCredentials();
      final future2 = auth.getCredentials();

      completer.complete(AuthToken(
        token: 'token_1',
        expiresAtEpochMs: clock.now().millisecondsSinceEpoch + 120000,
      ));

      final creds1 = await future1 as BearerToken;
      final creds2 = await future2 as BearerToken;

      expect(callCount, 1);
      expect(creds1.token, 'token_1');
      expect(creds2.token, 'token_1');

      // Subsequent call within valid window uses cache
      clock
          .advance(const Duration(seconds: 30)); // 90s remaining (> 60s buffer)
      final creds3 = await auth.getCredentials() as BearerToken;
      expect(callCount, 1);
      expect(creds3.token, 'token_1');

      // Advance clock into the 60s proactive buffer (50s remaining)
      clock.advance(const Duration(seconds: 40));
      final creds4 = await auth.getCredentials() as BearerToken;
      expect(callCount, 2);
      expect(creds4.token, 'token_2');

      // Invalidation clears cache immediately
      auth.invalidate();
      final creds5 = await auth.getCredentials() as BearerToken;
      expect(callCount, 3);
      expect(creds5.token, 'token_3');
    });

    test('SarvamException mapping for all HTTP error codes', () {
      final e400 = SarvamException.fromHttpResponse(
        statusCode: 400,
        headers: {},
        rawBody: '{"error":{"code":"bad_request","message":"invalid field"}}',
      );
      expect(e400, isA<BadRequestException>());
      expect((e400 as BadRequestException).rawBody, contains('invalid field'));

      final e404 = SarvamException.fromHttpResponse(
        statusCode: 404,
        headers: {},
        rawBody: '{"message":"not found"}',
      );
      expect(e404, isA<NotFoundException>());

      final e413 = SarvamException.fromHttpResponse(
        statusCode: 413,
        headers: {},
        rawBody: '{"message":"too large"}',
      );
      expect(e413, isA<PayloadTooLargeException>());

      final e422 = SarvamException.fromHttpResponse(
        statusCode: 422,
        headers: {},
        rawBody: '{"message":"unprocessable"}',
      );
      expect(e422, isA<UnprocessableEntityException>());

      final e429 = SarvamException.fromHttpResponse(
        statusCode: 429,
        headers: {'retry-after': '3'},
        rawBody: '{"message":"slow down"}',
      );
      expect(e429, isA<RateLimitException>());
      expect((e429 as RateLimitException).retryAfterMs, 3000);

      final e503RateLimit = SarvamException.fromHttpResponse(
        statusCode: 503,
        headers: {'retry-after-ms': '500'},
        rawBody:
            '{"error":{"code":"rate_limit_exceeded_error","message":"busy"}}',
      );
      expect(e503RateLimit, isA<RateLimitException>());
      expect((e503RateLimit as RateLimitException).retryAfterMs, 500);

      final e500 = SarvamException.fromHttpResponse(
        statusCode: 500,
        headers: {'x-request-id': 'req_abc'},
        rawBody: '{"message":"internal error"}',
      );
      expect(e500, isA<ServerException>());
      expect(e500.requestId, 'req_abc');
    });

    test('SarvamFileInput replayability', () {
      final fromBytes =
          SarvamFileInput.fromBytes('audio', Uint8List.fromList([1, 2, 3]));
      expect(fromBytes.isReplayable, isTrue);
      expect(fromBytes.bytes?.length, 3);

      final fromStreamNonReplayable = SarvamFileInput.fromStream(
        'audio',
        () => Stream.value([1, 2, 3]),
        3,
        isReplayable: false,
      );
      expect(fromStreamNonReplayable.isReplayable, isFalse);

      final fromStreamReplayable = SarvamFileInput.fromStream(
        'audio',
        () => Stream.value([1, 2, 3]),
        3,
        isReplayable: true,
      );
      expect(fromStreamReplayable.isReplayable, isTrue);
    });

    test('ChatSession session affinity header injection', () async {
      final transport = MockHttpTransport((req) async {
        expect(req.headers['x-session-affinity'], 'session-uuid-1234');
        return jsonResponse(
          statusCode: 200,
          data: <String, dynamic>{
            'id': 'chat_resp_1',
            'choices': <Map<String, dynamic>>[
              <String, dynamic>{
                'index': 0,
                'message': <String, dynamic>{
                  'role': 'assistant',
                  'content': 'Hello back'
                },
              },
            ],
          },
        );
      });

      final client = SarvamClient(
        auth: ApiKeyAuth('key'),
        transport: transport,
      );

      final session = client.chat.createSession(sessionId: 'session-uuid-1234');
      final res = await session.completions(
        const ChatCompletionRequest(
          model: 'sarvam-2b',
          messages: <ChatMessage>[ChatMessage(role: 'user', content: 'Hello')],
        ),
      );

      expect(res.choices.first.message?.content, 'Hello back');
      expect(transport.recordedRequests.first.headers['x-session-affinity'],
          'session-uuid-1234');
    });

    test('RetryMiddleware does retry idempotent on 500 with backoff', () async {
      var count = 0;
      final clock = MockClock();
      final transport = MockHttpTransport((req) async {
        count++;
        if (count < 3) {
          return HttpResponse(
            statusCode: 500,
            headers: {},
            bodyBytes: Uint8List.fromList(utf8.encode('{"message":"fail"}')),
          );
        }
        return jsonResponse(statusCode: 200, data: {'status': 'ok'});
      });

      final pipeline = buildPipeline(transport, [
        RetryMiddleware(clock: clock, maxRetries: 2),
      ]);

      final res = await pipeline(HttpRequest(
        url: Uri.parse('https://api.sarvam.ai/v2/models'),
        method: 'GET',
        operationKind: OperationKind.idempotent,
      ));

      expect(res.statusCode, 200);
      expect(count, 3);
      expect(clock.recordedSleeps.length, 2);
    });

    test('RetryMiddleware does NOT retry multipartCompute on 500', () async {
      var count = 0;
      final clock = MockClock();
      final transport = MockHttpTransport((req) async {
        count++;
        return jsonResponse(statusCode: 500, data: {'message': 'fail'});
      });

      final pipeline = buildPipeline(transport, [
        RetryMiddleware(clock: clock, maxRetries: 2),
      ]);

      expect(
        () => pipeline(HttpRequest(
          url: Uri.parse('https://api.sarvam.ai/speech-to-text'),
          method: 'POST',
          operationKind: OperationKind.multipartCompute,
        )),
        throwsA(isA<ServerException>()),
      );

      expect(count, 1, reason: 'multipartCompute must not retry on 500');
    });

    test(
        'RetryMiddleware retries jobCreate on 500 if Idempotency-Key header is present',
        () async {
      var count = 0;
      final clock = MockClock();
      final transport = MockHttpTransport((req) async {
        count++;
        if (count == 1) {
          return jsonResponse(statusCode: 500, data: {'message': 'fail'});
        }
        return jsonResponse(statusCode: 200, data: {'job_id': 'job_123'});
      });

      final pipeline = buildPipeline(transport, [
        RetryMiddleware(clock: clock, maxRetries: 2),
      ]);

      final res = await pipeline(HttpRequest(
        url: Uri.parse('https://api.sarvam.ai/doc-ai/v1/job/digitise'),
        method: 'POST',
        headers: {'Idempotency-Key': 'my-unique-key'},
        operationKind: OperationKind.jobCreate,
      ));

      expect(res.statusCode, 200);
      expect(count, 2);
    });
  });
}
