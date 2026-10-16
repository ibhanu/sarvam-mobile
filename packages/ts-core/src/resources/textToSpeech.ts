import { AudioCodec, LanguageCode, Speaker, TtsModel } from '../generated/sarvamSpecGenerated.js';
import { RequestOptions } from './types.js';
import { HttpRequest, HttpResponse } from '../transport/http.js';
import { WebSocketConnection, WebSocketFactory } from '../transport/websocket.js';
import { AuthProvider } from '../auth.js';
import { RealtimeError, createHttpError } from '../errors.js';
import { base64ToBytes } from '../utils/base64.js';

export interface TextToSpeechRequest {
  text?: string;
  inputs?: string[];
  target_language_code: LanguageCode | string;
  speaker?: Speaker | string;
  model?: TtsModel | string;
  pitch?: number;
  pace?: number;
  loudness?: number;
  speech_sample_rate?: number;
  enable_preprocessing?: boolean;
}

export interface TextToSpeechAudioItem {
  audio: string;
}

export interface TextToSpeechResponse {
  audios: TextToSpeechAudioItem[];
  audioBytes: Uint8Array;
}

export interface TextToSpeechStreamRequest {
  text: string;
  target_language_code: LanguageCode | string;
  speaker?: Speaker | string;
  model?: TtsModel | string;
  speech_sample_rate?: number;
  audio_codec?: AudioCodec | string;
}

export interface TtsStreamingConfig {
  language_code?: LanguageCode | string;
  languageCode?: LanguageCode | string;
  speaker?: Speaker | string;
  model?: TtsModel | string;
  voice_id?: string;
  voiceId?: string;
  ref_audio?: string;
  refAudio?: string;
  speech_sample_rate?: number;
  speechSampleRate?: number;
  output_audio_codec?: AudioCodec | string;
  outputAudioCodec?: AudioCodec | string;
}

export type TtsStreamEvent =
  | {
      type: 'audio';
      audioBytes: Uint8Array;
      contentType?: string;
      requestId?: string;
      raw: Record<string, unknown>;
    }
  | {
      type: 'completed';
      requestId?: string;
      raw: Record<string, unknown>;
    }
  | {
      type: 'error';
      message: string;
      code?: string;
      raw: Record<string, unknown>;
    }
  | {
      type: 'unknown';
      rawJson: string;
    };

export class TtsStreamingSession {
  private readonly ws: WebSocketConnection;
  private readonly eventQueue: TtsStreamEvent[] = [];
  private readonly waitingResolvers: Array<{
    resolve: (result: IteratorResult<TtsStreamEvent>) => void;
    reject: (err: any) => void;
  }> = [];
  private isClosed = false;
  private closeError: Error | null = null;

  constructor(ws: WebSocketConnection, initialConfig: TtsStreamingConfig) {
    this.ws = ws;

    // Send initial config frame immediately upon connect
    const isVoiceCloning = Boolean(
      initialConfig.voiceId ??
      initialConfig.voice_id ??
      initialConfig.refAudio ??
      initialConfig.ref_audio
    );

    const configData: Record<string, unknown> = {
      language_code: initialConfig.languageCode ?? initialConfig.language_code ?? 'hi-IN',
      speech_sample_rate:
        initialConfig.speechSampleRate ?? initialConfig.speech_sample_rate ?? 22050,
      output_audio_codec:
        initialConfig.outputAudioCodec ?? initialConfig.output_audio_codec ?? 'mp3',
    };

    if (isVoiceCloning) {
      if (initialConfig.voiceId ?? initialConfig.voice_id) {
        configData['voice_id'] = initialConfig.voiceId ?? initialConfig.voice_id;
      }
      if (initialConfig.refAudio ?? initialConfig.ref_audio) {
        configData['ref_audio'] = initialConfig.refAudio ?? initialConfig.ref_audio;
      }
      if (initialConfig.speaker) {
        configData['speaker'] = initialConfig.speaker;
      }
    } else {
      configData['speaker'] = initialConfig.speaker ?? 'simran_en_customer';
      configData['model'] = initialConfig.model ?? 'bulbul:v4-flash';
    }

    this.ws.send(
      JSON.stringify({
        type: 'config',
        data: configData,
      })
    );

    this.ws.on('message', (data: string | Uint8Array) => {
      const text = typeof data === 'string' ? data : new TextDecoder().decode(data);
      try {
        const json = JSON.parse(text) as Record<string, unknown>;
        const event = this.mapJsonToEvent(json, text);
        this.pushEvent(event);
      } catch {
        this.pushEvent({ type: 'unknown', rawJson: text });
      }
    });

    this.ws.on('error', (err: any) => {
      this.closeError = new RealtimeError(err?.message || 'WebSocket error', { cause: err });
      this.flushWaitingWithError(this.closeError);
    });

    this.ws.on('close', (code: number, reason: string) => {
      this.isClosed = true;
      if (code !== 1000 && code !== 1005) {
        this.closeError = new RealtimeError(`WebSocket closed abnormally with code ${code}: ${reason}`, {
          closeCode: code,
        });
        this.flushWaitingWithError(this.closeError);
      } else {
        this.flushWaitingWithDone();
      }
    });
  }

  private mapJsonToEvent(json: Record<string, unknown>, rawJson: string): TtsStreamEvent {
    const type = typeof json['type'] === 'string' ? json['type'] : '';
    const data = (json['data'] as Record<string, unknown> | undefined) ?? {};

    if (type === 'audio') {
      const b64 = typeof data['audio'] === 'string' ? data['audio'] : '';
      const audioBytes = b64 ? base64ToBytes(b64) : new Uint8Array(0);
      return {
        type: 'audio',
        audioBytes,
        contentType: data['content_type'] as string | undefined,
        requestId: (data['request_id'] as string) ?? (json['request_id'] as string | undefined),
        raw: json,
      };
    }

    if (
      type === 'event' &&
      (data['event'] === 'final' ||
        data['event_type'] === 'completion' ||
        json['event'] === 'final')
    ) {
      return {
        type: 'completed',
        requestId: (data['request_id'] as string) ?? (json['request_id'] as string | undefined),
        raw: json,
      };
    }

    if (type === 'error') {
      return {
        type: 'error',
        message:
          (data['message'] as string) ??
          (json['message'] as string) ??
          'TTS streaming error',
        code: (data['code'] as string) ?? (json['code'] as string | undefined),
        raw: json,
      };
    }

    return {
      type: 'unknown',
      rawJson,
    };
  }

  private pushEvent(event: TtsStreamEvent): void {
    if (this.waitingResolvers.length > 0) {
      const resolver = this.waitingResolvers.shift()!;
      resolver.resolve({ value: event, done: false });
    } else {
      this.eventQueue.push(event);
    }
  }

  private flushWaitingWithError(err: Error): void {
    while (this.waitingResolvers.length > 0) {
      const resolver = this.waitingResolvers.shift()!;
      resolver.reject(err);
    }
  }

  private flushWaitingWithDone(): void {
    while (this.waitingResolvers.length > 0) {
      const resolver = this.waitingResolvers.shift()!;
      resolver.resolve({ value: undefined as any, done: true });
    }
  }

  sendText(text: string): void {
    this.ws.send(
      JSON.stringify({
        type: 'text',
        data: { text },
      })
    );
  }

  flush(): void {
    this.ws.send(JSON.stringify({ type: 'flush' }));
  }

  ping(): void {
    this.ws.send(JSON.stringify({ type: 'ping' }));
  }

  close(code = 1000, reason = 'Normal Closure'): void {
    this.isClosed = true;
    this.ws.close(code, reason);
  }

  get events(): AsyncIterable<TtsStreamEvent> {
    return {
      [Symbol.asyncIterator]: () => {
        return {
          next: (): Promise<IteratorResult<TtsStreamEvent>> => {
            if (this.eventQueue.length > 0) {
              const event = this.eventQueue.shift()!;
              return Promise.resolve({ value: event, done: false });
            }
            if (this.isClosed) {
              if (this.closeError) {
                return Promise.reject(this.closeError);
              }
              return Promise.resolve({ value: undefined as any, done: true });
            }
            return new Promise<IteratorResult<TtsStreamEvent>>((resolve, reject) => {
              this.waitingResolvers.push({ resolve, reject });
            });
          },
        };
      },
    };
  }
}

export interface TextToSpeechClientContext {
  execute(request: HttpRequest): Promise<HttpResponse>;
  getApiBaseUrl(): string;
  getWsBaseUrl(): string;
  getAuthProvider(): AuthProvider;
  getWebSocketFactory(): WebSocketFactory;
}

export class TextToSpeechResource {
  private readonly context: TextToSpeechClientContext;

  constructor(context: TextToSpeechClientContext) {
    this.context = context;
  }

  async convert(
    request: TextToSpeechRequest,
    options?: RequestOptions
  ): Promise<TextToSpeechResponse> {
    const url = `${this.context.getApiBaseUrl()}/text-to-speech`;
    const headers: Record<string, string> = {
      'content-type': 'application/json',
      ...options?.headers,
    };
    if (options?.idempotencyKey) {
      headers['idempotency-key'] = options.idempotencyKey;
    }

    // Adapt request format: if caller provided `text` but not `inputs`, adapt to API spec
    const bodyObj: Record<string, unknown> = { ...request };
    if (request.text && !request.inputs) {
      bodyObj['inputs'] = [request.text];
    }

    const httpReq: HttpRequest = {
      method: 'POST',
      url,
      headers,
      body: JSON.stringify(bodyObj),
      signal: options?.signal,
      timeoutMs: options?.timeoutMs,
      operationKind: 'STATELESS_POST',
    };

    const res = await this.context.execute(httpReq);
    if (res.status >= 400) {
      const text = await res.text();
      throw await createHttpError(res.status, text, (n) => res.headers.get(n));
    }

    const json = (await res.json()) as { audios: TextToSpeechAudioItem[] };
    const audios = json.audios || [];
    let audioBytes: Uint8Array = new Uint8Array(0);
    const firstAudio = audios[0];
    if (firstAudio?.audio) {
      audioBytes = base64ToBytes(firstAudio.audio) as any;
    }

    return {
      audios,
      audioBytes,
    };
  }

  async stream(
    request: TextToSpeechStreamRequest,
    options?: RequestOptions
  ): Promise<AsyncIterable<Uint8Array>> {
    const url = `${this.context.getApiBaseUrl()}/text-to-speech/stream`;
    const headers: Record<string, string> = {
      'content-type': 'application/json',
      Accept: 'application/octet-stream',
      ...options?.headers,
    };
    if (options?.idempotencyKey) {
      headers['idempotency-key'] = options.idempotencyKey;
    }

    const httpReq: HttpRequest = {
      method: 'POST',
      url,
      headers,
      body: JSON.stringify(request),
      signal: options?.signal,
      timeoutMs: options?.timeoutMs,
      operationKind: 'STATELESS_POST',
    };

    const res = await this.context.execute(httpReq);
    if (res.status >= 400) {
      const text = await res.text();
      throw await createHttpError(res.status, text, (n) => res.headers.get(n));
    }

    const stream = res.bodyStream();
    if (!stream) {
      throw new Error('Response body stream is not available');
    }
    return stream;
  }

  async connect(config: TtsStreamingConfig, options?: RequestOptions): Promise<TtsStreamingSession> {
    const model = config.model ?? 'bulbul:v4-flash';
    const query = new URLSearchParams({
      model,
      send_completion_event: 'true',
    });

    const wsUrl = `${this.context.getWsBaseUrl()}/text-to-speech/ws?${query.toString()}`;

    // Resolve credentials
    const creds = await this.context.getAuthProvider().getCredentials();
    const wsHeaders: Record<string, string> = { ...options?.headers };
    const subprotocols: string[] = [];

    switch (creds.kind) {
      case 'subscriptionKey':
        wsHeaders['Api-Subscription-Key'] = creds.key;
        subprotocols.push(`api-subscription-key.${creds.key}`);
        break;
      case 'bearerToken':
        wsHeaders['Authorization'] = `Bearer ${creds.token}`;
        subprotocols.push(`bearer.${creds.token}`);
        break;
      case 'customHeaders':
        for (const [k, v] of Object.entries(creds.headers)) {
          wsHeaders[k] = v;
        }
        break;
    }

    const wsFactory = this.context.getWebSocketFactory();
    const ws = await wsFactory.connect(wsUrl, {
      headers: wsHeaders,
      protocols: subprotocols,
    });

    return new TtsStreamingSession(ws, config);
  }
}
