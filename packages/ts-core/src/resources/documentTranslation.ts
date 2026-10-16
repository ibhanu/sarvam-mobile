import { RequestOptions, ClientDispatcher } from './types.js';
import { createHttpError } from '../errors.js';
import {
  pollUntilComplete,
  WaitUntilCompleteOptions,
  isStandardJobComplete,
  isStandardJobFailed,
  getStandardJobFailureMessage,
} from './polling.js';

export class DocumentTranslationResource {
  private readonly dispatcher: ClientDispatcher;

  constructor(dispatcher: ClientDispatcher) {
    this.dispatcher = dispatcher;
  }

  async create(request: Record<string, unknown>, options?: RequestOptions): Promise<any> {
    const url = `${this.dispatcher.getApiBaseUrl()}/translate/document/jobs`;
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
      body: JSON.stringify(request),
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
    const url = `${this.dispatcher.getApiBaseUrl()}/translate/document/jobs/${encodeURIComponent(jobId)}/start`;
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
    const url = `${this.dispatcher.getApiBaseUrl()}/translate/document/jobs/${encodeURIComponent(jobId)}/live-status`;
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

  async triggerExport(
    jobId: string,
    request?: Record<string, unknown>,
    options?: RequestOptions
  ): Promise<any> {
    const url = `${this.dispatcher.getApiBaseUrl()}/translate/document/jobs/${encodeURIComponent(jobId)}/export`;
    const res = await this.dispatcher.execute({
      method: 'POST',
      url,
      headers: { 'content-type': 'application/json', ...options?.headers },
      body: JSON.stringify(request ?? {}),
      signal: options?.signal,
      timeoutMs: options?.timeoutMs,
      operationKind: 'STATELESS_POST',
    });
    if (res.status >= 400) {
      throw await createHttpError(res.status, await res.text(), (n) => res.headers.get(n));
    }
    return res.json();
  }

  async getExportStatus(jobId: string, options?: RequestOptions): Promise<any> {
    const url = `${this.dispatcher.getApiBaseUrl()}/translate/document/jobs/${encodeURIComponent(jobId)}/export/status`;
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
