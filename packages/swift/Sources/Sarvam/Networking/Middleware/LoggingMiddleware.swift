import Foundation

/// Log levels for SDK request/response logging.
public enum LogLevel: Int, Sendable, Comparable {
    case off = 0
    case error = 1
    case warn = 2
    case info = 3
    case debug = 4

    public static func < (lhs: LogLevel, rhs: LogLevel) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}

/// Logger adapter protocol allowing developers to route SDK logs to OSLog, print, or custom systems.
public protocol LoggerAdapter: Sendable {
    func log(level: LogLevel, message: String)
}

public struct PrintLogger: LoggerAdapter {
    public init() {}
    public func log(level: LogLevel, message: String) {
        print("[Sarvam][\(level)] \(message)")
    }
}

/// Structured logging middleware that redacts credentials and large binary payloads.
public final class LoggingMiddleware: Middleware, Sendable {
    public let level: LogLevel
    public let logger: LoggerAdapter

    public init(level: LogLevel = .off, logger: LoggerAdapter = PrintLogger()) {
        self.level = level
        self.logger = logger
    }

    public func process(
        request: HTTPRequest,
        next: @Sendable (HTTPRequest) async throws -> HTTPResponse
    ) async throws -> HTTPResponse {
        guard level >= .info else {
            return try await next(request)
        }

        let start = Date()
        let redactedHeaders = redactHeaders(request.headers)
        logger.log(level: .info, message: "-> \(request.method.rawValue) \(request.url.path) headers: \(redactedHeaders)")

        do {
            let response = try await next(request)
            let duration = Date().timeIntervalSince(start)
            logger.log(level: .info, message: "<- \(request.method.rawValue) \(request.url.path) [\(response.statusCode)] (\(String(format: "%.3f", duration))s)")
            return response
        } catch {
            let duration = Date().timeIntervalSince(start)
            logger.log(level: .error, message: "<! \(request.method.rawValue) \(request.url.path) FAILED after \(String(format: "%.3f", duration))s: \(error.localizedDescription)")
            throw error
        }
    }

    private func redactHeaders(_ headers: [String: String]) -> [String: String] {
        var result = headers
        for key in headers.keys {
            let lk = key.lowercased()
            if lk == "api-subscription-key" || lk == "authorization" {
                result[key] = "[REDACTED]"
            }
        }
        return result
    }
}
