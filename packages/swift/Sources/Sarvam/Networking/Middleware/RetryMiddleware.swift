import Foundation

/// Network resilience middleware implementing exponential backoff with full jitter and operation-aware retries.
public final class RetryMiddleware: Middleware, Sendable {
    public let defaultMaxRetries: Int
    public let baseBackoffMs: Int64
    public let maxBackoffMs: Int64
    public let clock: ClockProvider
    public let random: RandomProvider

    public init(
        defaultMaxRetries: Int = 2,
        baseBackoffMs: Int64 = 500,
        maxBackoffMs: Int64 = 8000,
        clock: ClockProvider = SystemClockProvider(),
        random: RandomProvider = SystemRandomProvider()
    ) {
        self.defaultMaxRetries = defaultMaxRetries
        self.baseBackoffMs = baseBackoffMs
        self.maxBackoffMs = maxBackoffMs
        self.clock = clock
        self.random = random
    }

    public func process(
        request: HTTPRequest,
        next: @Sendable (HTTPRequest) async throws -> HTTPResponse
    ) async throws -> HTTPResponse {
        var attempt = 0
        let maxRetries = defaultMaxRetries

        while true {
            do {
                let response = try await next(request)

                if isRetryableStatusCode(response.statusCode, request: request) && attempt < maxRetries {
                    let delayMs = computeDelayMs(headers: response.headers, attempt: attempt)
                    try await clock.sleep(ms: delayMs)
                    attempt += 1
                    continue
                }

                return response
            } catch is CancellationError {
                throw CancellationError()
            } catch let err as SarvamError {
                if isRetryableError(err, request: request) && attempt < maxRetries {
                    let delayMs = err.retryAfterMs ?? computeBackoffMs(attempt: attempt)
                    try await clock.sleep(ms: delayMs)
                    attempt += 1
                    continue
                }
                throw err
            } catch {
                if isTransientNetworkError(error, request: request) && attempt < maxRetries {
                    let delayMs = computeBackoffMs(attempt: attempt)
                    try await clock.sleep(ms: delayMs)
                    attempt += 1
                    continue
                }
                throw error
            }
        }
    }

    // MARK: - Retry Evaluation

    private func isRetryableStatusCode(_ statusCode: Int, request: HTTPRequest) -> Bool {
        if statusCode == 429 {
            return true
        }

        switch request.operationKind {
        case .idempotent:
            return statusCode == 408 || statusCode == 409 || statusCode == 500 ||
                   statusCode == 502 || statusCode == 503 || statusCode == 504
        case .statelessPost:
            return statusCode == 408 || statusCode == 409 || statusCode == 500 ||
                   statusCode == 502 || statusCode == 503 || statusCode == 504
        case .multipartCompute:
            return statusCode == 503 && request.isReplayable
        case .jobCreate:
            let hasIdempotencyKey = request.headers["Idempotency-Key"] != nil ||
                                    request.headers["idempotency-key"] != nil ||
                                    request.idempotencyKey != nil
            if hasIdempotencyKey {
                return statusCode == 500 || statusCode == 502 || statusCode == 503 || statusCode == 504
            }
            // JOB_CREATE operations must not retry 500 without idempotency key!
            return false
        }
    }

    private func isRetryableError(_ error: SarvamError, request: HTTPRequest) -> Bool {
        switch error {
        case .rateLimitError:
            return true
        case .serverError(let statusCode, _, _, _):
            return isRetryableStatusCode(statusCode, request: request)
        case .connectionError, .timeoutError:
            return request.operationKind == .idempotent || request.operationKind == .statelessPost
        default:
            return false
        }
    }

    private func isTransientNetworkError(_ error: Error, request: HTTPRequest) -> Bool {
        guard request.operationKind == .idempotent || request.operationKind == .statelessPost else {
            return false
        }
        let nsError = error as NSError
        return nsError.domain == NSURLErrorDomain
    }

    // MARK: - Backoff Computation

    private func computeDelayMs(headers: [String: String], attempt: Int) -> Int64 {
        // 1. Check retry-after-ms
        for (k, v) in headers where k.lowercased() == "retry-after-ms" {
            if let ms = Int64(v.trimmingCharacters(in: .whitespaces)) {
                return ms
            }
        }

        // 2. Check Retry-After
        for (k, v) in headers where k.lowercased() == "retry-after" {
            let trimmed = v.trimmingCharacters(in: .whitespaces)
            if let seconds = Int64(trimmed) {
                return seconds * 1000
            }
        }

        // 3. Check X-RateLimit-Reset
        for (k, v) in headers where k.lowercased() == "x-ratelimit-reset" {
            let trimmed = v.trimmingCharacters(in: .whitespaces)
            if let resetEpoch = Int64(trimmed) {
                let currentEpoch = clock.nowEpochMs() / 1000
                let delta = max(0, resetEpoch - currentEpoch)
                return delta * 1000
            }
        }

        // 4. Full jitter backoff
        return computeBackoffMs(attempt: attempt)
    }

    private func computeBackoffMs(attempt: Int) -> Int64 {
        let shift = min(attempt, 6)
        let multiplier = Int64(1 << shift)
        let ceilingMs = min(maxBackoffMs, baseBackoffMs * multiplier)
        if ceilingMs <= 0 { return 0 }
        return random.nextInt(in: 0...ceilingMs)
    }
}
