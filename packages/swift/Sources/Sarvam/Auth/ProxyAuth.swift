import Foundation

/// Proxy authentication provider for Backend-For-Frontend (BFF) architectures.
public final class ProxyAuth: AuthProvider, Sendable {
    public let proxyBaseUrl: String
    public let headersProvider: (@Sendable () async throws -> [String: String])?

    public init(
        proxyBaseUrl: String,
        headersProvider: (@Sendable () async throws -> [String: String])? = nil
    ) {
        self.proxyBaseUrl = proxyBaseUrl
        self.headersProvider = headersProvider
    }

    public func getCredentials() async throws -> SarvamCredentials {
        if let provider = headersProvider {
            let headers = try await provider()
            return .customHeaders(headers)
        }
        return .customHeaders([:])
    }

    public func invalidate() async {
        // No-op for proxy headers unless handled in caller's headersProvider
    }
}
