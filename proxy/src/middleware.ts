/**
 * Authentication extraction and sliding-window / token-bucket Rate Limiter.
 */

import { createCanonicalErrorResponse } from './token.js';

export interface ExtractedAuth {
  token: string | null;
  authType: 'bearer' | 'subscription-key' | null;
  subprotocolToEcho?: string;
}

/**
 * Extracts authentication token from headers or WebSocket subprotocols.
 * Supports:
 * - REST Header: `Authorization: Bearer <token>`
 * - REST Header: `api-subscription-key: <token>`
 * - WebSocket Subprotocol: `bearer.<token>`
 * - WebSocket Subprotocol: `api-subscription-key.<token>`
 */
export function extractClientToken(
  headers: Headers | Record<string, string | string[] | undefined>
): ExtractedAuth {
  const getHeader = (name: string): string | null => {
    if (typeof (headers as Headers).get === 'function') {
      return (headers as Headers).get(name);
    }
    const lowerName = name.toLowerCase();
    const record = headers as Record<string, string | string[] | undefined>;
    for (const key of Object.keys(record)) {
      if (key.toLowerCase() === lowerName) {
        const val = record[key];
        return Array.isArray(val) ? val[0] : val || null;
      }
    }
    return null;
  };

  // 1. Authorization: Bearer <token>
  const authHeader = getHeader('authorization');
  if (authHeader) {
    const match = authHeader.match(/^Bearer\s+(.+)$/i);
    if (match) {
      return { token: match[1].trim(), authType: 'bearer' };
    }
  }

  // 2. api-subscription-key: <token>
  const subKeyHeader = getHeader('api-subscription-key');
  if (subKeyHeader) {
    return { token: subKeyHeader.trim(), authType: 'subscription-key' };
  }

  // 3. WebSocket subprotocols: Sec-WebSocket-Protocol
  const wsProtocol = getHeader('sec-websocket-protocol');
  if (wsProtocol) {
    const protocols = wsProtocol.split(',').map((p) => p.trim());
    for (const proto of protocols) {
      if (proto.startsWith('bearer.')) {
        return {
          token: proto.slice('bearer.'.length).trim(),
          authType: 'bearer',
          subprotocolToEcho: proto,
        };
      }
      if (proto.startsWith('api-subscription-key.')) {
        return {
          token: proto.slice('api-subscription-key.'.length).trim(),
          authType: 'subscription-key',
          subprotocolToEcho: proto,
        };
      }
    }
  }

  return { token: null, authType: null };
}

export interface RateLimiterOptions {
  rpm?: number; // Requests per minute, default 60
}

export interface RateLimitResult {
  allowed: boolean;
  remaining: number;
  retryAfterMs: number;
}

interface Bucket {
  tokens: number;
  lastRefill: number;
}

/**
 * High-performance in-memory Token Bucket rate limiter with sliding refill.
 * Configured in Requests Per Minute (RPM) per client key (e.g. subject / IP).
 */
export class RateLimiter {
  private readonly rpm: number;
  private readonly buckets = new Map<string, Bucket>();
  private lastCleanup = Date.now();

  constructor(options: RateLimiterOptions = {}) {
    this.rpm = options.rpm && options.rpm > 0 ? options.rpm : 60;
  }

  /**
   * Check if a request for the given key is allowed.
   */
  check(key: string): RateLimitResult {
    const now = Date.now();
    this.cleanupIfNeeded(now);

    const capacity = this.rpm;
    const fillRatePerMs = capacity / 60000; // tokens per ms

    let bucket = this.buckets.get(key);
    if (!bucket) {
      bucket = { tokens: capacity, lastRefill: now };
      this.buckets.set(key, bucket);
    } else {
      const elapsed = Math.max(0, now - bucket.lastRefill);
      bucket.tokens = Math.min(capacity, bucket.tokens + elapsed * fillRatePerMs);
      bucket.lastRefill = now;
    }

    if (bucket.tokens >= 1) {
      bucket.tokens -= 1;
      return {
        allowed: true,
        remaining: Math.floor(bucket.tokens),
        retryAfterMs: 0,
      };
    } else {
      const needed = 1 - bucket.tokens;
      const retryAfterMs = Math.ceil(needed / fillRatePerMs);
      return {
        allowed: false,
        remaining: 0,
        retryAfterMs: Math.max(1, retryAfterMs),
      };
    }
  }

  /**
   * Reset all bucket states.
   */
  reset(): void {
    this.buckets.clear();
  }

  private cleanupIfNeeded(now: number): void {
    if (now - this.lastCleanup > 120000) {
      this.lastCleanup = now;
      for (const [key, bucket] of this.buckets.entries()) {
        if (now - bucket.lastRefill > 120000) {
          this.buckets.delete(key);
        }
      }
    }
  }
}

/**
 * Returns HTTP 429 RateLimitError response with retry-after-ms header.
 */
export function createRateLimitErrorResponse(retryAfterMs: number): Response {
  const retrySeconds = Math.max(1, Math.ceil(retryAfterMs / 1000));
  return createCanonicalErrorResponse(
    429,
    'rate_limit_exceeded_error',
    `Rate limit exceeded. Please retry after ${retrySeconds}s.`,
    {
      'retry-after-ms': retryAfterMs.toString(),
      'Retry-After': retrySeconds.toString(),
    }
  );
}
