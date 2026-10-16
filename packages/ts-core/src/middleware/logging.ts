import { Middleware, NextHandler } from './types.js';
import { HttpRequest, HttpResponse } from '../transport/http.js';

export interface Logger {
  debug?(message: string, ...args: unknown[]): void;
  info?(message: string, ...args: unknown[]): void;
  warn?(message: string, ...args: unknown[]): void;
  error?(message: string, ...args: unknown[]): void;
}

export function redactHeaders(headers: Record<string, string>): Record<string, string> {
  const redacted: Record<string, string> = {};
  for (const [k, v] of Object.entries(headers)) {
    const lower = k.toLowerCase();
    if (lower === 'api-subscription-key' || lower === 'authorization') {
      redacted[k] = '[REDACTED]';
    } else {
      redacted[k] = v;
    }
  }
  return redacted;
}

export function createLoggingMiddleware(logger?: Logger): Middleware {
  if (!logger) {
    // No-op middleware if no logger provided
    return async (request: HttpRequest, next: NextHandler): Promise<HttpResponse> => {
      return next(request);
    };
  }

  return async (request: HttpRequest, next: NextHandler): Promise<HttpResponse> => {
    const start = Date.now();
    try {
      const response = await next(request);
      const duration = Date.now() - start;
      const reqId = response.headers.get('x-request-id') ?? response.headers.get('x-ms-request-id');
      const msg = `[SarvamSDK] ${request.method} ${request.url} -> ${response.status} (${duration}ms)${
        reqId ? ` [req_id: ${reqId}]` : ''
      }`;
      if (response.status >= 500) {
        logger.error?.(msg);
      } else if (response.status >= 400) {
        logger.warn?.(msg);
      } else {
        logger.info?.(msg);
      }
      return response;
    } catch (err: unknown) {
      const duration = Date.now() - start;
      logger.error?.(
        `[SarvamSDK] ${request.method} ${request.url} failed after ${duration}ms: ${
          err instanceof Error ? err.message : String(err)
        }`
      );
      throw err;
    }
  };
}
