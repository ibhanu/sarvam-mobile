import { LanguageCode, SttModel, SttMode } from '../generated/sarvamSpecGenerated.js';
import { RequestOptions } from './types.js';
import { FileInput, HttpRequest, HttpResponse } from '../transport/http.js';
import { WebSocketConnection, WebSocketFactory } from '../transport/websocket.js';
import { AuthProvider } from '../auth.js';
import { BadRequestError, RealtimeError, createHttpError } from '../errors.js';
import { bytesToBase64 } from '../utils/base64.js';

export interface SttTranscribeRequest {
  file: FileInput;
  model?: SttModel | string;
  language_code?: LanguageCode | string;
  prompt?: string;
  with_diarization?: boolean;
}

export interface SttTranscribeResponse {
  transcript: string;
  language_code?: string;
  timestamps?: unknown;
  diarized_transcript?: unknown;
}

export interface SttTranslateRequest {
  file: FileInput;
  model?: SttModel | string;
  prompt?: string;
}

export interface SttTranslateResponse {
  transcript: string;
  language_code?: string;
  timestamps?: unknown;
}

export interface SttRealtimeConfig {
  language_code?: LanguageCode | string;
  languageCode?: LanguageCode | string;
  model?: SttModel | string;
  sample_rate?: number;
  sampleRate?: number;
  stream_type?: string;
  streamType?: string;
  mode?: SttMode | string;
  encoding?: string;
  return_timestamps?: boolean;
  returnTimestamps?: boolean;
  endpointing?: boolean;
  threshold?: number;
  prefix_padding_ms?: number;
  prefixPaddingMs?: number;
  silence_duration_ms?: number;
  silenceDurationMs?: number;
  min_speech_duration_ms?: number;
  minSpeechDurationMs?: number;
  prompt?: string;
  keyterms?: string[];
}

export interface SttRealtimeConfigUpdate {
  mode?: SttMode | string;
  keyterms?: string[];
  threshold?: number;
  silenceDurationMs?: number;
  silence_duration_ms?: number;
}

export type SttRealtimeEvent =
  | { type: 'session_begin'; sessionId: string; raw: Record<string, unknown> }
  | { type: 'vad_speech_start'; timestampMs?: number; raw: Record<string, unknown> }
  | { type: 'vad_speech_end'; timestampMs?: number; raw: Record<string, unknown> }
  | {
      type: 'transcript_partial';
      utteranceIdx?: number;
      text: string;
      language?: LanguageCode | string;
      raw: Record<string, unknown>;
    }
  | {
      type: 'transcript_final';
      utteranceIdx?: number;
      text: string;
      language?: LanguageCode | string;
      languageConfidence?: number;
      startS?: number;
      endS?: number;
      raw: Record<string, unknown>;
    }
  | { type: 'session_end'; durationSeconds?: number; raw: Record<string, unknown> }
  | { type: 'error'; code?: string; message: string; raw: Record<string, unknown> }
  | { type: 'unknown'; rawJson: string };

export class SttRealtimeSession {
  private readonly ws: WebSocketConnection;
  private readonly eventQueue: SttRealtimeEvent[] = [];
  private readonly waitingResolvers: Array<{
    resolve: (result: IteratorResult<SttRealtimeEvent>) => void;
    reject: (err: any) => void;
  }> = [];
  private isClosed = false;
  private closeError: Error | null = null;

  constructor(ws: WebSocketConnection) {
    this.ws = ws;

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

  private mapJsonToEvent(json: Record<string, unknown>, rawJson: string): SttRealtimeEvent {
    const eventName = typeof json['event'] === 'string' ? json['event'] : '';
    switch (eventName) {
      case 'session_begin':
        return {
          type: 'session_begin',
          sessionId: (json['session_id'] as string) ?? '',
          raw: json,
        };
      case 'vad_speech_start':
      case 'speech_start':
        return {
          type: 'vad_speech_start',
          timestampMs: json['timestamp_ms'] as number | undefined,
          raw: json,
        };
      case 'vad_speech_end':
      case 'speech_end':
        return {
          type: 'vad_speech_end',
          timestampMs: json['timestamp_ms'] as number | undefined,
          raw: json,
        };
      case 'transcript_partial':
        return {
          type: 'transcript_partial',
          utteranceIdx: json['utterance_idx'] as number | undefined,
          text: (json['text'] as string) ?? '',
          language: json['language'] as string | undefined,
          raw: json,
        };
      case 'transcript_final':
      case 'transcript':
        return {
          type: 'transcript_final',
          utteranceIdx: json['utterance_idx'] as number | undefined,
          text: (json['text'] as string) ?? '',
          language: json['language'] as string | undefined,
          languageConfidence: json['language_confidence'] as number | undefined,
          startS: json['start_s'] as number | undefined,
          endS: json['end_s'] as number | undefined,
          raw: json,
        };
      case 'session_end':
        return {
          type: 'session_end',
          durationSeconds: json['duration_seconds'] as number | undefined,
          raw: json,
        };
      case 'error':
        return {
          type: 'error',
          code: json['code'] as string | undefined,
          message: (json['message'] as string) ?? 'STT Realtime error',
          raw: json,
        };
      default:
        return {
          type: 'unknown',
          rawJson,
        };
    }
  }

  private pushEvent(event: SttRealtimeEvent): void {
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

  sendAudio(pcmBytes: Uint8Array): void {
    const base64 = bytesToBase64(pcmBytes);
    this.ws.send(JSON.stringify({ event: 'audio_input', audio: base64 }));
  }

  updateConfig(updates: SttRealtimeConfigUpdate): void {
    const payload: Record<string, unknown> = {
      event: 'config_update',
    };
    if (updates.mode) payload['mode'] = updates.mode;
    if (updates.keyterms) payload['keyterms'] = updates.keyterms;
    if (updates.threshold !== undefined) payload['threshold'] = updates.threshold;
    if (updates.silenceDurationMs !== undefined || updates.silence_duration_ms !== undefined) {
      payload['silence_duration_ms'] = updates.silenceDurationMs ?? updates.silence_duration_ms;
    }
    this.ws.send(JSON.stringify(payload));
  }

  flush(): void {
    this.ws.send(JSON.stringify({ event: 'flush' }));
  }

  ping(): void {
    this.ws.send(JSON.stringify({ event: 'ping' }));
  }

  end(): void {
    this.ws.send(JSON.stringify({ event: 'end' }));
  }

  close(code = 1000, reason = 'Normal Closure'): void {
    this.isClosed = true;
    this.ws.close(code, reason);
  }

  get events(): AsyncIterable<SttRealtimeEvent> {
    return {
      [Symbol.asyncIterator]: () => {
        return {
          next: (): Promise<IteratorResult<SttRealtimeEvent>> => {
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
            return new Promise<IteratorResult<SttRealtimeEvent>>((resolve, reject) => {
              this.waitingResolvers.push({ resolve, reject });
            });
          },
        };
      },
    };
  }
}

export interface SpeechToTextClientContext {
  execute(request: HttpRequest): Promise<HttpResponse>;
  getApiBaseUrl(): string;
  getWsBaseUrl(): string;
  getAuthProvider(): AuthProvider;
  getWebSocketFactory(): WebSocketFactory;
}

export class SpeechToTextResource {
  private readonly context: SpeechToTextClientContext;

  constructor(context: SpeechToTextClientContext) {
    this.context = context;
  }

  async transcribe(
    request: SttTranscribeRequest,
    options?: RequestOptions
  ): Promise<SttTranscribeResponse> {
    const url = `${this.context.getApiBaseUrl()}/speech-to-text`;
    const formData = new FormData();

    if (request.file instanceof Uint8Array) {
      formData.append('file', new Blob([request.file as any]), 'audio.wav');
    } else if (typeof Blob !== 'undefined' && request.file instanceof Blob) {
      formData.append('file', request.file, 'audio.wav');
    } else {
      // React Native file descriptor object
      formData.append('file', request.file as any);
    }

    if (request.model) formData.append('model', request.model);
    if (request.language_code) formData.append('language_code', request.language_code);
    if (request.prompt) formData.append('prompt', request.prompt);
    if (request.with_diarization !== undefined) {
      formData.append('with_diarization', String(request.with_diarization));
    }

    const headers: Record<string, string> = { ...options?.headers };
    if (options?.idempotencyKey) {
      headers['idempotency-key'] = options.idempotencyKey;
    }

    const httpReq: HttpRequest = {
      method: 'POST',
      url,
      headers,
      body: formData,
      signal: options?.signal,
      timeoutMs: options?.timeoutMs,
      operationKind: 'MULTIPART_COMPUTE',
    };

    const res = await this.context.execute(httpReq);
    if (res.status >= 400) {
      const text = await res.text();
      throw await createHttpError(res.status, text, (n) => res.headers.get(n));
    }

    return (await res.json()) as SttTranscribeResponse;
  }

  async translate(
    request: SttTranslateRequest,
    options?: RequestOptions
  ): Promise<SttTranslateResponse> {
    const url = `${this.context.getApiBaseUrl()}/speech-to-text-translate`;
    const formData = new FormData();

    if (request.file instanceof Uint8Array) {
      formData.append('file', new Blob([request.file as any]), 'audio.wav');
    } else if (typeof Blob !== 'undefined' && request.file instanceof Blob) {
      formData.append('file', request.file, 'audio.wav');
    } else {
      formData.append('file', request.file as any);
    }

    if (request.model) formData.append('model', request.model);
    if (request.prompt) formData.append('prompt', request.prompt);

    const headers: Record<string, string> = { ...options?.headers };
    if (options?.idempotencyKey) {
      headers['idempotency-key'] = options.idempotencyKey;
    }

    const httpReq: HttpRequest = {
      method: 'POST',
      url,
      headers,
      body: formData,
      signal: options?.signal,
      timeoutMs: options?.timeoutMs,
      operationKind: 'MULTIPART_COMPUTE',
    };

    const res = await this.context.execute(httpReq);
    if (res.status >= 400) {
      const text = await res.text();
      throw await createHttpError(res.status, text, (n) => res.headers.get(n));
    }

    return (await res.json()) as SttTranslateResponse;
  }

  async connect(config: SttRealtimeConfig, options?: RequestOptions): Promise<SttRealtimeSession> {
    const sampleRate = config.sampleRate ?? config.sample_rate;
    // Client-side sample rate validation (api-contract.md §7.2 / case ws-stt-invalid-sample-rate)
    if (sampleRate !== undefined && sampleRate !== 16000 && sampleRate !== 8000) {
      throw new BadRequestError('sampleRate must be 16000 or 8000', { statusCode: 400 });
    }

    const query = new URLSearchParams();
    const lang = config.languageCode ?? config.language_code;
    if (lang) query.set('language_code', lang);
    if (config.model) query.set('model', config.model);
    const streamType = config.streamType ?? config.stream_type;
    if (streamType) query.set('stream_type', streamType);
    if (config.mode) query.set('mode', config.mode);
    if (config.encoding) query.set('encoding', config.encoding);
    if (sampleRate !== undefined) query.set('sample_rate', String(sampleRate));
    const retTimestamps = config.returnTimestamps ?? config.return_timestamps;
    if (retTimestamps !== undefined) query.set('return_timestamps', String(retTimestamps));
    if (config.endpointing !== undefined) query.set('endpointing', String(config.endpointing));
    if (config.threshold !== undefined) query.set('threshold', String(config.threshold));
    const prefixPadding = config.prefixPaddingMs ?? config.prefix_padding_ms;
    if (prefixPadding !== undefined) query.set('prefix_padding_ms', String(prefixPadding));
    const silenceDuration = config.silenceDurationMs ?? config.silence_duration_ms;
    if (silenceDuration !== undefined) query.set('silence_duration_ms', String(silenceDuration));
    const minSpeechDuration = config.minSpeechDurationMs ?? config.min_speech_duration_ms;
    if (minSpeechDuration !== undefined) query.set('min_speech_duration_ms', String(minSpeechDuration));
    if (config.prompt) query.set('prompt', config.prompt);
    if (config.keyterms && config.keyterms.length > 0) {
      query.set('keyterms', config.keyterms.join(','));
    }

    const wsUrl = `${this.context.getWsBaseUrl()}/speech-to-text-realtime/ws?${query.toString()}`;

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

    return new SttRealtimeSession(ws);
  }
}
