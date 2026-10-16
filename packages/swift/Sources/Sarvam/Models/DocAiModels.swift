import Foundation

// MARK: - DocAI Job Start

public struct DocAIStartJobResponse: Codable, Sendable, Equatable {
    public let jobId: String
    public let status: String
    public let runId: String

    public init(jobId: String, status: String, runId: String) {
        self.jobId = jobId
        self.status = status
        self.runId = runId
    }

    enum CodingKeys: String, CodingKey {
        case jobId = "job_id"
        case status
        case runId = "run_id"
    }
}

// MARK: - Presigned Upload URL

public struct DocAIPresignUploadRequest: Codable, Sendable, Equatable {
    public var contentType: String?

    public init(contentType: String? = nil) {
        self.contentType = contentType
    }

    enum CodingKeys: String, CodingKey {
        case contentType = "content_type"
    }
}

public struct DocAIPresignUploadResponse: Codable, Sendable, Equatable {
    public let uploadId: String
    public let method: String
    public let url: String
    public let headers: [String: String]?
    public let expiresAt: String

    public init(
        uploadId: String,
        method: String,
        url: String,
        headers: [String: String]? = nil,
        expiresAt: String
    ) {
        self.uploadId = uploadId
        self.method = method
        self.url = url
        self.headers = headers
        self.expiresAt = expiresAt
    }

    enum CodingKeys: String, CodingKey {
        case uploadId = "upload_id"
        case method
        case url
        case headers
        case expiresAt = "expires_at"
    }
}

// MARK: - Job Status

public struct DocAIUsage: Codable, Sendable, Equatable {
    public let numPages: Int?
    public let numCharacters: Int?

    public init(numPages: Int? = nil, numCharacters: Int? = nil) {
        self.numPages = numPages
        self.numCharacters = numCharacters
    }

    enum CodingKeys: String, CodingKey {
        case numPages = "num_pages"
        case numCharacters = "num_characters"
    }
}

public struct DocAIJobStatusResponse: Codable, Sendable, Equatable {
    public let jobId: String
    public let status: String
    public let pipeline: String
    public let usage: DocAIUsage?
    public let createdAt: String
    public let updatedAt: String

    public init(
        jobId: String,
        status: String,
        pipeline: String,
        usage: DocAIUsage? = nil,
        createdAt: String,
        updatedAt: String
    ) {
        self.jobId = jobId
        self.status = status
        self.pipeline = pipeline
        self.usage = usage
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    enum CodingKeys: String, CodingKey {
        case jobId = "job_id"
        case status
        case pipeline
        case usage
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }
}

// MARK: - Presigned Download URL

public struct DocAIDownloadURLResponse: Codable, Sendable, Equatable {
    public let method: String
    public let url: String
    public let headers: [String: String]?
    public let expiresAt: String

    public init(
        method: String,
        url: String,
        headers: [String: String]? = nil,
        expiresAt: String
    ) {
        self.method = method
        self.url = url
        self.headers = headers
        self.expiresAt = expiresAt
    }

    enum CodingKeys: String, CodingKey {
        case method
        case url
        case headers
        case expiresAt = "expires_at"
    }
}

// MARK: - Job Results

public struct DocAIJobResultsResponse: Codable, Sendable, Equatable {
    public let rawBody: String

    public init(rawBody: String) {
        self.rawBody = rawBody
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let jsonObject = try? container.decode([String: String].self),
           let data = try? JSONSerialization.data(withJSONObject: jsonObject),
           let str = String(data: data, encoding: .utf8) {
            self.rawBody = str
        } else {
            self.rawBody = "{}"
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawBody)
    }
}
