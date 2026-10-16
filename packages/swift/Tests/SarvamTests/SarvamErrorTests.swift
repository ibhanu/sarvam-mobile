import Foundation
import Testing
@testable import Sarvam

@Suite("SarvamError Comprehensive Tests")
struct SarvamErrorTests {
    @Test("TimeoutPhase cases and Codable roundtrip")
    func testTimeoutPhase() throws {
        let phases: [TimeoutPhase] = [.connect, .read, .total]
        let encoder = JSONEncoder()
        let decoder = JSONDecoder()

        for phase in phases {
            let data = try encoder.encode(phase)
            let decoded = try decoder.decode(TimeoutPhase.self, from: data)
            #expect(decoded == phase)
            #expect(decoded.rawValue == phase.rawValue)
        }
    }

    @Test("All SarvamError cases property inspection")
    func testAllErrorCasesProperties() {
        let authErr = SarvamError.authenticationError(statusCode: 401, code: "invalid_key", requestId: "req-1", message: "Unauthorized")
        #expect(authErr.statusCode == 401)
        #expect(authErr.code == "invalid_key")
        #expect(authErr.requestId == "req-1")
        #expect(authErr.message == "Unauthorized")
        #expect(authErr.rawBody == nil)
        #expect(authErr.retryAfterMs == nil)
        #expect(!authErr.isRetryable)
        #expect(authErr.description.contains("authenticationError"))
        #expect(authErr.errorDescription == authErr.description)

        let permErr = SarvamError.permissionDeniedError(statusCode: 403, code: "forbidden", requestId: "req-2", message: "Forbidden")
        #expect(permErr.statusCode == 403)
        #expect(permErr.code == "forbidden")
        #expect(permErr.requestId == "req-2")
        #expect(permErr.message == "Forbidden")
        #expect(!permErr.isRetryable)
        #expect(permErr.description.contains("permissionDeniedError"))

        let badReq = SarvamError.badRequestError(statusCode: 400, code: "bad_req", requestId: "req-3", message: "Bad Request", rawBody: "{\"err\":\"detail\"}")
        #expect(badReq.statusCode == 400)
        #expect(badReq.code == "bad_req")
        #expect(badReq.requestId == "req-3")
        #expect(badReq.message == "Bad Request")
        #expect(badReq.rawBody == "{\"err\":\"detail\"}")
        #expect(!badReq.isRetryable)
        #expect(badReq.description.contains("badRequestError"))

        let notFound = SarvamError.notFoundError(statusCode: 404, code: "not_found", requestId: "req-4", message: "Not Found")
        #expect(notFound.statusCode == 404)
        #expect(notFound.code == "not_found")
        #expect(notFound.requestId == "req-4")
        #expect(notFound.message == "Not Found")
        #expect(!notFound.isRetryable)
        #expect(notFound.description.contains("notFoundError"))

        let payloadTooLarge = SarvamError.payloadTooLargeError(statusCode: 413, code: "too_large", requestId: "req-5", message: "Payload Too Large")
        #expect(payloadTooLarge.statusCode == 413)
        #expect(payloadTooLarge.code == "too_large")
        #expect(payloadTooLarge.requestId == "req-5")
        #expect(payloadTooLarge.message == "Payload Too Large")
        #expect(!payloadTooLarge.isRetryable)
        #expect(payloadTooLarge.description.contains("payloadTooLargeError"))

        let unprocessable = SarvamError.unprocessableEntityError(statusCode: 422, code: "unprocessable", requestId: "req-6", message: "Unprocessable", rawBody: "raw")
        #expect(unprocessable.statusCode == 422)
        #expect(unprocessable.code == "unprocessable")
        #expect(unprocessable.requestId == "req-6")
        #expect(unprocessable.message == "Unprocessable")
        #expect(unprocessable.rawBody == "raw")
        #expect(!unprocessable.isRetryable)
        #expect(unprocessable.description.contains("unprocessableEntityError"))

        let rateLimit = SarvamError.rateLimitError(statusCode: 429, code: "rate_limit", requestId: "req-7", message: "Too Many Requests", retryAfterMs: 3000)
        #expect(rateLimit.statusCode == 429)
        #expect(rateLimit.code == "rate_limit")
        #expect(rateLimit.requestId == "req-7")
        #expect(rateLimit.message == "Too Many Requests")
        #expect(rateLimit.retryAfterMs == 3000)
        #expect(rateLimit.isRetryable)
        #expect(rateLimit.description.contains("rateLimitError"))

        let serverErr = SarvamError.serverError(statusCode: 500, code: "server_error", requestId: "req-8", message: "Internal Error")
        #expect(serverErr.statusCode == 500)
        #expect(serverErr.code == "server_error")
        #expect(serverErr.requestId == "req-8")
        #expect(serverErr.message == "Internal Error")
        #expect(serverErr.isRetryable)
        #expect(serverErr.description.contains("serverError"))

        let connErr = SarvamError.connectionError(message: "Failed to connect", cause: "DNS")
        #expect(connErr.statusCode == nil)
        #expect(connErr.code == nil)
        #expect(connErr.requestId == nil)
        #expect(connErr.message == "Failed to connect")
        #expect(connErr.rawBody == nil)
        #expect(connErr.isRetryable)
        #expect(connErr.description.contains("connectionError"))

        let timeoutErr = SarvamError.timeoutError(phase: .connect, message: "Connect timed out")
        #expect(timeoutErr.statusCode == nil)
        #expect(timeoutErr.code == nil)
        #expect(timeoutErr.requestId == nil)
        #expect(timeoutErr.message == "Connect timed out")
        #expect(timeoutErr.isRetryable)
        #expect(timeoutErr.description.contains("timeoutError"))

        let streamErr = SarvamError.streamError(requestId: "req-9", message: "Stream broken")
        #expect(streamErr.statusCode == nil)
        #expect(streamErr.code == nil)
        #expect(streamErr.requestId == "req-9")
        #expect(streamErr.message == "Stream broken")
        #expect(!streamErr.isRetryable)
        #expect(streamErr.description.contains("streamError"))

        let realtimeErr = SarvamError.realtimeError(closeCode: 1006, code: "abnormal", message: "Abnormal close")
        #expect(realtimeErr.statusCode == nil)
        #expect(realtimeErr.code == "abnormal")
        #expect(realtimeErr.requestId == nil)
        #expect(realtimeErr.message == "Abnormal close")
        #expect(!realtimeErr.isRetryable)
        #expect(realtimeErr.description.contains("realtimeError"))

        let decodeErr = SarvamError.decodingError(rawBody: "{\"foo\":}", message: "Failed parsing", cause: "syntax")
        #expect(decodeErr.statusCode == nil)
        #expect(decodeErr.code == nil)
        #expect(decodeErr.requestId == nil)
        #expect(decodeErr.message == "Failed parsing")
        #expect(decodeErr.rawBody == "{\"foo\":}")
        #expect(!decodeErr.isRetryable)
        #expect(decodeErr.description.contains("decodingError"))
    }

    @Test("SarvamError.from status code and header mappings")
    func testErrorFromFactory() {
        // 401
        let err401 = SarvamError.from(statusCode: 401, headers: ["x-request-id": "req-401"], body: Data("{\"error\":{\"code\":\"unauthorized\",\"message\":\"Bad token\",\"request_id\":\"inner-req\"}}".utf8))
        if case let .authenticationError(status, code, reqId, msg) = err401 {
            #expect(status == 401)
            #expect(code == "unauthorized")
            #expect(reqId == "inner-req")
            #expect(msg == "Bad token")
        } else {
            #expect(Bool(false), "Expected authenticationError")
        }

        // 403 with invalid_api_key_error
        let err403Key = SarvamError.from(statusCode: 403, headers: [:], body: Data("{\"error\":{\"code\":\"invalid_api_key_error\",\"message\":\"Key revoked\"}}".utf8))
        if case let .authenticationError(status, code, _, msg) = err403Key {
            #expect(status == 403)
            #expect(code == "invalid_api_key_error")
            #expect(msg == "Key revoked")
        } else {
            #expect(Bool(false), "Expected authenticationError")
        }

        // 403 permission denied
        let err403Perm = SarvamError.from(statusCode: 403, headers: ["x-ms-request-id": "ms-req"], body: Data("{\"code\":\"forbidden\",\"detail\":\"No access\"}".utf8))
        if case let .permissionDeniedError(status, code, reqId, msg) = err403Perm {
            #expect(status == 403)
            #expect(code == "forbidden")
            #expect(reqId == "ms-req")
            #expect(msg == "No access")
        } else {
            #expect(Bool(false), "Expected permissionDeniedError")
        }

        // 400 bad request
        let err400 = SarvamError.from(statusCode: 400, headers: [:], body: Data("Invalid JSON input".utf8))
        if case let .badRequestError(status, code, reqId, msg, raw) = err400 {
            #expect(status == 400)
            #expect(code == nil)
            #expect(reqId == nil)
            #expect(msg == "Invalid JSON input")
            #expect(raw == "Invalid JSON input")
        } else {
            #expect(Bool(false), "Expected badRequestError")
        }

        // 404 not found
        let err404 = SarvamError.from(statusCode: 404, headers: [:], body: nil)
        if case let .notFoundError(status, _, _, msg) = err404 {
            #expect(status == 404)
            #expect(msg == "HTTP error 404")
        } else {
            #expect(Bool(false), "Expected notFoundError")
        }

        // 413 payload too large
        let err413 = SarvamError.from(statusCode: 413, headers: [:], body: Data())
        if case let .payloadTooLargeError(status, _, _, _) = err413 {
            #expect(status == 413)
        } else {
            #expect(Bool(false), "Expected payloadTooLargeError")
        }

        // 422 unprocessable entity
        let err422 = SarvamError.from(statusCode: 422, headers: [:], body: Data("{\"code\":\"val_err\",\"message\":\"bad input\"}".utf8))
        if case let .unprocessableEntityError(status, code, _, msg, _) = err422 {
            #expect(status == 422)
            #expect(code == "val_err")
            #expect(msg == "bad input")
        } else {
            #expect(Bool(false), "Expected unprocessableEntityError")
        }

        // 429 with retry-after-ms
        let err429Ms = SarvamError.from(statusCode: 429, headers: ["retry-after-ms": "2500"], body: nil)
        if case let .rateLimitError(status, _, _, _, ms) = err429Ms {
            #expect(status == 429)
            #expect(ms == 2500)
        } else {
            #expect(Bool(false), "Expected rateLimitError")
        }

        // 429 with retry-after (seconds)
        let err429Sec = SarvamError.from(statusCode: 429, headers: ["retry-after": "5"], body: nil)
        if case let .rateLimitError(status, _, _, _, ms) = err429Sec {
            #expect(status == 429)
            #expect(ms == 5000)
        } else {
            #expect(Bool(false), "Expected rateLimitError")
        }

        // 503 with rate_limit_exceeded_error
        let err503Rate = SarvamError.from(statusCode: 503, headers: [:], body: Data("{\"code\":\"rate_limit_exceeded_error\",\"message\":\"Slow down\"}".utf8))
        if case let .rateLimitError(status, code, _, msg, _) = err503Rate {
            #expect(status == 503)
            #expect(code == "rate_limit_exceeded_error")
            #expect(msg == "Slow down")
        } else {
            #expect(Bool(false), "Expected rateLimitError")
        }

        // 500 server error
        let err500 = SarvamError.from(statusCode: 500, headers: [:], body: nil)
        if case let .serverError(status, _, _, _) = err500 {
            #expect(status == 500)
        } else {
            #expect(Bool(false), "Expected serverError")
        }

        // 408 & 409 map to serverError per §4
        let err408 = SarvamError.from(statusCode: 408, headers: [:], body: nil)
        #expect(err408.statusCode == 408)
        let err409 = SarvamError.from(statusCode: 409, headers: [:], body: nil)
        #expect(err409.statusCode == 409)

        // 418 generic >= 400
        let err418 = SarvamError.from(statusCode: 418, headers: [:], body: nil)
        if case let .badRequestError(status, _, _, _, _) = err418 {
            #expect(status == 418)
        } else {
            #expect(Bool(false), "Expected badRequestError")
        }

        // 200/300 fallback to serverError
        let err300 = SarvamError.from(statusCode: 300, headers: [:], body: nil)
        if case let .serverError(status, _, _, _) = err300 {
            #expect(status == 300)
        } else {
            #expect(Bool(false), "Expected serverError")
        }
    }
}
