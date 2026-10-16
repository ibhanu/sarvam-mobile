import { RequestOptions, ClientDispatcher } from './types.js';
import { FileInput, HttpRequest, HttpResponse } from '../transport/http.js';
import { createHttpError } from '../errors.js';

export class JobsResource {
  private readonly dispatcher: ClientDispatcher;

  constructor(dispatcher: ClientDispatcher) {
    this.dispatcher = dispatcher;
  }

  /**
   * Uploads file data directly to an Azure Blob SAS signed URL.
   * Mandates and automatically injects header `x-ms-blob-type: BlockBlob`.
   */
  async uploadToSignedUrl(
    uploadUrl: string,
    fileInput: FileInput,
    options?: RequestOptions
  ): Promise<void> {
    const headers: Record<string, string> = {
      'x-ms-blob-type': 'BlockBlob',
      'content-type': 'application/octet-stream',
      ...options?.headers,
    };

    let body: any;
    if (fileInput instanceof Uint8Array) {
      body = fileInput;
    } else if (typeof Blob !== 'undefined' && fileInput instanceof Blob) {
      body = fileInput;
    } else if (typeof fileInput === 'object' && 'uri' in fileInput) {
      // React Native file input
      body = fileInput;
    } else {
      body = fileInput;
    }

    const httpReq: HttpRequest = {
      method: 'PUT',
      url: uploadUrl,
      headers,
      body,
      signal: options?.signal,
      timeoutMs: options?.timeoutMs,
      operationKind: 'IDEMPOTENT',
    };

    const res = await this.dispatcher.execute(httpReq);
    if (res.status >= 400) {
      const text = await res.text();
      throw await createHttpError(res.status, text, (n) => res.headers.get(n));
    }
  }
}
