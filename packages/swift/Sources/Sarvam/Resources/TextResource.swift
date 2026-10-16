import Foundation

/// Stateless request builder and response decoder for text endpoints.
public final class TextResource: Sendable {
    private let config: SarvamClientConfig
    private let executor: RequestExecutor

    init(config: SarvamClientConfig) {
        self.config = config
        self.executor = RequestExecutor(config: config)
    }

    /// Translates text across 11 Indic languages and English.
    public func translate(
        _ request: TranslateRequest,
        options: RequestOptions? = nil
    ) async throws -> TranslateResponse {
        let url = URL(string: "\(config.environment.apiBaseUrl)/translate")!
        let encoder = JSONEncoder()
        let body = try encoder.encode(request)

        var headers = options?.headers ?? [:]
        headers["content-type"] = "application/json"

        let httpRequest = HTTPRequest(
            method: .post,
            url: url,
            headers: headers,
            body: body,
            operationKind: .statelessPost,
            timeoutInterval: options?.timeoutInterval,
            idempotencyKey: options?.idempotencyKey
        )

        let response = try await executor.execute(request: httpRequest)
        let decoder = JSONDecoder()
        do {
            return try decoder.decode(TranslateResponse.self, from: response.body)
        } catch {
            throw SarvamError.decodingError(
                rawBody: String(data: response.body, encoding: .utf8),
                message: "Failed to decode TranslateResponse: \(error.localizedDescription)",
                cause: error.localizedDescription
            )
        }
    }

    /// Transliterates text into native Indic scripts.
    public func transliterate(
        _ request: TransliterateRequest,
        options: RequestOptions? = nil
    ) async throws -> TransliterateResponse {
        let url = URL(string: "\(config.environment.apiBaseUrl)/transliterate")!
        let encoder = JSONEncoder()
        let body = try encoder.encode(request)

        var headers = options?.headers ?? [:]
        headers["content-type"] = "application/json"

        let httpRequest = HTTPRequest(
            method: .post,
            url: url,
            headers: headers,
            body: body,
            operationKind: .statelessPost,
            timeoutInterval: options?.timeoutInterval,
            idempotencyKey: options?.idempotencyKey
        )

        let response = try await executor.execute(request: httpRequest)
        let decoder = JSONDecoder()
        do {
            return try decoder.decode(TransliterateResponse.self, from: response.body)
        } catch {
            throw SarvamError.decodingError(
                rawBody: String(data: response.body, encoding: .utf8),
                message: "Failed to decode TransliterateResponse: \(error.localizedDescription)",
                cause: error.localizedDescription
            )
        }
    }

    /// Identifies the language of the provided text.
    public func identifyLanguage(
        _ request: TextLidRequest,
        options: RequestOptions? = nil
    ) async throws -> TextLidResponse {
        let url = URL(string: "\(config.environment.apiBaseUrl)/text-lid")!
        let encoder = JSONEncoder()
        let body = try encoder.encode(request)

        var headers = options?.headers ?? [:]
        headers["content-type"] = "application/json"

        let httpRequest = HTTPRequest(
            method: .post,
            url: url,
            headers: headers,
            body: body,
            operationKind: .statelessPost,
            timeoutInterval: options?.timeoutInterval,
            idempotencyKey: options?.idempotencyKey
        )

        let response = try await executor.execute(request: httpRequest)
        let decoder = JSONDecoder()
        do {
            return try decoder.decode(TextLidResponse.self, from: response.body)
        } catch {
            throw SarvamError.decodingError(
                rawBody: String(data: response.body, encoding: .utf8),
                message: "Failed to decode TextLidResponse: \(error.localizedDescription)",
                cause: error.localizedDescription
            )
        }
    }
}
