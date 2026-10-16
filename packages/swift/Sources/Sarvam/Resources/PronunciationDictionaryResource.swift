import Foundation

/// Stateless request builder and response decoder for Pronunciation Dictionary endpoints.
public final class PronunciationDictionaryResource: Sendable {
    private let config: SarvamClientConfig
    private let executor: RequestExecutor

    init(config: SarvamClientConfig) {
        self.config = config
        self.executor = RequestExecutor(config: config)
    }

    /// Lists all pronunciation dictionaries owned by the authenticated user.
    public func list(options: RequestOptions? = nil) async throws -> PronunciationDictionaryListResponse {
        let url = URL(string: "\(config.environment.apiBaseUrl)/text-to-speech/pronunciation-dictionary")!
        let httpRequest = HTTPRequest(
            method: .get,
            url: url,
            headers: options?.headers ?? [:],
            operationKind: .idempotent,
            timeoutInterval: options?.timeoutInterval,
            idempotencyKey: options?.idempotencyKey
        )

        let response = try await executor.execute(request: httpRequest)
        let decoder = JSONDecoder()
        do {
            return try decoder.decode(PronunciationDictionaryListResponse.self, from: response.body)
        } catch {
            throw SarvamError.decodingError(
                rawBody: String(data: response.body, encoding: .utf8),
                message: "Failed to decode PronunciationDictionaryListResponse: \(error.localizedDescription)",
                cause: error.localizedDescription
            )
        }
    }

    /// Creates a new pronunciation dictionary from a JSON or CSV file.
    public func create(
        file: FileInput,
        options: RequestOptions? = nil
    ) async throws -> PronunciationDictionaryCreateResponse {
        let url = URL(string: "\(config.environment.apiBaseUrl)/text-to-speech/pronunciation-dictionary")!

        let multipartBuilder = MultipartFormDataBuilder()
        let bodyData = try multipartBuilder.build(fields: [:], files: [("file", file)])

        var headers = options?.headers ?? [:]
        headers["content-type"] = multipartBuilder.contentTypeHeader

        let httpRequest = HTTPRequest(
            method: .post,
            url: url,
            headers: headers,
            body: bodyData,
            operationKind: .multipartCompute,
            timeoutInterval: options?.timeoutInterval,
            idempotencyKey: options?.idempotencyKey,
            isReplayable: file.isReplayable
        )

        let response = try await executor.execute(request: httpRequest)
        let decoder = JSONDecoder()
        do {
            return try decoder.decode(PronunciationDictionaryCreateResponse.self, from: response.body)
        } catch {
            throw SarvamError.decodingError(
                rawBody: String(data: response.body, encoding: .utf8),
                message: "Failed to decode PronunciationDictionaryCreateResponse: \(error.localizedDescription)",
                cause: error.localizedDescription
            )
        }
    }

    /// Updates an existing pronunciation dictionary with a new file.
    public func update(
        dictId: String,
        file: FileInput,
        options: RequestOptions? = nil
    ) async throws -> PronunciationDictionaryUpdateResponse {
        var urlComponents = URLComponents(string: "\(config.environment.apiBaseUrl)/text-to-speech/pronunciation-dictionary")!
        urlComponents.queryItems = [URLQueryItem(name: "dict_id", value: dictId)]
        guard let url = urlComponents.url else {
            throw SarvamError.badRequestError(statusCode: 400, code: "invalid_url", requestId: nil, message: "Invalid URL")
        }

        let multipartBuilder = MultipartFormDataBuilder()
        let bodyData = try multipartBuilder.build(fields: [:], files: [("file", file)])

        var headers = options?.headers ?? [:]
        headers["content-type"] = multipartBuilder.contentTypeHeader

        let httpRequest = HTTPRequest(
            method: .put,
            url: url,
            headers: headers,
            body: bodyData,
            operationKind: .idempotent,
            timeoutInterval: options?.timeoutInterval,
            idempotencyKey: options?.idempotencyKey,
            isReplayable: file.isReplayable
        )

        let response = try await executor.execute(request: httpRequest)
        let decoder = JSONDecoder()
        do {
            return try decoder.decode(PronunciationDictionaryUpdateResponse.self, from: response.body)
        } catch {
            throw SarvamError.decodingError(
                rawBody: String(data: response.body, encoding: .utf8),
                message: "Failed to decode PronunciationDictionaryUpdateResponse: \(error.localizedDescription)",
                cause: error.localizedDescription
            )
        }
    }

    /// Retrieves pronunciation mappings for a specific dictionary ID.
    public func get(
        dictId: String,
        options: RequestOptions? = nil
    ) async throws -> PronunciationDictionaryData {
        let url = URL(string: "\(config.environment.apiBaseUrl)/text-to-speech/pronunciation-dictionary/\(dictId)")!
        let httpRequest = HTTPRequest(
            method: .get,
            url: url,
            headers: options?.headers ?? [:],
            operationKind: .idempotent,
            timeoutInterval: options?.timeoutInterval,
            idempotencyKey: options?.idempotencyKey
        )

        let response = try await executor.execute(request: httpRequest)
        let decoder = JSONDecoder()
        do {
            return try decoder.decode(PronunciationDictionaryData.self, from: response.body)
        } catch {
            throw SarvamError.decodingError(
                rawBody: String(data: response.body, encoding: .utf8),
                message: "Failed to decode PronunciationDictionaryData: \(error.localizedDescription)",
                cause: error.localizedDescription
            )
        }
    }

    /// Deletes a pronunciation dictionary.
    public func delete(
        dictId: String,
        options: RequestOptions? = nil
    ) async throws -> PronunciationDictionaryDeleteResponse {
        var urlComponents = URLComponents(string: "\(config.environment.apiBaseUrl)/text-to-speech/pronunciation-dictionary")!
        urlComponents.queryItems = [URLQueryItem(name: "dict_id", value: dictId)]
        guard let url = urlComponents.url else {
            throw SarvamError.badRequestError(statusCode: 400, code: "invalid_url", requestId: nil, message: "Invalid URL")
        }

        let httpRequest = HTTPRequest(
            method: .delete,
            url: url,
            headers: options?.headers ?? [:],
            operationKind: .idempotent,
            timeoutInterval: options?.timeoutInterval,
            idempotencyKey: options?.idempotencyKey
        )

        let response = try await executor.execute(request: httpRequest)
        let decoder = JSONDecoder()
        do {
            return try decoder.decode(PronunciationDictionaryDeleteResponse.self, from: response.body)
        } catch {
            throw SarvamError.decodingError(
                rawBody: String(data: response.body, encoding: .utf8),
                message: "Failed to decode PronunciationDictionaryDeleteResponse: \(error.localizedDescription)",
                cause: error.localizedDescription
            )
        }
    }
}
