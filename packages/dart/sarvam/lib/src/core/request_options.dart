/// Per-request options allowing callers to customize headers, timeouts, and idempotency keys.
class RequestOptions {
  /// Custom HTTP headers to merge into the outgoing request.
  final Map<String, String>? headers;

  /// Custom timeout for this specific operation.
  final Duration? timeout;

  /// Optional idempotency key for safely retrying non-idempotent operations.
  final String? idempotencyKey;

  /// Optional query parameters.
  final Map<String, dynamic>? queryParams;

  const RequestOptions({
    this.headers,
    this.timeout,
    this.idempotencyKey,
    this.queryParams,
  });

  /// Copies this [RequestOptions] with optional replacement fields.
  RequestOptions copyWith({
    Map<String, String>? headers,
    Duration? timeout,
    String? idempotencyKey,
    Map<String, dynamic>? queryParams,
  }) {
    return RequestOptions(
      headers: headers ?? this.headers,
      timeout: timeout ?? this.timeout,
      idempotencyKey: idempotencyKey ?? this.idempotencyKey,
      queryParams: queryParams ?? this.queryParams,
    );
  }
}
