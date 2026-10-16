import Foundation

/// Union of credentials emitted by an `AuthProvider`.
public enum SarvamCredentials: Sendable, Equatable {
    /// Static subscription key passed as `api-subscription-key` header (or subprotocol).
    case subscriptionKey(String)

    /// Ephemeral bearer token passed as `Authorization: Bearer <token>`.
    case bearerToken(token: String, expiresAtEpochMs: Int64? = nil)

    /// Custom headers passed when routing via Backend-For-Frontend (BFF) proxy.
    case customHeaders([String: String])
}
