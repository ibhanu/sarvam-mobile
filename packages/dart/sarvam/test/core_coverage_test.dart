import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:sarvam/sarvam.dart';
import 'package:sarvam/src/core/exceptions.dart';
import 'package:sarvam/src/core/sse/sse_event.dart';
import 'package:sarvam/src/core/sse/sse_transformer.dart';
import 'package:test/test.dart';

import 'test_helpers.dart';

class TestLogger implements LoggerAdapter {
  final List<String> logs = [];
  final List<String> levels = [];

  @override
  void log(String message, {String level = 'INFO'}) {
    logs.add(message);
    levels.add(level);
  }
}

void main() {
  group('SarvamCredentials Unit Tests', () {
    test('SubscriptionKey handles headers, webSocket native & subprotocol, equality & toString', () {
      const key1 = SubscriptionKey('my-secret-key');
      const key2 = SubscriptionKey('my-secret-key');
      const key3 = SubscriptionKey('other-key');

      expect(key1, equals(key2));
      expect(key1 == key3, isFalse);
      expect(key1.hashCode, equals(key2.hashCode));
      expect(key1.toString(), contains('REDACTED'));

      // HTTP headers
      final httpHeaders = <String, String>{};
      key1.applyToHttpHeaders(httpHeaders);
      expect(httpHeaders['api-subscription-key'], 'my-secret-key');

      // WebSocket native headers
      final wsHeaders = <String, String>{};
      final wsProtocols = <String>[];
      key1.applyToWebSocket(
        headers: wsHeaders,
        protocols: wsProtocols,
        useSubprotocolAuth: false,
      );
      expect(wsHeaders['Api-Subscription-Key'], 'my-secret-key');
      expect(wsProtocols, isEmpty);

      // WebSocket subprotocol
      final wsSubProtocols = <String>[];
      key1.applyToWebSocket(
        headers: wsHeaders,
        protocols: wsSubProtocols,
        useSubprotocolAuth: true,
      );
      expect(wsSubProtocols, contains('api-subscription-key.my-secret-key'));
    });

    test('BearerToken handles headers, webSocket native & subprotocol, equality & toString', () {
      const token1 = BearerToken('jwt-123', expiresAtEpochMs: 500000);
      const token2 = BearerToken('jwt-123', expiresAtEpochMs: 500000);
      const token3 = BearerToken('jwt-456');

      expect(token1, equals(token2));
      expect(token1 == token3, isFalse);
      expect(token1.hashCode, equals(token2.hashCode));
      expect(token1.toString(), contains('500000'));
      expect(token1.toString(), contains('REDACTED'));

      // HTTP headers
      final httpHeaders = <String, String>{};
      token1.applyToHttpHeaders(httpHeaders);
      expect(httpHeaders['Authorization'], 'Bearer jwt-123');

      // WebSocket native headers
      final wsHeaders = <String, String>{};
      final wsProtocols = <String>[];
      token1.applyToWebSocket(
        headers: wsHeaders,
        protocols: wsProtocols,
        useSubprotocolAuth: false,
      );
      expect(wsHeaders['Authorization'], 'Bearer jwt-123');
      expect(wsProtocols, isEmpty);

      // WebSocket subprotocol
      final wsSubProtocols = <String>[];
      token1.applyToWebSocket(
        headers: wsHeaders,
        protocols: wsSubProtocols,
        useSubprotocolAuth: true,
      );
      expect(wsSubProtocols, contains('bearer.jwt-123'));
    });

    test('CustomHeaders handles headers, webSocket, equality & toString', () {
      const custom1 = CustomHeaders({'x-bff-token': 'abc', 'x-tenant': 'tenant-1'});
      const custom2 = CustomHeaders({'x-bff-token': 'abc', 'x-tenant': 'tenant-1'});
      const custom3 = CustomHeaders({'x-other': 'val'});

      expect(custom1, equals(custom2));
      expect(custom1 == custom3, isFalse);
      expect(custom1.hashCode, isA<int>());
      expect(custom1.toString(), contains('x-bff-token'));

      final httpHeaders = <String, String>{'existing': 'prev'};
      custom1.applyToHttpHeaders(httpHeaders);
      expect(httpHeaders['x-bff-token'], 'abc');
      expect(httpHeaders['x-tenant'], 'tenant-1');
      expect(httpHeaders['existing'], 'prev');

      final wsHeaders = <String, String>{};
      final wsProtocols = <String>[];
      custom1.applyToWebSocket(
        headers: wsHeaders,
        protocols: wsProtocols,
        useSubprotocolAuth: false,
      );
      expect(wsHeaders['x-bff-token'], 'abc');
    });
  });

  group('SarvamEnvironment Unit Tests', () {
    test('production environment defaults', () {
      const prod = SarvamEnvironment.production;
      expect(prod.apiBaseUrl, 'https://api.sarvam.ai');
      expect(prod.dubbingBaseUrl, 'https://api.sarvam.ai/dubbing');
      expect(prod.wsBaseUrl, 'wss://api.sarvam.ai');
      expect(prod.toString(), contains('https://api.sarvam.ai'));
    });

    test('proxy constructor handles https, http, schemeless, trailing slashes, equality', () {
      final envHttps = SarvamEnvironment.proxy('https://proxy.example.com/api///');
      expect(envHttps.apiBaseUrl, 'https://proxy.example.com/api');
      expect(envHttps.dubbingBaseUrl, 'https://proxy.example.com/api/dubbing');
      expect(envHttps.wsBaseUrl, 'wss://proxy.example.com/api');

      final envHttp = SarvamEnvironment.proxy('http://proxy.example.com/api');
      expect(envHttp.wsBaseUrl, 'ws://proxy.example.com/api');

      final envSchemeless = SarvamEnvironment.proxy('proxy.example.com/api');
      expect(envSchemeless.wsBaseUrl, 'wss://proxy.example.com/api');

      final envCopy = SarvamEnvironment.proxy('https://proxy.example.com/api');
      expect(envHttps, equals(envCopy));
      expect(envHttps == envHttp, isFalse);
      expect(envHttps.hashCode, equals(envCopy.hashCode));
    });
  });

  group('SarvamFileInput & RequestOptions & Clock Unit Tests', () {
    test('SarvamFileInput.fromBytes and fromStream properties', () {
      final bytesFile = SarvamFileInput.fromBytes(
        'file',
        Uint8List.fromList([1, 2, 3]),
        filename: 'test.txt',
        contentType: 'text/plain',
      );
      expect(bytesFile.field, 'file');
      expect(bytesFile.length, 3);
      expect(bytesFile.isReplayable, isTrue);

      final streamFile = SarvamFileInput.fromStream(
        'file_stream',
        () => Stream.value([4, 5]),
        2,
        filename: 'stream.txt',
        contentType: 'text/plain',
        isReplayable: false,
      );
      expect(streamFile.field, 'file_stream');
      expect(streamFile.length, 2);
      expect(streamFile.isReplayable, isFalse);
    });

    test('RequestOptions copyWith and options', () {
      const initial = RequestOptions(
        timeout: Duration(seconds: 10),
        headers: {'a': '1'},
        queryParams: {'q': 'search'},
        idempotencyKey: 'key-1',
      );

      final updated = initial.copyWith(
        timeout: const Duration(seconds: 20),
        headers: {'b': '2'},
      );

      expect(updated.timeout, const Duration(seconds: 20));
      expect(updated.headers?['b'], '2');
      expect(updated.queryParams?['q'], 'search');
      expect(updated.idempotencyKey, 'key-1');
    });

    test('Clock implementations', () async {
      const sysClock = SystemClock();
      final now1 = sysClock.now();
      expect(now1.isBefore(DateTime.now().add(const Duration(seconds: 1))), isTrue);

      final settable = MockClock(initialTime: DateTime.utc(2026, 1, 1));
      expect(settable.now(), DateTime.utc(2026, 1, 1));
      settable.advance(const Duration(hours: 1));
      expect(settable.now(), DateTime.utc(2026, 1, 1, 1));
      await settable.sleep(const Duration(milliseconds: 1));
    });
  });

  group('HttpRequest copyWith and body Unit Tests', () {
    test('HttpRequest copyWith updates all parameters', () {
      final req = HttpRequest(
        url: Uri.parse('https://example.com/req'),
        method: 'POST',
        headers: {'k': 'v'},
        bodyBytes: Uint8List.fromList([65, 66]),
        operationKind: OperationKind.statelessPost,
        timeout: const Duration(seconds: 5),
        isStreaming: false,
      );
      expect(req.body, 'AB');

      final copied = req.copyWith(
        url: Uri.parse('https://example.com/copied'),
        method: 'PUT',
        headers: {'x': 'y'},
        bodyBytes: Uint8List.fromList([67, 68]),
        operationKind: OperationKind.idempotent,
        timeout: const Duration(seconds: 15),
        isStreaming: true,
      );

      expect(copied.url.toString(), 'https://example.com/copied');
      expect(copied.method, 'PUT');
      expect(copied.headers['x'], 'y');
      expect(copied.body, 'CD');
      expect(copied.operationKind, OperationKind.idempotent);
      expect(copied.timeout, const Duration(seconds: 15));
      expect(copied.isStreaming, isTrue);
    });

    test('HttpRequest.body handles null and malformed UTF-8 gracefully', () {
      final reqNull = HttpRequest(url: Uri.parse('https://example.com'), method: 'GET');
      expect(reqNull.body, '');

      final reqMalformed = HttpRequest(
        url: Uri.parse('https://example.com'),
        method: 'POST',
        bodyBytes: Uint8List.fromList([0xFF, 0xFE, 65]),
      );
      expect(reqMalformed.body, contains('A'));
    });
  });

  group('SarvamException Hierarchy and Parsing Unit Tests', () {
    test('SarvamException.fromHttpResponse parses all HTTP status codes', () {
      // 400
      final e400 = SarvamException.fromHttpResponse(
        statusCode: 400,
        headers: {},
        rawBody: '{"message":"bad request","code":"invalid_argument"}',
      );
      expect(e400, isA<BadRequestException>());
      expect(e400.message, 'bad request');
      expect(e400.code, 'invalid_argument');

      // 401
      final e401 = SarvamException.fromHttpResponse(
        statusCode: 401,
        headers: {},
        rawBody: '{"message":"unauthorized"}',
      );
      expect(e401, isA<AuthenticationException>());

      // 403 invalid_api_key_error -> AuthenticationException
      final e403Auth = SarvamException.fromHttpResponse(
        statusCode: 403,
        headers: {},
        rawBody: '{"message":"bad key","code":"invalid_api_key_error"}',
      );
      expect(e403Auth, isA<AuthenticationException>());

      // 403 general -> PermissionDeniedException
      final e403Perm = SarvamException.fromHttpResponse(
        statusCode: 403,
        headers: {},
        rawBody: '{"message":"forbidden","code":"forbidden_error"}',
      );
      expect(e403Perm, isA<PermissionDeniedException>());

      // 404
      final e404 = SarvamException.fromHttpResponse(
        statusCode: 404,
        headers: {},
        rawBody: '{"message":"not found"}',
      );
      expect(e404, isA<NotFoundException>());

      // 413
      final e413 = SarvamException.fromHttpResponse(
        statusCode: 413,
        headers: {},
        rawBody: '{"message":"too large"}',
      );
      expect(e413, isA<PayloadTooLargeException>());

      // 422
      final e422 = SarvamException.fromHttpResponse(
        statusCode: 422,
        headers: {},
        rawBody: '{"message":"unprocessable entity"}',
      );
      expect(e422, isA<UnprocessableEntityException>());

      // 429
      final e429 = SarvamException.fromHttpResponse(
        statusCode: 429,
        headers: {'retry-after': '3'},
        rawBody: '{"message":"rate limit exceeded"}',
      );
      expect(e429, isA<RateLimitException>());
      expect((e429 as RateLimitException).retryAfterMs, 3000);

      // 503 rate_limit_exceeded_error -> RateLimitException
      final e503Rate = SarvamException.fromHttpResponse(
        statusCode: 503,
        headers: {'retry-after-ms': '500'},
        rawBody: '{"code":"rate_limit_exceeded_error"}',
      );
      expect(e503Rate, isA<RateLimitException>());
      expect((e503Rate as RateLimitException).retryAfterMs, 500);

      // 500
      final e500 = SarvamException.fromHttpResponse(
        statusCode: 500,
        headers: {},
        rawBody: '{"message":"internal server error"}',
      );
      expect(e500, isA<ServerException>());

      // 408 & 409
      final e408 = SarvamException.fromHttpResponse(
        statusCode: 408,
        headers: {},
        rawBody: 'timeout',
      );
      expect(e408, isA<ServerException>());

      final e409 = SarvamException.fromHttpResponse(
        statusCode: 409,
        headers: {},
        rawBody: 'conflict',
      );
      expect(e409, isA<ServerException>());

      // Unknown status code fallback (e.g. 418 I'm a teapot)
      final e418 = SarvamException.fromHttpResponse(
        statusCode: 418,
        headers: {},
        rawBody: 'not json',
      );
      expect(e418, isA<ServerException>());
      expect(e418.message, 'HTTP error 418');

      // Unhandled exceptions direct instantiations
      final streamEx = StreamException(
        message: 'stream err',
        requestId: 'req-1',
        cause: Exception('eof'),
      );
      expect(streamEx.message, 'stream err');
      expect(streamEx.requestId, 'req-1');

      final realtimeEx = RealtimeException(
        message: 'ws closed',
        closeCode: 1006,
        code: 'ws_err',
      );
      expect(realtimeEx.message, 'ws closed');
      expect(realtimeEx.closeCode, 1006);
      expect(realtimeEx.code, 'ws_err');

      final decodingEx = DecodingException(
        message: 'decode failed',
        rawBody: '{malformed}',
      );
      expect(decodingEx.message, 'decode failed');
      expect(decodingEx.rawBody, '{malformed}');
    });

    test('SarvamException.toString formatting with all optional properties', () {
      final fullException = ServerException(
        statusCode: 500,
        code: 'internal_error',
        requestId: 'req-999',
        message: 'Something broke',
        cause: Exception('socket closed'),
      );
      final str = fullException.toString();
      expect(str, contains('status: 500'));
      expect(str, contains('[code: internal_error]'));
      expect(str, contains('[request_id: req-999]'));
      expect(str, contains('caused by: Exception: socket closed'));

      const minimalException = ServerException(message: 'Bare error');
      expect(minimalException.toString(), 'ServerException: Bare error');
    });

    test('parseRetryAfter parsing logic with ISO date and x-ratelimit-reset', () {
      expect(parseRetryAfter({'retry-after-ms': '1500'}), 1500);
      expect(parseRetryAfter({'retry-after': '10'}), 10000);
      expect(parseRetryAfter({'retry-after': 'invalid'}), isNull);
      expect(parseRetryAfter({}), isNull);

      // ISO HTTP date string (future & past)
      final futureDate = DateTime.now().add(const Duration(seconds: 15)).toIso8601String();
      final parsedFuture = parseRetryAfter({'retry-after': futureDate});
      expect(parsedFuture, isNotNull);
      expect(parsedFuture!, greaterThan(0));

      final pastDate = DateTime.now().subtract(const Duration(seconds: 15)).toIso8601String();
      final parsedPast = parseRetryAfter({'retry-after': pastDate});
      expect(parsedPast, equals(0));

      // x-ratelimit-reset (future & past epoch seconds)
      final nowSec = DateTime.now().millisecondsSinceEpoch ~/ 1000;
      final parsedFutureReset = parseRetryAfter({'x-ratelimit-reset': '${nowSec + 30}'});
      expect(parsedFutureReset, isNotNull);
      expect(parsedFutureReset!, greaterThan(0));

      final parsedPastReset = parseRetryAfter({'x-ratelimit-reset': '${nowSec - 30}'});
      expect(parsedPastReset, equals(0));
    });
  });

  group('LoggingMiddleware Unit Tests', () {
    test('enabled = false passes through without logging', () async {
      final logger = TestLogger();
      final middleware = LoggingMiddleware(logger: logger, enabled: false);
      final request = HttpRequest(url: Uri.parse('https://api.sarvam.ai/test'), method: 'GET');

      final resp = await middleware.handle(request, (req) async => jsonResponse(data: {}));
      expect(resp.statusCode, 200);
      expect(logger.logs, isEmpty);
    });

    test('enabled = true sanitizes sensitive headers and logs timing and errors', () async {
      final logger = TestLogger();
      final middleware = LoggingMiddleware(logger: logger, enabled: true);

      final request = HttpRequest(
        url: Uri.parse('https://api.sarvam.ai/test'),
        method: 'POST',
        headers: {
          'api-subscription-key': 'secret-sub-key',
          'authorization': 'Bearer secret-bearer',
          'content-type': 'application/json',
        },
      );

      // Successful request
      await middleware.handle(request, (req) async => jsonResponse(data: {'ok': true}));
      expect(logger.logs.length, 2);
      expect(logger.logs[0], contains('[REDACTED]'));
      expect(logger.logs[0], isNot(contains('secret-sub-key')));
      expect(logger.logs[0], isNot(contains('secret-bearer')));
      expect(logger.logs[1], contains('<-- 200 POST'));

      // Failing request
      await expectLater(
        () => middleware.handle(request, (req) async => throw Exception('network down')),
        throwsA(isA<Exception>()),
      );
      expect(logger.logs.last, contains('<-- FAILED POST'));
      expect(logger.levels.last, 'ERROR');
    });
  });

  group('RetryMiddleware Unit Tests', () {
    test('retries on 500 for idempotent requests up to maxRetries', () async {
      final clock = MockClock(initialTime: DateTime.utc(2026, 1, 1));
      final middleware = RetryMiddleware(
        maxRetries: 2,
        baseBackoffMs: 10,
        maxBackoffMs: 20,
        clock: clock,
        random: Random(42),
      );

      var calls = 0;
      final request = HttpRequest(
        url: Uri.parse('https://api.sarvam.ai/idempotent'),
        method: 'GET',
        operationKind: OperationKind.idempotent,
      );

      final resp = await middleware.handle(request, (req) async {
        calls++;
        if (calls < 3) {
          return HttpResponse(
            statusCode: 500,
            headers: {},
            bodyBytes: Uint8List(0),
            stream: Stream.value(Uint8List(0)),
          );
        }
        return jsonResponse(data: {'success': true});
      });

      expect(resp.statusCode, 200);
      expect(calls, 3);
    });

    test('retries on ConnectionException and TimeoutException', () async {
      final clock = MockClock(initialTime: DateTime.utc(2026, 1, 1));
      final middleware = RetryMiddleware(
        maxRetries: 2,
        baseBackoffMs: 5,
        clock: clock,
        random: Random(42),
      );

      var connCalls = 0;
      final req1 = HttpRequest(
        url: Uri.parse('https://api.sarvam.ai/conn'),
        method: 'GET',
        operationKind: OperationKind.idempotent,
      );

      final resp1 = await middleware.handle(req1, (req) async {
        connCalls++;
        if (connCalls == 1) {
          throw const ConnectionException(message: 'Connection failed');
        }
        return jsonResponse(data: {'ok': true});
      });
      expect(resp1.statusCode, 200);
      expect(connCalls, 2);

      var timeoutCalls = 0;
      final req2 = HttpRequest(
        url: Uri.parse('https://api.sarvam.ai/timeout'),
        method: 'GET',
        operationKind: OperationKind.idempotent,
      );

      final resp2 = await middleware.handle(req2, (req) async {
        timeoutCalls++;
        if (timeoutCalls == 1) {
          throw const TimeoutException(message: 'Timeout');
        }
        return jsonResponse(data: {'ok': true});
      });
      expect(resp2.statusCode, 200);
      expect(timeoutCalls, 2);
    });

    test('jobCreate retries on 500 only with idempotency key', () async {
      final clock = MockClock(initialTime: DateTime.utc(2026, 1, 1));
      final middleware = RetryMiddleware(
        maxRetries: 1,
        baseBackoffMs: 5,
        clock: clock,
        random: Random(42),
      );

      // Without idempotency-key -> immediately throws ServerException
      var noKeyCalls = 0;
      final reqWithoutKey = HttpRequest(
        url: Uri.parse('https://api.sarvam.ai/jobs'),
        method: 'POST',
        operationKind: OperationKind.jobCreate,
      );

      await expectLater(
        () => middleware.handle(reqWithoutKey, (req) async {
          noKeyCalls++;
          return HttpResponse(statusCode: 500, headers: {}, bodyBytes: Uint8List(0), stream: Stream.value(Uint8List(0)));
        }),
        throwsA(isA<ServerException>()),
      );
      expect(noKeyCalls, 1);

      // With idempotency-key -> retries on 500
      var withKeyCalls = 0;
      final reqWithKey = HttpRequest(
        url: Uri.parse('https://api.sarvam.ai/jobs'),
        method: 'POST',
        headers: {'idempotency-key': 'job-key-123'},
        operationKind: OperationKind.jobCreate,
      );

      final resp = await middleware.handle(reqWithKey, (req) async {
        withKeyCalls++;
        if (withKeyCalls == 1) {
          return HttpResponse(statusCode: 500, headers: {}, bodyBytes: Uint8List(0), stream: Stream.value(Uint8List(0)));
        }
        return jsonResponse(data: {'job_id': '123'});
      });
      expect(resp.statusCode, 200);
      expect(withKeyCalls, 2);
    });

    test('multipartCompute retries 503 only when replayable', () async {
      final clock = MockClock(initialTime: DateTime.utc(2026, 1, 1));
      final middleware = RetryMiddleware(
        maxRetries: 1,
        baseBackoffMs: 5,
        clock: clock,
        random: Random(42),
      );

      // Replayable file (bytes) -> retries on 503
      var replayableCalls = 0;
      final reqReplayable = HttpRequest(
        url: Uri.parse('https://api.sarvam.ai/compute'),
        method: 'POST',
        files: [SarvamFileInput.fromBytes('f', Uint8List(4))],
        operationKind: OperationKind.multipartCompute,
      );

      final resp = await middleware.handle(reqReplayable, (req) async {
        replayableCalls++;
        if (replayableCalls == 1) {
          return HttpResponse(statusCode: 503, headers: {}, bodyBytes: Uint8List(0), stream: Stream.value(Uint8List(0)));
        }
        return jsonResponse(data: {'done': true});
      });
      expect(resp.statusCode, 200);
      expect(replayableCalls, 2);

      // Non-replayable file (stream) -> does NOT retry on 503
      var nonReplayableCalls = 0;
      final reqNonReplayable = HttpRequest(
        url: Uri.parse('https://api.sarvam.ai/compute'),
        method: 'POST',
        files: [
          SarvamFileInput.fromStream('f', () => Stream.value([1, 2]), 2, isReplayable: false),
        ],
        operationKind: OperationKind.multipartCompute,
      );

      await expectLater(
        () => middleware.handle(reqNonReplayable, (req) async {
          nonReplayableCalls++;
          return HttpResponse(statusCode: 503, headers: {}, bodyBytes: Uint8List(0), stream: Stream.value(Uint8List(0)));
        }),
        throwsA(isA<ServerException>()),
      );
      expect(nonReplayableCalls, 1);

      // 429 with non-replayable file does NOT retry
      var nonReplayable429Calls = 0;
      await expectLater(
        () => middleware.handle(reqNonReplayable, (req) async {
          nonReplayable429Calls++;
          return HttpResponse(statusCode: 429, headers: {}, bodyBytes: Uint8List(0), stream: Stream.value(Uint8List(0)));
        }),
        throwsA(isA<RateLimitException>()),
      );
      expect(nonReplayable429Calls, 1);

      // 503 with rate_limit_exceeded_error body retries when replayable
      var rateLimit503Calls = 0;
      final respRateLimit = await middleware.handle(reqReplayable, (req) async {
        rateLimit503Calls++;
        if (rateLimit503Calls == 1) {
          return HttpResponse(
            statusCode: 503,
            headers: {},
            bodyBytes: utf8.encode(jsonEncode({'error': {'code': 'rate_limit_exceeded_error'}})),
            stream: Stream.value(Uint8List(0)),
          );
        }
        return jsonResponse(data: {'rate_limit_recovered': true});
      });
      expect(respRateLimit.statusCode, 200);
      expect(rateLimit503Calls, 2);

      // 503 with rate_limit_exceeded_error directly under code
      var rateLimitDirectCalls = 0;
      final respDirect = await middleware.handle(reqReplayable, (req) async {
        rateLimitDirectCalls++;
        if (rateLimitDirectCalls == 1) {
          return HttpResponse(
            statusCode: 503,
            headers: {},
            bodyBytes: utf8.encode(jsonEncode({'code': 'rate_limit_exceeded_error'})),
            stream: Stream.value(Uint8List(0)),
          );
        }
        return jsonResponse(data: {'direct_recovered': true});
      });
      expect(respDirect.statusCode, 200);
      expect(rateLimitDirectCalls, 2);

      // 503 with rate limit body but non-replayable files does NOT retry
      var nonReplayable503RateLimitCalls = 0;
      await expectLater(
        () => middleware.handle(reqNonReplayable, (req) async {
          nonReplayable503RateLimitCalls++;
          return HttpResponse(
            statusCode: 503,
            headers: {},
            bodyBytes: utf8.encode(jsonEncode({'error': {'code': 'rate_limit_exceeded_error'}})),
            stream: Stream.value(Uint8List(0)),
          );
        }),
        throwsA(isA<RateLimitException>()),
      );
      expect(nonReplayable503RateLimitCalls, 1);
    });

    test('network exception retry eligibility for different OperationKinds', () async {
      final clock = MockClock(initialTime: DateTime.utc(2026, 1, 1));
      final middleware = RetryMiddleware(
        maxRetries: 1,
        baseBackoffMs: 5,
        clock: clock,
        random: Random(42),
      );

      // statelessPost can retry network exception
      var statelessCalls = 0;
      final reqStateless = HttpRequest(
        url: Uri.parse('https://api.sarvam.ai/stateless'),
        method: 'POST',
        operationKind: OperationKind.statelessPost,
      );
      final respStateless = await middleware.handle(reqStateless, (req) async {
        statelessCalls++;
        if (statelessCalls == 1) {
          throw const ConnectionException(message: 'conn reset');
        }
        return jsonResponse(data: {'stateless_ok': true});
      });
      expect(respStateless.statusCode, 200);
      expect(statelessCalls, 2);

      // multipartCompute with non-replayable file cannot retry network exception
      var multipartCalls = 0;
      final reqMultipartNonReplayable = HttpRequest(
        url: Uri.parse('https://api.sarvam.ai/multipart'),
        method: 'POST',
        files: [
          SarvamFileInput.fromStream('f', () => Stream.value([1]), 1, isReplayable: false),
        ],
        operationKind: OperationKind.multipartCompute,
      );
      await expectLater(
        () => middleware.handle(reqMultipartNonReplayable, (req) async {
          multipartCalls++;
          throw const ConnectionException(message: 'conn broken');
        }),
        throwsA(isA<ConnectionException>()),
      );
      expect(multipartCalls, 1);

      // jobCreate cannot retry network exception without idempotency
      var jobCreateCalls = 0;
      final reqJobCreate = HttpRequest(
        url: Uri.parse('https://api.sarvam.ai/job-create'),
        method: 'POST',
        operationKind: OperationKind.jobCreate,
      );
      await expectLater(
        () => middleware.handle(reqJobCreate, (req) async {
          jobCreateCalls++;
          throw const ConnectionException(message: 'conn dropped');
        }),
        throwsA(isA<ConnectionException>()),
      );
      expect(jobCreateCalls, 1);
    });
  });

  group('AuthProvider Unit Tests', () {
    test('ProxyAuth provides credentials from headersProvider and invalidates cleanly', () async {
      final auth = ProxyAuth(headersProvider: () => {'x-custom-auth': 'token-xyz'});
      final creds = await auth.getCredentials();
      expect(creds, isA<CustomHeaders>());
      expect((creds as CustomHeaders).headers['x-custom-auth'], 'token-xyz');

      // Invalidate should not throw
      auth.invalidate();
    });

    test('ApiKeyAuth invalidates and re-provides credentials', () async {
      final auth = ApiKeyAuth('api-key-test');
      final creds = await auth.getCredentials();
      expect(creds, isA<SubscriptionKey>());
      expect((creds as SubscriptionKey).key, 'api-key-test');
      auth.invalidate();
    });
  });

  group('SseTransformer and SseEvent Unit Tests', () {
    test('SseTransformer parses event, id, retry, and multiline data and ignores comments', () async {
      const payload = '''
: keepalive ping
id: event-101
event: status_update
retry: 2500
data: line 1
data: line 2

: comment 2
data: single line

''';

      final byteStream = Stream<List<int>>.value(utf8.encode(payload));
      const transformer = SseTransformer();
      final events = await transformer.bind(byteStream).toList();

      expect(events.length, 2);
      expect(events[0].id, 'event-101');
      expect(events[0].event, 'status_update');
      expect(events[0].retry, 2500);
      expect(events[0].data, 'line 1\nline 2');
      expect(events[0].toString(), contains('event-101'));

      expect(events[1].data, 'single line');
    });
  });

  group('JobPoller and CancellationToken Unit Tests', () {
    test('CancellationToken state and cancel()', () {
      final token = CancellationToken();
      expect(token.isCancelled, isFalse);
      token.cancel();
      expect(token.isCancelled, isTrue);
    });

    test('JobCancelledException toString', () {
      const ex = JobCancelledException('operation was stopped');
      expect(ex.toString(), 'JobCancelledException: operation was stopped');
    });

    test('JobPoller cancels via isCancelled callback', () async {
      const poller = JobPoller();
      var cancelled = false;

      final future = poller.waitUntilComplete<String>(
        pollFn: () async => 'running',
        isComplete: (s) => s == 'done',
        isCancelled: () => cancelled,
        pollInterval: const Duration(milliseconds: 10),
      );

      cancelled = true;
      await expectLater(
        future,
        throwsA(isA<JobCancelledException>()),
      );
    });

    test('JobPoller handles failure without failureMessage callback', () async {
      const poller = JobPoller();

      await expectLater(
        () => poller.waitUntilComplete<String>(
          pollFn: () async => 'failed_state',
          isComplete: (s) => s == 'completed',
          isFailed: (s) => s == 'failed_state',
          failureMessage: null,
          pollInterval: const Duration(milliseconds: 10),
        ),
        throwsA(
          isA<ServerException>().having(
            (e) => e.message,
            'message',
            contains('Job failed with status: failed_state'),
          ),
        ),
      );
    });

    test('JobPoller times out after timeout duration', () async {
      final clock = MockClock(initialTime: DateTime.utc(2026, 1, 1));
      final poller = JobPoller(clock: clock);

      final future = poller.waitUntilComplete<String>(
        pollFn: () async {
          clock.advance(const Duration(seconds: 10));
          return 'still_running';
        },
        isComplete: (s) => s == 'completed',
        timeout: const Duration(seconds: 5),
        pollInterval: const Duration(seconds: 1),
      );

      await expectLater(
        future,
        throwsA(isA<TimeoutException>().having((e) => e.phase, 'phase', TimeoutPhase.total)),
      );
    });
  });
}
