import Foundation

/// Injects standardized RFC 7231 `User-Agent` and `X-Sarvam-SDK-Version` headers.
public final class UserAgentMiddleware: Middleware, Sendable {
    public let userAgentValue: String
    public let sdkVersionValue: String

    public init(
        sdkVersion: String = SarvamSpecMetadata.sdkVersion,
        specVersion: String = SarvamSpecMetadata.specVersion
    ) {
        self.sdkVersionValue = sdkVersion

        let osName: String
        let osVersion = ProcessInfo.processInfo.operatingSystemVersion
        let osVersionStr = "\(osVersion.majorVersion).\(osVersion.minorVersion)"

        #if os(iOS)
        osName = "ios/\(osVersionStr)"
        #elseif os(macOS)
        osName = "macos/\(osVersionStr)"
        #elseif os(watchOS)
        osName = "watchos/\(osVersionStr)"
        #elseif os(tvOS)
        osName = "tvos/\(osVersionStr)"
        #else
        osName = "apple"
        #endif

        self.userAgentValue = "sarvam-swift/\(sdkVersion) (spec/\(specVersion); \(osName); swift/6.0)"
    }

    public func process(
        request: HTTPRequest,
        next: @Sendable (HTTPRequest) async throws -> HTTPResponse
    ) async throws -> HTTPResponse {
        var modified = request
        if modified.headers["User-Agent"] == nil && modified.headers["user-agent"] == nil {
            modified.headers["User-Agent"] = userAgentValue
        }
        if modified.headers["X-Sarvam-SDK-Version"] == nil && modified.headers["x-sarvam-sdk-version"] == nil {
            modified.headers["X-Sarvam-SDK-Version"] = sdkVersionValue
        }
        return try await next(modified)
    }
}
