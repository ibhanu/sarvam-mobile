import { RequestOptions, ClientDispatcher } from './types.js';
import { FileInput } from '../transport/http.js';
import { createHttpError } from '../errors.js';
import { appendFileInput } from './form.js';

export interface PronunciationDictionaryCreateRequest {
  file: FileInput;
  language_code?: string;
  languageCode?: string;
  [key: string]: unknown;
}

export interface PronunciationDictionaryUpdateRequest {
  file: FileInput;
  [key: string]: unknown;
}

export class PronunciationDictionaryResource {
  private readonly dispatcher: ClientDispatcher;

  constructor(dispatcher: ClientDispatcher) {
    this.dispatcher = dispatcher;
  }

  async list(options?: RequestOptions): Promise<any> {
    const url = `${this.dispatcher.getApiBaseUrl()}/text-to-speech/pronunciation-dictionary`;
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
    return res.json();
  }

  async create(
    request: PronunciationDictionaryCreateRequest,
    options?: RequestOptions
  ): Promise<any> {
    const url = `${this.dispatcher.getApiBaseUrl()}/text-to-speech/pronunciation-dictionary`;
    const formData = new FormData();
    appendFileInput(formData, 'file', request.file, 'dictionary.json');

    const lang = request.language_code ?? request.languageCode;
    if (lang) formData.append('language_code', lang);

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
    return res.json();
  }

  async update(
    dictId: string,
    request: PronunciationDictionaryUpdateRequest,
    options?: RequestOptions
  ): Promise<any> {
    const url = `${this.dispatcher.getApiBaseUrl()}/text-to-speech/pronunciation-dictionary?dict_id=${encodeURIComponent(dictId)}`;
    const formData = new FormData();
    appendFileInput(formData, 'file', request.file, 'dictionary.json');

    const headers: Record<string, string> = { ...options?.headers };
    if (options?.idempotencyKey) {
      headers['idempotency-key'] = options.idempotencyKey;
    }

    const res = await this.dispatcher.execute({
      method: 'PUT',
      url,
      headers,
      body: formData,
      signal: options?.signal,
      timeoutMs: options?.timeoutMs,
      operationKind: 'IDEMPOTENT',
    });
    if (res.status >= 400) {
      throw await createHttpError(res.status, await res.text(), (n) => res.headers.get(n));
    }
    return res.json();
  }

  async get(dictId: string, options?: RequestOptions): Promise<any> {
    const url = `${this.dispatcher.getApiBaseUrl()}/text-to-speech/pronunciation-dictionary/${encodeURIComponent(dictId)}`;
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
    return res.json();
  }

  async delete(dictId: string, options?: RequestOptions): Promise<any> {
    const url = `${this.dispatcher.getApiBaseUrl()}/text-to-speech/pronunciation-dictionary?dict_id=${encodeURIComponent(dictId)}`;
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
    return res.json();
  }
}
