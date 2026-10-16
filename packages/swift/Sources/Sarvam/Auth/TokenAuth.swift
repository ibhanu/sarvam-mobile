import Foundation

/// Ephemeral auth token container.
public struct AuthToken: Sendable, Equatable {
    public let token: String
    public let expiresAtEpochMs: Int64?

    public init(token: String, expiresAtEpochMs: Int64? = nil) {
        self.token = token
        self.expiresAtEpochMs = expiresAtEpochMs
    }
}

/// Actor-backed dynamic token auth provider with single-flight refresh and 60-second proactive buffer.
public actor TokenAuth: AuthProvider {
    public typealias TokenProvider = @Sendable () async throws -> AuthToken

    private let tokenProvider: TokenProvider
    private let clock: ClockProvider
    private let expiryBufferMs: Int64

    private var cachedToken: AuthToken?
    private var inFlightRefreshTask: Task<AuthToken, Error>?

    public init(
        tokenProvider: @escaping TokenProvider,
        clock: ClockProvider = SystemClockProvider(),
        expiryBufferMs: Int64 = 60_000
    ) {
        self.tokenProvider = tokenProvider
        self.clock = clock
        self.expiryBufferMs = expiryBufferMs
    }

    public func getCredentials() async throws -> SarvamCredentials {
        let now = clock.nowEpochMs()

        if let cached = cachedToken {
            if let expiresAt = cached.expiresAtEpochMs {
                if expiresAt - now > expiryBufferMs {
                    return .bearerToken(token: cached.token, expiresAtEpochMs: cached.expiresAtEpochMs)
                }
            } else {
                return .bearerToken(token: cached.token, expiresAtEpochMs: nil)
            }
        }

        // Single-flight deduplication: if refresh is in flight, await it.
        if let existingTask = inFlightRefreshTask {
            let token = try await existingTask.value
            return .bearerToken(token: token.token, expiresAtEpochMs: token.expiresAtEpochMs)
        }

        let provider = self.tokenProvider
        let task = Task<AuthToken, Error> {
            try await provider()
        }
        self.inFlightRefreshTask = task

        do {
            let token = try await task.value
            self.cachedToken = token
            self.inFlightRefreshTask = nil
            return .bearerToken(token: token.token, expiresAtEpochMs: token.expiresAtEpochMs)
        } catch {
            self.inFlightRefreshTask = nil
            throw error
        }
    }

    public func invalidate() async {
        cachedToken = nil
    }
}
