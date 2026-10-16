import { RequestOptions, ClientDispatcher } from './types.js';
import { createHttpError } from '../errors.js';
import {
  pollUntilComplete,
  WaitUntilCompleteOptions,
  isStandardJobComplete,
  isStandardJobFailed,
  getStandardJobFailureMessage,
} from './polling.js';

export class SpeechToTextJobResource {
  private readonly dispatcher: ClientDispatcher;

  constructor(dispatcher: ClientDispatcher) {
    this.dispatcher = dispatcher;
  }

  async initialise(request: Record<string, unknown>, options?: RequestOptions): Promise<any> {
    const url = `${this.dispatcher.getApiBaseUrl()}/speech-to-text/job/v1`;
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

  async getUploadLinks(request: Record<string, unknown>, options?: RequestOptions): Promise<any> {
    const url = `${this.dispatcher.getApiBaseUrl()}/speech-to-text/job/v1/upload-files`;
    const res = await this.dispatcher.execute({
      method: 'POST',
      url,
      headers: { 'content-type': 'application/json', ...options?.headers },
      body: JSON.stringify(request),
      signal: options?.signal,
      timeoutMs: options?.timeoutMs,
      operationKind: 'STATELESS_POST',
    });
    if (res.status >= 400) {
      throw await createHttpError(res.status, await res.text(), (n) => res.headers.get(n));
    }
    return res.json();
  }

  async start(jobId: string, options?: RequestOptions): Promise<any> {
    const url = `${this.dispatcher.getApiBaseUrl()}/speech-to-text/job/v1/${encodeURIComponent(jobId)}/start`;
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

  async getStatus(jobId: string, options?: RequestOptions): Promise<any> {
    const url = `${this.dispatcher.getApiBaseUrl()}/speech-to-text/job/v1/${encodeURIComponent(jobId)}/status`;
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

  async getDownloadLinks(request: Record<string, unknown>, options?: RequestOptions): Promise<any> {
    const url = `${this.dispatcher.getApiBaseUrl()}/speech-to-text/job/v1/download-files`;
    const res = await this.dispatcher.execute({
      method: 'POST',
      url,
      headers: { 'content-type': 'application/json', ...options?.headers },
      body: JSON.stringify(request),
      signal: options?.signal,
      timeoutMs: options?.timeoutMs,
      operationKind: 'STATELESS_POST',
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
      poll: () => this.getStatus(jobId, options),
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

export class SpeechToTextTranslateJobResource {
  private readonly dispatcher: ClientDispatcher;

  constructor(dispatcher: ClientDispatcher) {
    this.dispatcher = dispatcher;
  }

  async initialise(request: Record<string, unknown>, options?: RequestOptions): Promise<any> {
    const url = `${this.dispatcher.getApiBaseUrl()}/speech-to-text-translate/job/v1`;
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

  async getUploadLinks(request: Record<string, unknown>, options?: RequestOptions): Promise<any> {
    const url = `${this.dispatcher.getApiBaseUrl()}/speech-to-text-translate/job/v1/upload-files`;
    const res = await this.dispatcher.execute({
      method: 'POST',
      url,
      headers: { 'content-type': 'application/json', ...options?.headers },
      body: JSON.stringify(request),
      signal: options?.signal,
      timeoutMs: options?.timeoutMs,
      operationKind: 'STATELESS_POST',
    });
    if (res.status >= 400) {
      throw await createHttpError(res.status, await res.text(), (n) => res.headers.get(n));
    }
    return res.json();
  }

  async start(jobId: string, options?: RequestOptions): Promise<any> {
    const url = `${this.dispatcher.getApiBaseUrl()}/speech-to-text-translate/job/v1/${encodeURIComponent(jobId)}/start`;
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

  async getStatus(jobId: string, options?: RequestOptions): Promise<any> {
    const url = `${this.dispatcher.getApiBaseUrl()}/speech-to-text-translate/job/v1/${encodeURIComponent(jobId)}/status`;
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

  async getDownloadLinks(request: Record<string, unknown>, options?: RequestOptions): Promise<any> {
    const url = `${this.dispatcher.getApiBaseUrl()}/speech-to-text-translate/job/v1/download-files`;
    const res = await this.dispatcher.execute({
      method: 'POST',
      url,
      headers: { 'content-type': 'application/json', ...options?.headers },
      body: JSON.stringify(request),
      signal: options?.signal,
      timeoutMs: options?.timeoutMs,
      operationKind: 'STATELESS_POST',
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
      poll: () => this.getStatus(jobId, options),
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
