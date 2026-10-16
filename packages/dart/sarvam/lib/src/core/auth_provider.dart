import 'dart:async';

import 'clock.dart';
import 'credentials.dart';

/// Contract for providing authentication credentials to HTTP requests and WebSockets.
abstract interface class AuthProvider {
  /// Retrieves valid credentials, refreshing if expired.
  Future<SarvamCredentials> getCredentials();

  /// Invalidates any internally cached credentials after an authentication failure.
  void invalidate();
}

/// Static API key authentication provider.
class ApiKeyAuth implements AuthProvider {
  final String apiKey;

  const ApiKeyAuth(this.apiKey);

  @override
  Future<SarvamCredentials> getCredentials() async => SubscriptionKey(apiKey);

  @override
  void invalidate() {
    // Static keys cannot be invalidated.
  }
}

/// Ephemeral authentication token returned by a custom token provider function.
class AuthToken {
  final String token;
  final int expiresAtEpochMs;

  const AuthToken({
    required this.token,
    required this.expiresAtEpochMs,
  });
}

/// Dynamic token authentication provider with in-memory caching,
/// single-flight deduplication, and proactive 60-second expiration buffer.
class TokenAuth implements AuthProvider {
  final Future<AuthToken> Function() tokenProvider;
  final Clock clock;

  AuthToken? _cachedToken;
  Future<AuthToken>? _inFlightRefresh;

  TokenAuth(
    this.tokenProvider, {
    Clock? clock,
  }) : clock = clock ?? const SystemClock();

  @override
  Future<SarvamCredentials> getCredentials() async {
    final nowMs = clock.now().millisecondsSinceEpoch;

    // Use cached token if valid and outside the 60s expiry window.
    if (_cachedToken != null &&
        nowMs < _cachedToken!.expiresAtEpochMs - 60000) {
      return BearerToken(
        _cachedToken!.token,
        expiresAtEpochMs: _cachedToken!.expiresAtEpochMs,
      );
    }

    // Single-flight deduplication for concurrent callers.
    _inFlightRefresh ??= _fetchToken();

    try {
      final token = await _inFlightRefresh!;
      return BearerToken(token.token, expiresAtEpochMs: token.expiresAtEpochMs);
    } finally {
      _inFlightRefresh = null;
    }
  }

  Future<AuthToken> _fetchToken() async {
    final token = await tokenProvider();
    _cachedToken = token;
    return token;
  }

  @override
  void invalidate() {
    _cachedToken = null;
    _inFlightRefresh = null;
  }
}

/// Custom headers authentication provider for Backend-For-Frontend (BFF) proxy setups.
class ProxyAuth implements AuthProvider {
  final FutureOr<Map<String, String>> Function() headersProvider;

  const ProxyAuth({required this.headersProvider});

  @override
  Future<SarvamCredentials> getCredentials() async {
    final headers = await headersProvider();
    return CustomHeaders(headers);
  }

  @override
  void invalidate() {
    // Proxy headers provider is queried dynamically.
  }
}
