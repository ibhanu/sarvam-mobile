import { RequestOptions, ClientDispatcher } from './types.js';
import { FileInput } from '../transport/http.js';
import { createHttpError } from '../errors.js';
import { appendFileInput } from './form.js';
import {
  pollUntilComplete,
  WaitUntilCompleteOptions,
  isStandardJobComplete,
  isStandardJobFailed,
  getStandardJobFailureMessage,
} from './polling.js';

export interface DocAiDigitiseRequest {
  file?: FileInput | FileInput[];
  files?: FileInput[];
  output_format?: 'md' | 'html' | string;
  outputFormat?: 'md' | 'html' | string;
  language_code?: string;
  languageCode?: string;
  [key: string]: unknown;
}

export interface DocAiExtractRequest {
  file?: FileInput | FileInput[];
  files?: FileInput[];
  schema: Record<string, unknown> | unknown[] | string;
  language_code?: string;
  languageCode?: string;
  [key: string]: unknown;
}

export interface DocAiCreateUploadUrlRequest {
  file_name?: string;
  fileName?: string;
  content_type?: string;
  contentType?: string;
  [key: string]: unknown;
}

export interface DocAiJobInitialResponse {
  job_id: string;
  status?: string;
  [key: string]: unknown;
}

export interface DocAiJobStatusResponse {
  job_id: string;
  status: string;
  job_state?: string;
  error_message?: string;
  [key: string]: unknown;
}

export interface DocAiJobResultsResponse {
  job_id: string;
  status?: string;
  data?: unknown;
  extracted_data?: unknown;
  markdown?: string;
  html?: string;
  [key: string]: unknown;
}

export interface DocAiJobWaitResponse extends Omit<DocAiJobResultsResponse, 'status'> {
  status: DocAiJobStatusResponse;
}

export interface DocAiDownloadUrlResponse {
  job_id: string;
  download_url?: string;
  downloadUrl?: string;
  [key: string]: unknown;
}

export class DocAiResource {
  private readonly dispatcher: ClientDispatcher;

  constructor(dispatcher: ClientDispatcher) {
    this.dispatcher = dispatcher;
  }

  async digitise(
    request: DocAiDigitiseRequest,
    options?: RequestOptions
  ): Promise<DocAiJobInitialResponse> {
    const url = `${this.dispatcher.getApiBaseUrl()}/doc-ai/v1/job/digitise`;
    const formData = new FormData();

    const rawFiles = request.files ?? request.file;
    const files = Array.isArray(rawFiles) ? rawFiles : rawFiles ? [rawFiles] : [];

    for (const f of files) {
      appendFileInput(formData, 'file', f, 'document.pdf');
    }

    const outputFormat = request.output_format ?? request.outputFormat;
    if (outputFormat) formData.append('output_format', outputFormat);

    const lang = request.language_code ?? request.languageCode;
    if (lang) formData.append('language_code', lang);

    for (const [k, v] of Object.entries(request)) {
      if (
        k !== 'file' &&
        k !== 'files' &&
        k !== 'output_format' &&
        k !== 'outputFormat' &&
        k !== 'language_code' &&
        k !== 'languageCode'
      ) {
        if (typeof v === 'string') formData.append(k, v);
        else if (typeof v === 'number' || typeof v === 'boolean') formData.append(k, String(v));
      }
    }

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
    return (await res.json()) as DocAiJobInitialResponse;
  }

  async extract(
    request: DocAiExtractRequest,
    options?: RequestOptions
  ): Promise<DocAiJobInitialResponse> {
    const url = `${this.dispatcher.getApiBaseUrl()}/doc-ai/v1/job/extract`;
    const formData = new FormData();

    const rawFiles = request.files ?? request.file;
    const files = Array.isArray(rawFiles) ? rawFiles : rawFiles ? [rawFiles] : [];

    for (const f of files) {
      appendFileInput(formData, 'file', f, 'document.pdf');
    }

    // Auto-serializing schema object or string into a JSON string multipart field!
    const schemaStr =
      typeof request.schema === 'string'
        ? request.schema
        : JSON.stringify(request.schema);
    formData.append('schema', schemaStr);

    const lang = request.language_code ?? request.languageCode;
    if (lang) formData.append('language_code', lang);

    for (const [k, v] of Object.entries(request)) {
      if (
        k !== 'file' &&
        k !== 'files' &&
        k !== 'schema' &&
        k !== 'language_code' &&
        k !== 'languageCode'
      ) {
        if (typeof v === 'string') formData.append(k, v);
        else if (typeof v === 'number' || typeof v === 'boolean') formData.append(k, String(v));
      }
    }

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
    return (await res.json()) as DocAiJobInitialResponse;
  }

  async createUploadUrl(
    request?: DocAiCreateUploadUrlRequest,
    options?: RequestOptions
  ): Promise<Record<string, unknown>> {
    const url = `${this.dispatcher.getApiBaseUrl()}/doc-ai/v1/job/upload`;
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
      body: JSON.stringify(request ?? {}),
      signal: options?.signal,
      timeoutMs: options?.timeoutMs,
      operationKind: 'STATELESS_POST',
    });
    if (res.status >= 400) {
      throw await createHttpError(res.status, await res.text(), (n) => res.headers.get(n));
    }
    return (await res.json()) as Record<string, unknown>;
  }

  async getStatus(jobId: string, options?: RequestOptions): Promise<DocAiJobStatusResponse> {
    const url = `${this.dispatcher.getApiBaseUrl()}/doc-ai/v1/job/${encodeURIComponent(jobId)}/status`;
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
    return (await res.json()) as DocAiJobStatusResponse;
  }

  async getResults(jobId: string, options?: RequestOptions): Promise<DocAiJobResultsResponse> {
    const url = `${this.dispatcher.getApiBaseUrl()}/doc-ai/v1/job/${encodeURIComponent(jobId)}/results`;
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
    return (await res.json()) as DocAiJobResultsResponse;
  }

  async getDownloadUrl(jobId: string, options?: RequestOptions): Promise<DocAiDownloadUrlResponse> {
    const url = `${this.dispatcher.getApiBaseUrl()}/doc-ai/v1/job/${encodeURIComponent(jobId)}/download-url`;
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
    return (await res.json()) as DocAiDownloadUrlResponse;
  }

  async digitiseAndWait(
    request: DocAiDigitiseRequest,
    options?: RequestOptions & WaitUntilCompleteOptions
  ): Promise<DocAiJobWaitResponse> {
    const initial = await this.digitise(request, options);
    const jobId = initial.job_id ?? (initial as any).jobId;
    const status = await pollUntilComplete({
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
    const results = await this.getResults(jobId, options);
    return {
      ...results,
      status,
    };
  }

  async extractAndWait(
    request: DocAiExtractRequest,
    options?: RequestOptions & WaitUntilCompleteOptions
  ): Promise<DocAiJobWaitResponse> {
    const initial = await this.extract(request, options);
    const jobId = initial.job_id ?? (initial as any).jobId;
    const status = await pollUntilComplete({
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
    const results = await this.getResults(jobId, options);
    return {
      ...results,
      status,
    };
  }
}
