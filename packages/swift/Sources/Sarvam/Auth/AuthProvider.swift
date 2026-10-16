import Foundation

/// Protocol governing authentication credentials lifecycle for the Sarvam SDK.
public protocol AuthProvider: Sendable {
    /// Obtains valid credentials for authenticating an outgoing request.
    func getCredentials() async throws -> SarvamCredentials

    /// Invalidates cached credentials upon encountering authentication failure (HTTP 401 or 403 invalid_api_key_error).
    func invalidate() async
}
