package ai.sarvam

import ai.sarvam.core.SarvamClientConfig
import ai.sarvam.core.SarvamEnvironment
import ai.sarvam.core.auth.ApiKeyAuth
import ai.sarvam.core.auth.AuthProvider
import ai.sarvam.core.http.HttpTransport
import ai.sarvam.core.http.OkHttpTransport
import ai.sarvam.core.middleware.AuthMiddleware
import ai.sarvam.core.middleware.LogLevel
import ai.sarvam.core.middleware.LoggingMiddleware
import ai.sarvam.core.middleware.Middleware
import ai.sarvam.core.middleware.RetryMiddleware
import ai.sarvam.core.middleware.UserAgentMiddleware
import ai.sarvam.core.util.Clock
import ai.sarvam.core.util.DefaultRandomSource
import ai.sarvam.core.util.JsonHelper
import ai.sarvam.core.util.RandomSource
import ai.sarvam.core.util.SystemClock
import ai.sarvam.core.ws.OkHttpWebSocketFactory
import ai.sarvam.core.ws.WebSocketFactory
import ai.sarvam.resources.ChatResource
import ai.sarvam.resources.DocAiResource
import ai.sarvam.resources.DocumentTranslationResource
import ai.sarvam.resources.DubbingResource
import ai.sarvam.resources.JobsResource
import ai.sarvam.resources.PronunciationDictionaryResource
import ai.sarvam.resources.ResponsesResource
import ai.sarvam.resources.SpeechToTextJobResource
import ai.sarvam.resources.SpeechToTextResource
import ai.sarvam.resources.SpeechToTextTranslateJobResource
import ai.sarvam.resources.TextResource
import ai.sarvam.resources.TextToSpeechResource
import ai.sarvam.resources.VoiceCloningResource

public class SarvamClient private constructor(
    public val config: SarvamClientConfig
) {
    public val text: TextResource = TextResource(config)
    public val speechToText: SpeechToTextResource = SpeechToTextResource(config)
    public val textToSpeech: TextToSpeechResource = TextToSpeechResource(config)
    public val chat: ChatResource = ChatResource(config)
    public val responses: ResponsesResource = ResponsesResource(config)
    public val jobs: JobsResource = JobsResource(config)
    public val voiceCloning: VoiceCloningResource = VoiceCloningResource(config)
    public val docAi: DocAiResource = DocAiResource(config)
    public val pronunciationDictionary: PronunciationDictionaryResource = PronunciationDictionaryResource(config)
    public val speechToTextJob: SpeechToTextJobResource = SpeechToTextJobResource(config)
    public val speechToTextTranslateJob: SpeechToTextTranslateJobResource = SpeechToTextTranslateJobResource(config)
    public val documentTranslation: DocumentTranslationResource = DocumentTranslationResource(config)
    public val dubbing: DubbingResource = DubbingResource(config)

    public companion object {
        public operator fun invoke(apiKey: String): SarvamClient =
            Builder().apiKey(apiKey).build()

        public operator fun invoke(authProvider: AuthProvider): SarvamClient =
            Builder().authProvider(authProvider).build()

        public fun builder(): Builder = Builder()
    }

    public class Builder {
        private var authProvider: AuthProvider? = null
        private var environment: SarvamEnvironment = SarvamEnvironment.PRODUCTION
        private var transport: HttpTransport? = null
        private var webSocketFactory: WebSocketFactory? = null
        private val customMiddlewares = mutableListOf<Middleware>()
        private var maxRetries: Int = 2
        private var baseBackoffMs: Long = 500L
        private var maxBackoffMs: Long = 8000L
        private var clock: Clock = SystemClock
        private var randomSource: RandomSource = DefaultRandomSource
        private var logLevel: LogLevel = LogLevel.NONE

        public fun apiKey(apiKey: String): Builder = apply {
            this.authProvider = ApiKeyAuth(apiKey)
        }

        public fun authProvider(authProvider: AuthProvider): Builder = apply {
            this.authProvider = authProvider
        }

        public fun environment(environment: SarvamEnvironment): Builder = apply {
            this.environment = environment
        }

        public fun apiBaseUrl(url: String): Builder = apply {
            this.environment = SarvamEnvironment(
                apiBaseUrl = url.trimEnd('/'),
                dubbingBaseUrl = "${url.trimEnd('/')}/dubbing",
                wsBaseUrl = environment.wsBaseUrl
            )
        }

        public fun wsBaseUrl(url: String): Builder = apply {
            this.environment = environment.copy(wsBaseUrl = url.trimEnd('/'))
        }

        public fun transport(transport: HttpTransport): Builder = apply {
            this.transport = transport
        }

        public fun webSocketFactory(factory: WebSocketFactory): Builder = apply {
            this.webSocketFactory = factory
        }

        public fun addMiddleware(middleware: Middleware): Builder = apply {
            this.customMiddlewares.add(middleware)
        }

        public fun maxRetries(retries: Int): Builder = apply {
            this.maxRetries = retries
        }

        public fun baseBackoffMs(ms: Long): Builder = apply {
            this.baseBackoffMs = ms
        }

        public fun maxBackoffMs(ms: Long): Builder = apply {
            this.maxBackoffMs = ms
        }

        public fun clock(clock: Clock): Builder = apply {
            this.clock = clock
        }

        public fun randomSource(randomSource: RandomSource): Builder = apply {
            this.randomSource = randomSource
        }

        public fun logLevel(level: LogLevel): Builder = apply {
            this.logLevel = level
        }

        public fun build(): SarvamClient {
            val resolvedAuth = authProvider ?: throw IllegalStateException("An AuthProvider or apiKey must be configured.")
            val resolvedTransport = transport ?: OkHttpTransport(clock = clock)
            val resolvedWsFactory = webSocketFactory ?: OkHttpWebSocketFactory()

            val pipeline = mutableListOf<Middleware>()
            pipeline.add(LoggingMiddleware(logLevel = logLevel))
            pipeline.add(
                RetryMiddleware(
                    maxRetries = maxRetries,
                    baseBackoffMs = baseBackoffMs,
                    maxBackoffMs = maxBackoffMs,
                    clock = clock,
                    randomSource = randomSource
                )
            )
            pipeline.add(AuthMiddleware(resolvedAuth))
            pipeline.add(UserAgentMiddleware())
            pipeline.addAll(customMiddlewares)

            val clientConfig = SarvamClientConfig(
                environment = environment,
                authProvider = resolvedAuth,
                transport = resolvedTransport,
                webSocketFactory = resolvedWsFactory,
                middlewares = pipeline,
                clock = clock,
                randomSource = randomSource,
                json = JsonHelper.defaultJson
            )

            return SarvamClient(clientConfig)
        }
    }
}

public fun sarvamClient(block: SarvamClient.Builder.() -> Unit): SarvamClient =
    SarvamClient.Builder().apply(block).build()
