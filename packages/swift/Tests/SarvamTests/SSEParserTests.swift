import Foundation
import Testing
@testable import Sarvam

@Suite("SSE Parser Edge Case Tests")
struct SSEParserTests {

    @Test("SSEParser handles multiline data fields concatenated with newlines")
    func testMultilineData() async throws {
        let raw = "event: message\ndata: line 1\ndata: line 2\ndata: line 3\n\n"
        let stream = AsyncThrowingStream<Data, Error> { continuation in
            continuation.yield(raw.data(using: .utf8)!)
            continuation.finish()
        }

        let parsedStream = SSEParser.parse(byteStream: stream)
        var events: [SSEEvent] = []
        for try await evt in parsedStream {
            events.append(evt)
        }

        #expect(events.count == 1)
        #expect(events[0].event == "message")
        #expect(events[0].data == "line 1\nline 2\nline 3")
    }

    @Test("SSEParser splits across arbitrary chunk boundaries")
    func testChunkBoundaries() async throws {
        let part1 = "event: upd"
        let part2 = "ate\ndata: {\"key\":"
        let part3 = " \"val\"}\n\n"

        let stream = AsyncThrowingStream<Data, Error> { continuation in
            continuation.yield(part1.data(using: .utf8)!)
            continuation.yield(part2.data(using: .utf8)!)
            continuation.yield(part3.data(using: .utf8)!)
            continuation.finish()
        }

        let parsedStream = SSEParser.parse(byteStream: stream)
        var events: [SSEEvent] = []
        for try await evt in parsedStream {
            events.append(evt)
        }

        #expect(events.count == 1)
        #expect(events[0].event == "update")
        #expect(events[0].data == "{\"key\": \"val\"}")
    }

    @Test("SSEParser ignores comment lines starting with colon")
    func testCommentsIgnored() async throws {
        let raw = ": ping comment\nevent: ping\n: another comment\ndata: pong\n\n"
        let stream = AsyncThrowingStream<Data, Error> { continuation in
            continuation.yield(raw.data(using: .utf8)!)
            continuation.finish()
        }

        let parsedStream = SSEParser.parse(byteStream: stream)
        var events: [SSEEvent] = []
        for try await evt in parsedStream {
            events.append(evt)
        }

        #expect(events.count == 1)
        #expect(events[0].event == "ping")
        #expect(events[0].data == "pong")
    }

    @Test("SSEParser handles CRLF, id, retry, EOF remaining buffer, and stream errors")
    func testSseAdvancedEdgeCases() async throws {
        // 1. CRLF + id + retry + trailing EOF block without double newline
        let raw = "id: 42\r\nretry: 1500\r\nevent: first\r\ndata: one\r\n\r\n: only-comment\r\n\r\nevent: trailing\ndata: two"
        let stream1 = AsyncThrowingStream<Data, Error> { continuation in
            continuation.yield(Data(raw.utf8))
            continuation.finish()
        }
        var events1: [SSEEvent] = []
        for try await evt in SSEParser.parse(byteStream: stream1) {
            events1.append(evt)
        }
        #expect(events1.count == 2)
        #expect(events1[0].id == "42")
        #expect(events1[0].retry == 1500)
        #expect(events1[0].data == "one")
        #expect(events1[1].event == "trailing")
        #expect(events1[1].data == "two")

        // 2. Trailing [DONE] on EOF without double newline
        let streamDone = AsyncThrowingStream<Data, Error> { continuation in
            continuation.yield(Data("data: [DONE]".utf8))
            continuation.finish()
        }
        var eventsDone: [SSEEvent] = []
        for try await evt in SSEParser.parse(byteStream: streamDone) {
            eventsDone.append(evt)
        }
        #expect(eventsDone.isEmpty)

        // 3. Trailing customTermination on EOF without double newline
        let streamCustom = AsyncThrowingStream<Data, Error> { continuation in
            continuation.yield(Data("event: response.completed\ndata: ok".utf8))
            continuation.finish()
        }
        var eventsCustom: [SSEEvent] = []
        for try await evt in SSEParser.parse(byteStream: streamCustom, customTermination: { $0.event == "response.completed" }) {
            eventsCustom.append(evt)
        }
        #expect(eventsCustom.count == 1)

        // 4. Stream throwing error propagates
        let streamErr = AsyncThrowingStream<Data, Error> { continuation in
            continuation.finish(throwing: SarvamError.connectionError(message: "broken pipe"))
        }
        await #expect(throws: SarvamError.self) {
            for try await _ in SSEParser.parse(byteStream: streamErr) {}
        }
    }
}
