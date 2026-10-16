import Foundation

/// Stateless request builder and polling coordinator for Document Translation jobs.
public final class DocumentTranslationResource: Sendable {
    private let config: SarvamClientConfig
    private let executor: RequestExecutor

    init(config: SarvamClientConfig) {
        self.config = config
        self.executor = RequestExecutor(config: config)
    }

    /// Creates a new document translation job and returns an upload URL.
    public func create(
        _ request: DocumentTranslationCreateRequest,
        options: RequestOptions? = nil
    ) async throws -> DocumentTranslationCreateResponse {
        let url = URL(string: "\(config.environment.apiBaseUrl)/translate/document/jobs")!
        let encoder = JSONEncoder()
        let body = try encoder.encode(request)

        var headers = options?.headers ?? [:]
        headers["content-type"] = "application/json"

        let httpRequest = HTTPRequest(
            method: .post,
            url: url,
            headers: headers,
            body: body,
            operationKind: .jobCreate,
            timeoutInterval: options?.timeoutInterval,
            idempotencyKey: options?.idempotencyKey
        )

        let response = try await executor.execute(request: httpRequest)
        let decoder = JSONDecoder()
        do {
            return try decoder.decode(DocumentTranslationCreateResponse.self, from: response.body)
        } catch {
            throw SarvamError.decodingError(
                rawBody: String(data: response.body, encoding: .utf8),
                message: "Failed to decode DocumentTranslationCreateResponse: \(error.localizedDescription)",
                cause: error.localizedDescription
            )
        }
    }

    /// Starts processing on an uploaded document translation job.
    public func start(
        jobId: String,
        options: RequestOptions? = nil
    ) async throws -> DocumentTranslationStartResponse {
        let url = URL(string: "\(config.environment.apiBaseUrl)/translate/document/jobs/\(jobId)/start")!
        let httpRequest = HTTPRequest(
            method: .post,
            url: url,
            headers: options?.headers ?? [:],
            operationKind: .statelessPost,
            timeoutInterval: options?.timeoutInterval,
            idempotencyKey: options?.idempotencyKey
        )

        let response = try await executor.execute(request: httpRequest)
        let decoder = JSONDecoder()
        do {
            return try decoder.decode(DocumentTranslationStartResponse.self, from: response.body)
        } catch {
            throw SarvamError.decodingError(
                rawBody: String(data: response.body, encoding: .utf8),
                message: "Failed to decode DocumentTranslationStartResponse: \(error.localizedDescription)",
                cause: error.localizedDescription
            )
        }
    }

    /// Retrieves real-time translation progress for an active job.
    public func getLiveStatus(
        jobId: String,
        options: RequestOptions? = nil
    ) async throws -> DocumentTranslationJobLiveStatusResponse {
        let url = URL(string: "\(config.environment.apiBaseUrl)/translate/document/jobs/\(jobId)/live-status")!
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
            return try decoder.decode(DocumentTranslationJobLiveStatusResponse.self, from: response.body)
        } catch {
            throw SarvamError.decodingError(
                rawBody: String(data: response.body, encoding: .utf8),
                message: "Failed to decode DocumentTranslationJobLiveStatusResponse: \(error.localizedDescription)",
                cause: error.localizedDescription
            )
        }
    }

    /// Triggers an export of the translated document in the specified target language and format.
    public func triggerExport(
        jobId: String,
        request: DocumentTranslationExportRequest,
        options: RequestOptions? = nil
    ) async throws -> DocumentTranslationExportStatusResponse {
        var urlComponents = URLComponents(string: "\(config.environment.apiBaseUrl)/translate/document/jobs/\(jobId)/export")!
        var queryItems = [URLQueryItem(name: "lang", value: request.lang.rawValue)]
        if let format = request.format {
            queryItems.append(URLQueryItem(name: "format", value: format))
        }
        if let fitLineHeight = request.fitLineHeight {
            queryItems.append(URLQueryItem(name: "fit_line_height", value: String(fitLineHeight)))
        }
        if let fitFontShrink = request.fitFontShrink {
            queryItems.append(URLQueryItem(name: "fit_font_shrink", value: String(fitFontShrink)))
        }
        urlComponents.queryItems = queryItems
        guard let url = urlComponents.url else {
            throw SarvamError.badRequestError(statusCode: 400, code: "invalid_url", requestId: nil, message: "Invalid URL")
        }

        let httpRequest = HTTPRequest(
            method: .post,
            url: url,
            headers: options?.headers ?? [:],
            operationKind: .statelessPost,
            timeoutInterval: options?.timeoutInterval,
            idempotencyKey: options?.idempotencyKey
        )

        let response = try await executor.execute(request: httpRequest)
        let decoder = JSONDecoder()
        do {
            return try decoder.decode(DocumentTranslationExportStatusResponse.self, from: response.body)
        } catch {
            throw SarvamError.decodingError(
                rawBody: String(data: response.body, encoding: .utf8),
                message: "Failed to decode DocumentTranslationExportStatusResponse: \(error.localizedDescription)",
                cause: error.localizedDescription
            )
        }
    }

    /// Retrieves export status and download URL for an exported document.
    public func getExportStatus(
        jobId: String,
        lang: LanguageCode? = nil,
        exportId: String? = nil,
        options: RequestOptions? = nil
    ) async throws -> DocumentTranslationExportStatusResponse {
        var urlComponents = URLComponents(string: "\(config.environment.apiBaseUrl)/translate/document/jobs/\(jobId)/export/status")!
        var queryItems: [URLQueryItem] = []
        if let lang = lang {
            queryItems.append(URLQueryItem(name: "lang", value: lang.rawValue))
        }
        if let exportId = exportId {
            queryItems.append(URLQueryItem(name: "export_id", value: exportId))
        }
        if !queryItems.isEmpty {
            urlComponents.queryItems = queryItems
        }
        guard let url = urlComponents.url else {
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
        let decoder = JSONDecoder()
        do {
            return try decoder.decode(DocumentTranslationExportStatusResponse.self, from: response.body)
        } catch {
            throw SarvamError.decodingError(
                rawBody: String(data: response.body, encoding: .utf8),
                message: "Failed to decode DocumentTranslationExportStatusResponse: \(error.localizedDescription)",
                cause: error.localizedDescription
            )
        }
    }

    /// Polls until the document translation job reaches a terminal state (`Completed`, `PartiallyCompleted`, `Failed`).
    public func waitUntilComplete(
        jobId: String,
        pollingOptions: PollingOptions? = nil,
        options: RequestOptions? = nil
    ) async throws -> DocumentTranslationJobLiveStatusResponse {
        try await JobPoller.waitUntilComplete(
            pollInterval: pollingOptions?.pollInterval ?? 2.0,
            timeoutInterval: pollingOptions?.timeoutInterval ?? 300.0,
            clock: config.clock
        ) {
            let status = try await self.getLiveStatus(jobId: jobId, options: options)
            let lower = status.jobState.lowercased()
            let isTerminal = ["completed", "partiallycompleted", "partially_completed", "failed"].contains(lower)
            return (isTerminal, status)
        }
    }
}
