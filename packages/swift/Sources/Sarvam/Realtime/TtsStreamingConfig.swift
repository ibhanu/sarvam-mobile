import Foundation

/// Configuration options for initiating a TTS WebSocket streaming session.
public struct TtsStreamingConfig: Sendable, Equatable {
    public var languageCode: LanguageCode?
    public var speaker: Speaker?
    public var model: TtsModel
    public var speechSampleRate: Int?
    public var outputAudioCodec: AudioCodec?
    public var voiceId: String?
    public var useSubprotocolAuth: Bool
    public var subprotocols: [String]?

    public init(
        languageCode: LanguageCode? = nil,
        speaker: Speaker? = nil,
        model: TtsModel = .bulbulV4Flash,
        speechSampleRate: Int? = 22050,
        outputAudioCodec: AudioCodec? = .mp3,
        voiceId: String? = nil,
        useSubprotocolAuth: Bool = false,
        subprotocols: [String]? = nil
    ) {
        self.languageCode = languageCode
        self.speaker = speaker
        self.model = model
        self.speechSampleRate = speechSampleRate
        self.outputAudioCodec = outputAudioCodec
        self.voiceId = voiceId
        self.useSubprotocolAuth = useSubprotocolAuth
        self.subprotocols = subprotocols
    }
}
