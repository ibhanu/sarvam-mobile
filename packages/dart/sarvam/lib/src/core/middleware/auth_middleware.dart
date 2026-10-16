import 'dart:convert';

import '../auth_provider.dart';
import '../transport.dart';
import 'middleware.dart';

/// Middleware managing credential injection, invalidation, and single-attempt retry on auth error.
class AuthMiddleware implements Middleware {
  final AuthProvider authProvider;

  AuthMiddleware(this.authProvider);

  @override
  Future<HttpResponse> handle(HttpRequest request, HttpHandler next) async {
    // 1. Resolve and apply credentials to request headers.
    final credentials = await authProvider.getCredentials();
    credentials.applyToHttpHeaders(request.headers);

    // 2. Execute request through inner pipeline.
    var response = await next(request);

    // 3. Check for 401 or 403 with invalid_api_key_error.
    if (_isAuthError(response)) {
      authProvider.invalidate();

      // Refetch credentials and retry at most once.
      final newCredentials = await authProvider.getCredentials();
      newCredentials.applyToHttpHeaders(request.headers);

      response = await next(request);
    }

    return response;
  }

  bool _isAuthError(HttpResponse response) {
    if (response.statusCode == 401) return true;
    if (response.statusCode == 403) {
      try {
        final decoded = jsonDecode(response.body);
        if (decoded is Map<String, dynamic>) {
          final err = decoded['error'];
          if (err is Map<String, dynamic> &&
              err['code'] == 'invalid_api_key_error') {
            return true;
          }
          if (decoded['code'] == 'invalid_api_key_error') {
            return true;
          }
        }
      } catch (_) {
        // If not JSON, cannot be verified as invalid_api_key_error.
      }
    }
    return false;
  }
}
