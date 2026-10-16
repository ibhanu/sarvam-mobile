/// Sealed union representing credentials produced by an [AuthProvider].
sealed class SarvamCredentials {
  const SarvamCredentials();

  /// Applies these credentials to an outgoing HTTP request headers map.
  void applyToHttpHeaders(Map<String, String> headers);

  /// Applies these credentials to WebSocket connection parameters.
  ///
  /// If [useSubprotocolAuth] is true, adds subprotocol tokens.
  /// If false, injects headers for native handshake.
  void applyToWebSocket({
    required Map<String, String> headers,
    required List<String> protocols,
    required bool useSubprotocolAuth,
  });
}

/// Static API key authentication (`api-subscription-key`).
final class SubscriptionKey extends SarvamCredentials {
  final String key;

  const SubscriptionKey(this.key);

  @override
  void applyToHttpHeaders(Map<String, String> headers) {
    headers['api-subscription-key'] = key;
  }

  @override
  void applyToWebSocket({
    required Map<String, String> headers,
    required List<String> protocols,
    required bool useSubprotocolAuth,
  }) {
    if (useSubprotocolAuth) {
      protocols.add('api-subscription-key.$key');
    } else {
      headers['Api-Subscription-Key'] = key;
    }
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is SubscriptionKey &&
          runtimeType == other.runtimeType &&
          key == other.key;

  @override
  int get hashCode => key.hashCode;

  @override
  String toString() => 'SubscriptionKey([REDACTED])';
}

/// Dynamic bearer token authentication (`Authorization: Bearer <token>`).
final class BearerToken extends SarvamCredentials {
  final String token;
  final int? expiresAtEpochMs;

  const BearerToken(this.token, {this.expiresAtEpochMs});

  @override
  void applyToHttpHeaders(Map<String, String> headers) {
    headers['Authorization'] = 'Bearer $token';
  }

  @override
  void applyToWebSocket({
    required Map<String, String> headers,
    required List<String> protocols,
    required bool useSubprotocolAuth,
  }) {
    if (useSubprotocolAuth) {
      protocols.add('bearer.$token');
    } else {
      headers['Authorization'] = 'Bearer $token';
    }
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is BearerToken &&
          runtimeType == other.runtimeType &&
          token == other.token &&
          expiresAtEpochMs == other.expiresAtEpochMs;

  @override
  int get hashCode => token.hashCode ^ expiresAtEpochMs.hashCode;

  @override
  String toString() => 'BearerToken([REDACTED], expiresAt: $expiresAtEpochMs)';
}

/// Custom headers authentication for proxy / Backend-For-Frontend deployments.
final class CustomHeaders extends SarvamCredentials {
  final Map<String, String> headers;

  const CustomHeaders(this.headers);

  @override
  void applyToHttpHeaders(Map<String, String> targetHeaders) {
    targetHeaders.addAll(headers);
  }

  @override
  void applyToWebSocket({
    required Map<String, String> headers,
    required List<String> protocols,
    required bool useSubprotocolAuth,
  }) {
    headers.addAll(this.headers);
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is CustomHeaders &&
          runtimeType == other.runtimeType &&
          headers.toString() == other.headers.toString();

  @override
  int get hashCode => headers.hashCode;

  @override
  String toString() => 'CustomHeaders(${headers.keys.toList()})';
}
