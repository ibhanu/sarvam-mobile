import Foundation

/// Static subscription key authentication provider.
///
/// Intended for local development, prototyping, or server-side usage.
/// Emits a one-time warning in mobile release builds reminding developers to use
/// `TokenAuth` or `ProxyAuth` in production.
public final class ApiKeyAuth: AuthProvider, Sendable {
    public let apiKey: String

    private static let hasWarned: ActorState = ActorState()

    private actor ActorState {
        var warned = false
        func warnOnce() {
            if !warned {
                warned = true
                #if !DEBUG
                print("[WARN] Sarvam SDK: ApiKeyAuth with static subscription key should not be embedded in production mobile binaries. Prefer TokenAuth or ProxyAuth.")
                #endif
            }
        }
    }

    public init(apiKey: String) {
        self.apiKey = apiKey
        Task {
            await Self.hasWarned.warnOnce()
        }
    }

    public func getCredentials() async throws -> SarvamCredentials {
        .subscriptionKey(apiKey)
    }

    public func invalidate() async {
        // No-op for static API key.
    }
}
