import Foundation
import Testing
@testable import Sarvam

@Suite("PronunciationDictionaryResource Unit Tests")
struct PronunciationDictionaryResourceTests {
    private func makeClient(transport: MockHTTPTransport) -> SarvamClient {
        SarvamClient(
            authProvider: ApiKeyAuth(apiKey: "test-api-key"),
            transport: transport
        )
    }

    @Test("list dictionaries makes GET /text-to-speech/pronunciation-dictionary")
    func testListDictionaries() async throws {
        let transport = MockHTTPTransport()
        let json = """
        {
            "dictionary_count": 2,
            "dictionaries": ["dict-1", "dict-2"]
        }
        """
        transport.queueResponse(HTTPResponse(statusCode: 200, headers: [:], body: Data(json.utf8)))
        let client = makeClient(transport: transport)

        let resp = try await client.pronunciationDictionary.list()
        #expect(resp.dictionaryCount == 2)
        #expect(resp.dictionaries == ["dict-1", "dict-2"])
        #expect(transport.executedRequests.first?.url.path == "/text-to-speech/pronunciation-dictionary")
    }

    @Test("create dictionary makes POST with multipart file")
    func testCreateDictionary() async throws {
        let transport = MockHTTPTransport()
        let json = """
        {
            "dictionary_id": "dict-new"
        }
        """
        transport.queueResponse(HTTPResponse(statusCode: 200, headers: [:], body: Data(json.utf8)))
        let client = makeClient(transport: transport)

        let file = FileInput(data: Data("{\"hello\":\"namaste\"}".utf8), fileName: "dict.json", mimeType: "application/json")
        let resp = try await client.pronunciationDictionary.create(file: file)

        #expect(resp.dictionaryId == "dict-new")
        let req = transport.executedRequests.first
        #expect(req?.method == .post)
        #expect(req?.url.path == "/text-to-speech/pronunciation-dictionary")
        #expect(req?.headers["content-type"]?.contains("multipart/form-data") == true)
    }

    @Test("update dictionary makes PUT with query dict_id")
    func testUpdateDictionary() async throws {
        let transport = MockHTTPTransport()
        let json = """
        {
            "dictionary_id": "dict-1",
            "updated_pronunciations": {
                "Sarvam": {"phoneme": "sar-vum"}
            }
        }
        """
        transport.queueResponse(HTTPResponse(statusCode: 200, headers: [:], body: Data(json.utf8)))
        let client = makeClient(transport: transport)

        let file = FileInput(data: Data("word,phoneme".utf8), fileName: "dict.csv", mimeType: "text/csv")
        let resp = try await client.pronunciationDictionary.update(dictId: "dict-1", file: file)

        #expect(resp.dictionaryId == "dict-1")
        #expect(resp.updatedPronunciations["Sarvam"] != nil)
        let req = transport.executedRequests.first
        #expect(req?.method == .put)
        #expect(req?.url.path == "/text-to-speech/pronunciation-dictionary")
        #expect(req?.url.query?.contains("dict_id=dict-1") == true)
    }

    @Test("get dictionary makes GET /text-to-speech/pronunciation-dictionary/{dict_id}")
    func testGetDictionary() async throws {
        let transport = MockHTTPTransport()
        let json = """
        {
            "pronunciations": {
                "Sarvam": {"phoneme": "sar-vum"}
            }
        }
        """
        transport.queueResponse(HTTPResponse(statusCode: 200, headers: [:], body: Data(json.utf8)))
        let client = makeClient(transport: transport)

        let resp = try await client.pronunciationDictionary.get(dictId: "dict-1")
        #expect(resp.pronunciations["Sarvam"] != nil)
        #expect(transport.executedRequests.first?.url.path == "/text-to-speech/pronunciation-dictionary/dict-1")
    }

    @Test("delete dictionary makes DELETE /text-to-speech/pronunciation-dictionary?dict_id={dict_id}")
    func testDeleteDictionary() async throws {
        let transport = MockHTTPTransport()
        let json = """
        {
            "success": true,
            "message": "Dictionary deleted"
        }
        """
        transport.queueResponse(HTTPResponse(statusCode: 200, headers: [:], body: Data(json.utf8)))
        let client = makeClient(transport: transport)

        let resp = try await client.pronunciationDictionary.delete(dictId: "dict-1")
        #expect(resp.success == true)
        #expect(resp.message == "Dictionary deleted")
        let req = transport.executedRequests.first
        #expect(req?.method == .delete)
        #expect(req?.url.path == "/text-to-speech/pronunciation-dictionary")
        #expect(req?.url.query?.contains("dict_id=dict-1") == true)
    }
}
