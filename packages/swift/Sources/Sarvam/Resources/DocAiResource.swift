import Foundation

/// Stateless request builder and polling coordinator for Document AI endpoints.
public final class DocAiResource: Sendable {
    private let config: SarvamClientConfig
    private let executor: RequestExecutor

    init(config: SarvamClientConfig) {
        self.config = config
        self.executor = RequestExecutor(config: config)
    }

    // MARK: - Digitise

    /// Initiates a Document AI digitisation job with one or more files.
    public func digitise(
        files: [FileInput],
        language: String? = nil,
        contentType: String? = nil,
        model: String? = nil,
        uploadIds: String? = nil,
        options: RequestOptions? = nil
    ) async throws -> DocAIStartJobResponse {
        let url = URL(string: "\(config.environment.apiBaseUrl)/doc-ai/v1/job/digitise")!

        var fields: [String: String] = [:]
        if let language = language {
            fields["language"] = language
        }
        if let contentType = contentType {
            fields["content_type"] = contentType
        }
        if let model = model {
            fields["model"] = model
        }
        if let uploadIds = uploadIds {
            fields["upload_ids"] = uploadIds
        }

        let multipartFiles = files.map { ("file", $0) }
        let multipartBuilder = MultipartFormDataBuilder()
        let bodyData = try multipartBuilder.build(fields: fields, files: multipartFiles)

        var headers = options?.headers ?? [:]
        headers["content-type"] = multipartBuilder.contentTypeHeader

        let httpRequest = HTTPRequest(
            method: .post,
            url: url,
            headers: headers,
            body: bodyData,
            operationKind: .jobCreate,
            timeoutInterval: options?.timeoutInterval,
            idempotencyKey: options?.idempotencyKey,
            isReplayable: files.allSatisfy { $0.isReplayable }
        )

        let response = try await executor.execute(request: httpRequest)
        let decoder = JSONDecoder()
        do {
            return try decoder.decode(DocAIStartJobResponse.self, from: response.body)
        } catch {
            throw SarvamError.decodingError(
                rawBody: String(data: response.body, encoding: .utf8),
                message: "Failed to decode DocAIStartJobResponse: \(error.localizedDescription)",
                cause: error.localizedDescription
            )
        }
    }

    /// Convenience: Initiates a Document AI digitisation job for a single file.
    public func digitise(
        file: FileInput,
        language: String? = nil,
        contentType: String? = nil,
        model: String? = nil,
        uploadIds: String? = nil,
        options: RequestOptions? = nil
    ) async throws -> DocAIStartJobResponse {
        try await digitise(
            files: [file],
            language: language,
            contentType: contentType,
            model: model,
            uploadIds: uploadIds,
            options: options
        )
    }

    // MARK: - Extract

    /// Initiates a Document AI extraction job, auto-serializing schema dictionary or string.
    public func extract(
        files: [FileInput]? = nil,
        schema: String? = nil,
        schemaDict: [String: Any]? = nil,
        configId: String? = nil,
        outputFormat: String? = nil,
        classification: String? = nil,
        model: String? = nil,
        uploadIds: String? = nil,
        options: RequestOptions? = nil
    ) async throws -> DocAIStartJobResponse {
        let url = URL(string: "\(config.environment.apiBaseUrl)/doc-ai/v1/job/extract")!

        var fields: [String: String] = [:]

        // Auto-serialize schema dictionary or string into JSON string
        if let schemaDict = schemaDict {
            let jsonData = try JSONSerialization.data(withJSONObject: schemaDict, options: [.sortedKeys])
            guard let jsonString = String(data: jsonData, encoding: .utf8) else {
                throw SarvamError.badRequestError(
                    statusCode: 400,
                    code: "invalid_schema",
                    requestId: nil,
                    message: "Failed to convert schema dictionary to JSON string"
                )
            }
            fields["schema"] = jsonString
        } else if let schema = schema {
            fields["schema"] = schema
        }

        if let configId = configId {
            fields["config_id"] = configId
        }
        if let outputFormat = outputFormat {
            fields["output_format"] = outputFormat
        }
        if let classification = classification {
            fields["classification"] = classification
        }
        if let model = model {
            fields["model"] = model
        }
        if let uploadIds = uploadIds {
            fields["upload_ids"] = uploadIds
        }

        let inputFiles = files ?? []
        let multipartFiles = inputFiles.map { ("file", $0) }
        let multipartBuilder = MultipartFormDataBuilder()
        let bodyData = try multipartBuilder.build(fields: fields, files: multipartFiles)

        var headers = options?.headers ?? [:]
        headers["content-type"] = multipartBuilder.contentTypeHeader

        let httpRequest = HTTPRequest(
            method: .post,
            url: url,
            headers: headers,
            body: bodyData,
            operationKind: .jobCreate,
            timeoutInterval: options?.timeoutInterval,
            idempotencyKey: options?.idempotencyKey,
            isReplayable: inputFiles.allSatisfy { $0.isReplayable }
        )

        let response = try await executor.execute(request: httpRequest)
        let decoder = JSONDecoder()
        do {
            return try decoder.decode(DocAIStartJobResponse.self, from: response.body)
        } catch {
            throw SarvamError.decodingError(
                rawBody: String(data: response.body, encoding: .utf8),
                message: "Failed to decode DocAIStartJobResponse: \(error.localizedDescription)",
                cause: error.localizedDescription
            )
        }
    }

    /// Convenience: Initiates a Document AI extraction job for a single file.
    public func extract(
        file: FileInput,
        schema: String? = nil,
        schemaDict: [String: Any]? = nil,
        configId: String? = nil,
        outputFormat: String? = nil,
        classification: String? = nil,
        model: String? = nil,
        uploadIds: String? = nil,
        options: RequestOptions? = nil
    ) async throws -> DocAIStartJobResponse {
        try await extract(
            files: [file],
            schema: schema,
            schemaDict: schemaDict,
            configId: configId,
            outputFormat: outputFormat,
            classification: classification,
            model: model,
            uploadIds: uploadIds,
            options: options
        )
    }

    // MARK: - Status, Download URL, Results, Upload URL

    /// Creates a presigned URL to upload document files directly.
    public func createUploadUrl(
        _ request: DocAIPresignUploadRequest = DocAIPresignUploadRequest(),
        options: RequestOptions? = nil
    ) async throws -> DocAIPresignUploadResponse {
        let url = URL(string: "\(config.environment.apiBaseUrl)/doc-ai/v1/job/upload")!
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
            return try decoder.decode(DocAIPresignUploadResponse.self, from: response.body)
        } catch {
            throw SarvamError.decodingError(
                rawBody: String(data: response.body, encoding: .utf8),
                message: "Failed to decode DocAIPresignUploadResponse: \(error.localizedDescription)",
                cause: error.localizedDescription
            )
        }
    }

    /// Fetches the current lifecycle status of a Document AI job.
    public func getStatus(
        jobId: String,
        options: RequestOptions? = nil
    ) async throws -> DocAIJobStatusResponse {
        let url = URL(string: "\(config.environment.apiBaseUrl)/doc-ai/v1/job/\(jobId)/status")!
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
            return try decoder.decode(DocAIJobStatusResponse.self, from: response.body)
        } catch {
            throw SarvamError.decodingError(
                rawBody: String(data: response.body, encoding: .utf8),
                message: "Failed to decode DocAIJobStatusResponse: \(error.localizedDescription)",
                cause: error.localizedDescription
            )
        }
    }

    /// Retrieves structured extraction or digitisation results.
    public func getResults(
        jobId: String,
        format: String? = nil,
        options: RequestOptions? = nil
    ) async throws -> DocAIJobResultsResponse {
        var urlComponents = URLComponents(string: "\(config.environment.apiBaseUrl)/doc-ai/v1/job/\(jobId)/results")
        if let format = format {
            urlComponents?.queryItems = [URLQueryItem(name: "format", value: format)]
        }
        guard let url = urlComponents?.url else {
            throw SarvamError.badRequestError(statusCode: 400, code: "invalid_url", requestId: nil, message: "Invalid URL")
        }

        let httpRequest = HTTPRequest(
            method: .get,
            url: url,
            headers: options?.headers ?? [:],
            operationKind: .idempotent,
            timeoutInterval: options?.timeoutInterval,
            idempotencyKey: options?.idempotencyKey
        )

        let response = try await executor.execute(request: httpRequest)
        let bodyString = String(data: response.body, encoding: .utf8) ?? "{}"
        return DocAIJobResultsResponse(rawBody: bodyString)
    }

    /// Generates a presigned download URL for the finalized job output.
    public func getDownloadUrl(
        jobId: String,
        options: RequestOptions? = nil
    ) async throws -> DocAIDownloadURLResponse {
        let url = URL(string: "\(config.environment.apiBaseUrl)/doc-ai/v1/job/\(jobId)/download-url")!
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
            return try decoder.decode(DocAIDownloadURLResponse.self, from: response.body)
        } catch {
            throw SarvamError.decodingError(
                rawBody: String(data: response.body, encoding: .utf8),
                message: "Failed to decode DocAIDownloadURLResponse: \(error.localizedDescription)",
                cause: error.localizedDescription
            )
        }
    }

    // MARK: - Polling Helpers

    /// Polls until a job reaches a terminal status (`completed`, `partially_completed`, `failed`, `rejected`).
    public func waitUntilComplete(
        jobId: String,
        pollingOptions: PollingOptions? = nil,
        options: RequestOptions? = nil
    ) async throws -> DocAIJobStatusResponse {
        try await JobPoller.waitUntilComplete(
            pollInterval: pollingOptions?.pollInterval ?? 2.0,
            timeoutInterval: pollingOptions?.timeoutInterval ?? 300.0,
            clock: config.clock
        ) {
            let status = try await self.getStatus(jobId: jobId, options: options)
            let lower = status.status.lowercased()
            let isTerminal = ["completed", "partially_completed", "failed", "rejected"].contains(lower)
            return (isTerminal, status)
        }
    }

    /// Initiates digitisation and waits until the job reaches a terminal status.
    public func digitiseAndWait(
        files: [FileInput],
        language: String? = nil,
        contentType: String? = nil,
        model: String? = nil,
        uploadIds: String? = nil,
        pollingOptions: PollingOptions? = nil,
        requestOptions: RequestOptions? = nil
    ) async throws -> DocAIJobStatusResponse {
        let startResponse = try await digitise(
            files: files,
            language: language,
            contentType: contentType,
            model: model,
            uploadIds: uploadIds,
            options: requestOptions
        )
        return try await waitUntilComplete(
            jobId: startResponse.jobId,
            pollingOptions: pollingOptions,
            options: requestOptions
        )
    }

    /// Convenience: Initiates digitisation for a single file and waits until complete.
    public func digitiseAndWait(
        file: FileInput,
        language: String? = nil,
        contentType: String? = nil,
        model: String? = nil,
        uploadIds: String? = nil,
        pollingOptions: PollingOptions? = nil,
        requestOptions: RequestOptions? = nil
    ) async throws -> DocAIJobStatusResponse {
        try await digitiseAndWait(
            files: [file],
            language: language,
            contentType: contentType,
            model: model,
            uploadIds: uploadIds,
            pollingOptions: pollingOptions,
            requestOptions: requestOptions
        )
    }

    /// Initiates extraction and waits until the job reaches a terminal status.
    public func extractAndWait(
        files: [FileInput]? = nil,
        schema: String? = nil,
        schemaDict: [String: Any]? = nil,
        configId: String? = nil,
        outputFormat: String? = nil,
        classification: String? = nil,
        model: String? = nil,
        uploadIds: String? = nil,
        pollingOptions: PollingOptions? = nil,
        requestOptions: RequestOptions? = nil
    ) async throws -> DocAIJobStatusResponse {
        let startResponse = try await extract(
            files: files,
            schema: schema,
            schemaDict: schemaDict,
            configId: configId,
            outputFormat: outputFormat,
            classification: classification,
            model: model,
            uploadIds: uploadIds,
            options: requestOptions
        )
        return try await waitUntilComplete(
            jobId: startResponse.jobId,
            pollingOptions: pollingOptions,
            options: requestOptions
        )
    }

    /// Convenience: Initiates extraction for a single file and waits until complete.
    public func extractAndWait(
        file: FileInput,
        schema: String? = nil,
        schemaDict: [String: Any]? = nil,
        configId: String? = nil,
        outputFormat: String? = nil,
        classification: String? = nil,
        model: String? = nil,
        uploadIds: String? = nil,
        pollingOptions: PollingOptions? = nil,
        requestOptions: RequestOptions? = nil
    ) async throws -> DocAIJobStatusResponse {
        try await extractAndWait(
            files: [file],
            schema: schema,
            schemaDict: schemaDict,
            configId: configId,
            outputFormat: outputFormat,
            classification: classification,
            model: model,
            uploadIds: uploadIds,
            pollingOptions: pollingOptions,
            requestOptions: requestOptions
        )
    }
}
