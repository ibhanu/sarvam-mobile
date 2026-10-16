import Foundation

/// HTTP methods supported by the SDK.
public enum HTTPMethod: String, Sendable, Codable, Equatable {
    case get = "GET"
    case post = "POST"
    case put = "PUT"
    case delete = "DELETE"
    case patch = "PATCH"
    case head = "HEAD"
}

/// Request-scoped options passed to individual SDK method calls.
public struct RequestOptions: Sendable, Equatable {
    /// Custom headers to merge into the outgoing request.
    public var headers: [String: String]

    /// Per-request timeout override in seconds.
    public var timeoutInterval: TimeInterval?

    /// Idempotency key for mutation operations.
    public var idempotencyKey: String?

    /// Max retry attempts override.
    public var maxRetries: Int?

    public init(
        headers: [String: String] = [:],
        timeoutInterval: TimeInterval? = nil,
        idempotencyKey: String? = nil,
        maxRetries: Int? = nil
    ) {
        self.headers = headers
        self.timeoutInterval = timeoutInterval
        self.idempotencyKey = idempotencyKey
        self.maxRetries = maxRetries
    }
}

/// Internal normalized HTTP request representation.
public struct HTTPRequest: Sendable {
    public var method: HTTPMethod
    public var url: URL
    public var headers: [String: String]
    public var body: Data?
    public var operationKind: OperationKind
    public var timeoutInterval: TimeInterval?
    public var idempotencyKey: String?
    public var isReplayable: Bool

    public init(
        method: HTTPMethod,
        url: URL,
        headers: [String: String] = [:],
        body: Data? = nil,
        operationKind: OperationKind = .statelessPost,
        timeoutInterval: TimeInterval? = nil,
        idempotencyKey: String? = nil,
        isReplayable: Bool = true
    ) {
        self.method = method
        self.url = url
        self.headers = headers
        self.body = body
        self.operationKind = operationKind
        self.timeoutInterval = timeoutInterval
        self.idempotencyKey = idempotencyKey
        self.isReplayable = isReplayable
    }
}

/// Normalized HTTP response.
public struct HTTPResponse: Sendable {
    public let statusCode: Int
    public let headers: [String: String]
    public let body: Data

    public init(statusCode: Int, headers: [String: String], body: Data) {
        self.statusCode = statusCode
        self.headers = headers
        self.body = body
    }

    /// Header value lookup (case-insensitive).
    public func header(_ name: String) -> String? {
        let lower = name.lowercased()
        for (k, v) in headers where k.lowercased() == lower {
            return v
        }
        return nil
    }
}
