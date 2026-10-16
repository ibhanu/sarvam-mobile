import Foundation
import Testing
@testable import Sarvam

final class MockLoggerAdapter: LoggerAdapter, @unchecked Sendable {
    private var _logs: [(LogLevel, String)] = []
    private let lock = NSLock()

    var logs: [(LogLevel, String)] {
        lock.withLock { _logs }
    }

    func log(level: LogLevel, message: String) {
        lock.withLock {
            _logs.append((level, message))
        }
    }
}

final class AtomicCounter: @unchecked Sendable {
    private var _count: Int
    private let lock = NSLock()

    init(_ initial: Int = 0) {
        self._count = initial
    }

    var value: Int {
        lock.withLock { _count }
    }

    @discardableResult
    func increment() -> Int {
        lock.withLock {
            _count += 1
            return _count
        }
    }
}

@Suite("Logging & Retry Middleware Tests")
struct MiddlewareTests {
    // MARK: - LoggingMiddleware Tests

    @Test("LogLevel ordering and PrintLogger")
    func testLogLevelAndPrintLogger() {
        #expect(LogLevel.off < LogLevel.error)
        #expect(LogLevel.error < LogLevel.warn)
        #expect(LogLevel.warn < LogLevel.info)
        #expect(LogLevel.info < LogLevel.debug)
        #expect(!(LogLevel.debug < LogLevel.off))

        let printLogger = PrintLogger()
        printLogger.log(level: .info, message: "Testing print logger")
    }

    @Test("LoggingMiddleware with level off does not log")
    func testLoggingOff() async throws {
        let mockLogger = MockLoggerAdapter()
        let middleware = LoggingMiddleware(level: .off, logger: mockLogger)
        let request = HTTPRequest(method: .get, url: URL(string: "https://api.sarvam.ai/v1/test")!)

        let response = try await middleware.process(request: request) { _ in
            HTTPResponse(statusCode: 200, headers: [:], body: Data())
        }
        #expect(response.statusCode == 200)
        #expect(mockLogger.logs.isEmpty)
    }

    @Test("LoggingMiddleware with level info logs requests and redacts auth headers")
    func testLoggingInfoSuccess() async throws {
        let mockLogger = MockLoggerAdapter()
        let middleware = LoggingMiddleware(level: .info, logger: mockLogger)
        let request = HTTPRequest(
            method: .post,
            url: URL(string: "https://api.sarvam.ai/v1/chat")!,
            headers: [
                "api-subscription-key": "secret-key",
                "Authorization": "Bearer token123",
                "X-Custom": "visible"
            ]
        )

        let response = try await middleware.process(request: request) { _ in
            HTTPResponse(statusCode: 200, headers: [:], body: Data())
        }
        #expect(response.statusCode == 200)
        #expect(mockLogger.logs.count == 2)
        let requestLog = mockLogger.logs[0].1
        #expect(requestLog.contains("[REDACTED]"))
        #expect(requestLog.contains("visible"))
        let responseLog = mockLogger.logs[1].1
        #expect(responseLog.contains("200"))
    }

    @Test("LoggingMiddleware with level info logs errors and rethrows")
    func testLoggingInfoFailure() async throws {
        let mockLogger = MockLoggerAdapter()
        let middleware = LoggingMiddleware(level: .info, logger: mockLogger)
        let request = HTTPRequest(method: .get, url: URL(string: "https://api.sarvam.ai/v1/fail")!)

        await #expect(throws: SarvamError.self) {
            _ = try await middleware.process(request: request) { _ in
                throw SarvamError.serverError(statusCode: 500, code: "server_err", requestId: nil, message: "Internal error")
            }
        }
        #expect(mockLogger.logs.count == 2)
        let errorLog = mockLogger.logs[1].1
        #expect(errorLog.contains("FAILED"))
        #expect(errorLog.contains("Internal error"))
    }

    @Test("LoggingMiddleware default initializer")
    func testLoggingDefaultInit() {
        let defaultMw = LoggingMiddleware()
        #expect(defaultMw.level == .off)
    }

    // MARK: - RetryMiddleware Tests

    @Test("RetryMiddleware retries 429 using retry-after-ms, retry-after, and x-ratelimit-reset")
    func testRetry429WithHeaders() async throws {
        let clock = MockClockProvider(initialEpochMs: 1_000_000)
        let random = MockRandomProvider()
        let middleware = RetryMiddleware(defaultMaxRetries: 3, clock: clock, random: random)

        // Case 1: retry-after-ms
        let attempts1 = AtomicCounter()
        let req1 = HTTPRequest(method: .post, url: URL(string: "https://api.sarvam.ai/test")!)
        _ = try await middleware.process(request: req1) { _ in
            let count = attempts1.increment()
            if count == 1 {
                return HTTPResponse(statusCode: 429, headers: ["retry-after-ms": "1500"], body: Data())
            }
            return HTTPResponse(statusCode: 200, headers: [:], body: Data())
        }
        #expect(attempts1.value == 2)
        #expect(clock.sleepCalls.contains(1500))

        // Case 2: retry-after in seconds
        let attempts2 = AtomicCounter()
        _ = try await middleware.process(request: req1) { _ in
            let count = attempts2.increment()
            if count == 1 {
                return HTTPResponse(statusCode: 429, headers: ["retry-after": "2"], body: Data())
            }
            return HTTPResponse(statusCode: 200, headers: [:], body: Data())
        }
        #expect(attempts2.value == 2)
        #expect(clock.sleepCalls.contains(2000))

        // Case 3: x-ratelimit-reset epoch
        let attempts3 = AtomicCounter()
        let currentEpochSec = clock.nowEpochMs() / 1000
        let resetEpochSec = currentEpochSec + 4
        _ = try await middleware.process(request: req1) { _ in
            let count = attempts3.increment()
            if count == 1 {
                return HTTPResponse(statusCode: 429, headers: ["x-ratelimit-reset": String(resetEpochSec)], body: Data())
            }
            return HTTPResponse(statusCode: 200, headers: [:], body: Data())
        }
        #expect(attempts3.value == 2)
        #expect(clock.sleepCalls.contains(4000))
    }

    @Test("RetryMiddleware retries idempotent and statelessPost on 5xx and 408/409")
    func testRetryIdempotentStatusCodes() async throws {
        let clock = MockClockProvider()
        let random = MockRandomProvider(fixedInt: 100)
        let middleware = RetryMiddleware(defaultMaxRetries: 2, clock: clock, random: random)

        let statusCodesToTest = [408, 409, 500, 502, 503, 504]
        for status in statusCodesToTest {
            let calls = AtomicCounter()
            let req = HTTPRequest(method: .get, url: URL(string: "https://api.sarvam.ai/v1")!, operationKind: .idempotent)
            _ = try await middleware.process(request: req) { _ in
                let count = calls.increment()
                if count == 1 {
                    return HTTPResponse(statusCode: status, headers: [:], body: Data())
                }
                return HTTPResponse(statusCode: 200, headers: [:], body: Data())
            }
            #expect(calls.value == 2, "Status \(status) should be retried for idempotent request")
        }
    }

    @Test("RetryMiddleware jobCreate retries 500 only with idempotency key")
    func testJobCreateIdempotencyKeyRetries() async throws {
        let clock = MockClockProvider()
        let random = MockRandomProvider(fixedInt: 100)
        let middleware = RetryMiddleware(defaultMaxRetries: 2, clock: clock, random: random)

        // With Idempotency-Key header: retried
        let callsWithKey = AtomicCounter()
        let reqWithKey = HTTPRequest(
            method: .post,
            url: URL(string: "https://api.sarvam.ai/job")!,
            headers: ["Idempotency-Key": "idemp-123"],
            operationKind: .jobCreate
        )
        _ = try await middleware.process(request: reqWithKey) { _ in
            let count = callsWithKey.increment()
            if count == 1 {
                return HTTPResponse(statusCode: 500, headers: [:], body: Data())
            }
            return HTTPResponse(statusCode: 200, headers: [:], body: Data())
        }
        #expect(callsWithKey.value == 2)

        // With request.idempotencyKey property: retried
        let callsWithProp = AtomicCounter()
        let reqWithProp = HTTPRequest(
            method: .post,
            url: URL(string: "https://api.sarvam.ai/job")!,
            operationKind: .jobCreate,
            idempotencyKey: "idemp-prop"
        )
        _ = try await middleware.process(request: reqWithProp) { _ in
            let count = callsWithProp.increment()
            if count == 1 {
                return HTTPResponse(statusCode: 502, headers: [:], body: Data())
            }
            return HTTPResponse(statusCode: 200, headers: [:], body: Data())
        }
        #expect(callsWithProp.value == 2)

        // Without idempotency key: not retried
        let callsWithout = AtomicCounter()
        let reqWithout = HTTPRequest(
            method: .post,
            url: URL(string: "https://api.sarvam.ai/job")!,
            operationKind: .jobCreate
        )
        let resWithout = try await middleware.process(request: reqWithout) { _ in
            _ = callsWithout.increment()
            return HTTPResponse(statusCode: 500, headers: [:], body: Data())
        }
        #expect(callsWithout.value == 1)
        #expect(resWithout.statusCode == 500)
    }

    @Test("RetryMiddleware retries on SarvamError.rateLimitError, serverError, connectionError, timeoutError")
    func testRetryOnSarvamErrors() async throws {
        let clock = MockClockProvider()
        let random = MockRandomProvider(fixedInt: 50)
        let middleware = RetryMiddleware(defaultMaxRetries: 2, clock: clock, random: random)

        // rateLimitError
        let callsRate = AtomicCounter()
        let req = HTTPRequest(method: .get, url: URL(string: "https://api.sarvam.ai/test")!, operationKind: .idempotent)
        let resRate = try await middleware.process(request: req) { _ in
            let count = callsRate.increment()
            if count == 1 {
                throw SarvamError.rateLimitError(statusCode: 429, code: "rate", requestId: nil, message: "slow", retryAfterMs: 500)
            }
            return HTTPResponse(statusCode: 200, headers: [:], body: Data())
        }
        #expect(callsRate.value == 2)
        #expect(resRate.statusCode == 200)

        // connectionError on idempotent
        let callsConn = AtomicCounter()
        let resConn = try await middleware.process(request: req) { _ in
            let count = callsConn.increment()
            if count == 1 {
                throw SarvamError.connectionError(message: "offline")
            }
            return HTTPResponse(statusCode: 200, headers: [:], body: Data())
        }
        #expect(callsConn.value == 2)
        #expect(resConn.statusCode == 200)

        // timeoutError on idempotent
        let callsTimeout = AtomicCounter()
        let resTimeout = try await middleware.process(request: req) { _ in
            let count = callsTimeout.increment()
            if count == 1 {
                throw SarvamError.timeoutError(phase: .total, message: "timeout")
            }
            return HTTPResponse(statusCode: 200, headers: [:], body: Data())
        }
        #expect(callsTimeout.value == 2)
        #expect(resTimeout.statusCode == 200)

        // Non-retryable error (permissionDeniedError)
        await #expect(throws: SarvamError.self) {
            try await middleware.process(request: req) { _ in
                throw SarvamError.permissionDeniedError(statusCode: 403, code: "forbidden", requestId: nil, message: "no")
            }
        }
    }

    @Test("RetryMiddleware transient NSURLErrorDomain retried on idempotent")
    func testTransientNetworkError() async throws {
        let clock = MockClockProvider()
        let random = MockRandomProvider(fixedInt: 100)
        let middleware = RetryMiddleware(defaultMaxRetries: 2, clock: clock, random: random)

        let calls = AtomicCounter()
        let req = HTTPRequest(method: .get, url: URL(string: "https://api.sarvam.ai/v1")!, operationKind: .idempotent)
        _ = try await middleware.process(request: req) { _ in
            let count = calls.increment()
            if count == 1 {
                throw NSError(domain: NSURLErrorDomain, code: NSURLErrorNetworkConnectionLost, userInfo: nil)
            }
            return HTTPResponse(statusCode: 200, headers: [:], body: Data())
        }
        #expect(calls.value == 2)

        // Non-transient error throws immediately
        await #expect(throws: Error.self) {
            try await middleware.process(request: req) { _ in
                throw NSError(domain: "CustomDomain", code: 999, userInfo: nil)
            }
        }
    }

    @Test("RetryMiddleware maxBackoffMs ceiling <= 0 edge case")
    func testBackoffCeilingZero() async throws {
        let clock = MockClockProvider()
        let random = MockRandomProvider(fixedInt: 100)
        let middleware = RetryMiddleware(defaultMaxRetries: 2, baseBackoffMs: 0, maxBackoffMs: 0, clock: clock, random: random)

        let calls = AtomicCounter()
        let req = HTTPRequest(method: .get, url: URL(string: "https://api.sarvam.ai/test")!, operationKind: .idempotent)
        _ = try await middleware.process(request: req) { _ in
            let count = calls.increment()
            if count == 1 {
                return HTTPResponse(statusCode: 500, headers: [:], body: Data())
            }
            return HTTPResponse(statusCode: 200, headers: [:], body: Data())
        }
        #expect(calls.value == 2)
        #expect(clock.sleepCalls.contains(0))
    }

    // MARK: - AuthMiddleware, TokenAuth, RequestExecutor, and HTTPResponse Tests

    @Test("AuthMiddleware, TokenAuth, RequestExecutor.executeStream, and HTTPResponse.header coverage")
    func testAuthMiddlewareAndExecutorAndHttpTypes() async throws {
        // 1. HTTPResponse.header case-insensitive lookup
        let resp = HTTPResponse(statusCode: 200, headers: ["X-Request-Id": "req-abc"], body: Data())
        #expect(resp.header("x-request-id") == "req-abc")
        #expect(resp.header("X-REQUEST-ID") == "req-abc")
        #expect(resp.header("Missing-Header") == nil)

        // 2. TokenAuth with nil expiresAtEpochMs cached hit & provider error
        let nilExpiryCalls = AtomicCounter()
        let tokenAuthNilExpiry = TokenAuth(tokenProvider: {
            _ = nilExpiryCalls.increment()
            return AuthToken(token: "tok-no-exp", expiresAtEpochMs: nil)
        })
        let cred1 = try await tokenAuthNilExpiry.getCredentials()
        let cred2 = try await tokenAuthNilExpiry.getCredentials()
        #expect(cred1 == .bearerToken(token: "tok-no-exp", expiresAtEpochMs: nil))
        #expect(cred2 == .bearerToken(token: "tok-no-exp", expiresAtEpochMs: nil))
        #expect(nilExpiryCalls.value == 1)

        let failingTokenAuth = TokenAuth(tokenProvider: {
            throw SarvamError.authenticationError(statusCode: 401, code: "fail", requestId: nil, message: "bad")
        })
        await #expect(throws: SarvamError.self) {
            _ = try await failingTokenAuth.getCredentials()
        }

        // 3. AuthMiddleware 403 invalid_api_key_error (nested and top-level) and thrown SarvamError.authenticationError
        let tokenCalls = AtomicCounter()
        let tokenAuth = TokenAuth(tokenProvider: {
            let c = tokenCalls.increment()
            return AuthToken(token: "tok-\(c)")
        })
        let authMw = AuthMiddleware(authProvider: tokenAuth)
        let req = HTTPRequest(method: .get, url: URL(string: "https://api.sarvam.ai/v1")!)

        // 403 with top-level code == "invalid_api_key_error"
        let attempt403Top = AtomicCounter()
        let res403Top = try await authMw.process(request: req) { r in
            if attempt403Top.increment() == 1 {
                return HTTPResponse(statusCode: 403, headers: [:], body: Data("{\"code\":\"invalid_api_key_error\"}".utf8))
            }
            return HTTPResponse(statusCode: 200, headers: r.headers, body: Data())
        }
        #expect(res403Top.statusCode == 200)

        // 403 with nested error.code == "invalid_api_key_error"
        let attempt403Nested = AtomicCounter()
        let res403Nested = try await authMw.process(request: req) { r in
            if attempt403Nested.increment() == 1 {
                return HTTPResponse(statusCode: 403, headers: [:], body: Data("{\"error\":{\"code\":\"invalid_api_key_error\"}}".utf8))
            }
            return HTTPResponse(statusCode: 200, headers: r.headers, body: Data())
        }
        #expect(res403Nested.statusCode == 200)

        // Thrown SarvamError.authenticationError triggers refresh on TokenAuth
        let attemptThrownAuth = AtomicCounter()
        let resThrownAuth = try await authMw.process(request: req) { r in
            if attemptThrownAuth.increment() == 1 {
                throw SarvamError.authenticationError(statusCode: 401, code: "auth", requestId: nil, message: "expired")
            }
            return HTTPResponse(statusCode: 200, headers: r.headers, body: Data())
        }
        #expect(resThrownAuth.statusCode == 200)

        // Thrown non-auth SarvamError is rethrown
        await #expect(throws: SarvamError.self) {
            _ = try await authMw.process(request: req) { _ in
                throw SarvamError.serverError(statusCode: 500, code: "err", requestId: nil, message: "boom")
            }
        }

        // ApiKeyAuth does NOT retry on 401
        let apiKeyMw = AuthMiddleware(authProvider: ApiKeyAuth(apiKey: "key"))
        let res401 = try await apiKeyMw.process(request: req) { _ in
            HTTPResponse(statusCode: 401, headers: [:], body: Data())
        }
        #expect(res401.statusCode == 401)

        // ProxyAuth custom headers in AuthMiddleware
        let proxyMw = AuthMiddleware(authProvider: ProxyAuth(proxyBaseUrl: "https://proxy.example.com", headersProvider: { ["X-Proxy": "1"] }))
        let resProxy = try await proxyMw.process(request: req) { r in
            HTTPResponse(statusCode: 200, headers: r.headers, body: Data())
        }
        #expect(resProxy.headers["X-Proxy"] == "1")

        // 4. RequestExecutor.executeStream with TokenAuth, ProxyAuth, and HTTP >= 400 error body
        let transport = MockHTTPTransport()
        transport.queueStream(
            response: HTTPResponse(statusCode: 200, headers: [:], body: Data()),
            chunks: [Data([1, 2])]
        )
        let tokenClient = SarvamClient(authProvider: tokenAuth, transport: transport)
        let stream1 = try await tokenClient.textToSpeech.stream(TextToSpeechRequest(text: "hi", targetLanguageCode: .hiIn))
        for try await _ in stream1 {}

        transport.queueStream(
            response: HTTPResponse(statusCode: 400, headers: [:], body: Data()),
            chunks: [Data("{\"error\":{\"message\":\"stream bad request\"}}".utf8)]
        )
        let proxyClient = SarvamClient(
            authProvider: ProxyAuth(proxyBaseUrl: "https://proxy.example.com", headersProvider: { ["X-Proxy": "2"] }),
            transport: transport
        )
        await #expect(throws: SarvamError.self) {
            _ = try await proxyClient.textToSpeech.stream(TextToSpeechRequest(text: "hi", targetLanguageCode: .hiIn))
        }
    }
}
