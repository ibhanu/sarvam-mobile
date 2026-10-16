import { SarvamEnvironment } from './environment.js';
import { AuthProvider, ApiKeyAuth } from './auth.js';
import { HttpTransport, FetchHttpTransport, HttpRequest, HttpResponse } from './transport/http.js';
import { WebSocketFactory, DefaultWebSocketFactory } from './transport/websocket.js';
import { Middleware, composeMiddlewares, NextHandler } from './middleware/types.js';
import { createUserAgentMiddleware } from './middleware/userAgent.js';
import { createAuthMiddleware } from './middleware/auth.js';
import { createRetryMiddleware } from './middleware/retry.js';
import { createLoggingMiddleware, Logger } from './middleware/logging.js';
import { Clock, defaultClock, Random, defaultRandom } from './utils/timing.js';

import { TextResource } from './resources/text.js';
import { SpeechToTextResource, SpeechToTextClientContext } from './resources/speechToText.js';
import { TextToSpeechResource, TextToSpeechClientContext } from './resources/textToSpeech.js';
import { ChatResource } from './resources/chat.js';
import { ResponsesResource } from './resources/responses.js';
import { JobsResource } from './resources/jobs.js';
import {
  DocAiResource,
  VoiceCloningResource,
  PronunciationDictionaryResource,
  SpeechToTextJobResource,
  SpeechToTextTranslateJobResource,
  DocumentTranslationResource,
  DubbingResource,
} from './resources/other.js';

export interface SarvamClientConfig {
  apiKey?: string;
  authProvider?: AuthProvider;
  environment?: SarvamEnvironment;
  baseUrl?: string;
  dubbingBaseUrl?: string;
  wsBaseUrl?: string;
  httpTransport?: HttpTransport;
  wsFactory?: WebSocketFactory;
  middlewares?: Middleware[];
  maxRetries?: number;
  timeoutMs?: number;
  logger?: Logger;
  clock?: Clock;
  random?: Random;
  userAgentPrefix?: string;
}

export class SarvamClient {
  readonly environment: SarvamEnvironment;
  readonly authProvider: AuthProvider;
  readonly httpTransport: HttpTransport;
  readonly wsFactory: WebSocketFactory;
  private readonly executePipeline: NextHandler;

  // P0 Resources
  readonly text: TextResource;
  readonly speechToText: SpeechToTextResource;
  readonly textToSpeech: TextToSpeechResource;
  readonly chat: ChatResource;
  readonly responses: ResponsesResource;
  readonly jobs: JobsResource;

  // P1 & P2 Resources
  readonly docAi: DocAiResource;
  readonly voiceCloning: VoiceCloningResource;
  readonly pronunciationDictionary: PronunciationDictionaryResource;
  readonly speechToTextJob: SpeechToTextJobResource;
  readonly speechToTextTranslateJob: SpeechToTextTranslateJobResource;
  readonly documentTranslation: DocumentTranslationResource;
  readonly dubbing: DubbingResource;

  constructor(config: SarvamClientConfig) {
    // 1. Resolve AuthProvider
    if (config.authProvider) {
      this.authProvider = config.authProvider;
    } else if (config.apiKey) {
      this.authProvider = new ApiKeyAuth(config.apiKey);
    } else {
      throw new Error(
        'SarvamClient configuration requires either apiKey or authProvider'
      );
    }

    // 2. Resolve Environment
    if (config.environment) {
      this.environment = config.environment;
    } else if (config.baseUrl) {
      this.environment = SarvamEnvironment.custom({
        apiBaseUrl: config.baseUrl,
        dubbingBaseUrl: config.dubbingBaseUrl,
        wsBaseUrl: config.wsBaseUrl,
      });
    } else {
      this.environment = SarvamEnvironment.production;
    }

    // 3. Resolve Transport & WebSocketFactory
    this.httpTransport = config.httpTransport ?? new FetchHttpTransport({ defaultTimeoutMs: config.timeoutMs });
    this.wsFactory = config.wsFactory ?? new DefaultWebSocketFactory();

    // 4. Build Middleware Chain
    const clock = config.clock ?? defaultClock;
    const random = config.random ?? defaultRandom;

    const pipelineMiddlewares: Middleware[] = [
      createUserAgentMiddleware({ customPrefix: config.userAgentPrefix }),
      createAuthMiddleware(this.authProvider),
      createRetryMiddleware({
        maxRetries: config.maxRetries ?? 2,
        clock,
        random,
      }),
      createLoggingMiddleware(config.logger),
      ...(config.middlewares ?? []),
    ];

    this.executePipeline = composeMiddlewares(pipelineMiddlewares, (req) =>
      this.httpTransport.execute(req)
    );

    const dispatcher = {
      execute: (req: HttpRequest): Promise<HttpResponse> => this.executePipeline(req),
      getApiBaseUrl: () => this.environment.apiBaseUrl,
      getDubbingBaseUrl: () => this.environment.dubbingBaseUrl,
      getWsBaseUrl: () => this.environment.wsBaseUrl,
      getAuthProvider: () => this.authProvider,
      getWebSocketFactory: () => this.wsFactory,
      getClock: () => clock,
    };

    const sttContext: SpeechToTextClientContext = {
      execute: (req: HttpRequest) => this.executePipeline(req),
      getApiBaseUrl: () => this.environment.apiBaseUrl,
      getWsBaseUrl: () => this.environment.wsBaseUrl,
      getAuthProvider: () => this.authProvider,
      getWebSocketFactory: () => this.wsFactory,
    };

    const ttsContext: TextToSpeechClientContext = {
      execute: (req: HttpRequest) => this.executePipeline(req),
      getApiBaseUrl: () => this.environment.apiBaseUrl,
      getWsBaseUrl: () => this.environment.wsBaseUrl,
      getAuthProvider: () => this.authProvider,
      getWebSocketFactory: () => this.wsFactory,
    };

    // 6. Instantiate Resources
    this.text = new TextResource(dispatcher);
    this.speechToText = new SpeechToTextResource(sttContext);
    this.textToSpeech = new TextToSpeechResource(ttsContext);
    this.chat = new ChatResource(dispatcher);
    this.responses = new ResponsesResource(dispatcher);
    this.jobs = new JobsResource(dispatcher);

    this.docAi = new DocAiResource(dispatcher);
    this.voiceCloning = new VoiceCloningResource(dispatcher);
    this.pronunciationDictionary = new PronunciationDictionaryResource(dispatcher);
    this.speechToTextJob = new SpeechToTextJobResource(dispatcher);
    this.speechToTextTranslateJob = new SpeechToTextTranslateJobResource(dispatcher);
    this.documentTranslation = new DocumentTranslationResource(dispatcher);
    this.dubbing = new DubbingResource(dispatcher);
  }

  /**
   * Directly executes an HttpRequest through the full middleware pipeline.
   */
  async execute(request: HttpRequest): Promise<HttpResponse> {
    return this.executePipeline(request);
  }
}
