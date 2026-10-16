import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// Abstract low-level HTTP transport protocol.
public protocol HTTPTransport: Sendable {
    /// Executes a unary HTTP request.
    func execute(request: HTTPRequest) async throws -> HTTPResponse

    /// Executes an HTTP request returning a streaming response body.
    func executeStream(request: HTTPRequest) async throws -> (HTTPResponse, AsyncThrowingStream<Data, Error>)
}

/// Production HTTP transport using Apple's `URLSession`.
public final class URLSessionHTTPTransport: HTTPTransport, @unchecked Sendable {
    private let session: URLSession

    public init(session: URLSession = .shared) {
        self.session = session
    }

    public func execute(request: HTTPRequest) async throws -> HTTPResponse {
        let urlRequest = try buildURLRequest(from: request)

        do {
            let (data, response) = try await session.data(for: urlRequest)
            guard let httpResponse = response as? HTTPURLResponse else {
                throw SarvamError.connectionError(message: "Non-HTTP response received from server")
            }

            var headers: [String: String] = [:]
            for (key, value) in httpResponse.allHeaderFields {
                if let k = key as? String, let v = value as? String {
                    headers[k] = v
                }
            }

            return HTTPResponse(statusCode: httpResponse.statusCode, headers: headers, body: data)
        } catch is CancellationError {
            throw CancellationError()
        } catch let err as SarvamError {
            throw err
        } catch {
            throw mapURLError(error)
        }
    }

    public func executeStream(request: HTTPRequest) async throws -> (HTTPResponse, AsyncThrowingStream<Data, Error>) {
        let urlRequest = try buildURLRequest(from: request)

        do {
            let (bytes, response) = try await session.bytes(for: urlRequest)
            guard let httpResponse = response as? HTTPURLResponse else {
                throw SarvamError.connectionError(message: "Non-HTTP response received from server")
            }

            var headers: [String: String] = [:]
            for (key, value) in httpResponse.allHeaderFields {
                if let k = key as? String, let v = value as? String {
                    headers[k] = v
                }
            }

            let initialResponse = HTTPResponse(statusCode: httpResponse.statusCode, headers: headers, body: Data())

            let stream = AsyncThrowingStream<Data, Error> { continuation in
                let task = Task {
                    do {
                        var buffer = Data()
                        buffer.reserveCapacity(4096)
                        for try await byte in bytes {
                            buffer.append(byte)
                            if buffer.count >= 4096 {
                                continuation.yield(buffer)
                                buffer.removeAll(keepingCapacity: true)
                            }
                        }
                        if !buffer.isEmpty {
                            continuation.yield(buffer)
                        }
                        continuation.finish()
                    } catch is CancellationError {
                        continuation.finish(throwing: CancellationError())
                    } catch {
                        continuation.finish(throwing: self.mapURLError(error))
                    }
                }
                continuation.onTermination = { @Sendable _ in
                    task.cancel()
                }
            }

            return (initialResponse, stream)
        } catch is CancellationError {
            throw CancellationError()
        } catch let err as SarvamError {
            throw err
        } catch {
            throw mapURLError(error)
        }
    }

    private func buildURLRequest(from request: HTTPRequest) throws -> URLRequest {
        var urlRequest = URLRequest(url: request.url)
        urlRequest.httpMethod = request.method.rawValue
        for (k, v) in request.headers {
            urlRequest.setValue(v, forHTTPHeaderField: k)
        }
        if let timeout = request.timeoutInterval {
            urlRequest.timeoutInterval = timeout
        }
        urlRequest.httpBody = request.body
        return urlRequest
    }

    private func mapURLError(_ error: Error) -> SarvamError {
        let nsError = error as NSError
        if nsError.domain == NSURLErrorDomain {
            if nsError.code == NSURLErrorTimedOut {
                return .timeoutError(phase: .total, message: "Request timed out: \(error.localizedDescription)")
            } else if nsError.code == NSURLErrorCannotConnectToHost ||
                        nsError.code == NSURLErrorNetworkConnectionLost ||
                        nsError.code == NSURLErrorDNSLookupFailed ||
                        nsError.code == NSURLErrorSecureConnectionFailed {
                return .connectionError(message: "Network connection failure: \(error.localizedDescription)", cause: error.localizedDescription)
            }
        }
        return .connectionError(message: error.localizedDescription, cause: error.localizedDescription)
    }
}
