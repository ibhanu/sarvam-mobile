import Foundation
import Testing
@testable import Sarvam

@Suite("VoiceCloningResource Unit Tests")
struct VoiceCloningResourceTests {
    private func makeClient(transport: MockHTTPTransport, wsFactory: MockWebSocketFactory = MockWebSocketFactory()) -> SarvamClient {
        SarvamClient(
            authProvider: ApiKeyAuth(apiKey: "test-api-key"),
            transport: transport,
            webSocketFactory: wsFactory
        )
    }

    @Test("listVoices makes GET /voices and decodes list response")
    func testListVoices() async throws {
        let transport = MockHTTPTransport()
        let json = """
        {
            "status": "success",
            "data": {
                "voices": [
                    {
                        "id": "v-1",
                        "name": "Asha",
                        "language": "hi-IN",
                        "style": "conversational",
                        "gender": "female",
                        "status": "active"
                    }
                ],
                "total": 1
            }
        }
        """
        transport.queueResponse(HTTPResponse(statusCode: 200, headers: [:], body: Data(json.utf8)))
        let client = makeClient(transport: transport)

        let resp = try await client.voiceCloning.listVoices()
        #expect(resp.data.total == 1)
        #expect(resp.data.voices.first?.id == "v-1")
        #expect(resp.data.voices.first?.name == "Asha")

        let req = transport.executedRequests.first
        #expect(req?.method == .get)
        #expect(req?.url.path == "/voices")
    }

    @Test("createVoice sends multipart form and decodes create response")
    func testCreateVoice() async throws {
        let transport = MockHTTPTransport()
        let json = """
        {
            "status": "success",
            "data": {
                "voice_id": "v-new-123",
                "status": "ready"
            }
        }
        """
        transport.queueResponse(HTTPResponse(statusCode: 200, headers: [:], body: Data(json.utf8)))
        let client = makeClient(transport: transport)

        let fileInput = FileInput(data: Data([1, 2, 3, 4]), fileName: "audio.wav", mimeType: "audio/wav")
        let resp = try await client.voiceCloning.createVoice(
            file: fileInput,
            name: "New Voice",
            language: "hi-IN",
            style: "expressive",
            gender: "female"
        )

        #expect(resp.data.voiceId == "v-new-123")
        #expect(resp.data.status == "ready")

        let req = transport.executedRequests.first
        #expect(req?.method == .post)
        #expect(req?.url.path == "/voices/create")
        #expect(req?.headers["content-type"]?.contains("multipart/form-data") == true)
    }

    @Test("getVoice makes GET /voices/{voice_id}")
    func testGetVoice() async throws {
        let transport = MockHTTPTransport()
        let json = """
        {
            "status": "success",
            "data": {
                "id": "v-123",
                "name": "My Voice",
                "language": "bn-IN",
                "status": "active"
            }
        }
        """
        transport.queueResponse(HTTPResponse(statusCode: 200, headers: [:], body: Data(json.utf8)))
        let client = makeClient(transport: transport)

        let resp = try await client.voiceCloning.getVoice(voiceId: "v-123")
        #expect(resp.data.id == "v-123")
        #expect(resp.data.name == "My Voice")
        #expect(transport.executedRequests.first?.url.path == "/voices/v-123")
    }

    @Test("deleteVoice makes DELETE /voices/delete/{voice_id}")
    func testDeleteVoice() async throws {
        let transport = MockHTTPTransport()
        transport.queueResponse(HTTPResponse(statusCode: 200, headers: [:], body: Data("{}".utf8)))
        let client = makeClient(transport: transport)

        _ = try await client.voiceCloning.deleteVoice(voiceId: "v-123")
        #expect(transport.executedRequests.first?.method == .delete)
        #expect(transport.executedRequests.first?.url.path == "/voices/delete/v-123")
    }

    @Test("convert decodes audioBytes from Base64 root audio")
    func testConvertAudioBytes() async throws {
        let transport = MockHTTPTransport()
        let rawAudio = Data([0xDE, 0xAD, 0xBE, 0xEF])
        let b64 = rawAudio.base64EncodedString()
        let json = """
        {
            "audio": "\(b64)",
            "request_id": "req-vc-1",
            "audio_duration": 1.5
        }
        """
        transport.queueResponse(HTTPResponse(statusCode: 200, headers: [:], body: Data(json.utf8)))
        let client = makeClient(transport: transport)

        let req = VoiceCloneRequest(
            text: "Hello world",
            languageCode: .hiIn,
            voiceId: "v-123"
        )
        let resp = try await client.voiceCloning.convert(req)
        #expect(resp.requestId == "req-vc-1")
        #expect(resp.audioDuration == 1.5)
        #expect(resp.audioBytes == rawAudio)
    }

    @Test("stream returns AsyncThrowingStream of binary audio chunks")
    func testStreamAudio() async throws {
        let transport = MockHTTPTransport()
        let chunk1 = Data([1, 2, 3])
        let chunk2 = Data([4, 5, 6])
        transport.queueStreamResponse(chunks: [chunk1, chunk2])
        let client = makeClient(transport: transport)

        let req = VoiceCloneRequest(
            text: "Streaming test",
            languageCode: .enIn,
            voiceId: "v-456"
        )
        let stream = client.voiceCloning.stream(req)

        var received: [Data] = []
        for try await chunk in stream {
            received.append(chunk)
        }

        #expect(received == [chunk1, chunk2])
        #expect(transport.executedRequests.first?.url.path == "/voices/clone/stream")
    }

    @Test("connect connects to /voices/clone/ws?send_completion_event=true")
    func testConnectVoiceCloningWs() async throws {
        let transport = MockHTTPTransport()
        let wsFactory = MockWebSocketFactory()
        let mockSocket = MockWebSocketSession()
        wsFactory.queueSession(mockSocket)

        let client = makeClient(transport: transport, wsFactory: wsFactory)
        _ = try await client.voiceCloning.connect()

        let connection = wsFactory.connections.first
        #expect(connection != nil)
        #expect(connection?.url.path == "/voices/clone/ws")
        #expect(connection?.url.query?.contains("send_completion_event=true") == true)
    }
}
