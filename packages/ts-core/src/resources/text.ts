import { LanguageCode } from '../generated/sarvamSpecGenerated.js';
import { RequestOptions, ClientDispatcher } from './types.js';
import { HttpRequest, HttpResponse } from '../transport/http.js';
import { createHttpError } from '../errors.js';

export interface TextTranslateRequest {
  input: string;
  source_language_code?: LanguageCode | string;
  target_language_code: LanguageCode | string;
  speaker_gender?: 'Male' | 'Female' | (string & {});
  mode?: 'formal' | 'code-mixed' | (string & {});
  model?: string;
}

export interface TextTranslateResponse {
  translated_text: string;
  translatedText: string;
}

export interface TextTransliterateRequest {
  input: string;
  source_language_code?: LanguageCode | string;
  target_language_code: LanguageCode | string;
  numerals_format?: string;
}

export interface TextTransliterateResponse {
  transliterated_text: string;
  transliteratedText: string;
}

export interface TextIdentifyLanguageRequest {
  input: string;
}

export interface TextIdentifyLanguageResponse {
  detected_language: string;
  confidence: number;
  detectedLanguage: string;
}

export class TextResource {
  private readonly dispatcher: ClientDispatcher;

  constructor(dispatcher: ClientDispatcher) {
    this.dispatcher = dispatcher;
  }

  async translate(
    request: TextTranslateRequest,
    options?: RequestOptions
  ): Promise<TextTranslateResponse> {
    const url = `${this.dispatcher.getApiBaseUrl()}/translate`;
    const headers: Record<string, string> = {
      'content-type': 'application/json',
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

    const res = await this.dispatcher.execute(httpReq);
    if (res.status >= 400) {
      const text = await res.text();
      throw await createHttpError(res.status, text, (n) => res.headers.get(n));
    }

    const data = (await res.json()) as { translated_text: string };
    return {
      translated_text: data.translated_text,
      translatedText: data.translated_text,
    };
  }

  async transliterate(
    request: TextTransliterateRequest,
    options?: RequestOptions
  ): Promise<TextTransliterateResponse> {
    const url = `${this.dispatcher.getApiBaseUrl()}/transliterate`;
    const headers: Record<string, string> = {
      'content-type': 'application/json',
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

    const res = await this.dispatcher.execute(httpReq);
    if (res.status >= 400) {
      const text = await res.text();
      throw await createHttpError(res.status, text, (n) => res.headers.get(n));
    }

    const data = (await res.json()) as { transliterated_text: string };
    return {
      transliterated_text: data.transliterated_text,
      transliteratedText: data.transliterated_text,
    };
  }

  async identifyLanguage(
    request: TextIdentifyLanguageRequest,
    options?: RequestOptions
  ): Promise<TextIdentifyLanguageResponse> {
    const url = `${this.dispatcher.getApiBaseUrl()}/text-lid`;
    const headers: Record<string, string> = {
      'content-type': 'application/json',
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

    const res = await this.dispatcher.execute(httpReq);
    if (res.status >= 400) {
      const text = await res.text();
      throw await createHttpError(res.status, text, (n) => res.headers.get(n));
    }

    const data = (await res.json()) as { detected_language: string; confidence: number };
    return {
      detected_language: data.detected_language,
      confidence: data.confidence,
      detectedLanguage: data.detected_language,
    };
  }
}
