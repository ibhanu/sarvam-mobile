import { OperationKind } from '../generated/sarvamSpecGenerated.js';
import {
  ConnectionError,
  TimeoutError,
  isAbortError,
} from '../errors.js';

/**
 * Universal file input union supporting Uint8Array, Web Blob,
 * and React Native native file descriptor object.
 */
export type FileInput =
  | Uint8Array
  | Blob
  | {
      uri: string;
      name: string;
      type: string;
    };

export interface HttpRequest {
  method: string;
  url: string;
  headers: Record<string, string>;
  body?: string | Uint8Array | FormData | null;
  signal?: AbortSignal;
  operationKind?: OperationKind;
  timeoutMs?: number;
}

export interface HttpResponse {
  readonly status: number;
  readonly statusText: string;
  readonly headers: {
    get(name: string): string | null;
    has(name: string): boolean;
    entries(): IterableIterator<[string, string]>;
  };
  json<T = unknown>(): Promise<T>;
  text(): Promise<string>;
  bytes(): Promise<Uint8Array>;
  bodyStream(): AsyncIterable<Uint8Array> | null;
}

export interface HttpTransport {
  execute(request: HttpRequest): Promise<HttpResponse>;
}

/**
 * Standard fetch-based HttpTransport implementation.
 * Zero Node built-ins; works across Modern Browsers, React Native, Hermes, and Edge runtimes.
 */
export class FetchHttpTransport implements HttpTransport {
  private readonly defaultTimeoutMs: number;

  constructor(options?: { defaultTimeoutMs?: number }) {
    this.defaultTimeoutMs = options?.defaultTimeoutMs ?? 60_000;
  }

  async execute(request: HttpRequest): Promise<HttpResponse> {
    const timeoutMs = request.timeoutMs ?? this.defaultTimeoutMs;
    const controller = new AbortController();
    let timeoutId: ReturnType<typeof setTimeout> | undefined;
    let didTimeout = false;

    if (timeoutMs > 0 && timeoutMs !== Infinity) {
      timeoutId = setTimeout(() => {
        didTimeout = true;
        controller.abort(new TimeoutError(`Request timed out after ${timeoutMs}ms`, { phase: 'total' }));
      }, timeoutMs);
    }

    // Link caller's AbortSignal if provided
    const onCallerAbort = () => {
      controller.abort(request.signal?.reason);
    };
    if (request.signal) {
      if (request.signal.aborted) {
        if (timeoutId) clearTimeout(timeoutId);
        throw request.signal.reason ?? new Error('Request aborted');
      }
      request.signal.addEventListener('abort', onCallerAbort, { once: true });
    }

    try {
      const headersInit: Record<string, string> = { ...request.headers };

      let fetchBody: any = request.body;
      // If body is FormData, do not set Content-Type header so fetch can set boundary automatically
      if (typeof FormData !== 'undefined' && request.body instanceof FormData) {
        for (const key of Object.keys(headersInit)) {
          if (key.toLowerCase() === 'content-type') {
            delete headersInit[key];
          }
        }
      }

      const response = await globalThis.fetch(request.url, {
        method: request.method,
        headers: headersInit,
        body: fetchBody,
        signal: controller.signal,
      });

      return {
        status: response.status,
        statusText: response.statusText,
        headers: {
          get: (name: string) => response.headers.get(name),
          has: (name: string) => response.headers.has(name),
          entries: () => (response.headers.entries ? response.headers.entries() : [][Symbol.iterator]()),
        },
        json: async <T = unknown>(): Promise<T> => {
          return (await response.json()) as T;
        },
        text: async (): Promise<string> => {
          return await response.text();
        },
        bytes: async (): Promise<Uint8Array> => {
          const ab = await response.arrayBuffer();
          return new Uint8Array(ab);
        },
        bodyStream: (): AsyncIterable<Uint8Array> | null => {
          // If response.body is an async iterable or ReadableStream
          const body = response.body as any;
          if (!body) {
            // Fallback: arrayBuffer chunk
            return {
              async *[Symbol.asyncIterator]() {
                const ab = await response.arrayBuffer();
                yield new Uint8Array(ab);
              },
            };
          }

          if (typeof body[Symbol.asyncIterator] === 'function') {
            return {
              async *[Symbol.asyncIterator]() {
                for await (const chunk of body) {
                  yield chunk instanceof Uint8Array ? chunk : new Uint8Array(chunk);
                }
              },
            };
          }

          if (typeof body.getReader === 'function') {
            return {
              async *[Symbol.asyncIterator]() {
                const reader = body.getReader();
                try {
                  while (true) {
                    const { done, value } = await reader.read();
                    if (done) break;
                    if (value) {
                      yield value instanceof Uint8Array ? value : new Uint8Array(value);
                    }
                  }
                } finally {
                  reader.releaseLock?.();
                }
              },
            };
          }

          // Fallback if streaming is not supported
          return {
            async *[Symbol.asyncIterator]() {
              const ab = await response.arrayBuffer();
              yield new Uint8Array(ab);
            },
          };
        },
      };
    } catch (err: unknown) {
      if (didTimeout) {
        throw new TimeoutError(`Request timed out after ${timeoutMs}ms`, { phase: 'total', cause: err });
      }
      if (isAbortError(err)) {
        throw err;
      }
      if (request.signal?.aborted) {
        throw request.signal.reason ?? err;
      }
      throw new ConnectionError(err instanceof Error ? err.message : String(err), { cause: err });
    } finally {
      if (timeoutId) {
        clearTimeout(timeoutId);
      }
      if (request.signal) {
        request.signal.removeEventListener('abort', onCallerAbort);
      }
    }
  }
}
