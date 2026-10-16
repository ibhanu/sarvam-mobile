import Foundation
import Testing
@testable import Sarvam

@Suite("DubbingResource Unit Tests")
struct DubbingResourceTests {
    private func makeClient(transport: MockHTTPTransport, clock: MockClockProvider = MockClockProvider()) -> SarvamClient {
        SarvamClient(
            authProvider: ApiKeyAuth(apiKey: "test-api-key"),
            transport: transport,
            clock: clock
        )
    }

    @Test("create maps sourceLanguageCode to src_lang and targetLanguageCodes to target_langs, routing to dubbing host")
    func testDubbingCreate() async throws {
        let transport = MockHTTPTransport()
        let json = """
        {
            "status": "success",
            "message": "Job created",
            "data": {
                "job_id": "dub-job-99",
                "upload_url": "https://storage.sarvam.ai/upload/dub-job-99"
            }
        }
        """
        transport.queueResponse(HTTPResponse(statusCode: 200, headers: [:], body: Data(json.utf8)))
        let client = makeClient(transport: transport)

        let req = DubbingCreateRequest(
            sourceLanguageCode: .enIn,
            targetLanguageCodes: [.hiIn, .mrIn],
            jobName: "Dubbing Demo Video"
        )
        let resp = try await client.dubbing.create(req)

        #expect(resp.data?.jobId == "dub-job-99")

        let executed = transport.executedRequests.first
        #expect(executed?.method == .post)

        // Verifies routing to EnvironmentHost.dubbing (api.sarvam.ai/dubbing/jobs or configured dubbingBaseUrl)
        #expect(executed?.url.absoluteString.contains("/jobs") == true)
        #expect(executed?.url.absoluteString == "\(client.config.environment.dubbingBaseUrl)/jobs")

        // Verifies mapping of sourceLanguageCode -> src_lang and targetLanguageCodes -> target_langs in JSON body
        let bodyString = String(data: executed?.body ?? Data(), encoding: .utf8) ?? ""
        #expect(bodyString.contains("\"src_lang\":\"en-IN\""))
        #expect(bodyString.contains("\"target_langs\":[\"hi-IN\",\"mr-IN\"]"))
    }

    @Test("start, live status, export status, and waitUntilComplete on dubbing host")
    func testDubbingWorkflow() async throws {
        let transport = MockHTTPTransport()
        let clock = MockClockProvider(initialEpochMs: 1_000_000)
        let client = makeClient(transport: transport, clock: clock)

        // 1. Start
        let startJson = """
        {
            "status": "success",
            "message": "Started"
        }
        """
        transport.queueResponse(HTTPResponse(statusCode: 200, headers: [:], body: Data(startJson.utf8)))
        let startResp = try await client.dubbing.start(jobId: "dub-job-99")
        #expect(startResp.status == "success")
        #expect(transport.executedRequests.last?.url.absoluteString == "\(client.config.environment.dubbingBaseUrl)/jobs/dub-job-99/start")

        // 2. Live status
        let liveStatusJson = """
        {
            "status": "success",
            "message": "",
            "data": {
                "job_id": "dub-job-99",
                "status": "processing",
                "progress": 60
            }
        }
        """
        transport.queueResponse(HTTPResponse(statusCode: 200, headers: [:], body: Data(liveStatusJson.utf8)))
        let liveResp = try await client.dubbing.getLiveStatus(jobId: "dub-job-99")
        #expect(liveResp.data.status == "processing")
        #expect(liveResp.data.progress == 60)
        #expect(transport.executedRequests.last?.url.absoluteString == "\(client.config.environment.dubbingBaseUrl)/jobs/dub-job-99/live-status")

        // 3. Export status
        let exportStatusJson = """
        {
            "status": "completed",
            "message": "Export completed"
        }
        """
        transport.queueResponse(HTTPResponse(statusCode: 200, headers: [:], body: Data(exportStatusJson.utf8)))
        let exportResp = try await client.dubbing.getExportStatus(jobId: "dub-job-99", limit: 5)
        #expect(exportResp.status == "completed")
        #expect(transport.executedRequests.last?.url.absoluteString.contains("/jobs/dub-job-99/export-status?limit=5") == true)

        // 4. Polling: waitUntilComplete
        transport.queueResponse(HTTPResponse(statusCode: 200, headers: [:], body: Data("{\"status\":\"success\",\"message\":\"\",\"data\":{\"job_id\":\"dub-job-99\",\"status\":\"processing\",\"progress\":80}}".utf8)))
        transport.queueResponse(HTTPResponse(statusCode: 200, headers: [:], body: Data("{\"status\":\"success\",\"message\":\"\",\"data\":{\"job_id\":\"dub-job-99\",\"status\":\"completed\",\"progress\":100}}".utf8)))

        let completed = try await client.dubbing.waitUntilComplete(
            jobId: "dub-job-99",
            pollingOptions: PollingOptions(pollInterval: 0.1, timeoutInterval: 5.0)
        )
        #expect(completed.data.status == "completed")
    }
}
