import Foundation

/// Stateless request builder and polling coordinator for Dubbing jobs.
///
/// Routes requests directly to `dubbingBaseUrl` (`EnvironmentHost.dubbing`).
public final class DubbingResource: Sendable {
    private let config: SarvamClientConfig
    private let executor: RequestExecutor

    init(config: SarvamClientConfig) {
        self.config = config
        self.executor = RequestExecutor(config: config)
    }

    /// Creates a dubbing job, mapping `sourceLanguageCode` -> `src_lang` and `targetLanguageCodes` -> `target_langs`.
    public func create(
        _ request: DubbingCreateRequest,
        options: RequestOptions? = nil
    ) async throws -> DubbingCreateResponse {
        let url = URL(string: "\(config.environment.dubbingBaseUrl)/jobs")!
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
            return try decoder.decode(DubbingCreateResponse.self, from: response.body)
        } catch {
            throw SarvamError.decodingError(
                rawBody: String(data: response.body, encoding: .utf8),
                message: "Failed to decode DubbingCreateResponse: \(error.localizedDescription)",
                cause: error.localizedDescription
            )
        }
    }

    /// Starts processing on an uploaded dubbing job.
    public func start(
        jobId: String,
        options: RequestOptions? = nil
    ) async throws -> DubbingStartResponse {
        let url = URL(string: "\(config.environment.dubbingBaseUrl)/jobs/\(jobId)/start")!
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
            return try decoder.decode(DubbingStartResponse.self, from: response.body)
        } catch {
            throw SarvamError.decodingError(
                rawBody: String(data: response.body, encoding: .utf8),
                message: "Failed to decode DubbingStartResponse: \(error.localizedDescription)",
                cause: error.localizedDescription
            )
        }
    }

    /// Retrieves real-time pipeline status and progress of a dubbing job.
    public func getLiveStatus(
        jobId: String,
        options: RequestOptions? = nil
    ) async throws -> DubbingLiveStatusResponse {
        let url = URL(string: "\(config.environment.dubbingBaseUrl)/jobs/\(jobId)/live-status")!
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
            return try decoder.decode(DubbingLiveStatusResponse.self, from: response.body)
        } catch {
            throw SarvamError.decodingError(
                rawBody: String(data: response.body, encoding: .utf8),
                message: "Failed to decode DubbingLiveStatusResponse: \(error.localizedDescription)",
                cause: error.localizedDescription
            )
        }
    }

    /// Retrieves export status and produced media files for a dubbing job.
    public func getExportStatus(
        jobId: String,
        limit: Int? = nil,
        options: RequestOptions? = nil
    ) async throws -> DubbingExportStatusResponse {
        var urlComponents = URLComponents(string: "\(config.environment.dubbingBaseUrl)/jobs/\(jobId)/export-status")!
        if let limit = limit {
            urlComponents.queryItems = [URLQueryItem(name: "limit", value: String(limit))]
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
            return try decoder.decode(DubbingExportStatusResponse.self, from: response.body)
        } catch {
            throw SarvamError.decodingError(
                rawBody: String(data: response.body, encoding: .utf8),
                message: "Failed to decode DubbingExportStatusResponse: \(error.localizedDescription)",
                cause: error.localizedDescription
            )
        }
    }

    /// Polls until the dubbing job reaches a terminal state (`completed`, `failed`, `partial_failure`, `deleted`).
    public func waitUntilComplete(
        jobId: String,
        pollingOptions: PollingOptions? = nil,
        options: RequestOptions? = nil
    ) async throws -> DubbingLiveStatusResponse {
        try await JobPoller.waitUntilComplete(
            pollInterval: pollingOptions?.pollInterval ?? 2.0,
            timeoutInterval: pollingOptions?.timeoutInterval ?? 300.0,
            clock: config.clock
        ) {
            let status = try await self.getLiveStatus(jobId: jobId, options: options)
            let lower = status.data.status.lowercased()
            let isTerminal = ["completed", "failed", "partial_failure", "deleted"].contains(lower)
            return (isTerminal, status)
        }
    }
}
