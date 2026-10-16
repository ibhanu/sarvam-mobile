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
}
