import { AudioCodec, LanguageCode, Speaker, TtsModel } from '../generated/sarvamSpecGenerated.js';
import { RequestOptions, ClientDispatcher } from './types.js';
import { FileInput } from '../transport/http.js';
import { createHttpError } from '../errors.js';
import { base64ToBytes } from '../utils/base64.js';
import { appendFileInput } from './form.js';
import { TtsStreamingSession, TtsStreamingConfig } from './textToSpeech.js';

export interface VoiceCloningProfile {
  voice_id: string;
  name?: string;
  created_at?: string;
  reference_text?: string;
  [key: string]: unknown;
}

export interface VoiceCloningListResponse {
  voices: VoiceCloningProfile[];
  [key: string]: unknown;
}

export interface VoiceCloningCreateRequest {
  file: FileInput;
  name?: string;
  reference_text?: string;
  referenceText?: string;
}

export interface VoiceCloningCreateResponse {
  voice_id: string;
  reference_text?: string;
  [key: string]: unknown;
}

export interface VoiceCloningConvertRequest {
  text: string;
  voice_id?: string;
  voiceId?: string;
  ref_audio?: FileInput;
  refAudio?: FileInput;
  target_language_code?: LanguageCode | string;
  targetLanguageCode?: LanguageCode | string;
  language_code?: LanguageCode | string;
  languageCode?: LanguageCode | string;
  speaker?: Speaker | string;
  model?: TtsModel | string;
  speech_sample_rate?: number;
  speechSampleRate?: number;
  output_audio_codec?: AudioCodec | string;
  outputAudioCodec?: AudioCodec | string;
  pace?: number;
  pitch?: number;
  loudness?: number;
  temperature?: number;
  enable_preprocessing?: boolean;
  enablePreprocessing?: boolean;
}

export interface VoiceCloningConvertResponse {
  audio?: string;
  audioBytes: Uint8Array;
  [key: string]: unknown;
}

export interface VoiceCloningStreamRequest {
  text: string;
  voice_id?: string;
  voiceId?: string;
  ref_audio?: FileInput;
  refAudio?: FileInput;
  target_language_code?: LanguageCode | string;
  targetLanguageCode?: LanguageCode | string;
  language_code?: LanguageCode | string;
  languageCode?: LanguageCode | string;
  speaker?: Speaker | string;
  model?: TtsModel | string;
  speech_sample_rate?: number;
  speechSampleRate?: number;
  output_audio_codec?: AudioCodec | string;
  outputAudioCodec?: AudioCodec | string;
  pace?: number;
  pitch?: number;
  loudness?: number;
  temperature?: number;
  enable_preprocessing?: boolean;
  enablePreprocessing?: boolean;
}

export interface VoiceCloningStreamingConfig extends TtsStreamingConfig {
  voice_id?: string;
  voiceId?: string;
  ref_audio?: string;
  refAudio?: string;
}

export class VoiceCloningResource {
  private readonly dispatcher: ClientDispatcher;

  constructor(dispatcher: ClientDispatcher) {
    this.dispatcher = dispatcher;
  }

  async listVoices(options?: RequestOptions): Promise<VoiceCloningListResponse> {
    const url = `${this.dispatcher.getApiBaseUrl()}/voices`;
    const res = await this.dispatcher.execute({
      method: 'GET',
      url,
      headers: { ...options?.headers },
      signal: options?.signal,
      timeoutMs: options?.timeoutMs,
      operationKind: 'IDEMPOTENT',
    });
    if (res.status >= 400) {
      throw await createHttpError(res.status, await res.text(), (n) => res.headers.get(n));
    }
    return (await res.json()) as VoiceCloningListResponse;
  }

  async createVoice(
    request: VoiceCloningCreateRequest,
    options?: RequestOptions
  ): Promise<VoiceCloningCreateResponse> {
    const url = `${this.dispatcher.getApiBaseUrl()}/voices/create`;
    const formData = new FormData();
    appendFileInput(formData, 'file', request.file, 'sample.wav');

    if (request.name) formData.append('name', request.name);
    const refText = request.reference_text ?? request.referenceText;
    if (refText) formData.append('reference_text', refText);

    const headers: Record<string, string> = { ...options?.headers };
    if (options?.idempotencyKey) {
      headers['idempotency-key'] = options.idempotencyKey;
    }

    const res = await this.dispatcher.execute({
      method: 'POST',
      url,
      headers,
      body: formData,
      signal: options?.signal,
      timeoutMs: options?.timeoutMs,
      operationKind: 'JOB_CREATE',
    });
    if (res.status >= 400) {
      throw await createHttpError(res.status, await res.text(), (n) => res.headers.get(n));
    }
    return (await res.json()) as VoiceCloningCreateResponse;
  }

  async getVoice(voiceId: string, options?: RequestOptions): Promise<VoiceCloningProfile> {
    const url = `${this.dispatcher.getApiBaseUrl()}/voices/${encodeURIComponent(voiceId)}`;
    const res = await this.dispatcher.execute({
      method: 'GET',
      url,
      headers: { ...options?.headers },
      signal: options?.signal,
      timeoutMs: options?.timeoutMs,
      operationKind: 'IDEMPOTENT',
    });
    if (res.status >= 400) {
      throw await createHttpError(res.status, await res.text(), (n) => res.headers.get(n));
    }
    return (await res.json()) as VoiceCloningProfile;
  }

  async deleteVoice(voiceId: string, options?: RequestOptions): Promise<Record<string, unknown>> {
    const url = `${this.dispatcher.getApiBaseUrl()}/voices/delete/${encodeURIComponent(voiceId)}`;
    const res = await this.dispatcher.execute({
      method: 'DELETE',
      url,
      headers: { ...options?.headers },
      signal: options?.signal,
      timeoutMs: options?.timeoutMs,
      operationKind: 'IDEMPOTENT',
    });
    if (res.status >= 400) {
      throw await createHttpError(res.status, await res.text(), (n) => res.headers.get(n));
    }
    return (await res.json()) as Record<string, unknown>;
  }

  async convert(
    request: VoiceCloningConvertRequest,
    options?: RequestOptions
  ): Promise<VoiceCloningConvertResponse> {
    const url = `${this.dispatcher.getApiBaseUrl()}/voices/clone`;
    const formData = new FormData();
    formData.append('text', request.text);

    const voiceId = request.voice_id ?? request.voiceId;
    if (voiceId) formData.append('voice_id', voiceId);

    const refAudio = request.ref_audio ?? request.refAudio;
    if (refAudio) appendFileInput(formData, 'ref_audio', refAudio, 'ref_audio.wav');

    const lang =
      request.target_language_code ??
      request.targetLanguageCode ??
      request.language_code ??
      request.languageCode;
    if (lang) formData.append('target_language_code', lang);

    if (request.speaker) formData.append('speaker', request.speaker);
    if (request.model) formData.append('model', request.model);
    const rate = request.speech_sample_rate ?? request.speechSampleRate;
    if (rate !== undefined) formData.append('speech_sample_rate', String(rate));
    const codec = request.output_audio_codec ?? request.outputAudioCodec;
    if (codec) formData.append('output_audio_codec', codec);
    if (request.pace !== undefined) formData.append('pace', String(request.pace));
    if (request.pitch !== undefined) formData.append('pitch', String(request.pitch));
    if (request.loudness !== undefined) formData.append('loudness', String(request.loudness));
    if (request.temperature !== undefined) formData.append('temperature', String(request.temperature));
    const preproc = request.enable_preprocessing ?? request.enablePreprocessing;
    if (preproc !== undefined) formData.append('enable_preprocessing', String(preproc));

    const headers: Record<string, string> = { ...options?.headers };
    if (options?.idempotencyKey) {
      headers['idempotency-key'] = options.idempotencyKey;
    }

    const res = await this.dispatcher.execute({
      method: 'POST',
      url,
      headers,
      body: formData,
      signal: options?.signal,
      timeoutMs: options?.timeoutMs,
      operationKind: 'MULTIPART_COMPUTE',
    });
    if (res.status >= 400) {
      throw await createHttpError(res.status, await res.text(), (n) => res.headers.get(n));
    }

    const json = (await res.json()) as Record<string, unknown>;
    const audioB64 = typeof json['audio'] === 'string' ? json['audio'] : '';
    const audioBytes = audioB64 ? base64ToBytes(audioB64) : new Uint8Array(0);

    return {
      ...json,
      audioBytes,
    };
  }

  async stream(
    request: VoiceCloningStreamRequest,
    options?: RequestOptions
  ): Promise<AsyncIterable<Uint8Array>> {
    const url = `${this.dispatcher.getApiBaseUrl()}/voices/clone/stream`;
    const formData = new FormData();
    formData.append('text', request.text);

    const voiceId = request.voice_id ?? request.voiceId;
    if (voiceId) formData.append('voice_id', voiceId);

    const refAudio = request.ref_audio ?? request.refAudio;
    if (refAudio) appendFileInput(formData, 'ref_audio', refAudio, 'ref_audio.wav');

    const lang =
      request.target_language_code ??
      request.targetLanguageCode ??
      request.language_code ??
      request.languageCode;
    if (lang) formData.append('target_language_code', lang);

    if (request.speaker) formData.append('speaker', request.speaker);
    if (request.model) formData.append('model', request.model);
    const rate = request.speech_sample_rate ?? request.speechSampleRate;
    if (rate !== undefined) formData.append('speech_sample_rate', String(rate));
    const codec = request.output_audio_codec ?? request.outputAudioCodec;
    if (codec) formData.append('output_audio_codec', codec);
    if (request.pace !== undefined) formData.append('pace', String(request.pace));
    if (request.pitch !== undefined) formData.append('pitch', String(request.pitch));
    if (request.loudness !== undefined) formData.append('loudness', String(request.loudness));
    if (request.temperature !== undefined) formData.append('temperature', String(request.temperature));
    const preproc = request.enable_preprocessing ?? request.enablePreprocessing;
    if (preproc !== undefined) formData.append('enable_preprocessing', String(preproc));

    const headers: Record<string, string> = {
      Accept: 'application/octet-stream',
      ...options?.headers,
    };
    if (options?.idempotencyKey) {
      headers['idempotency-key'] = options.idempotencyKey;
    }

    const res = await this.dispatcher.execute({
      method: 'POST',
      url,
      headers,
      body: formData,
      signal: options?.signal,
      timeoutMs: options?.timeoutMs,
      operationKind: 'MULTIPART_COMPUTE',
    });
    if (res.status >= 400) {
      throw await createHttpError(res.status, await res.text(), (n) => res.headers.get(n));
    }

    const stream = res.bodyStream();
    if (!stream) {
      throw new Error('Response body stream is not available');
    }
    return stream;
  }

  async connect(
    config: VoiceCloningStreamingConfig,
    options?: RequestOptions
  ): Promise<TtsStreamingSession> {
    if (
      !this.dispatcher.getWsBaseUrl ||
      !this.dispatcher.getAuthProvider ||
      !this.dispatcher.getWebSocketFactory
    ) {
      throw new Error('VoiceCloningResource.connect requires WebSocket context');
    }

    const wsUrl = `${this.dispatcher.getWsBaseUrl()}/voices/clone/ws?send_completion_event=true`;
    const creds = await this.dispatcher.getAuthProvider().getCredentials();
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

    const wsFactory = this.dispatcher.getWebSocketFactory();
    const ws = await wsFactory.connect(wsUrl, {
      headers: wsHeaders,
      protocols: subprotocols,
    });

    return new TtsStreamingSession(ws, config);
  }
}
