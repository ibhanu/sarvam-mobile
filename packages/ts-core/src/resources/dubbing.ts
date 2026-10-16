import { RequestOptions, ClientDispatcher } from './types.js';
import { createHttpError } from '../errors.js';
import {
  pollUntilComplete,
  WaitUntilCompleteOptions,
  isStandardJobComplete,
  isStandardJobFailed,
  getStandardJobFailureMessage,
} from './polling.js';

export interface DubbingCreateRequest {
  source_language_code?: string;
  sourceLanguageCode?: string;
  src_lang?: string;
  target_language_codes?: string[];
  targetLanguageCodes?: string[];
  target_langs?: string[];
  [key: string]: unknown;
}

export class DubbingResource {
  private readonly dispatcher: ClientDispatcher;

  constructor(dispatcher: ClientDispatcher) {
    this.dispatcher = dispatcher;
  }

  async create(request: DubbingCreateRequest, options?: RequestOptions): Promise<any> {
    // Routes to dubbing environment host!
    const url = `${this.dispatcher.getDubbingBaseUrl()}/jobs`;

    const body: Record<string, unknown> = { ...request };
    const srcLang =
      request.source_language_code ?? request.sourceLanguageCode ?? request.src_lang;
    if (srcLang) {
      body['src_lang'] = srcLang;
      delete body['source_language_code'];
      delete body['sourceLanguageCode'];
    }

    const targetLangs =
      request.target_language_codes ?? request.targetLanguageCodes ?? request.target_langs;
    if (targetLangs) {
      body['target_langs'] = targetLangs;
      delete body['target_language_codes'];
      delete body['targetLanguageCodes'];
    }

    const headers: Record<string, string> = {
      'content-type': 'application/json',
      ...options?.headers,
    };
    if (options?.idempotencyKey) {
      headers['idempotency-key'] = options.idempotencyKey;
    }

    const res = await this.dispatcher.execute({
      method: 'POST',
      url,
      headers,
      body: JSON.stringify(body),
      signal: options?.signal,
      timeoutMs: options?.timeoutMs,
      operationKind: 'JOB_CREATE',
    });
    if (res.status >= 400) {
      throw await createHttpError(res.status, await res.text(), (n) => res.headers.get(n));
    }
    return res.json();
  }

  async start(jobId: string, options?: RequestOptions): Promise<any> {
    const url = `${this.dispatcher.getDubbingBaseUrl()}/jobs/${encodeURIComponent(jobId)}/start`;
    const res = await this.dispatcher.execute({
      method: 'POST',
      url,
      headers: { ...options?.headers },
      signal: options?.signal,
      timeoutMs: options?.timeoutMs,
      operationKind: 'STATELESS_POST',
    });
    if (res.status >= 400) {
      throw await createHttpError(res.status, await res.text(), (n) => res.headers.get(n));
    }
    return res.json();
  }

  async getLiveStatus(jobId: string, options?: RequestOptions): Promise<any> {
    const url = `${this.dispatcher.getDubbingBaseUrl()}/jobs/${encodeURIComponent(jobId)}/live-status`;
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

  async getExportStatus(jobId: string, options?: RequestOptions): Promise<any> {
    const url = `${this.dispatcher.getDubbingBaseUrl()}/jobs/${encodeURIComponent(jobId)}/export-status`;
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

  async waitUntilComplete(
    jobId: string,
    options?: RequestOptions & WaitUntilCompleteOptions
  ): Promise<any> {
    return pollUntilComplete({
      poll: () => this.getLiveStatus(jobId, options),
      isComplete: isStandardJobComplete,
      isFailed: isStandardJobFailed,
      getFailureMessage: getStandardJobFailureMessage,
      clock: options?.clock ?? this.dispatcher.getClock?.(),
      signal: options?.signal,
      timeoutMs: options?.timeoutMs,
      initialIntervalMs: options?.initialIntervalMs,
      maxIntervalMs: options?.maxIntervalMs,
      backoffMultiplier: options?.backoffMultiplier,
    });
  }
}
