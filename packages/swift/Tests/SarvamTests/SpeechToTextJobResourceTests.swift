import Foundation
import Testing
@testable import Sarvam

@Suite("SpeechToTextJob Resources Unit Tests")
struct SpeechToTextJobResourceTests {
    private func makeClient(transport: MockHTTPTransport, clock: MockClockProvider = MockClockProvider()) -> SarvamClient {
        SarvamClient(
            authProvider: ApiKeyAuth(apiKey: "test-api-key"),
            transport: transport,
            clock: clock
        )
    }

    @Test("STT Job initialise, upload links, start, status, download links, and waitUntilComplete")
    func testSttJobWorkflow() async throws {
        let transport = MockHTTPTransport()
        let clock = MockClockProvider(initialEpochMs: 1_000_000)
        let client = makeClient(transport: transport, clock: clock)

        // 1. Initialise
        let initJson = """
        {
            "job_id": "stt-job-1",
            "job_state": "created"
        }
        """
        transport.queueResponse(HTTPResponse(statusCode: 200, headers: [:], body: Data(initJson.utf8)))
        let initResp = try await client.speechToTextJob.initialise(SpeechToTextJobInitRequest(jobParameters: SpeechToTextJobParameters()))
        #expect(initResp.jobId == "stt-job-1")
        #expect(transport.executedRequests.last?.url.path == "/speech-to-text/job/v1")

        // 2. Upload Links
        let uploadJson = """
        {
            "job_id": "stt-job-1",
            "job_state": "pending",
            "upload_urls": {"file1.wav": {"file_url": "https://storage.sarvam.ai/upload/file1.wav"}}
        }
        """
        transport.queueResponse(HTTPResponse(statusCode: 200, headers: [:], body: Data(uploadJson.utf8)))
        let uploadResp = try await client.speechToTextJob.getUploadLinks(FilesRequest(jobId: "stt-job-1", files: ["file1.wav"]))
        #expect(uploadResp.jobId == "stt-job-1")
        #expect(uploadResp.uploadUrls["file1.wav"] != nil)
        #expect(transport.executedRequests.last?.url.path == "/speech-to-text/job/v1/upload-files")

        // 3. Start
        let startJson = """
        {
            "job_id": "stt-job-1",
            "job_state": "in_progress",
            "total_files": 1,
            "successful_files": 0,
            "failed_files": 0
        }
        """
        transport.queueResponse(HTTPResponse(statusCode: 200, headers: [:], body: Data(startJson.utf8)))
        let startResp = try await client.speechToTextJob.start(jobId: "stt-job-1")
        #expect(startResp.jobState == "in_progress")
        #expect(transport.executedRequests.last?.url.path == "/speech-to-text/job/v1/stt-job-1/start")

        // 4. Status
        let statusJson = """
        {
            "job_id": "stt-job-1",
            "job_state": "completed",
            "total_files": 1,
            "successful_files": 1,
            "failed_files": 0
        }
        """
        transport.queueResponse(HTTPResponse(statusCode: 200, headers: [:], body: Data(statusJson.utf8)))
        let statusResp = try await client.speechToTextJob.getStatus(jobId: "stt-job-1")
        #expect(statusResp.jobState == "completed")
        #expect(transport.executedRequests.last?.url.path == "/speech-to-text/job/v1/stt-job-1/status")

        // 5. Download links
        let downloadJson = """
        {
            "job_id": "stt-job-1",
            "job_state": "completed",
            "download_urls": {"file1.json": {"file_url": "https://storage.sarvam.ai/download/file1.json"}}
        }
        """
        transport.queueResponse(HTTPResponse(statusCode: 200, headers: [:], body: Data(downloadJson.utf8)))
        let downloadResp = try await client.speechToTextJob.getDownloadLinks(FilesRequest(jobId: "stt-job-1", files: ["file1.json"]))
        #expect(downloadResp.downloadUrls["file1.json"] != nil)
        #expect(transport.executedRequests.last?.url.path == "/speech-to-text/job/v1/download-files")

        // 6. Polling: waitUntilComplete
        transport.queueResponse(HTTPResponse(statusCode: 200, headers: [:], body: Data("{\"job_id\":\"stt-job-1\",\"job_state\":\"in_progress\",\"total_files\":1,\"successful_files\":0,\"failed_files\":0}".utf8)))
        transport.queueResponse(HTTPResponse(statusCode: 200, headers: [:], body: Data("{\"job_id\":\"stt-job-1\",\"job_state\":\"completed\",\"total_files\":1,\"successful_files\":1,\"failed_files\":0}".utf8)))

        let polled = try await client.speechToTextJob.waitUntilComplete(
            jobId: "stt-job-1",
            pollingOptions: PollingOptions(pollInterval: 0.1, timeoutInterval: 5.0)
        )
        #expect(polled.jobState == "completed")
    }

    @Test("STT Translate Job initialise and status")
    func testSttTranslateJobWorkflow() async throws {
        let transport = MockHTTPTransport()
        let client = makeClient(transport: transport)

        // Initialise
        let initJson = """
        {
            "job_id": "stt-tr-job-1",
            "job_state": "created"
        }
        """
        transport.queueResponse(HTTPResponse(statusCode: 200, headers: [:], body: Data(initJson.utf8)))
        let initResp = try await client.speechToTextTranslateJob.initialise(SpeechToTextTranslateJobInitRequest(jobParameters: SpeechToTextTranslateJobParameters()))
        #expect(initResp.jobId == "stt-tr-job-1")
        #expect(transport.executedRequests.last?.url.path == "/speech-to-text-translate/job/v1")

        // Status
        let statusJson = """
        {
            "job_id": "stt-tr-job-1",
            "job_state": "completed",
            "total_files": 1,
            "successful_files": 1,
            "failed_files": 0
        }
        """
        transport.queueResponse(HTTPResponse(statusCode: 200, headers: [:], body: Data(statusJson.utf8)))
        let statusResp = try await client.speechToTextTranslateJob.getStatus(jobId: "stt-tr-job-1")
        #expect(statusResp.jobState == "completed")
        #expect(transport.executedRequests.last?.url.path == "/speech-to-text-translate/job/v1/stt-tr-job-1/status")
    }
}
