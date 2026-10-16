import Foundation
import Testing
@testable import Sarvam

@Suite("DocumentTranslationResource Unit Tests")
struct DocumentTranslationResourceTests {
    private func makeClient(transport: MockHTTPTransport, clock: MockClockProvider = MockClockProvider()) -> SarvamClient {
        SarvamClient(
            authProvider: ApiKeyAuth(apiKey: "test-api-key"),
            transport: transport,
            clock: clock
        )
    }

    @Test("create, start, live status, trigger export, export status, and waitUntilComplete")
    func testDocumentTranslationWorkflow() async throws {
        let transport = MockHTTPTransport()
        let clock = MockClockProvider(initialEpochMs: 1_000_000)
        let client = makeClient(transport: transport, clock: clock)

        // 1. Create
        let createJson = """
        {
            "job_id": "doc-tr-1",
            "upload_url": "https://storage.sarvam.ai/upload/doc-tr-1",
            "source_language_code": "en-IN",
            "target_language_codes": ["hi-IN", "te-IN"]
        }
        """
        transport.queueResponse(HTTPResponse(statusCode: 200, headers: [:], body: Data(createJson.utf8)))
        let createResp = try await client.documentTranslation.create(
            DocumentTranslationCreateRequest(
                sourceLanguageCode: .enIn,
                targetLanguageCodes: [.hiIn, .teIn],
                originalFilename: "contract.pdf"
            )
        )
        #expect(createResp.jobId == "doc-tr-1")
        #expect(transport.executedRequests.last?.url.path == "/translate/document/jobs")

        // 2. Start
        let startJson = """
        {
            "job_id": "doc-tr-1",
            "job_state": "started"
        }
        """
        transport.queueResponse(HTTPResponse(statusCode: 200, headers: [:], body: Data(startJson.utf8)))
        let startResp = try await client.documentTranslation.start(jobId: "doc-tr-1")
        #expect(startResp.jobId == "doc-tr-1")
        #expect(startResp.jobState == "started")
        #expect(transport.executedRequests.last?.url.path == "/translate/document/jobs/doc-tr-1/start")

        // 3. Live status
        let liveStatusJson = """
        {
            "job_id": "doc-tr-1",
            "job_name": "Contract Translation",
            "job_state": "in_progress",
            "source_language_code": "en-IN",
            "progress": 75,
            "created_at": "2026-01-01T00:00:00Z",
            "updated_at": "2026-01-01T00:00:00Z"
        }
        """
        transport.queueResponse(HTTPResponse(statusCode: 200, headers: [:], body: Data(liveStatusJson.utf8)))
        let statusResp = try await client.documentTranslation.getLiveStatus(jobId: "doc-tr-1")
        #expect(statusResp.jobState == "in_progress")
        #expect(statusResp.progress == 75)
        #expect(transport.executedRequests.last?.url.path == "/translate/document/jobs/doc-tr-1/live-status")

        // 4. Trigger export
        let exportJson = """
        {
            "export_id": "exp-1",
            "job_id": "doc-tr-1",
            "target_language_code": "hi-IN",
            "format": "pdf",
            "export_state": "ready",
            "download_url": "https://storage.sarvam.ai/download/contract_hi.pdf",
            "created_at": "2026-01-01T00:00:00Z"
        }
        """
        transport.queueResponse(HTTPResponse(statusCode: 200, headers: [:], body: Data(exportJson.utf8)))
        let exportResp = try await client.documentTranslation.triggerExport(
            jobId: "doc-tr-1",
            request: DocumentTranslationExportRequest(lang: .hiIn, format: "pdf")
        )
        #expect(exportResp.exportId == "exp-1")
        #expect(transport.executedRequests.last?.url.path == "/translate/document/jobs/doc-tr-1/export")
        #expect(transport.executedRequests.last?.url.query?.contains("lang=hi-IN") == true)

        // 5. Get export status
        transport.queueResponse(HTTPResponse(statusCode: 200, headers: [:], body: Data(exportJson.utf8)))
        let exportStatusResp = try await client.documentTranslation.getExportStatus(jobId: "doc-tr-1", lang: .hiIn, exportId: "exp-1")
        #expect(exportStatusResp.exportId == "exp-1")
        #expect(transport.executedRequests.last?.url.path == "/translate/document/jobs/doc-tr-1/export/status")

        // 6. Polling: waitUntilComplete
        transport.queueResponse(HTTPResponse(statusCode: 200, headers: [:], body: Data("{\"job_id\":\"doc-tr-1\",\"job_name\":\"Contract\",\"job_state\":\"InProgress\",\"source_language_code\":\"en-IN\",\"progress\":50,\"created_at\":\"2026-01-01T00:00:00Z\",\"updated_at\":\"2026-01-01T00:00:00Z\"}".utf8)))
        transport.queueResponse(HTTPResponse(statusCode: 200, headers: [:], body: Data("{\"job_id\":\"doc-tr-1\",\"job_name\":\"Contract\",\"job_state\":\"Completed\",\"source_language_code\":\"en-IN\",\"progress\":100,\"created_at\":\"2026-01-01T00:00:00Z\",\"updated_at\":\"2026-01-01T00:00:00Z\"}".utf8)))

        let completed = try await client.documentTranslation.waitUntilComplete(
            jobId: "doc-tr-1",
            pollingOptions: PollingOptions(pollInterval: 0.1, timeoutInterval: 5.0)
        )
        #expect(completed.jobState == "Completed")
    }
}
