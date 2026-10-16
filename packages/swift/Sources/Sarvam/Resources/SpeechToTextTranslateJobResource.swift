import Foundation

/// Stateless request builder and polling coordinator for Speech-to-Text Translation Bulk Jobs.
public final class SpeechToTextTranslateJobResource: Sendable {
    private let config: SarvamClientConfig
    private let executor: RequestExecutor

    init(config: SarvamClientConfig) {
        self.config = config
        self.executor = RequestExecutor(config: config)
    }

    /// Initiates a bulk speech-to-text translation job.
    public func initialise(
        _ request: SpeechToTextTranslateJobInitRequest,
        options: RequestOptions? = nil
    ) async throws -> BulkJobInitResponse {
        let url = URL(string: "\(config.environment.apiBaseUrl)/speech-to-text-translate/job/v1")!
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
            return try decoder.decode(BulkJobInitResponse.self, from: response.body)
        } catch {
            throw SarvamError.decodingError(
                rawBody: String(data: response.body, encoding: .utf8),
                message: "Failed to decode BulkJobInitResponse: \(error.localizedDescription)",
                cause: error.localizedDescription
            )
        }
    }

    /// Obtains presigned Azure SAS upload URLs for bulk audio files to translate.
    public func getUploadLinks(
        _ request: FilesRequest,
        options: RequestOptions? = nil
    ) async throws -> FilesUploadResponse {
        let url = URL(string: "\(config.environment.apiBaseUrl)/speech-to-text-translate/job/v1/upload-files")!
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
            return try decoder.decode(FilesUploadResponse.self, from: response.body)
        } catch {
            throw SarvamError.decodingError(
                rawBody: String(data: response.body, encoding: .utf8),
                message: "Failed to decode FilesUploadResponse: \(error.localizedDescription)",
                cause: error.localizedDescription
            )
        }
    }

    /// Starts processing on an initiated speech-to-text translation bulk job.
    public func start(
        jobId: String,
        options: RequestOptions? = nil
    ) async throws -> JobStatusResponse {
        let url = URL(string: "\(config.environment.apiBaseUrl)/speech-to-text-translate/job/v1/\(jobId)/start")!
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
            return try decoder.decode(JobStatusResponse.self, from: response.body)
        } catch {
            throw SarvamError.decodingError(
                rawBody: String(data: response.body, encoding: .utf8),
                message: "Failed to decode JobStatusResponse: \(error.localizedDescription)",
                cause: error.localizedDescription
            )
        }
    }

    /// Retrieves status and progress of a bulk speech-to-text translation job.
    public func getStatus(
        jobId: String,
        options: RequestOptions? = nil
    ) async throws -> JobStatusResponse {
        let url = URL(string: "\(config.environment.apiBaseUrl)/speech-to-text-translate/job/v1/\(jobId)/status")!
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
            return try decoder.decode(JobStatusResponse.self, from: response.body)
        } catch {
            throw SarvamError.decodingError(
                rawBody: String(data: response.body, encoding: .utf8),
                message: "Failed to decode JobStatusResponse: \(error.localizedDescription)",
                cause: error.localizedDescription
            )
        }
    }

    /// Obtains presigned download URLs for the output translation files.
    public func getDownloadLinks(
        _ request: FilesRequest,
        options: RequestOptions? = nil
    ) async throws -> FilesDownloadResponse {
        let url = URL(string: "\(config.environment.apiBaseUrl)/speech-to-text-translate/job/v1/download-files")!
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
            return try decoder.decode(FilesDownloadResponse.self, from: response.body)
        } catch {
            throw SarvamError.decodingError(
                rawBody: String(data: response.body, encoding: .utf8),
                message: "Failed to decode FilesDownloadResponse: \(error.localizedDescription)",
                cause: error.localizedDescription
            )
        }
    }

    /// Polls until the bulk translation job completes or fails.
    public func waitUntilComplete(
        jobId: String,
        pollingOptions: PollingOptions? = nil,
        options: RequestOptions? = nil
    ) async throws -> JobStatusResponse {
        try await JobPoller.waitUntilComplete(
            pollInterval: pollingOptions?.pollInterval ?? 2.0,
            timeoutInterval: pollingOptions?.timeoutInterval ?? 300.0,
            clock: config.clock
        ) {
            let status = try await self.getStatus(jobId: jobId, options: options)
            let lower = status.jobState.lowercased()
            let isTerminal = ["completed", "failed"].contains(lower)
            return (isTerminal, status)
        }
    }
}
