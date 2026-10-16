import Foundation

// MARK: - Voice Library Listing & Detail

public struct VoiceLibraryDetail: Codable, Sendable, Equatable {
    public let id: String
    public let name: String
    public let language: String
    public let gender: String?
    public let accent: String?
    public let descriptor: String?
    public let status: String
    public let source: String?
    public let createdBy: String?
    public let createdAt: String?
    public let sampleDurationSeconds: Double?
    public let referenceText: String?
    public let previewAudioUrl: String?
    public let referenceAudioUrl: String?
    public let recordedAudioUrl: String?

    public init(
        id: String,
        name: String,
        language: String,
        gender: String? = nil,
        accent: String? = nil,
        descriptor: String? = nil,
        status: String = "active",
        source: String? = "cloned",
        createdBy: String? = nil,
        createdAt: String? = nil,
        sampleDurationSeconds: Double? = nil,
        referenceText: String? = nil,
        previewAudioUrl: String? = nil,
        referenceAudioUrl: String? = nil,
        recordedAudioUrl: String? = nil
    ) {
        self.id = id
        self.name = name
        self.language = language
        self.gender = gender
        self.accent = accent
        self.descriptor = descriptor
        self.status = status
        self.source = source
        self.createdBy = createdBy
        self.createdAt = createdAt
        self.sampleDurationSeconds = sampleDurationSeconds
        self.referenceText = referenceText
        self.previewAudioUrl = previewAudioUrl
        self.referenceAudioUrl = referenceAudioUrl
        self.recordedAudioUrl = recordedAudioUrl
    }

    enum CodingKeys: String, CodingKey {
        case id
        case name
        case language
        case gender
        case accent
        case descriptor
        case status
        case source
        case createdBy = "created_by"
        case createdAt = "created_at"
        case sampleDurationSeconds = "sample_duration_seconds"
        case referenceText = "reference_text"
        case previewAudioUrl = "preview_audio_url"
        case referenceAudioUrl = "reference_audio_url"
        case recordedAudioUrl = "recorded_audio_url"
    }
}

public struct VoiceLibraryListData: Codable, Sendable, Equatable {
    public let voices: [VoiceLibraryDetail]
    public let total: Int

    public init(voices: [VoiceLibraryDetail], total: Int) {
        self.voices = voices
        self.total = total
    }
}

public struct VoiceLibraryListResponse: Codable, Sendable, Equatable {
    public let status: String
    public let data: VoiceLibraryListData

    public init(status: String = "success", data: VoiceLibraryListData) {
        self.status = status
        self.data = data
    }
}

public struct VoiceLibraryDetailResponse: Codable, Sendable, Equatable {
    public let status: String
    public let data: VoiceLibraryDetail

    public init(status: String = "success", data: VoiceLibraryDetail) {
        self.status = status
        self.data = data
    }
}

public struct VoiceLibraryCreateData: Codable, Sendable, Equatable {
    public let voiceId: String
    public let status: String
    public let referenceText: String?

    public init(voiceId: String, status: String, referenceText: String? = nil) {
        self.voiceId = voiceId
        self.status = status
        self.referenceText = referenceText
    }

    enum CodingKeys: String, CodingKey {
        case voiceId = "voice_id"
        case status
        case referenceText = "reference_text"
    }
}

public struct VoiceLibraryCreateResponse: Codable, Sendable, Equatable {
    public let status: String
    public let data: VoiceLibraryCreateData

    public init(status: String = "success", data: VoiceLibraryCreateData) {
        self.status = status
        self.data = data
    }
}

public struct VoiceLibraryDeleteResponse: Codable, Sendable, Equatable {
    public init() {}
}

// MARK: - Voice Cloning Convert & Stream Request/Response

public struct VoiceCloneRequest: Sendable, Equatable {
    public var text: String
    public var languageCode: LanguageCode
    public var voiceId: String?
    public var refAudio: FileInput?
    public var refText: String?
    public var pace: Double?
    public var outputAudioCodec: AudioCodec?
    public var speechSampleRate: Int?
    public var enableQc: Bool?
    public var enableVad: Bool?
    public var enableTextNormalization: Bool?
    public var minAudioDuration: Double?
    public var maxAudioDuration: Double?
    public var refAudioDuration: Double?

    public init(
        text: String,
        languageCode: LanguageCode,
        voiceId: String? = nil,
        refAudio: FileInput? = nil,
        refText: String? = nil,
        pace: Double? = nil,
        outputAudioCodec: AudioCodec? = nil,
        speechSampleRate: Int? = nil,
        enableQc: Bool? = nil,
        enableVad: Bool? = nil,
        enableTextNormalization: Bool? = nil,
        minAudioDuration: Double? = nil,
        maxAudioDuration: Double? = nil,
        refAudioDuration: Double? = nil
    ) {
        self.text = text
        self.languageCode = languageCode
        self.voiceId = voiceId
        self.refAudio = refAudio
        self.refText = refText
        self.pace = pace
        self.outputAudioCodec = outputAudioCodec
        self.speechSampleRate = speechSampleRate
        self.enableQc = enableQc
        self.enableVad = enableVad
        self.enableTextNormalization = enableTextNormalization
        self.minAudioDuration = minAudioDuration
        self.maxAudioDuration = maxAudioDuration
        self.refAudioDuration = refAudioDuration
    }
}

public struct VoiceCloneResponse: Codable, Sendable, Equatable {
    public let audio: String
    public let audioB64: String?
    public let requestId: String?
    public let audioDuration: Double?

    public init(
        audio: String,
        audioB64: String? = nil,
        requestId: String? = nil,
        audioDuration: Double? = nil
    ) {
        self.audio = audio
        self.audioB64 = audioB64 ?? audio
        self.requestId = requestId
        self.audioDuration = audioDuration
    }

    /// Computed Base64-decoded binary audio bytes from root `audio`.
    public var audioBytes: Data? {
        Data(base64Encoded: audio)
    }

    enum CodingKeys: String, CodingKey {
        case audio
        case audioB64 = "audio_b64"
        case requestId = "request_id"
        case audioDuration = "audio_duration"
    }
}
