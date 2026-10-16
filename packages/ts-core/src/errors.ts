/**
 * Canonical SarvamError hierarchy.
 * Authoritative specification matching api-contract.md §4.
 */

export interface SarvamErrorOptions {
  message?: string;
  statusCode?: number;
  code?: string;
  requestId?: string;
  rawBody?: string;
  cause?: unknown;
}

export class SarvamError extends Error {
  readonly statusCode?: number;
  readonly code?: string;
  readonly requestId?: string;
  readonly rawBody?: string;

  constructor(message: string, options?: SarvamErrorOptions) {
    super(message, { cause: options?.cause });
    this.name = this.constructor.name;
    this.statusCode = options?.statusCode;
    this.code = options?.code;
    this.requestId = options?.requestId;
    this.rawBody = options?.rawBody;
    // Set prototype explicitly for older environments / inheritance
    Object.setPrototypeOf(this, new.target.prototype);
  }
}

/**
 * Thrown on HTTP 401 or HTTP 403 with code === 'invalid_api_key_error'.
 * Retryable once via TokenAuth token refresh.
 */
export class AuthenticationError extends SarvamError {
  constructor(message: string, options?: SarvamErrorOptions) {
    super(message, options);
  }
}

/**
 * Thrown on HTTP 403 with error.code !== 'invalid_api_key_error' (e.g. tier lock).
 * Not retryable.
 */
export class PermissionDeniedError extends SarvamError {
  constructor(message: string, options?: SarvamErrorOptions) {
    super(message, options);
  }
}

/**
 * Thrown on HTTP 400.
 */
export class BadRequestError extends SarvamError {
  constructor(message: string, options?: SarvamErrorOptions) {
    super(message, options);
  }
}

/**
 * Thrown on HTTP 404.
 */
export class NotFoundError extends SarvamError {
  constructor(message: string, options?: SarvamErrorOptions) {
    super(message, options);
  }
}

/**
 * Thrown on HTTP 413.
 */
export class PayloadTooLargeError extends SarvamError {
  constructor(message: string, options?: SarvamErrorOptions) {
    super(message, options);
  }
}

/**
 * Thrown on HTTP 422.
 */
export class UnprocessableEntityError extends SarvamError {
  constructor(message: string, options?: SarvamErrorOptions) {
    super(message, options);
  }
}

export interface RateLimitErrorOptions extends SarvamErrorOptions {
  retryAfterMs?: number;
}

/**
 * Thrown on HTTP 429 or HTTP 503 with code === 'rate_limit_exceeded_error'.
 * Retryable with backoff or server-specified delay.
 */
export class RateLimitError extends SarvamError {
  readonly retryAfterMs?: number;

  constructor(message: string, options?: RateLimitErrorOptions) {
    super(message, options);
    this.retryAfterMs = options?.retryAfterMs;
  }
}

/**
 * Thrown on HTTP 500, 502, 503, 504, 408, 409.
 */
export class ServerError extends SarvamError {
  constructor(message: string, options?: SarvamErrorOptions) {
    super(message, options);
  }
}

/**
 * Thrown on network drop, DNS failure, TLS failure, or socket reset.
 */
export class ConnectionError extends SarvamError {
  constructor(message: string, options?: SarvamErrorOptions) {
    super(message, options);
  }
}

export type TimeoutPhase = 'connect' | 'read' | 'total';

export interface TimeoutErrorOptions extends SarvamErrorOptions {
  phase?: TimeoutPhase;
}

/**
 * Thrown on connection or read timeouts.
 */
export class TimeoutError extends SarvamError {
  readonly phase: TimeoutPhase;

  constructor(message: string, options?: TimeoutErrorOptions) {
    super(message, options);
    this.phase = options?.phase ?? 'total';
  }
}

/**
 * Thrown on unexpected EOF or malformed SSE frame mid-stream.
 */
export class StreamError extends SarvamError {
  constructor(message: string, options?: SarvamErrorOptions) {
    super(message, options);
  }
}

export interface RealtimeErrorOptions extends SarvamErrorOptions {
  closeCode?: number;
}

/**
 * Thrown on WebSocket error frame or abnormal socket termination.
 */
export class RealtimeError extends SarvamError {
  readonly closeCode?: number;

  constructor(message: string, options?: RealtimeErrorOptions) {
    super(message, options);
    this.closeCode = options?.closeCode;
  }
}

/**
 * Thrown when server response fails schema decoding or JSON parsing.
 */
export class DecodingError extends SarvamError {
  constructor(message: string, options?: SarvamErrorOptions) {
    super(message, options);
  }
}

/**
 * Helper to check if an error is an AbortError (which should never be wrapped).
 */
export function isAbortError(error: unknown): boolean {
  if (!error) return false;
  if (typeof error === 'object' && 'name' in error) {
    return (error as { name?: string }).name === 'AbortError';
  }
  return false;
}

/**
 * Parses retry delay from HTTP headers.
 * Header Precedence on 429 / 503:
 * 1. retry-after-ms: parse integer milliseconds
 * 2. Retry-After: parse integer seconds (* 1000) or HTTP-date delta
 * 3. X-RateLimit-Reset: parse Unix epoch seconds delta
 */
export function parseRetryAfterHeader(
  getHeader: (name: string) => string | null | undefined
): number | undefined {
  const retryAfterMsStr = getHeader('retry-after-ms');
  if (retryAfterMsStr) {
    const val = parseInt(retryAfterMsStr, 10);
    if (!isNaN(val) && val >= 0) {
      return val;
    }
  }

  const retryAfterStr = getHeader('retry-after');
  if (retryAfterStr) {
    // Check if integer seconds
    const val = parseInt(retryAfterStr, 10);
    if (!isNaN(val) && val >= 0) {
      return val * 1000;
    }
    // Check if HTTP date
    const dateMs = Date.parse(retryAfterStr);
    if (!isNaN(dateMs)) {
      const delta = dateMs - Date.now();
      return delta > 0 ? delta : 0;
    }
  }

  const rateLimitResetStr = getHeader('x-ratelimit-reset');
  if (rateLimitResetStr) {
    const epochSec = parseInt(rateLimitResetStr, 10);
    if (!isNaN(epochSec) && epochSec > 0) {
      const delta = epochSec * 1000 - Date.now();
      return delta > 0 ? delta : 0;
    }
  }

  return undefined;
}

/**
 * Parses HTTP response into a canonical SarvamError subtype.
 */
export async function createHttpError(
  status: number,
  rawBody: string,
  getHeader: (name: string) => string | null | undefined
): Promise<SarvamError> {
  let parsedCode: string | undefined;
  let parsedMessage: string | undefined;
  let parsedRequestId: string | undefined =
    getHeader('x-request-id') ?? getHeader('x-ms-request-id') ?? undefined;

  if (rawBody && rawBody.trim().startsWith('{')) {
    try {
      const json = JSON.parse(rawBody) as Record<string, unknown>;
      const errorObj = json['error'] as Record<string, unknown> | undefined;
      if (errorObj && typeof errorObj === 'object') {
        parsedCode = typeof errorObj['code'] === 'string' ? errorObj['code'] : undefined;
        parsedMessage = typeof errorObj['message'] === 'string' ? errorObj['message'] : undefined;
        if (typeof errorObj['request_id'] === 'string') {
          parsedRequestId = errorObj['request_id'];
        }
      } else {
        parsedCode = typeof json['code'] === 'string' ? json['code'] : undefined;
        parsedMessage =
          typeof json['message'] === 'string'
            ? json['message']
            : typeof json['detail'] === 'string'
            ? json['detail']
            : undefined;
        if (typeof json['request_id'] === 'string') {
          parsedRequestId = json['request_id'];
        }
      }
    } catch {
      // Ignore JSON parse failure for error body
    }
  }

  const message = parsedMessage || `HTTP ${status}`;
  const commonOptions: SarvamErrorOptions = {
    message,
    statusCode: status,
    code: parsedCode,
    requestId: parsedRequestId,
    rawBody,
  };

  switch (status) {
    case 401:
      return new AuthenticationError(message, commonOptions);

    case 403:
      if (parsedCode === 'invalid_api_key_error') {
        return new AuthenticationError(message, commonOptions);
      }
      return new PermissionDeniedError(message, commonOptions);

    case 400:
      return new BadRequestError(message, commonOptions);

    case 404:
      return new NotFoundError(message, commonOptions);

    case 413:
      return new PayloadTooLargeError(message, commonOptions);

    case 422:
      return new UnprocessableEntityError(message, commonOptions);

    case 429: {
      const retryAfterMs = parseRetryAfterHeader(getHeader);
      return new RateLimitError(message, { ...commonOptions, retryAfterMs });
    }

    case 503: {
      if (parsedCode === 'rate_limit_exceeded_error') {
        const retryAfterMs = parseRetryAfterHeader(getHeader);
        return new RateLimitError(message, { ...commonOptions, retryAfterMs });
      }
      return new ServerError(message, commonOptions);
    }

    case 408:
    case 409:
    case 500:
    case 502:
    case 504:
    default:
      if (status >= 500) {
        return new ServerError(message, commonOptions);
      }
      return new SarvamError(message, commonOptions);
  }
}
