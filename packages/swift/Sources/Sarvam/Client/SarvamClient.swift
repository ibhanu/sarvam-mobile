import Foundation

/// Main entry point for interacting with Sarvam AI APIs.
///
/// Thread-safe, immutable client conforming to Swift 6 strict concurrency (`Sendable`).
public final class SarvamClient: Sendable {
    public let config: SarvamClientConfig

    /// Text operations (translation, transliteration, language identification).
    public let text: TextResource

    /// Speech-to-text operations (file transcription/translation, real-time WebSocket session).
    public let speechToText: SpeechToTextResource

    /// Text-to-speech operations (synthesis conversion, HTTP chunked stream, real-time WebSocket session).
    public let textToSpeech: TextToSpeechResource

    /// Chat completions operations (V1, V2, streaming, models, stateful sessions).
    public let chat: ChatResource

    /// Responses API operations (structured SSE streams).
    public let responses: ResponsesResource

    /// Asynchronous job management and SAS blob storage uploads.
    public let jobs: JobsResource

    /// Voice cloning operations (listing, creating, deleting, synthesizing speech, WebSocket streaming).
    public let voiceCloning: VoiceCloningResource

    /// Document AI operations (digitisation, structured extraction, job polling, download URLs).
    public let docAi: DocAiResource

    /// Pronunciation dictionary operations (listing, creating, updating, retrieving, deleting).
    public let pronunciationDictionary: PronunciationDictionaryResource

    /// Asynchronous Speech-to-Text bulk job operations.
    public let speechToTextJob: SpeechToTextJobResource

    /// Asynchronous Speech-to-Text translation bulk job operations.
    public let speechToTextTranslateJob: SpeechToTextTranslateJobResource

    /// Document translation operations (file creation, live status tracking, export triggering).
    public let documentTranslation: DocumentTranslationResource

    /// Video & audio dubbing operations (creation, live status tracking, export status).
    public let dubbing: DubbingResource

    /// Initializes a client using a `SarvamClientConfig` configuration instance.
    public init(configuration: SarvamClientConfig) {
        self.config = configuration
        self.text = TextResource(config: configuration)
        self.speechToText = SpeechToTextResource(config: configuration)
        self.textToSpeech = TextToSpeechResource(config: configuration)
        self.chat = ChatResource(config: configuration)
        self.responses = ResponsesResource(config: configuration)
        self.jobs = JobsResource(config: configuration)
        self.voiceCloning = VoiceCloningResource(config: configuration)
        self.docAi = DocAiResource(config: configuration)
        self.pronunciationDictionary = PronunciationDictionaryResource(config: configuration)
        self.speechToTextJob = SpeechToTextJobResource(config: configuration)
        self.speechToTextTranslateJob = SpeechToTextTranslateJobResource(config: configuration)
        self.documentTranslation = DocumentTranslationResource(config: configuration)
        self.dubbing = DubbingResource(config: configuration)
    }

    /// Initializes a client using an `AuthProvider` implementation.
    public convenience init(
        authProvider: AuthProvider,
        environment: SarvamEnvironment = .production,
        transport: HTTPTransport = URLSessionHTTPTransport(),
        webSocketFactory: WebSocketFactory = URLSessionWebSocketFactory(),
        middlewares: [Middleware]? = nil,
        clock: ClockProvider = SystemClockProvider(),
        random: RandomProvider = SystemRandomProvider(),
        defaultTimeoutInterval: TimeInterval = 60,
        maxRetries: Int = 2
    ) {
        let config = SarvamClientConfig(
            authProvider: authProvider,
            environment: environment,
            transport: transport,
            webSocketFactory: webSocketFactory,
            middlewares: middlewares,
            clock: clock,
            random: random,
            defaultTimeoutInterval: defaultTimeoutInterval,
            maxRetries: maxRetries
        )
        self.init(configuration: config)
    }

    /// Convenience initializer using a static subscription key.
    public convenience init(
        apiKey: String,
        environment: SarvamEnvironment = .production,
        transport: HTTPTransport = URLSessionHTTPTransport(),
        webSocketFactory: WebSocketFactory = URLSessionWebSocketFactory(),
        clock: ClockProvider = SystemClockProvider(),
        random: RandomProvider = SystemRandomProvider(),
        defaultTimeoutInterval: TimeInterval = 60,
        maxRetries: Int = 2
    ) {
        let auth = ApiKeyAuth(apiKey: apiKey)
        self.init(
            authProvider: auth,
            environment: environment,
            transport: transport,
            webSocketFactory: webSocketFactory,
            clock: clock,
            random: random,
            defaultTimeoutInterval: defaultTimeoutInterval,
            maxRetries: maxRetries
        )
    }
}
