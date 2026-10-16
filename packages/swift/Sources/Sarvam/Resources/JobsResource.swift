import Foundation

/// Utilities for asynchronous bulk job management and Azure SAS blob storage uploads.
public final class JobsResource: Sendable {
    private let config: SarvamClientConfig

    init(config: SarvamClientConfig) {
        self.config = config
    }

    /// Uploads a binary file input directly to an Azure Blob Storage signed SAS URL.
    ///
    /// Automatically injects the mandatory `x-ms-blob-type: BlockBlob` header.
    public func uploadToSignedUrl(
        uploadUrl: String,
        fileInput: FileInput,
        options: RequestOptions? = nil
    ) async throws {
        guard let url = URL(string: uploadUrl) else {
            throw SarvamError.badRequestError(
                statusCode: 400,
                code: "invalid_upload_url",
                requestId: nil,
                message: "Invalid signed upload URL: \(uploadUrl)"
            )
        }

        let bodyData = try fileInput.readData()

        var headers = options?.headers ?? [:]
        headers["x-ms-blob-type"] = "BlockBlob"
        if headers["content-type"] == nil && headers["Content-Type"] == nil {
            headers["content-type"] = fileInput.mimeType ?? "application/octet-stream"
        }

        let httpRequest = HTTPRequest(
            method: .put,
            url: url,
            headers: headers,
            body: bodyData,
            operationKind: .idempotent,
            timeoutInterval: options?.timeoutInterval,
            idempotencyKey: options?.idempotencyKey,
            isReplayable: fileInput.isReplayable
        )

        let response = try await config.transport.execute(request: httpRequest)

        if response.statusCode >= 400 {
            throw SarvamError.from(
                statusCode: response.statusCode,
                headers: response.headers,
                body: response.body
            )
        }
    }
}
