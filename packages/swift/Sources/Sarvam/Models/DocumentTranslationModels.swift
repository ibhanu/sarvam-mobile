import Foundation

public struct DocumentTranslationCreateRequest: Codable, Sendable, Equatable {
    public var sourceLanguageCode: LanguageCode
    public var targetLanguageCodes: [LanguageCode]
    public var originalFilename: String
    public var jobName: String?
    public var genre: String?
    public var useNativeNumerals: Bool?
    public var styleGuidelines: String?

    public init(
        sourceLanguageCode: LanguageCode,
        targetLanguageCodes: [LanguageCode],
        originalFilename: String,
        jobName: String? = nil,
        genre: String? = nil,
        useNativeNumerals: Bool? = nil,
        styleGuidelines: String? = nil
    ) {
        self.sourceLanguageCode = sourceLanguageCode
        self.targetLanguageCodes = targetLanguageCodes
        self.originalFilename = originalFilename
        self.jobName = jobName
        self.genre = genre
        self.useNativeNumerals = useNativeNumerals
        self.styleGuidelines = styleGuidelines
    }

    enum CodingKeys: String, CodingKey {
        case sourceLanguageCode = "source_language_code"
        case targetLanguageCodes = "target_language_codes"
        case originalFilename = "original_filename"
        case jobName = "job_name"
        case genre
        case useNativeNumerals = "use_native_numerals"
        case styleGuidelines = "style_guidelines"
    }
}

public struct DocumentTranslationCreateResponse: Codable, Sendable, Equatable {
    public let jobId: String
    public let uploadUrl: String
    public let expiresInHours: Int?
    public let sourceLanguageCode: String
    public let targetLanguageCodes: [String]

    public init(
        jobId: String,
        uploadUrl: String,
        expiresInHours: Int? = nil,
        sourceLanguageCode: String,
        targetLanguageCodes: [String]
    ) {
        self.jobId = jobId
        self.uploadUrl = uploadUrl
        self.expiresInHours = expiresInHours
        self.sourceLanguageCode = sourceLanguageCode
        self.targetLanguageCodes = targetLanguageCodes
    }

    enum CodingKeys: String, CodingKey {
        case jobId = "job_id"
        case uploadUrl = "upload_url"
        case expiresInHours = "expires_in_hours"
        case sourceLanguageCode = "source_language_code"
        case targetLanguageCodes = "target_language_codes"
    }
}

public struct DocumentTranslationStartResponse: Codable, Sendable, Equatable {
    public let jobId: String
    public let jobState: String
    public let numPages: Int?
    public let warnings: [String]?

    public init(jobId: String, jobState: String, numPages: Int? = nil, warnings: [String]? = nil) {
        self.jobId = jobId
        self.jobState = jobState
        self.numPages = numPages
        self.warnings = warnings
    }

    enum CodingKeys: String, CodingKey {
        case jobId = "job_id"
        case jobState = "job_state"
        case numPages = "num_pages"
        case warnings
    }
}

public struct DocumentTranslationJobLiveStatusResponse: Codable, Sendable, Equatable {
    public let jobId: String
    public let jobName: String
    public let jobState: String
    public let sourceLanguageCode: String
    public let progress: Int?
    public let createdAt: String
    public let updatedAt: String
    public let errorMessage: String?

    public init(
        jobId: String,
        jobName: String,
        jobState: String,
        sourceLanguageCode: String,
        progress: Int? = nil,
        createdAt: String,
        updatedAt: String,
        errorMessage: String? = nil
    ) {
        self.jobId = jobId
        self.jobName = jobName
        self.jobState = jobState
        self.sourceLanguageCode = sourceLanguageCode
        self.progress = progress
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.errorMessage = errorMessage
    }

    enum CodingKeys: String, CodingKey {
        case jobId = "job_id"
        case jobName = "job_name"
        case jobState = "job_state"
        case sourceLanguageCode = "source_language_code"
        case progress
        case createdAt = "created_at"
        case updatedAt = "updated_at"
        case errorMessage = "error_message"
    }
}

public struct DocumentTranslationExportRequest: Codable, Sendable, Equatable {
    public var lang: LanguageCode
    public var format: String?
    public var fitLineHeight: Bool?
    public var fitFontShrink: Bool?

    public init(
        lang: LanguageCode,
        format: String? = nil,
        fitLineHeight: Bool? = nil,
        fitFontShrink: Bool? = nil
    ) {
        self.lang = lang
        self.format = format
        self.fitLineHeight = fitLineHeight
        self.fitFontShrink = fitFontShrink
    }

    enum CodingKeys: String, CodingKey {
        case lang
        case format
        case fitLineHeight = "fit_line_height"
        case fitFontShrink = "fit_font_shrink"
    }
}

public struct DocumentTranslationExportStatusResponse: Codable, Sendable, Equatable {
    public let exportId: String
    public let jobId: String
    public let targetLanguageCode: String
    public let format: String
    public let exportState: String
    public let downloadUrl: String?
    public let filename: String?
    public let fileSize: Int?
    public let expiresInHours: Int?
    public let errorMessage: String?
    public let createdAt: String

    public init(
        exportId: String,
        jobId: String,
        targetLanguageCode: String,
        format: String,
        exportState: String,
        downloadUrl: String? = nil,
        filename: String? = nil,
        fileSize: Int? = nil,
        expiresInHours: Int? = nil,
        errorMessage: String? = nil,
        createdAt: String
    ) {
        self.exportId = exportId
        self.jobId = jobId
        self.targetLanguageCode = targetLanguageCode
        self.format = format
        self.exportState = exportState
        self.downloadUrl = downloadUrl
        self.filename = filename
        self.fileSize = fileSize
        self.expiresInHours = expiresInHours
        self.errorMessage = errorMessage
        self.createdAt = createdAt
    }

    enum CodingKeys: String, CodingKey {
        case exportId = "export_id"
        case jobId = "job_id"
        case targetLanguageCode = "target_language_code"
        case format
        case exportState = "export_state"
        case downloadUrl = "download_url"
        case filename
        case fileSize = "file_size"
        case expiresInHours = "expires_in_hours"
        case errorMessage = "error_message"
        case createdAt = "created_at"
    }
}
