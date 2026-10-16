import Foundation

/// Pipeline coordinator that executes requests through configured middlewares and transport.
internal struct RequestExecutor: Sendable {
    let config: SarvamClientConfig

    func execute(request: HTTPRequest) async throws -> HTTPResponse {
        var req = request
        if req.timeoutInterval == nil {
            req.timeoutInterval = config.defaultTimeoutInterval
        }

        let transport = config.transport

        var handler: @Sendable (HTTPRequest) async throws -> HTTPResponse = { currentReq in
            try await transport.execute(request: currentReq)
        }

        for middleware in config.middlewares.reversed() {
            let nextHandler = handler
            handler = { currentReq in
                try await middleware.process(request: currentReq, next: nextHandler)
            }
        }

        let response = try await handler(req)

        if response.statusCode >= 400 {
            throw SarvamError.from(statusCode: response.statusCode, headers: response.headers, body: response.body)
        }

        return response
    }

    func executeStream(request: HTTPRequest) async throws -> (HTTPResponse, AsyncThrowingStream<Data, Error>) {
        var modified = request
        if modified.timeoutInterval == nil {
            modified.timeoutInterval = config.defaultTimeoutInterval
        }

        // Apply User-Agent
        let ua = UserAgentMiddleware()
        if modified.headers["User-Agent"] == nil && modified.headers["user-agent"] == nil {
            modified.headers["User-Agent"] = ua.userAgentValue
        }
        if modified.headers["X-Sarvam-SDK-Version"] == nil && modified.headers["x-sarvam-sdk-version"] == nil {
            modified.headers["X-Sarvam-SDK-Version"] = ua.sdkVersionValue
        }

        // Apply Auth credentials
        let credentials = try await config.authProvider.getCredentials()
        switch credentials {
        case .subscriptionKey(let key):
            modified.headers["api-subscription-key"] = key
        case .bearerToken(let token, _):
            modified.headers["Authorization"] = "Bearer \(token)"
        case .customHeaders(let headers):
            for (k, v) in headers {
                modified.headers[k] = v
            }
        }

        let (response, stream) = try await config.transport.executeStream(request: modified)

        if response.statusCode >= 400 {
            var errorBody = Data()
            for try await chunk in stream {
                errorBody.append(chunk)
                if errorBody.count > 65536 { break }
            }
            throw SarvamError.from(statusCode: response.statusCode, headers: response.headers, body: errorBody)
        }

        return (response, stream)
    }
}
