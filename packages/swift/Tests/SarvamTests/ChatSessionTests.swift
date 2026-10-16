import Foundation
import Testing
@testable import Sarvam

@Suite("ChatSession Affinity Tests")
struct ChatSessionTests {

    @Test("ChatSession injects constant x-session-affinity UUID across requests")
    func testChatSessionAffinity() async throws {
        let mock = MockHTTPTransport()
        let respJson = """
        {"id":"chatcmpl-1","choices":[{"index":0,"message":{"role":"assistant","content":"Response"}}]}
        """
        mock.queueResponse(HTTPResponse(statusCode: 200, headers: ["content-type": "application/json"], body: respJson.data(using: .utf8)!))
        mock.queueResponse(HTTPResponse(statusCode: 200, headers: ["content-type": "application/json"], body: respJson.data(using: .utf8)!))

        let client = SarvamClient(
            apiKey: "test-api-key",
            transport: mock
        )

        let session = client.chat.createSession(affinityId: "affinity-fixed-1234")
        #expect(session.affinityId == "affinity-fixed-1234")

        let req1 = ChatCompletionRequest(
            model: ChatModel(rawValue: "sarvam-2b"),
            messages: [ChatMessage(role: "user", content: "Turn 1")]
        )
        _ = try await session.completions(req1)

        let req2 = ChatCompletionRequest(
            model: ChatModel(rawValue: "sarvam-2b"),
            messages: [
                ChatMessage(role: "user", content: "Turn 1"),
                ChatMessage(role: "assistant", content: "Response"),
                ChatMessage(role: "user", content: "Turn 2")
            ]
        )
        _ = try await session.completions(req2)

        #expect(mock.executedRequests.count == 2)
        #expect(mock.executedRequests[0].headers["x-session-affinity"] == "affinity-fixed-1234")
        #expect(mock.executedRequests[1].headers["x-session-affinity"] == "affinity-fixed-1234")
    }
}
