import 'dart:convert';
import 'dart:math';

import 'package:sarvam/src/generated/sarvam_spec_generated.dart';
import '../clock.dart';
import '../exceptions.dart';
import '../transport.dart';
import 'middleware.dart';

/// Middleware implementing network resilience, safe backoff retry, and operation retry classifications.
class RetryMiddleware implements Middleware {
  final int maxRetries;
  final int baseBackoffMs;
  final int maxBackoffMs;
  final Clock clock;
  final Random random;

  RetryMiddleware({
    this.maxRetries = 2,
    this.baseBackoffMs = 500,
    this.maxBackoffMs = 8000,
    Clock? clock,
    Random? random,
  })  : clock = clock ?? const SystemClock(),
        random = random ?? Random();

  @override
  Future<HttpResponse> handle(HttpRequest request, HttpHandler next) async {
    var attempt = 0;

    while (true) {
      try {
        final response = await next(request);

        final hasIdempotencyKey = _hasIdempotencyKey(request.headers);
        final isRetryable = _isRetryableStatus(
          response.statusCode,
          response.body,
          request.operationKind,
          hasIdempotencyKey: hasIdempotencyKey,
          hasNonReplayableFiles: request.hasNonReplayableFiles,
        );

        if (isRetryable && attempt < maxRetries) {
          final retryAfterMs = parseRetryAfter(response.headers);
          await _sleep(attempt, retryAfterMs);
          attempt++;
          continue;
        }

        // If response is an error (status >= 400), throw canonical SarvamException.
        if (response.statusCode >= 400) {
          throw SarvamException.fromHttpResponse(
            statusCode: response.statusCode,
            headers: response.headers,
            rawBody: response.body,
          );
        }

        return response;
      } on ConnectionException {
        if (attempt < maxRetries &&
            _canRetryNetworkException(
              request.operationKind,
              hasNonReplayableFiles: request.hasNonReplayableFiles,
            )) {
          await _sleep(attempt, null);
          attempt++;
          continue;
        }
        rethrow;
      } on TimeoutException {
        if (attempt < maxRetries &&
            _canRetryNetworkException(
              request.operationKind,
              hasNonReplayableFiles: request.hasNonReplayableFiles,
            )) {
          await _sleep(attempt, null);
          attempt++;
          continue;
        }
        rethrow;
      }
    }
  }

  bool _hasIdempotencyKey(Map<String, String> headers) {
    for (final entry in headers.entries) {
      if (entry.key.toLowerCase() == 'idempotency-key' &&
          entry.value.trim().isNotEmpty) {
        return true;
      }
    }
    return false;
  }

  bool _isRateLimitError(String body) {
    try {
      final decoded = jsonDecode(body);
      if (decoded is Map<String, dynamic>) {
        final err = decoded['error'];
        if (err is Map<String, dynamic> &&
            err['code'] == 'rate_limit_exceeded_error') {
          return true;
        }
        if (decoded['code'] == 'rate_limit_exceeded_error') {
          return true;
        }
      }
    } catch (_) {}
    return false;
  }

  bool _isRetryableStatus(
    int statusCode,
    String body,
    OperationKind kind, {
    required bool hasIdempotencyKey,
    required bool hasNonReplayableFiles,
  }) {
    if (statusCode == 429) {
      if (kind == OperationKind.multipartCompute && hasNonReplayableFiles) {
        return false;
      }
      return true;
    }

    if (statusCode == 503 && _isRateLimitError(body)) {
      if (kind == OperationKind.multipartCompute && hasNonReplayableFiles) {
        return false;
      }
      return true;
    }

    if (kind == OperationKind.jobCreate) {
      if (hasIdempotencyKey) {
        return statusCode == 500 ||
            statusCode == 502 ||
            statusCode == 503 ||
            statusCode == 504 ||
            statusCode == 408 ||
            statusCode == 409;
      }
      return false;
    }

    if (kind == OperationKind.multipartCompute) {
      if (hasNonReplayableFiles) return false;
      return statusCode == 503;
    }

    if (kind == OperationKind.idempotent ||
        kind == OperationKind.statelessPost) {
      return statusCode == 500 ||
          statusCode == 502 ||
          statusCode == 503 ||
          statusCode == 504 ||
          statusCode == 408 ||
          statusCode == 409;
    }

    return false;
  }

  bool _canRetryNetworkException(
    OperationKind kind, {
    required bool hasNonReplayableFiles,
  }) {
    if (kind == OperationKind.idempotent ||
        kind == OperationKind.statelessPost) {
      return true;
    }
    if (kind == OperationKind.multipartCompute && !hasNonReplayableFiles) {
      return true;
    }
    return false;
  }

  Future<void> _sleep(int attempt, int? explicitDelayMs) async {
    final int delayMs;
    if (explicitDelayMs != null && explicitDelayMs >= 0) {
      delayMs = explicitDelayMs;
    } else {
      final ceilingMs = min(maxBackoffMs, baseBackoffMs * (1 << attempt));
      delayMs = random.nextInt(ceilingMs + 1);
    }

    await clock.sleep(Duration(milliseconds: delayMs));
  }
}
