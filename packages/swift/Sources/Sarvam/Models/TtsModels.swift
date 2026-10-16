import Foundation

public struct TextToSpeechRequest: Codable, Sendable, Equatable {
    public var text: String
    public var targetLanguageCode: LanguageCode
    public var speaker: Speaker?
    public var model: TtsModel?
    public var speechSampleRate: Int?
    public var enablePreprocessing: Bool?
    public var outputAudioCodec: AudioCodec?

    public init(
        text: String,
        targetLanguageCode: LanguageCode,
        speaker: Speaker? = nil,
        model: TtsModel? = nil,
        speechSampleRate: Int? = nil,
        enablePreprocessing: Bool? = nil,
        outputAudioCodec: AudioCodec? = nil
    ) {
        self.text = text
        self.targetLanguageCode = targetLanguageCode
        self.speaker = speaker
        self.model = model
        self.speechSampleRate = speechSampleRate
        self.enablePreprocessing = enablePreprocessing
        self.outputAudioCodec = outputAudioCodec
    }

    enum CodingKeys: String, CodingKey {
        case text
        case targetLanguageCode = "target_language_code"
        case speaker
        case model
        case speechSampleRate = "speech_sample_rate"
        case enablePreprocessing = "enable_preprocessing"
        case outputAudioCodec = "output_audio_codec"
    }
}

public struct TtsAudioItem: Codable, Sendable, Equatable {
    public let audio: String

    public init(audio: String) {
        self.audio = audio
    }
}

public struct TextToSpeechResponse: Codable, Sendable, Equatable {
    public let audios: [TtsAudioItem]?

    public init(audios: [TtsAudioItem]?) {
        self.audios = audios
    }

    /// Number of audio clips returned.
    public var audioCount: Int {
        audios?.count ?? 0
    }

    /// Base64-encoded audio string of the first audio clip.
    public var firstAudioBase64: String? {
        audios?.first?.audio
    }

    /// Decoded binary audio bytes of the primary audio clip (`audios[0].audio`).
    public var audioBytes: Data? {
        guard let b64 = audios?.first?.audio else { return nil }
        return Data(base64Encoded: b64)
    }
}
