import { OperationKind } from '../generated/sarvamSpecGenerated.js';
import {
  ConnectionError,
  TimeoutError,
  RateLimitError,
  parseRetryAfterHeader,
} from '../errors.js';
import { Clock, defaultClock, Random, defaultRandom } from '../utils/timing.js';
import { Middleware, NextHandler } from './types.js';
import { HttpRequest, HttpResponse } from '../transport/http.js';

export interface RetryMiddlewareOptions {
  maxRetries?: number;
  baseBackoffMs?: number;
  maxBackoffMs?: number;
  clock?: Clock;
  random?: Random;
}

export function isRetryableStatus(status: number, operationKind: OperationKind, hasIdempotencyKey: boolean): boolean {
  if (status === 429) {
    // 429 is always retryable for all operation kinds
    return true;
  }

  if (operationKind === 'JOB_CREATE') {
    // JOB_CREATE only retries on 429 unless Idempotency-Key is present
    if (hasIdempotencyKey) {
      return status === 408 || status === 409 || status >= 500;
    }
    return false;
  }

  if (operationKind === 'MULTIPART_COMPUTE') {
    // Retries on 429 and 503 only
    return status === 503;
  }

  if (operationKind === 'IDEMPOTENT' || operationKind === 'STATELESS_POST') {
    return status === 408 || status === 409 || status === 500 || status === 502 || status === 503 || status === 504;
  }

  return false;
}

export function isRetryableError(error: unknown, operationKind: OperationKind, hasIdempotencyKey: boolean): boolean {
  if (error instanceof RateLimitError) {
    return true;
  }

  if (operationKind === 'JOB_CREATE') {
    return false;
  }

  if (error instanceof ConnectionError || error instanceof TimeoutError) {
    return operationKind === 'IDEMPOTENT' || operationKind === 'STATELESS_POST';
  }

  return false;
}

export function createRetryMiddleware(options?: RetryMiddlewareOptions): Middleware {
  const maxRetries = options?.maxRetries ?? 2;
  const baseBackoffMs = options?.baseBackoffMs ?? 500;
  const maxBackoffMs = options?.maxBackoffMs ?? 8000;
  const clock = options?.clock ?? defaultClock;
  const random = options?.random ?? defaultRandom;

  function calculateDelay(attempt: number, retryAfterMs?: number): number {
    if (retryAfterMs !== undefined && retryAfterMs >= 0) {
      return retryAfterMs;
    }
    const ceilingMs = Math.min(maxBackoffMs, baseBackoffMs * Math.pow(2, attempt));
    return Math.floor(random.random() * ceilingMs);
  }

  return async (request: HttpRequest, next: NextHandler): Promise<HttpResponse> => {
    const opKind: OperationKind = request.operationKind ?? 'STATELESS_POST';
    const hasIdempotencyKey = Boolean(
      request.headers['idempotency-key'] || request.headers['Idempotency-Key']
    );

    let attempt = 0;

    while (true) {
      try {
        const response = await next(request);

        if (attempt < maxRetries && isRetryableStatus(response.status, opKind, hasIdempotencyKey)) {
          const retryAfterMs = parseRetryAfterHeader((name) => response.headers.get(name));
          const delayMs = calculateDelay(attempt, retryAfterMs);
          attempt++;
          await clock.sleep(delayMs);
          continue;
        }

        return response;
      } catch (err: unknown) {
        if (attempt < maxRetries && isRetryableError(err, opKind, hasIdempotencyKey)) {
          let retryAfterMs: number | undefined;
          if (err instanceof RateLimitError) {
            retryAfterMs = err.retryAfterMs;
          }
          const delayMs = calculateDelay(attempt, retryAfterMs);
          attempt++;
          await clock.sleep(delayMs);
          continue;
        }

        throw err;
      }
    }
  };
}
