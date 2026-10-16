import { RequestOptions, ClientDispatcher } from './types.js';
import { HttpRequest, HttpResponse } from '../transport/http.js';
import { createHttpError } from '../errors.js';
import { parseSseStream, SseEvent } from '../streaming/sse.js';

export interface ResponsesRequest {
  model: string;
  input: string | unknown[];
  [key: string]: unknown;
}

export interface ResponsesSseEvent {
  event?: string;
  data: Record<string, unknown>;
  raw: SseEvent;
}

export class ResponsesResource {
  private readonly dispatcher: ClientDispatcher;

  constructor(dispatcher: ClientDispatcher) {
    this.dispatcher = dispatcher;
  }

  async createStream(
    request: ResponsesRequest,
    options?: RequestOptions
  ): Promise<AsyncIterable<ResponsesSseEvent>> {
    const url = `${this.dispatcher.getApiBaseUrl()}/v2/responses`;
    const headers: Record<string, string> = {
      'content-type': 'application/json',
      Accept: 'text/event-stream',
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

    const stream = res.bodyStream();
    if (!stream) {
      throw new Error('Response stream not available');
    }

    return {
      async *[Symbol.asyncIterator]() {
        for await (const sse of parseSseStream(stream, {
          isResponsesApi: true,
          signal: options?.signal,
        })) {
          let dataObj: Record<string, unknown> = {};
          if (sse.data) {
            try {
              dataObj = JSON.parse(sse.data) as Record<string, unknown>;
            } catch {
              dataObj = { raw: sse.data };
            }
          }
          yield {
            event: sse.event,
            data: dataObj,
            raw: sse,
          };
        }
      },
    };
  }
}
