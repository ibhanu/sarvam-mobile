import Foundation

// MARK: - STT Bulk Job Parameters

public struct SpeechToTextJobParameters: Codable, Sendable, Equatable {
    public var languageCode: LanguageCode?
    public var model: SttModel?
    public var withTimestamps: Bool?
    public var withDiarization: Bool?
    public var numSpeakers: Int?

    public init(
        languageCode: LanguageCode? = nil,
        model: SttModel? = nil,
        withTimestamps: Bool? = nil,
        withDiarization: Bool? = nil,
        numSpeakers: Int? = nil
    ) {
        self.languageCode = languageCode
        self.model = model
        self.withTimestamps = withTimestamps
        self.withDiarization = withDiarization
        self.numSpeakers = numSpeakers
    }

    enum CodingKeys: String, CodingKey {
        case languageCode = "language_code"
        case model
        case withTimestamps = "with_timestamps"
        case withDiarization = "with_diarization"
        case numSpeakers = "num_speakers"
    }
}

public struct SpeechToTextJobInitRequest: Codable, Sendable, Equatable {
    public var jobParameters: SpeechToTextJobParameters

    public init(jobParameters: SpeechToTextJobParameters) {
        self.jobParameters = jobParameters
    }

    enum CodingKeys: String, CodingKey {
        case jobParameters = "job_parameters"
    }
}

public struct SpeechToTextTranslateJobParameters: Codable, Sendable, Equatable {
    public var model: SttModel?
    public var withTimestamps: Bool?
    public var withDiarization: Bool?
    public var numSpeakers: Int?

    public init(
        model: SttModel? = nil,
        withTimestamps: Bool? = nil,
        withDiarization: Bool? = nil,
        numSpeakers: Int? = nil
    ) {
        self.model = model
        self.withTimestamps = withTimestamps
        self.withDiarization = withDiarization
        self.numSpeakers = numSpeakers
    }

    enum CodingKeys: String, CodingKey {
        case model
        case withTimestamps = "with_timestamps"
        case withDiarization = "with_diarization"
        case numSpeakers = "num_speakers"
    }
}

public struct SpeechToTextTranslateJobInitRequest: Codable, Sendable, Equatable {
    public var jobParameters: SpeechToTextTranslateJobParameters

    public init(jobParameters: SpeechToTextTranslateJobParameters) {
        self.jobParameters = jobParameters
    }

    enum CodingKeys: String, CodingKey {
        case jobParameters = "job_parameters"
    }
}

// MARK: - Bulk Job Responses

public struct BulkJobInitResponse: Codable, Sendable, Equatable {
    public let jobId: String
    public let jobState: String

    public init(jobId: String, jobState: String) {
        self.jobId = jobId
        self.jobState = jobState
    }

    enum CodingKeys: String, CodingKey {
        case jobId = "job_id"
        case jobState = "job_state"
    }
}

public struct FilesRequest: Codable, Sendable, Equatable {
    public var jobId: String
    public var files: [String]

    public init(jobId: String, files: [String]) {
        self.jobId = jobId
        self.files = files
    }

    enum CodingKeys: String, CodingKey {
        case jobId = "job_id"
        case files
    }
}

public struct FileSignedURLDetails: Codable, Sendable, Equatable {
    public let fileUrl: String

    public init(fileUrl: String) {
        self.fileUrl = fileUrl
    }

    enum CodingKeys: String, CodingKey {
        case fileUrl = "file_url"
    }
}

public struct FilesUploadResponse: Codable, Sendable, Equatable {
    public let jobId: String
    public let jobState: String
    public let uploadUrls: [String: FileSignedURLDetails]

    public init(jobId: String, jobState: String, uploadUrls: [String: FileSignedURLDetails]) {
        self.jobId = jobId
        self.jobState = jobState
        self.uploadUrls = uploadUrls
    }

    enum CodingKeys: String, CodingKey {
        case jobId = "job_id"
        case jobState = "job_state"
        case uploadUrls = "upload_urls"
    }
}

public struct FilesDownloadResponse: Codable, Sendable, Equatable {
    public let jobId: String
    public let jobState: String
    public let downloadUrls: [String: FileSignedURLDetails]

    public init(jobId: String, jobState: String, downloadUrls: [String: FileSignedURLDetails]) {
        self.jobId = jobId
        self.jobState = jobState
        self.downloadUrls = downloadUrls
    }

    enum CodingKeys: String, CodingKey {
        case jobId = "job_id"
        case jobState = "job_state"
        case downloadUrls = "download_urls"
    }
}

public struct JobStatusResponse: Codable, Sendable, Equatable {
    public let jobId: String
    public let jobState: String
    public let createdAt: String?
    public let updatedAt: String?
    public let totalFiles: Int?
    public let successfulFilesCount: Int?
    public let failedFilesCount: Int?
    public let errorMessage: String?

    public init(
        jobId: String,
        jobState: String,
        createdAt: String? = nil,
        updatedAt: String? = nil,
        totalFiles: Int? = nil,
        successfulFilesCount: Int? = nil,
        failedFilesCount: Int? = nil,
        errorMessage: String? = nil
    ) {
        self.jobId = jobId
        self.jobState = jobState
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.totalFiles = totalFiles
        self.successfulFilesCount = successfulFilesCount
        self.failedFilesCount = failedFilesCount
        self.errorMessage = errorMessage
    }

    enum CodingKeys: String, CodingKey {
        case jobId = "job_id"
        case jobState = "job_state"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
        case totalFiles = "total_files"
        case successfulFilesCount = "successful_files_count"
        case failedFilesCount = "failed_files_count"
        case errorMessage = "error_message"
    }
}
