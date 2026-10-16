import Foundation

/// Injects authentication credentials and handles automatic single retry upon authentication failure.
public final class AuthMiddleware: Middleware, Sendable {
    public let authProvider: AuthProvider

    public init(authProvider: AuthProvider) {
        self.authProvider = authProvider
    }

    public func process(
        request: HTTPRequest,
        next: @Sendable (HTTPRequest) async throws -> HTTPResponse
    ) async throws -> HTTPResponse {
        let authenticatedRequest = try await applyCredentials(to: request)

        do {
            let response = try await next(authenticatedRequest)

            if isAuthFailure(response: response) {
                if authProvider is TokenAuth {
                    // Invalidate credentials and retry once with freshly fetched token
                    await authProvider.invalidate()
                    let retriedRequest = try await applyCredentials(to: request)
                    return try await next(retriedRequest)
                }
                return response
            }

            return response
        } catch let err as SarvamError {
            if case .authenticationError = err, authProvider is TokenAuth {
                await authProvider.invalidate()
                let retriedRequest = try await applyCredentials(to: request)
                return try await next(retriedRequest)
            }
            throw err
        }
    }

    private func applyCredentials(to request: HTTPRequest) async throws -> HTTPRequest {
        var modified = request
        let credentials = try await authProvider.getCredentials()

        switch credentials {
        case .subscriptionKey(let key):
            modified.headers["api-subscription-key"] = key
        case .bearerToken(let token, _):
            modified.headers["Authorization"] = "Bearer \(token)"
        case .customHeaders(let headers):
            for (k, v) in headers {
                modified.headers[k] = v
            }
        }

        return modified
    }

    private func isAuthFailure(response: HTTPResponse) -> Bool {
        if response.statusCode == 401 {
            return true
        }
        if response.statusCode == 403 {
            // Check for invalid_api_key_error
            if let json = try? JSONSerialization.jsonObject(with: response.body) as? [String: Any] {
                if let errObj = json["error"] as? [String: Any],
                   let code = errObj["code"] as? String,
                   code == "invalid_api_key_error" {
                    return true
                }
                if let code = json["code"] as? String, code == "invalid_api_key_error" {
                    return true
                }
            }
        }
        return false
    }
}
