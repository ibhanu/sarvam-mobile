import Foundation

/// Phases during which a request timeout can occur.
public enum TimeoutPhase: String, Sendable, Codable, Equatable {
    case connect
    case read
    case total
}

/// Canonical error hierarchy for Sarvam AI Mobile SDKs.
///
/// Implements the error contract defined in `api-contract.md` §4.
/// Native cancellation (`CancellationError`) is never wrapped.
public enum SarvamError: Error, Sendable, Equatable, CustomStringConvertible, LocalizedError {
    /// HTTP 401 or HTTP 403 with `code == "invalid_api_key_error"`.
    /// Retryable once via `TokenAuth` refresh; never via backoff.
    case authenticationError(statusCode: Int, code: String?, requestId: String?, message: String)

    /// HTTP 403 with `code != "invalid_api_key_error"`. Not retryable.
    case permissionDeniedError(statusCode: Int, code: String?, requestId: String?, message: String)

    /// HTTP 400 Bad Request. Not retryable.
    case badRequestError(statusCode: Int, code: String?, requestId: String?, message: String, rawBody: String? = nil)

    /// HTTP 404 Not Found. Not retryable.
    case notFoundError(statusCode: Int, code: String?, requestId: String?, message: String)

    /// HTTP 413 Payload Too Large. Not retryable.
    case payloadTooLargeError(statusCode: Int, code: String?, requestId: String?, message: String)

    /// HTTP 422 Unprocessable Entity. Not retryable.
    case unprocessableEntityError(statusCode: Int, code: String?, requestId: String?, message: String, rawBody: String? = nil)

    /// HTTP 429 or HTTP 503 with `code == "rate_limit_exceeded_error"`. Retryable.
    case rateLimitError(statusCode: Int, code: String?, requestId: String?, message: String, retryAfterMs: Int64? = nil)

    /// HTTP 500, 502, 503, 504, 408, 409. Retryable per OperationKind retry matrix.
    case serverError(statusCode: Int, code: String?, requestId: String?, message: String)

    /// DNS failure, TLS handshake error, socket reset. Retryable per OperationKind.
    case connectionError(message: String, cause: String? = nil)

    /// Connect, read, or total request timeout exceeded. Retryable if idempotent.
    case timeoutError(phase: TimeoutPhase, message: String)

    /// Unexpected EOF or malformed SSE frame mid-stream. Not retryable.
    case streamError(requestId: String?, message: String)

    /// WebSocket protocol error frame or abnormal socket closure.
    case realtimeError(closeCode: Int?, code: String?, message: String)

    /// Response JSON failed schema deserialization. Not retryable.
    case decodingError(rawBody: String?, message: String, cause: String? = nil)

    // MARK: - Properties

    public var statusCode: Int? {
        switch self {
        case let .authenticationError(status, _, _, _),
             let .permissionDeniedError(status, _, _, _),
             let .badRequestError(status, _, _, _, _),
             let .notFoundError(status, _, _, _),
             let .payloadTooLargeError(status, _, _, _),
             let .unprocessableEntityError(status, _, _, _, _),
             let .rateLimitError(status, _, _, _, _),
             let .serverError(status, _, _, _):
            return status
        default:
            return nil
        }
    }

    public var code: String? {
        switch self {
        case let .authenticationError(_, code, _, _),
             let .permissionDeniedError(_, code, _, _),
             let .badRequestError(_, code, _, _, _),
             let .notFoundError(_, code, _, _),
             let .payloadTooLargeError(_, code, _, _),
             let .unprocessableEntityError(_, code, _, _, _),
             let .rateLimitError(_, code, _, _, _),
             let .serverError(_, code, _, _),
             let .realtimeError(_, code, _):
            return code
        default:
            return nil
        }
    }

    public var requestId: String? {
        switch self {
        case let .authenticationError(_, _, reqId, _),
             let .permissionDeniedError(_, _, reqId, _),
             let .badRequestError(_, _, reqId, _, _),
             let .notFoundError(_, _, reqId, _),
             let .payloadTooLargeError(_, _, reqId, _),
             let .unprocessableEntityError(_, _, reqId, _, _),
             let .rateLimitError(_, _, reqId, _, _),
             let .serverError(_, _, reqId, _),
             let .streamError(reqId, _):
            return reqId
        default:
            return nil
        }
    }

    public var message: String {
        switch self {
        case let .authenticationError(_, _, _, msg),
             let .permissionDeniedError(_, _, _, msg),
             let .badRequestError(_, _, _, msg, _),
             let .notFoundError(_, _, _, msg),
             let .payloadTooLargeError(_, _, _, msg),
             let .unprocessableEntityError(_, _, _, msg, _),
             let .rateLimitError(_, _, _, msg, _),
             let .serverError(_, _, _, msg),
             let .connectionError(msg, _),
             let .timeoutError(_, msg),
             let .streamError(_, msg),
             let .realtimeError(_, _, msg),
             let .decodingError(_, msg, _):
            return msg
        }
    }

    public var rawBody: String? {
        switch self {
        case let .badRequestError(_, _, _, _, body):
            return body
        case let .unprocessableEntityError(_, _, _, _, body):
            return body
        case let .decodingError(body, _, _):
            return body
        default:
            return nil
        }
    }

    public var retryAfterMs: Int64? {
        if case let .rateLimitError(_, _, _, _, ms) = self {
            return ms
        }
        return nil
    }

    public var isRetryable: Bool {
        switch self {
        case .rateLimitError, .serverError, .connectionError, .timeoutError:
            return true
        default:
            return false
        }
    }

    public var description: String {
        var parts: [String] = []
        if let status = statusCode {
            parts.append("status: \(status)")
        }
        if let c = code {
            parts.append("code: \(c)")
        }
        if let reqId = requestId {
            parts.append("requestId: \(reqId)")
        }
        let details = parts.isEmpty ? "" : " (\(parts.joined(separator: ", ")))"
        return "SarvamError.\(caseName): \(message)\(details)"
    }

    public var errorDescription: String? {
        description
    }

    private var caseName: String {
        switch self {
        case .authenticationError: return "authenticationError"
        case .permissionDeniedError: return "permissionDeniedError"
        case .badRequestError: return "badRequestError"
        case .notFoundError: return "notFoundError"
        case .payloadTooLargeError: return "payloadTooLargeError"
        case .unprocessableEntityError: return "unprocessableEntityError"
        case .rateLimitError: return "rateLimitError"
        case .serverError: return "serverError"
        case .connectionError: return "connectionError"
        case .timeoutError: return "timeoutError"
        case .streamError: return "streamError"
        case .realtimeError: return "realtimeError"
        case .decodingError: return "decodingError"
        }
    }

    // MARK: - Factory from HTTP Response

    /// Parses an HTTP response into the corresponding canonical `SarvamError`.
    public static func from(statusCode: Int, headers: [String: String], body: Data?) -> SarvamError {
        var parsedCode: String?
        var parsedMessage: String?
        var parsedRequestId: String?
        var rawBodyString: String?

        if let body = body, !body.isEmpty {
            rawBodyString = String(data: body, encoding: .utf8)
            if let json = try? JSONSerialization.jsonObject(with: body) as? [String: Any] {
                if let errObj = json["error"] as? [String: Any] {
                    parsedCode = errObj["code"] as? String
                    parsedMessage = errObj["message"] as? String
                    parsedRequestId = errObj["request_id"] as? String
                } else {
                    parsedCode = json["code"] as? String
                    parsedMessage = (json["message"] as? String) ?? (json["detail"] as? String)
                    parsedRequestId = json["request_id"] as? String
                }
            }
        }

        // Header fallback for request ID:
        if parsedRequestId == nil {
            for (k, v) in headers {
                let lk = k.lowercased()
                if lk == "x-request-id" || lk == "x-ms-request-id" {
                    parsedRequestId = v
                    break
                }
            }
        }

        let message = parsedMessage ?? rawBodyString ?? "HTTP error \(statusCode)"

        // Parse retry-after if present:
        var retryAfterMs: Int64?
        for (k, v) in headers {
            let lk = k.lowercased()
            if lk == "retry-after-ms" {
                if let ms = Int64(v.trimmingCharacters(in: .whitespaces)) {
                    retryAfterMs = ms
                }
            } else if lk == "retry-after" && retryAfterMs == nil {
                let trimmed = v.trimmingCharacters(in: .whitespaces)
                if let seconds = Int64(trimmed) {
                    retryAfterMs = seconds * 1000
                }
            }
        }

        // §4 Canonical Error Mapping
        if statusCode == 401 || (statusCode == 403 && parsedCode == "invalid_api_key_error") {
            return .authenticationError(statusCode: statusCode, code: parsedCode, requestId: parsedRequestId, message: message)
        } else if statusCode == 403 {
            return .permissionDeniedError(statusCode: statusCode, code: parsedCode, requestId: parsedRequestId, message: message)
        } else if statusCode == 400 {
            return .badRequestError(statusCode: statusCode, code: parsedCode, requestId: parsedRequestId, message: message, rawBody: rawBodyString)
        } else if statusCode == 404 {
            return .notFoundError(statusCode: statusCode, code: parsedCode, requestId: parsedRequestId, message: message)
        } else if statusCode == 413 {
            return .payloadTooLargeError(statusCode: statusCode, code: parsedCode, requestId: parsedRequestId, message: message)
        } else if statusCode == 422 {
            return .unprocessableEntityError(statusCode: statusCode, code: parsedCode, requestId: parsedRequestId, message: message, rawBody: rawBodyString)
        } else if statusCode == 429 || (statusCode == 503 && parsedCode == "rate_limit_exceeded_error") {
            return .rateLimitError(statusCode: statusCode, code: parsedCode, requestId: parsedRequestId, message: message, retryAfterMs: retryAfterMs)
        } else if statusCode >= 500 || statusCode == 408 || statusCode == 409 {
            return .serverError(statusCode: statusCode, code: parsedCode, requestId: parsedRequestId, message: message)
        } else if statusCode >= 400 {
            return .badRequestError(statusCode: statusCode, code: parsedCode, requestId: parsedRequestId, message: message, rawBody: rawBodyString)
        } else {
            return .serverError(statusCode: statusCode, code: parsedCode, requestId: parsedRequestId, message: message)
        }
    }
}
