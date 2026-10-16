import Foundation
import Testing
@testable import Sarvam

@Suite("DocAiResource Unit Tests")
struct DocAiResourceTests {
    private func makeClient(transport: MockHTTPTransport, clock: MockClockProvider = MockClockProvider()) -> SarvamClient {
        SarvamClient(
            authProvider: ApiKeyAuth(apiKey: "test-api-key"),
            transport: transport,
            clock: clock
        )
    }

    @Test("digitise with multiple files sends each with name 'file'")
    func testDigitiseMultipleFiles() async throws {
        let transport = MockHTTPTransport()
        let json = """
        {
            "job_id": "job-doc-123",
            "status": "pending",
            "run_id": "run-doc-123"
        }
        """
        transport.queueResponse(HTTPResponse(statusCode: 200, headers: [:], body: Data(json.utf8)))
        let client = makeClient(transport: transport)

        let file1 = FileInput(data: Data([1, 2]), fileName: "doc1.pdf", mimeType: "application/pdf")
        let file2 = FileInput(data: Data([3, 4]), fileName: "doc2.pdf", mimeType: "application/pdf")

        let resp = try await client.docAi.digitise(
            files: [file1, file2],
            language: "hi-IN",
            contentType: "pdf"
        )

        #expect(resp.jobId == "job-doc-123")
        #expect(resp.runId == "run-doc-123")
        let req = transport.executedRequests.first
        #expect(req?.method == .post)
        #expect(req?.url.path == "/doc-ai/v1/job/digitise")
        #expect(req?.operationKind == .jobCreate)
        #expect(req?.headers["content-type"]?.contains("multipart/form-data") == true)

        let bodyString = String(data: req?.body ?? Data(), encoding: .utf8) ?? ""
        // Both files should have name="file"
        let matches = bodyString.components(separatedBy: "name=\"file\"").count - 1
        #expect(matches == 2)
    }

    @Test("extract with schemaDict serializes dictionary to JSON string field 'schema'")
    func testExtractWithSchemaDict() async throws {
        let transport = MockHTTPTransport()
        let json = """
        {
            "job_id": "job-extract-456",
            "status": "pending",
            "run_id": "run-extract-456"
        }
        """
        transport.queueResponse(HTTPResponse(statusCode: 200, headers: [:], body: Data(json.utf8)))
        let client = makeClient(transport: transport)

        let schemaDict: [String: Any] = [
            "name": "string",
            "age": "number"
        ]
        let file = FileInput(data: Data([5, 6]), fileName: "form.png", mimeType: "image/png")

        let resp = try await client.docAi.extract(
            file: file,
            schemaDict: schemaDict,
            outputFormat: "json"
        )

        #expect(resp.jobId == "job-extract-456")
        #expect(resp.runId == "run-extract-456")
        let req = transport.executedRequests.first
        #expect(req?.url.path == "/doc-ai/v1/job/extract")

        let bodyString = String(data: req?.body ?? Data(), encoding: .utf8) ?? ""
        #expect(bodyString.contains("name=\"schema\""))
        #expect(bodyString.contains("\"age\":\"number\"") || bodyString.contains("\"age\": \"number\""))
        #expect(bodyString.contains("\"name\":\"string\"") || bodyString.contains("\"name\": \"string\""))
    }

    @Test("createUploadUrl, getStatus, getResults, and getDownloadUrl")
    func testDocAiLifecycleMethods() async throws {
        let transport = MockHTTPTransport()
        let client = makeClient(transport: transport)

        // 1. Upload URL
        let uploadJson = """
        {
            "upload_id": "up-123",
            "method": "PUT",
            "url": "https://storage.sarvam.ai/upload/up-123",
            "expires_at": "2026-01-01T00:00:00Z"
        }
        """
        transport.queueResponse(HTTPResponse(statusCode: 200, headers: [:], body: Data(uploadJson.utf8)))
        let uploadResp = try await client.docAi.createUploadUrl()
        #expect(uploadResp.uploadId == "up-123")
        #expect(uploadResp.url == "https://storage.sarvam.ai/upload/up-123")
        #expect(transport.executedRequests.last?.url.path == "/doc-ai/v1/job/upload")

        // 2. Status
        let statusJson = """
        {
            "job_id": "job-1",
            "status": "pending",
            "pipeline": "digitise",
            "created_at": "2026-01-01T00:00:00Z",
            "updated_at": "2026-01-01T00:00:00Z"
        }
        """
        transport.queueResponse(HTTPResponse(statusCode: 200, headers: [:], body: Data(statusJson.utf8)))
        let statusResp = try await client.docAi.getStatus(jobId: "job-1")
        #expect(statusResp.status == "pending")
        #expect(transport.executedRequests.last?.url.path == "/doc-ai/v1/job/job-1/status")

        // 3. Results
        let resultsJson = """
        {"extracted_text":"Sample document text"}
        """
        transport.queueResponse(HTTPResponse(statusCode: 200, headers: [:], body: Data(resultsJson.utf8)))
        let resultsResp = try await client.docAi.getResults(jobId: "job-1", format: "json")
        #expect(resultsResp.rawBody.contains("Sample document text"))
        #expect(transport.executedRequests.last?.url.path == "/doc-ai/v1/job/job-1/results")

        // 4. Download URL
        let downloadJson = """
        {
            "method": "GET",
            "url": "https://storage.sarvam.ai/download/result.zip",
            "expires_at": "2026-01-01T00:00:00Z"
        }
        """
        transport.queueResponse(HTTPResponse(statusCode: 200, headers: [:], body: Data(downloadJson.utf8)))
        let downloadResp = try await client.docAi.getDownloadUrl(jobId: "job-1")
        #expect(downloadResp.url == "https://storage.sarvam.ai/download/result.zip")
        #expect(transport.executedRequests.last?.url.path == "/doc-ai/v1/job/job-1/download-url")
    }

    @Test("digitiseAndWait and extractAndWait poll until completed")
    func testDigitiseAndWait() async throws {
        let transport = MockHTTPTransport()
        let clock = MockClockProvider(initialEpochMs: 1_000_000)
        let client = makeClient(transport: transport, clock: clock)

        // Response 1: digitise start
        transport.queueResponse(HTTPResponse(statusCode: 200, headers: [:], body: Data("{\"job_id\":\"job-poll-1\",\"status\":\"pending\",\"run_id\":\"run-poll-1\"}".utf8)))
        // Response 2: getStatus -> in_progress
        transport.queueResponse(HTTPResponse(statusCode: 200, headers: [:], body: Data("{\"job_id\":\"job-poll-1\",\"status\":\"in_progress\",\"pipeline\":\"digitise\",\"created_at\":\"2026-01-01T00:00:00Z\",\"updated_at\":\"2026-01-01T00:00:00Z\"}".utf8)))
        // Response 3: getStatus -> completed
        transport.queueResponse(HTTPResponse(statusCode: 200, headers: [:], body: Data("{\"job_id\":\"job-poll-1\",\"status\":\"completed\",\"pipeline\":\"digitise\",\"created_at\":\"2026-01-01T00:00:00Z\",\"updated_at\":\"2026-01-01T00:00:00Z\"}".utf8)))

        let file = FileInput(data: Data([1]), fileName: "test.pdf")
        let finalStatus = try await client.docAi.digitiseAndWait(
            file: file,
            pollingOptions: PollingOptions(pollInterval: 0.1, timeoutInterval: 5.0)
        )

        #expect(finalStatus.status == "completed")
        #expect(finalStatus.jobId == "job-poll-1")
    }
}
