import Foundation

/// Configuration options for establishing an STT Realtime WebSocket session.
public struct SttRealtimeConfig: Sendable, Equatable {
    public var languageCode: LanguageCode?
    public var model: SttModel?
    public var sampleRate: Int
    public var streamType: String?
    public var mode: SttMode?
    public var encoding: String?
    public var returnTimestamps: Bool?
    public var endpointing: Bool?
    public var threshold: Double?
    public var prefixPaddingMs: Int?
    public var silenceDurationMs: Int?
    public var minSpeechDurationMs: Int?
    public var prompt: String?
    public var keyterms: [String]?
    public var useSubprotocolAuth: Bool
    public var subprotocols: [String]?

    public init(
        languageCode: LanguageCode? = nil,
        model: SttModel? = .saarasV3Realtime,
        sampleRate: Int = 16000,
        streamType: String? = nil,
        mode: SttMode? = nil,
        encoding: String? = nil,
        returnTimestamps: Bool? = nil,
        endpointing: Bool? = nil,
        threshold: Double? = nil,
        prefixPaddingMs: Int? = nil,
        silenceDurationMs: Int? = nil,
        minSpeechDurationMs: Int? = nil,
        prompt: String? = nil,
        keyterms: [String]? = nil,
        useSubprotocolAuth: Bool = false,
        subprotocols: [String]? = nil
    ) {
        self.languageCode = languageCode
        self.model = model
        self.sampleRate = sampleRate
        self.streamType = streamType
        self.mode = mode
        self.encoding = encoding
        self.returnTimestamps = returnTimestamps
        self.endpointing = endpointing
        self.threshold = threshold
        self.prefixPaddingMs = prefixPaddingMs
        self.silenceDurationMs = silenceDurationMs
        self.minSpeechDurationMs = minSpeechDurationMs
        self.prompt = prompt
        self.keyterms = keyterms
        self.useSubprotocolAuth = useSubprotocolAuth
        self.subprotocols = subprotocols
    }
}
