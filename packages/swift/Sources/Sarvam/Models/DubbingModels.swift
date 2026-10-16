import Foundation

// MARK: - Dubbing Job Creation

public struct DubbingCreateRequest: Codable, Sendable, Equatable {
    public var sourceLanguageCode: LanguageCode
    public var targetLanguageCodes: [LanguageCode]
    public var jobName: String?
    public var voiceCloning: Bool?
    public var voiceId: String?
    public var pacePreset: String?
    public var numSpeakers: Int?
    public var disableWatermark: Bool?
    public var editorFlow: Bool?
    public var exportOptions: [String]?
    public var register: String?

    public init(
        sourceLanguageCode: LanguageCode,
        targetLanguageCodes: [LanguageCode],
        jobName: String? = nil,
        voiceCloning: Bool? = nil,
        voiceId: String? = nil,
        pacePreset: String? = nil,
        numSpeakers: Int? = nil,
        disableWatermark: Bool? = nil,
        editorFlow: Bool? = nil,
        exportOptions: [String]? = nil,
        register: String? = nil
    ) {
        self.sourceLanguageCode = sourceLanguageCode
        self.targetLanguageCodes = targetLanguageCodes
        self.jobName = jobName
        self.voiceCloning = voiceCloning
        self.voiceId = voiceId
        self.pacePreset = pacePreset
        self.numSpeakers = numSpeakers
        self.disableWatermark = disableWatermark
        self.editorFlow = editorFlow
        self.exportOptions = exportOptions
        self.register = register
    }

    enum CodingKeys: String, CodingKey {
        case sourceLanguageCode = "src_lang"
        case targetLanguageCodes = "target_langs"
        case jobName = "job_name"
        case voiceCloning = "voice_cloning"
        case voiceId = "voice_id"
        case pacePreset = "pace_preset"
        case numSpeakers = "num_speakers"
        case disableWatermark = "disable_watermark"
        case editorFlow = "editor_flow"
        case exportOptions = "export_options"
        case register
    }
}

public struct DubbingCreateData: Codable, Sendable, Equatable {
    public let jobId: String
    public let uploadUrl: String?

    public init(jobId: String, uploadUrl: String? = nil) {
        self.jobId = jobId
        self.uploadUrl = uploadUrl
    }

    enum CodingKeys: String, CodingKey {
        case jobId = "job_id"
        case uploadUrl = "upload_url"
    }
}

public struct DubbingCreateResponse: Codable, Sendable, Equatable {
    public let status: String
    public let message: String
    public let data: DubbingCreateData?

    public init(status: String = "success", message: String = "", data: DubbingCreateData? = nil) {
        self.status = status
        self.message = message
        self.data = data
    }
}

public struct DubbingStartResponse: Codable, Sendable, Equatable {
    public let status: String
    public let message: String

    public init(status: String = "success", message: String = "") {
        self.status = status
        self.message = message
    }
}

// MARK: - Dubbing Live Status

public struct DubbingLiveStatusData: Codable, Sendable, Equatable {
    public let jobId: String
    public let jobName: String?
    public let status: String
    public let progress: Int
    public let currentStep: String?
    public let currentStepLabel: String?
    public let errorMessage: String?

    public init(
        jobId: String,
        jobName: String? = nil,
        status: String,
        progress: Int = 0,
        currentStep: String? = nil,
        currentStepLabel: String? = nil,
        errorMessage: String? = nil
    ) {
        self.jobId = jobId
        self.jobName = jobName
        self.status = status
        self.progress = progress
        self.currentStep = currentStep
        self.currentStepLabel = currentStepLabel
        self.errorMessage = errorMessage
    }

    enum CodingKeys: String, CodingKey {
        case jobId = "job_id"
        case jobName = "job_name"
        case status
        case progress
        case currentStep = "current_step"
        case currentStepLabel = "current_step_label"
        case errorMessage = "error_message"
    }
}

public struct DubbingLiveStatusResponse: Codable, Sendable, Equatable {
    public let status: String
    public let message: String
    public let data: DubbingLiveStatusData

    public init(status: String = "success", message: String = "", data: DubbingLiveStatusData) {
        self.status = status
        self.message = message
        self.data = data
    }
}

// MARK: - Dubbing Export Status

public struct DubbingExportStatusResponse: Codable, Sendable, Equatable {
    public let status: String
    public let message: String
    public let rawData: String?

    public init(status: String = "success", message: String = "", rawData: String? = nil) {
        self.status = status
        self.message = message
        self.rawData = rawData
    }

    enum CodingKeys: String, CodingKey {
        case status
        case message
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.status = try container.decode(String.self, forKey: .status)
        self.message = try container.decodeIfPresent(String.self, forKey: .message) ?? ""
        self.rawData = nil
    }
}
