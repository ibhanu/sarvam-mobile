import Foundation
import Testing
@testable import Sarvam

final class MockURLProtocol: URLProtocol, @unchecked Sendable {
    typealias Handler = (URLRequest) throws -> (URLResponse, Data)
    nonisolated(unsafe) static var handler: Handler?

    override class func canInit(with request: URLRequest) -> Bool {
        true
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest {
        request
    }

    override func startLoading() {
        guard let handler = Self.handler else {
            client?.urlProtocol(self, didFailWithError: NSError(domain: NSURLErrorDomain, code: NSURLErrorUnknown, userInfo: nil))
            return
        }

        do {
            let (response, data) = try handler(request)
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            if !data.isEmpty {
                client?.urlProtocol(self, didLoad: data)
            }
            client?.urlProtocolDidFinishLoading(self)
        } catch {
            client?.urlProtocol(self, didFailWithError: error)
        }
    }

    override func stopLoading() {}
}

@Suite("URLSessionHTTPTransport Unit Tests", .serialized)
struct URLSessionHTTPTransportTests {
    private func makeTransport() -> (URLSessionHTTPTransport, URLSession) {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [MockURLProtocol.self]
        let session = URLSession(configuration: config)
        let transport = URLSessionHTTPTransport(session: session)
        return (transport, session)
    }

    @Test("execute returns valid HTTPResponse on 200 OK")
    func testExecuteSuccess() async throws {
        let (transport, _) = makeTransport()
        let expectedData = Data("{\"status\":\"ok\"}".utf8)
        let targetUrl = URL(string: "https://api.sarvam.ai/test")!

        MockURLProtocol.handler = { req in
            #expect(req.url == targetUrl)
            #expect(req.httpMethod == "POST")
            #expect(req.value(forHTTPHeaderField: "X-Test") == "Value")
            let resp = HTTPURLResponse(
                url: targetUrl,
                statusCode: 200,
                httpVersion: "HTTP/1.1",
                headerFields: ["Content-Type": "application/json", "X-Custom": "HeaderValue"]
            )!
            return (resp, expectedData)
        }

        let request = HTTPRequest(
            method: .post,
            url: targetUrl,
            headers: ["X-Test": "Value"],
            body: Data("input".utf8),
            operationKind: .statelessPost,
            timeoutInterval: 15.0
        )

        let response = try await transport.execute(request: request)
        #expect(response.statusCode == 200)
        #expect(response.body == expectedData)
        #expect(response.headers["Content-Type"] == "application/json" || response.headers["content-type"] == "application/json")
    }

    @Test("execute throws SarvamError.connectionError on non-HTTP response")
    func testExecuteNonHTTPResponse() async throws {
        let (transport, _) = makeTransport()
        let targetUrl = URL(string: "https://api.sarvam.ai/test")!

        MockURLProtocol.handler = { req in
            let resp = URLResponse(url: req.url!, mimeType: nil, expectedContentLength: 0, textEncodingName: nil)
            return (resp, Data())
        }

        let request = HTTPRequest(method: .get, url: targetUrl)
        await #expect(throws: SarvamError.self) {
            _ = try await transport.execute(request: request)
        }
    }

    @Test("execute maps NSURLErrorTimedOut to SarvamError.timeoutError")
    func testExecuteTimeout() async throws {
        let (transport, _) = makeTransport()
        let targetUrl = URL(string: "https://api.sarvam.ai/test")!

        MockURLProtocol.handler = { _ in
            throw NSError(domain: NSURLErrorDomain, code: NSURLErrorTimedOut, userInfo: [NSLocalizedDescriptionKey: "timed out"])
        }

        let request = HTTPRequest(method: .get, url: targetUrl)
        do {
            _ = try await transport.execute(request: request)
            #expect(Bool(false), "Should have thrown")
        } catch let SarvamError.timeoutError(phase, msg) {
            #expect(phase == .total)
            #expect(msg.contains("timed out"))
        } catch {
            #expect(Bool(false), "Unexpected error: \(error)")
        }
    }

    @Test("execute maps connection failure error codes to connectionError")
    func testExecuteConnectionFailures() async throws {
        let (transport, _) = makeTransport()
        let targetUrl = URL(string: "https://api.sarvam.ai/test")!

        let connectionCodes = [
            NSURLErrorCannotConnectToHost,
            NSURLErrorNetworkConnectionLost,
            NSURLErrorDNSLookupFailed,
            NSURLErrorSecureConnectionFailed,
            NSURLErrorNotConnectedToInternet
        ]

        for code in connectionCodes {
            MockURLProtocol.handler = { _ in
                throw NSError(domain: NSURLErrorDomain, code: code, userInfo: [NSLocalizedDescriptionKey: "connection failed"])
            }

            let request = HTTPRequest(method: .get, url: targetUrl)
            do {
                _ = try await transport.execute(request: request)
                #expect(Bool(false), "Should have thrown for code \(code)")
            } catch let SarvamError.connectionError(msg, cause) {
                #expect(msg.contains("connection failed") || msg.contains("Network connection failure"))
                #expect(cause != nil)
            } catch {
                #expect(Bool(false), "Unexpected error for code \(code): \(error)")
            }
        }
    }

    @Test("executeStream streams chunks correctly with buffer >= 4096 and remainder")
    func testExecuteStreamSuccess() async throws {
        let (transport, _) = makeTransport()
        let targetUrl = URL(string: "https://api.sarvam.ai/stream")!
        // 5000 bytes so > 4096 bytes chunking branch is exercised
        var bigData = Data()
        for i in 0..<5000 {
            bigData.append(UInt8(i % 256))
        }

        MockURLProtocol.handler = { req in
            let resp = HTTPURLResponse(
                url: targetUrl,
                statusCode: 200,
                httpVersion: "HTTP/1.1",
                headerFields: ["Content-Type": "application/octet-stream"]
            )!
            return (resp, bigData)
        }

        let request = HTTPRequest(method: .get, url: targetUrl)
        let (response, stream) = try await transport.executeStream(request: request)
        #expect(response.statusCode == 200)

        var receivedData = Data()
        for try await chunk in stream {
            receivedData.append(chunk)
        }
        #expect(receivedData == bigData)
        #expect(receivedData.count == 5000)
    }

    @Test("executeStream throws connectionError on non-HTTP response")
    func testExecuteStreamNonHTTP() async throws {
        let (transport, _) = makeTransport()
        let targetUrl = URL(string: "https://api.sarvam.ai/stream")!

        MockURLProtocol.handler = { req in
            let resp = URLResponse(url: req.url!, mimeType: nil, expectedContentLength: 0, textEncodingName: nil)
            return (resp, Data())
        }

        let request = HTTPRequest(method: .get, url: targetUrl)
        await #expect(throws: SarvamError.self) {
            _ = try await transport.executeStream(request: request)
        }
    }

    @Test("executeStream handles error in URLRequest execution")
    func testExecuteStreamURLError() async throws {
        let (transport, _) = makeTransport()
        let targetUrl = URL(string: "https://api.sarvam.ai/stream")!

        MockURLProtocol.handler = { _ in
            throw NSError(domain: NSURLErrorDomain, code: NSURLErrorTimedOut, userInfo: [NSLocalizedDescriptionKey: "timeout"])
        }

        let request = HTTPRequest(method: .get, url: targetUrl)
        await #expect(throws: SarvamError.self) {
            _ = try await transport.executeStream(request: request)
        }
    }

    @Test("URLSessionHTTPTransport default init")
    func testDefaultInit() {
        let transport = URLSessionHTTPTransport()
        _ = transport
    }
}
