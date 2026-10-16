import '../transport.dart';
import 'middleware.dart';

/// Contract for structured logging in the SDK.
abstract interface class LoggerAdapter {
  void log(String message, {String level});
}

/// No-op logger used by default.
class NoOpLogger implements LoggerAdapter {
  const NoOpLogger();

  @override
  void log(String message, {String level = 'INFO'}) {}
}

/// Middleware logging requests and responses while redacting sensitive headers and payloads.
class LoggingMiddleware implements Middleware {
  final LoggerAdapter logger;
  final bool enabled;

  LoggingMiddleware({
    LoggerAdapter? logger,
    this.enabled = true,
  }) : logger = logger ?? const NoOpLogger();

  @override
  Future<HttpResponse> handle(HttpRequest request, HttpHandler next) async {
    if (!enabled) {
      return next(request);
    }

    final sanitizedHeaders = _sanitizeHeaders(request.headers);
    logger.log(
        '--> ${request.method} ${request.url} headers: $sanitizedHeaders',
        level: 'DEBUG');

    final stopwatch = Stopwatch()..start();
    try {
      final response = await next(request);
      stopwatch.stop();

      logger.log(
        '<-- ${response.statusCode} ${request.method} ${request.url} (${stopwatch.elapsedMilliseconds}ms)',
        level: 'DEBUG',
      );
      return response;
    } catch (e) {
      stopwatch.stop();
      logger.log(
        '<-- FAILED ${request.method} ${request.url} (${stopwatch.elapsedMilliseconds}ms): $e',
        level: 'ERROR',
      );
      rethrow;
    }
  }

  Map<String, String> _sanitizeHeaders(Map<String, String> headers) {
    final sanitized = <String, String>{};
    for (final entry in headers.entries) {
      final keyLower = entry.key.toLowerCase();
      if (keyLower == 'api-subscription-key' ||
          keyLower == 'authorization' ||
          keyLower == 'x-api-key') {
        sanitized[entry.key] = '[REDACTED]';
      } else {
        sanitized[entry.key] = entry.value;
      }
    }
    return sanitized;
  }
}
