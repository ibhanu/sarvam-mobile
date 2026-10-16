import Foundation

public struct SpeechToTextOptions: Sendable, Equatable {
    public var model: SttModel?
    public var languageCode: LanguageCode?
    public var prompt: String?
    public var withTimestamps: Bool?
    public var withDiarization: Bool?
    public var numSpeakers: Int?

    public init(
        model: SttModel? = nil,
        languageCode: LanguageCode? = nil,
        prompt: String? = nil,
        withTimestamps: Bool? = nil,
        withDiarization: Bool? = nil,
        numSpeakers: Int? = nil
    ) {
        self.model = model
        self.languageCode = languageCode
        self.prompt = prompt
        self.withTimestamps = withTimestamps
        self.withDiarization = withDiarization
        self.numSpeakers = numSpeakers
    }
}

public struct SttWordTimestamp: Codable, Sendable, Equatable {
    public let word: String?
    public let start: Double?
    public let end: Double?

    public init(word: String?, start: Double?, end: Double?) {
        self.word = word
        self.start = start
        self.end = end
    }
}

public struct SttDiarizedEntry: Codable, Sendable, Equatable {
    public let speakerId: String?
    public let transcript: String?
    public let start: Double?
    public let end: Double?

    enum CodingKeys: String, CodingKey {
        case speakerId = "speaker_id"
        case transcript
        case start
        case end
    }
}

public struct SttDiarizedTranscript: Codable, Sendable, Equatable {
    public let entries: [SttDiarizedEntry]?

    public init(entries: [SttDiarizedEntry]?) {
        self.entries = entries
    }
}

public struct SpeechToTextResponse: Codable, Sendable, Equatable {
    public let transcript: String
    public let timestamps: [SttWordTimestamp]?
    public let diarizedTranscript: SttDiarizedTranscript?
    public let languageCode: LanguageCode?

    public init(
        transcript: String,
        timestamps: [SttWordTimestamp]? = nil,
        diarizedTranscript: SttDiarizedTranscript? = nil,
        languageCode: LanguageCode? = nil
    ) {
        self.transcript = transcript
        self.timestamps = timestamps
        self.diarizedTranscript = diarizedTranscript
        self.languageCode = languageCode
    }

    enum CodingKeys: String, CodingKey {
        case transcript
        case timestamps
        case diarizedTranscript = "diarized_transcript"
        case languageCode = "language_code"
    }
}
