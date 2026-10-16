import Foundation
import Testing
@testable import Sarvam

@Suite("Retry Middleware Tests")
struct RetryTests {

    @Test("Retry-After header in seconds parsed to milliseconds")
    func testRetryAfterSecondsParsing() async throws {
        let mock = MockHTTPTransport()
        let clock = MockClockProvider()

        mock.queueResponse(HTTPResponse(statusCode: 429, headers: ["retry-after": "3"], body: Data()))
        mock.queueResponse(HTTPResponse(statusCode: 200, headers: [:], body: "{}".data(using: .utf8)!))

        let retryMiddleware = RetryMiddleware(
            defaultMaxRetries: 2,
            clock: clock,
            random: MockRandomProvider()
        )

        let req = HTTPRequest(
            method: .get,
            url: URL(string: "https://api.sarvam.ai/v2/models")!,
            operationKind: .idempotent
        )

        let res = try await retryMiddleware.process(request: req) { r in
            try await mock.execute(request: r)
        }

        #expect(res.statusCode == 200)
        #expect(clock.sleepCalls == [3000])
    }

    @Test("Non-retryable HTTP 400 Bad Request is not retried")
    func testBadRequestNotRetried() async throws {
        let mock = MockHTTPTransport()
        mock.queueResponse(HTTPResponse(statusCode: 400, headers: [:], body: "{\"error\":{\"code\":\"bad_request\",\"message\":\"Malformed request\"}}".data(using: .utf8)!))

        let client = SarvamClient(
            apiKey: "test-api-key",
            transport: mock
        )

        do {
            _ = try await client.text.identifyLanguage(TextLidRequest(input: ""))
            Issue.record("Expected BadRequestError")
        } catch let err as SarvamError {
            guard case let .badRequestError(status, code, _, message, _) = err else {
                Issue.record("Expected badRequestError, got \(err)")
                return
            }
            #expect(status == 400)
            #expect(code == "bad_request")
            #expect(message == "Malformed request")
            #expect(mock.executedRequests.count == 1)
        }
    }

    @Test("Non-replayable multipartCompute does not retry on 503")
    func testNonReplayableMultipartNoRetry() async throws {
        let mock = MockHTTPTransport()
        mock.queueResponse(HTTPResponse(statusCode: 503, headers: [:], body: "{\"error\":{\"code\":\"service_unavailable\",\"message\":\"Service unavailable\"}}".data(using: .utf8)!))

        let client = SarvamClient(
            apiKey: "test-api-key",
            transport: mock
        )

        let nonReplayableFile = FileInput(data: "audio".data(using: .utf8)!, isReplayable: false)
        do {
            _ = try await client.speechToText.transcribe(file: nonReplayableFile)
            Issue.record("Expected ServerError")
        } catch let err as SarvamError {
            guard case let .serverError(status, _, _, _) = err else {
                Issue.record("Expected serverError, got \(err)")
                return
            }
            #expect(status == 503)
            #expect(mock.executedRequests.count == 1) // Did not retry because isReplayable is false
        }
    }
}
