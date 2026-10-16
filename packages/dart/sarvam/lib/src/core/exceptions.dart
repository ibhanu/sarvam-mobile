import 'dart:convert';

/// Phase in which a network timeout occurred.
enum TimeoutPhase {
  connect,
  read,
  total,
}

/// Sealed root exception class for all errors emitted by the Sarvam SDK.
sealed class SarvamException implements Exception {
  final String message;
  final int? statusCode;
  final String? code;
  final String? requestId;
  final Object? cause;

  const SarvamException({
    required this.message,
    this.statusCode,
    this.code,
    this.requestId,
    this.cause,
  });

  /// Factory creating the canonical [SarvamException] subtype from an HTTP response.
  factory SarvamException.fromHttpResponse({
    required int statusCode,
    required Map<String, String> headers,
    required String rawBody,
  }) {
    String? code;
    String? message;
    String? requestId = _findHeader(headers, 'x-request-id') ??
        _findHeader(headers, 'x-ms-request-id') ??
        _findHeader(headers, 'request-id');

    if (rawBody.trim().isNotEmpty) {
      try {
        final decoded = jsonDecode(rawBody);
        if (decoded is Map<String, dynamic>) {
          if (decoded['error'] is Map<String, dynamic>) {
            final err = decoded['error'] as Map<String, dynamic>;
            code = err['code']?.toString();
            message = err['message']?.toString();
            requestId = err['request_id']?.toString() ?? requestId;
          } else {
            code = decoded['code']?.toString();
            message =
                decoded['message']?.toString() ?? decoded['error']?.toString();
            requestId = decoded['request_id']?.toString() ?? requestId;
          }
        }
      } catch (_) {
        // Fall back to rawBody if not JSON.
      }
    }

    message ??= 'HTTP error $statusCode';

    if (statusCode == 401) {
      return AuthenticationException(
        statusCode: statusCode,
        code: code,
        requestId: requestId,
        message: message,
      );
    }

    if (statusCode == 403) {
      if (code == 'invalid_api_key_error') {
        return AuthenticationException(
          statusCode: statusCode,
          code: code,
          requestId: requestId,
          message: message,
        );
      }
      return PermissionDeniedException(
        statusCode: statusCode,
        code: code,
        requestId: requestId,
        message: message,
      );
    }

    if (statusCode == 400) {
      return BadRequestException(
        statusCode: statusCode,
        code: code,
        requestId: requestId,
        message: message,
        rawBody: rawBody,
      );
    }

    if (statusCode == 404) {
      return NotFoundException(
        statusCode: statusCode,
        code: code,
        requestId: requestId,
        message: message,
      );
    }

    if (statusCode == 413) {
      return PayloadTooLargeException(
        statusCode: statusCode,
        code: code,
        requestId: requestId,
        message: message,
      );
    }

    if (statusCode == 422) {
      return UnprocessableEntityException(
        statusCode: statusCode,
        code: code,
        requestId: requestId,
        message: message,
        rawBody: rawBody,
      );
    }

    if (statusCode == 429 ||
        (statusCode == 503 && code == 'rate_limit_exceeded_error')) {
      final retryAfterMs = parseRetryAfter(headers);
      return RateLimitException(
        statusCode: statusCode,
        code: code,
        requestId: requestId,
        message: message,
        retryAfterMs: retryAfterMs,
      );
    }

    if (statusCode >= 500 || statusCode == 408 || statusCode == 409) {
      return ServerException(
        statusCode: statusCode,
        code: code,
        requestId: requestId,
        message: message,
      );
    }

    return ServerException(
      statusCode: statusCode,
      code: code,
      requestId: requestId,
      message: message,
    );
  }

  @override
  String toString() {
    final sb = StringBuffer('$runtimeType: $message');
    if (statusCode != null) sb.write(' (status: $statusCode)');
    if (code != null) sb.write(' [code: $code]');
    if (requestId != null) sb.write(' [request_id: $requestId]');
    if (cause != null) sb.write(' caused by: $cause');
    return sb.toString();
  }
}

/// Helper to parse retry after duration in milliseconds from response headers.
int? parseRetryAfter(Map<String, String> headers) {
  // 1. retry-after-ms: integer milliseconds.
  final retryAfterMs = _findHeader(headers, 'retry-after-ms');
  if (retryAfterMs != null) {
    final parsed = int.tryParse(retryAfterMs.trim());
    if (parsed != null && parsed >= 0) return parsed;
  }

  // 2. Retry-After: integer seconds or HTTP date.
  final retryAfter = _findHeader(headers, 'retry-after');
  if (retryAfter != null) {
    final seconds = int.tryParse(retryAfter.trim());
    if (seconds != null && seconds >= 0) {
      return seconds * 1000;
    }
    final httpDate = DateTime.tryParse(retryAfter.trim());
    if (httpDate != null) {
      final deltaMs = httpDate.difference(DateTime.now()).inMilliseconds;
      return deltaMs > 0 ? deltaMs : 0;
    }
  }

  // 3. X-RateLimit-Reset: Unix epoch seconds delta.
  final resetEpoch = _findHeader(headers, 'x-ratelimit-reset');
  if (resetEpoch != null) {
    final resetSec = int.tryParse(resetEpoch.trim());
    if (resetSec != null) {
      final nowSec = DateTime.now().millisecondsSinceEpoch ~/ 1000;
      final deltaSec = resetSec - nowSec;
      return deltaSec > 0 ? deltaSec * 1000 : 0;
    }
  }

  return null;
}

String? _findHeader(Map<String, String> headers, String target) {
  final lower = target.toLowerCase();
  for (final entry in headers.entries) {
    if (entry.key.toLowerCase() == lower) {
      return entry.value;
    }
  }
  return null;
}

/// Thrown when authentication fails (HTTP 401 or HTTP 403 with code `invalid_api_key_error`).
final class AuthenticationException extends SarvamException {
  const AuthenticationException({
    required super.message,
    super.statusCode,
    super.code,
    super.requestId,
    super.cause,
  });
}

/// Thrown when access is forbidden for reasons other than an invalid API key
/// (e.g., tier locked, feature disabled).
final class PermissionDeniedException extends SarvamException {
  const PermissionDeniedException({
    required super.message,
    super.statusCode,
    super.code,
    super.requestId,
    super.cause,
  });
}

/// Thrown when the server rejects a request due to invalid client input (HTTP 400).
final class BadRequestException extends SarvamException {
  final String? rawBody;

  const BadRequestException({
    required super.message,
    super.statusCode,
    super.code,
    super.requestId,
    this.rawBody,
    super.cause,
  });
}

/// Thrown when a requested resource does not exist (HTTP 404).
final class NotFoundException extends SarvamException {
  const NotFoundException({
    required super.message,
    super.statusCode,
    super.code,
    super.requestId,
    super.cause,
  });
}

/// Thrown when the request payload exceeds server limits (HTTP 413).
final class PayloadTooLargeException extends SarvamException {
  const PayloadTooLargeException({
    required super.message,
    super.statusCode,
    super.code,
    super.requestId,
    super.cause,
  });
}

/// Thrown when request parameters fail server validation (HTTP 422).
final class UnprocessableEntityException extends SarvamException {
  final String? rawBody;

  const UnprocessableEntityException({
    required super.message,
    super.statusCode,
    super.code,
    super.requestId,
    this.rawBody,
    super.cause,
  });
}

/// Thrown when rate limits are exceeded (HTTP 429 or HTTP 503 `rate_limit_exceeded_error`).
final class RateLimitException extends SarvamException {
  final int? retryAfterMs;

  const RateLimitException({
    required super.message,
    this.retryAfterMs,
    super.statusCode,
    super.code,
    super.requestId,
    super.cause,
  });
}

/// Thrown when an internal server error occurs (HTTP 500, 502, 503, 504, 408, 409).
final class ServerException extends SarvamException {
  const ServerException({
    required super.message,
    super.statusCode,
    super.code,
    super.requestId,
    super.cause,
  });
}

/// Thrown when a low-level network failure occurs (DNS resolution failure, TLS error, socket reset).
final class ConnectionException extends SarvamException {
  const ConnectionException({
    required super.message,
    super.cause,
  });
}

/// Thrown when an operation exceeds its configured timeout.
final class TimeoutException extends SarvamException {
  final TimeoutPhase phase;

  const TimeoutException({
    required super.message,
    this.phase = TimeoutPhase.total,
    super.cause,
  });
}

/// Thrown when an error occurs during an active stream (premature EOF, malformed chunk).
final class StreamException extends SarvamException {
  const StreamException({
    required super.message,
    super.requestId,
    super.cause,
  });
}

/// Thrown when a WebSocket error occurs or the connection closes abnormally.
final class RealtimeException extends SarvamException {
  final int? closeCode;

  const RealtimeException({
    required super.message,
    this.closeCode,
    super.code,
    super.cause,
  });
}

/// Thrown when JSON deserialization of a server response fails.
final class DecodingException extends SarvamException {
  final String? rawBody;

  const DecodingException({
    required super.message,
    this.rawBody,
    super.cause,
  });
}
