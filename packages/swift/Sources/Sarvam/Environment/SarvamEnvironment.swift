import Foundation

/// Sarvam AI multi-base-URL environment configuration.
///
/// Sarvam routes API calls across three distinct hosts (REST, Dubbing, WebSocket).
public struct SarvamEnvironment: Sendable, Equatable, Hashable {
    /// Base URL for REST and HTTP streaming endpoints.
    public let apiBaseUrl: String

    /// Base URL for Dubbing / Jobs endpoints.
    public let dubbingBaseUrl: String

    /// Base URL for WebSocket endpoints.
    public let wsBaseUrl: String

    /// Initializes a custom Sarvam environment.
    public init(apiBaseUrl: String, dubbingBaseUrl: String? = nil, wsBaseUrl: String? = nil) {
        let trimmedApi = apiBaseUrl.hasSuffix("/") ? String(apiBaseUrl.dropLast()) : apiBaseUrl
        self.apiBaseUrl = trimmedApi

        if let dubbing = dubbingBaseUrl {
            self.dubbingBaseUrl = dubbing.hasSuffix("/") ? String(dubbing.dropLast()) : dubbing
        } else {
            self.dubbingBaseUrl = "\(trimmedApi)/dubbing"
        }

        if let ws = wsBaseUrl {
            self.wsBaseUrl = ws.hasSuffix("/") ? String(ws.dropLast()) : ws
        } else {
            if trimmedApi.hasPrefix("https://") {
                self.wsBaseUrl = "wss://" + trimmedApi.dropFirst(8)
            } else if trimmedApi.hasPrefix("http://") {
                self.wsBaseUrl = "ws://" + trimmedApi.dropFirst(7)
            } else {
                self.wsBaseUrl = trimmedApi
            }
        }
    }

    /// Official Sarvam AI production environment.
    public static let production = SarvamEnvironment(
        apiBaseUrl: SarvamSpecMetadata.defaultApiBaseUrl,
        dubbingBaseUrl: SarvamSpecMetadata.defaultDubbingBaseUrl,
        wsBaseUrl: SarvamSpecMetadata.defaultWsBaseUrl
    )

    /// Factory for Backend-For-Frontend (BFF) proxy environments.
    public static func proxy(baseUrl: String) -> SarvamEnvironment {
        let trimmed = baseUrl.hasSuffix("/") ? String(baseUrl.dropLast()) : baseUrl
        let wsUrl: String
        if trimmed.hasPrefix("https://") {
            wsUrl = "wss://" + trimmed.dropFirst(8)
        } else if trimmed.hasPrefix("http://") {
            wsUrl = "ws://" + trimmed.dropFirst(7)
        } else {
            wsUrl = trimmed
        }
        return SarvamEnvironment(
            apiBaseUrl: trimmed,
            dubbingBaseUrl: "\(trimmed)/dubbing",
            wsBaseUrl: wsUrl
        )
    }
}
