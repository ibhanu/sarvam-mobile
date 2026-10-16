/**
 * Multi-Host Routing, Ephemeral Token Auth & Streaming Passthrough.
 */

import {
  createEphemeralToken,
  verifyEphemeralToken,
  isScopeAllowedForPath,
  createAuthErrorResponse,
  createCanonicalErrorResponse,
} from './token.js';
import {
  RateLimiter,
  extractClientToken,
  createRateLimitErrorResponse,
} from './middleware.js';

export interface ProxyConfig {
  sarvamApiKey: string;
  tokenSecret: string;
  upstreamApiBaseUrl?: string; // Default: 'https://api.sarvam.ai'
  upstreamDubbingBaseUrl?: string; // Default: 'https://api.sarvam.ai/dubbing'
  upstreamWsBaseUrl?: string; // Default: 'wss://api.sarvam.ai'
  rateLimitRpm?: number; // Default: 60
  tokenTtlSeconds?: number; // Default: 900 (15 minutes)
}

/**
 * Resolves upstream target URL based on pathname.
 * Routes `/dubbing/*` to `upstreamDubbingBaseUrl` and all other paths to `upstreamApiBaseUrl`.
 */
export function resolveUpstreamUrl(
  pathname: string,
  search: string,
  config: ProxyConfig
): string {
  const isDubbing = pathname.startsWith('/dubbing');
  if (isDubbing) {
    const rawBase = (config.upstreamDubbingBaseUrl || 'https://api.sarvam.ai/dubbing').replace(/\/+$/, '');
    const url = new URL(rawBase);
    // If rawBase already ends with /dubbing, strip /dubbing from pathname to prevent duplication
    const subpath = url.pathname.endsWith('/dubbing')
      ? pathname.slice('/dubbing'.length) || '/'
      : pathname;
    const combinedPath = (url.pathname.replace(/\/+$/, '') + subpath).replace(/\/{2,}/g, '/');
    return `${url.origin}${combinedPath}${search}`;
  }

  const rawBase = (config.upstreamApiBaseUrl || 'https://api.sarvam.ai').replace(/\/+$/, '');
  const url = new URL(rawBase);
  const combinedPath = (url.pathname.replace(/\/+$/, '') + pathname).replace(/\/{2,}/g, '/');
  return `${url.origin}${combinedPath}${search}`;
}

/**
 * Resolves upstream WebSocket URL based on pathname.
 */
export function resolveUpstreamWsUrl(
  pathname: string,
  search: string,
  config: ProxyConfig
): string {
  const rawBase = (config.upstreamWsBaseUrl || 'wss://api.sarvam.ai').replace(/\/+$/, '');
  const url = new URL(rawBase);
  const combinedPath = (url.pathname.replace(/\/+$/, '') + pathname).replace(/\/{2,}/g, '/');
  return `${url.protocol}//${url.host}${combinedPath}${search}`;
}

/**
 * Standard Web Fetch API handler for Edge runtimes (Cloudflare Workers, WinterCG) and Node.js.
 */
export async function handleFetch(
  request: Request,
  config: ProxyConfig,
  rateLimiter: RateLimiter
): Promise<Response> {
  const url = new URL(request.url);
  const pathname = url.pathname;

  // 1. CORS Preflight
  if (request.method === 'OPTIONS') {
    return new Response(null, {
      status: 204,
      headers: {
        'Access-Control-Allow-Origin': '*',
        'Access-Control-Allow-Methods': 'GET, POST, PUT, DELETE, OPTIONS',
        'Access-Control-Allow-Headers': '*',
        'Access-Control-Max-Age': '86400',
      },
    });
  }

  // 2. Health check endpoint
  if (pathname === '/health' || (pathname === '/' && request.method === 'GET')) {
    return new Response(JSON.stringify({ status: 'ok', service: 'sarvam-bff-proxy' }), {
      status: 200,
      headers: {
        'Content-Type': 'application/json',
        'Access-Control-Allow-Origin': '*',
      },
    });
  }

  // 3. Ephemeral Token Minting: POST /auth/token
  if (pathname === '/auth/token' && request.method === 'POST') {
    let bodyData: any = {};
    if (request.body) {
      try {
        const text = await request.text();
        if (text.trim().length > 0) {
          bodyData = JSON.parse(text);
        }
      } catch {
        return createCanonicalErrorResponse(
          400,
          'bad_request_error',
          'Invalid JSON payload in request body'
        );
      }
    }

    try {
      const mintResult = await createEphemeralToken({
        secret: config.tokenSecret,
        sub: bodyData.sub || 'mobile-client',
        scopes: bodyData.scopes,
        ttlSeconds: bodyData.ttlSeconds || config.tokenTtlSeconds || 900,
      });

      return new Response(JSON.stringify(mintResult), {
        status: 200,
        headers: {
          'Content-Type': 'application/json',
          'Access-Control-Allow-Origin': '*',
        },
      });
    } catch (err: any) {
      return createCanonicalErrorResponse(
        500,
        'server_error',
        err.message || 'Failed to mint ephemeral token'
      );
    }
  }

  // 4. Authenticate client request
  const { token } = extractClientToken(request.headers);
  if (!token) {
    return createAuthErrorResponse('Missing authentication credentials');
  }

  let payload;
  try {
    payload = await verifyEphemeralToken(token, config.tokenSecret);
  } catch (err: any) {
    return createAuthErrorResponse(err.message || 'Invalid or expired token');
  }

  // 5. Verify token scopes
  if (!isScopeAllowedForPath(payload.scopes, pathname)) {
    return createAuthErrorResponse('Token scope does not allow access to this endpoint');
  }

  // 6. Rate limiting check (keyed by token subject `sub`)
  const rateLimitResult = rateLimiter.check(payload.sub);
  if (!rateLimitResult.allowed) {
    return createRateLimitErrorResponse(rateLimitResult.retryAfterMs);
  }

  // 7. Resolve upstream destination
  const upstreamUrl = resolveUpstreamUrl(pathname, url.search, config);

  // 8. Rebuild headers: strip client credentials and inject secret upstream key
  const upstreamHeaders = new Headers();
  for (const [key, value] of request.headers.entries()) {
    const lower = key.toLowerCase();
    if (
      lower === 'authorization' ||
      lower === 'api-subscription-key' ||
      lower === 'host' ||
      lower === 'connection' ||
      lower === 'keep-alive' ||
      lower === 'transfer-encoding'
    ) {
      continue;
    }
    upstreamHeaders.set(key, value);
  }
  upstreamHeaders.set('api-subscription-key', config.sarvamApiKey);

  // 9. Execute upstream fetch
  const fetchInit: RequestInit = {
    method: request.method,
    headers: upstreamHeaders,
    redirect: 'follow',
  };

  if (request.method !== 'GET' && request.method !== 'HEAD') {
    fetchInit.body = request.body;
    // @ts-ignore - duplex is needed for Node fetch streaming
    fetchInit.duplex = 'half';
  }

  let upstreamResponse: Response;
  try {
    upstreamResponse = await fetch(upstreamUrl, fetchInit);
  } catch (err: any) {
    return createCanonicalErrorResponse(
      502,
      'connection_error',
      `Failed to reach upstream Sarvam service: ${err.message}`
    );
  }

  // 10. Rebuild client response headers
  const responseHeaders = new Headers();
  for (const [key, value] of upstreamResponse.headers.entries()) {
    const lower = key.toLowerCase();
    // Never leak upstream secrets or hop-by-hop headers
    if (
      lower === 'api-subscription-key' ||
      lower === 'connection' ||
      lower === 'keep-alive' ||
      lower === 'transfer-encoding'
    ) {
      continue;
    }
    responseHeaders.set(key, value);
  }

  // Ensure CORS headers on all proxied responses
  responseHeaders.set('Access-Control-Allow-Origin', '*');
  responseHeaders.set('Access-Control-Allow-Methods', 'GET, POST, PUT, DELETE, OPTIONS');
  responseHeaders.set('Access-Control-Allow-Headers', '*');
  responseHeaders.set('Access-Control-Expose-Headers', '*');

  // Streaming passthrough headers (SSE, chunked audio, octet-stream)
  const contentType = upstreamResponse.headers.get('content-type') || '';
  if (
    contentType.includes('text/event-stream') ||
    contentType.includes('application/octet-stream') ||
    contentType.includes('audio/')
  ) {
    responseHeaders.set('Cache-Control', 'no-cache');
    responseHeaders.set('X-Accel-Buffering', 'no');
  }

  return new Response(upstreamResponse.body, {
    status: upstreamResponse.status,
    statusText: upstreamResponse.statusText,
    headers: responseHeaders,
  });
}
