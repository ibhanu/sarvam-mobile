import 'dart:async';
import 'dart:math';

import 'core/auth_provider.dart';
import 'core/clock.dart';
import 'core/environment.dart';
import 'core/middleware/auth_middleware.dart';
import 'core/middleware/logging_middleware.dart';
import 'core/middleware/middleware.dart';
import 'core/middleware/retry_middleware.dart';
import 'core/middleware/user_agent_middleware.dart';
import 'core/package_http_transport.dart';
import 'core/transport.dart';
import 'core/websocket_channel_impl.dart';
import 'core/websocket_factory.dart';
import 'core/job_poller.dart';
import 'resources/chat_resource.dart';
import 'resources/doc_ai_resource.dart';
import 'resources/document_translation_resource.dart';
import 'resources/dubbing_resource.dart';
import 'resources/jobs_resource.dart';
import 'resources/pronunciation_dictionary_resource.dart';
import 'resources/responses_resource.dart';
import 'resources/speech_to_text_job_resource.dart';
import 'resources/speech_to_text_resource.dart';
import 'resources/text_resource.dart';
import 'resources/text_to_speech_resource.dart';
import 'resources/voice_cloning_resource.dart';

/// Client configuration for customizing transport, environment, authentication, and pipeline.
class SarvamClientConfig {
  final AuthProvider auth;
  final SarvamEnvironment environment;
  final HttpTransport transport;
  final WebSocketFactory webSocketFactory;
  final List<Middleware> middlewares;
  final int maxRetries;
  final Clock clock;
  final Random random;
  final LoggerAdapter logger;

  SarvamClientConfig({
    required this.auth,
    SarvamEnvironment? environment,
    HttpTransport? transport,
    WebSocketFactory? webSocketFactory,
    List<Middleware>? middlewares,
    this.maxRetries = 2,
    Clock? clock,
    Random? random,
    LoggerAdapter? logger,
  })  : environment = environment ?? SarvamEnvironment.production,
        transport = transport ?? PackageHttpTransport(),
        webSocketFactory = webSocketFactory ?? const DefaultWebSocketFactory(),
        clock = clock ?? const SystemClock(),
        random = random ?? Random(),
        logger = logger ?? const NoOpLogger(),
        middlewares = middlewares ??
            <Middleware>[
              UserAgentMiddleware(),
              RetryMiddleware(
                maxRetries: maxRetries,
                clock: clock ?? const SystemClock(),
                random: random ?? Random(),
              ),
              AuthMiddleware(auth),
              LoggingMiddleware(logger: logger),
            ];
}

/// Official client for interacting with Sarvam AI services.
///
/// Exposes resources:
/// - [text]: Text translation, transliteration, and language identification.
/// - [speechToText]: Audio transcription, audio translation, and realtime STT streaming.
/// - [textToSpeech]: Speech synthesis, chunked binary streaming, and realtime TTS streaming.
/// - [chat]: Chat completions (V1 & V2), streaming delta tokens, models, and session affinity.
/// - [responses]: Responses API streaming (`/v2/responses`).
/// - [jobs]: Azure SAS blob uploads and job management.
class SarvamClient {
  final SarvamClientConfig config;
  final HttpHandler _pipeline;

  late final TextResource text;
  late final SpeechToTextResource speechToText;
  late final TextToSpeechResource textToSpeech;
  late final ChatResource chat;
  late final ResponsesResource responses;
  late final JobsResource jobs;
  late final VoiceCloningResource voiceCloning;
  late final DocAiResource docAi;
  late final PronunciationDictionaryResource pronunciationDictionary;
  late final SpeechToTextJobResource speechToTextJob;
  late final SpeechToTextTranslateJobResource speechToTextTranslateJob;
  late final DocumentTranslationResource documentTranslation;
  late final DubbingResource dubbing;

  /// Creates a [SarvamClient] from a full [SarvamClientConfig].
  SarvamClient.fromConfig(this.config)
      : _pipeline = buildPipeline(config.transport, config.middlewares) {
    _initResources();
  }

  /// Primary constructor accepting explicit configuration parameters.
  SarvamClient({
    required AuthProvider auth,
    SarvamEnvironment? environment,
    HttpTransport? transport,
    WebSocketFactory? webSocketFactory,
    List<Middleware>? middlewares,
    int maxRetries = 2,
    Clock? clock,
    Random? random,
    LoggerAdapter? logger,
  }) : this.fromConfig(
          SarvamClientConfig(
            auth: auth,
            environment: environment,
            transport: transport,
            webSocketFactory: webSocketFactory,
            middlewares: middlewares,
            maxRetries: maxRetries,
            clock: clock,
            random: random,
            logger: logger,
          ),
        );

  /// Convenience factory for initializing with a static API subscription key.
  factory SarvamClient.withApiKey(
    String apiKey, {
    SarvamEnvironment? environment,
    HttpTransport? transport,
    WebSocketFactory? webSocketFactory,
    List<Middleware>? middlewares,
    int maxRetries = 2,
    Clock? clock,
    Random? random,
    LoggerAdapter? logger,
  }) {
    return SarvamClient(
      auth: ApiKeyAuth(apiKey),
      environment: environment,
      transport: transport,
      webSocketFactory: webSocketFactory,
      middlewares: middlewares,
      maxRetries: maxRetries,
      clock: clock,
      random: random,
      logger: logger,
    );
  }

  /// Convenience factory for initializing with dynamic token authentication.
  factory SarvamClient.withTokenProvider(
    Future<AuthToken> Function() tokenProvider, {
    SarvamEnvironment? environment,
    HttpTransport? transport,
    WebSocketFactory? webSocketFactory,
    List<Middleware>? middlewares,
    int maxRetries = 2,
    Clock? clock,
    Random? random,
    LoggerAdapter? logger,
  }) {
    return SarvamClient(
      auth: TokenAuth(tokenProvider, clock: clock),
      environment: environment,
      transport: transport,
      webSocketFactory: webSocketFactory,
      middlewares: middlewares,
      maxRetries: maxRetries,
      clock: clock,
      random: random,
      logger: logger,
    );
  }

  /// Convenience factory for initializing through a Backend-For-Frontend (BFF) proxy.
  factory SarvamClient.withProxy(
    String proxyBaseUrl, {
    FutureOr<Map<String, String>> Function()? headersProvider,
    HttpTransport? transport,
    WebSocketFactory? webSocketFactory,
    List<Middleware>? middlewares,
    int maxRetries = 2,
    Clock? clock,
    Random? random,
    LoggerAdapter? logger,
  }) {
    return SarvamClient(
      auth: ProxyAuth(headersProvider: headersProvider ?? () => const {}),
      environment: SarvamEnvironment.proxy(proxyBaseUrl),
      transport: transport,
      webSocketFactory: webSocketFactory,
      middlewares: middlewares,
      maxRetries: maxRetries,
      clock: clock,
      random: random,
      logger: logger,
    );
  }

  void _initResources() {
    final jobPoller = JobPoller(clock: config.clock);
    text = TextResource(_pipeline, config.environment);
    speechToText = SpeechToTextResource(
      _pipeline,
      config.environment,
      config.auth,
      config.webSocketFactory,
    );
    textToSpeech = TextToSpeechResource(
      _pipeline,
      config.environment,
      config.auth,
      config.webSocketFactory,
    );
    chat = ChatResource(_pipeline, config.environment);
    responses = ResponsesResource(_pipeline, config.environment);
    jobs = JobsResource(_pipeline);
    voiceCloning = VoiceCloningResource(
      _pipeline,
      config.environment,
      config.auth,
      config.webSocketFactory,
    );
    docAi = DocAiResource(
      _pipeline,
      config.environment,
      jobPoller: jobPoller,
    );
    pronunciationDictionary = PronunciationDictionaryResource(
      _pipeline,
      config.environment,
    );
    speechToTextJob = SpeechToTextJobResource(
      _pipeline,
      config.environment,
      jobPoller: jobPoller,
    );
    speechToTextTranslateJob = SpeechToTextTranslateJobResource(
      _pipeline,
      config.environment,
      jobPoller: jobPoller,
    );
    documentTranslation = DocumentTranslationResource(
      _pipeline,
      config.environment,
      jobPoller: jobPoller,
    );
    dubbing = DubbingResource(
      _pipeline,
      config.environment,
      jobPoller: jobPoller,
    );
  }

  /// Releases resources held by the underlying HTTP transport.
  void close() {
    config.transport.close();
  }
}
