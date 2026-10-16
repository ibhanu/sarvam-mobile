/* node:coverage disable */
/**
 * Cloudflare Workers / WinterCG Edge entrypoint for Sarvam BFF Proxy.
 * Supports Web Fetch API, streaming, and WebSocket upgrades via WebSocketPair.
 */

import { ProxyConfig, resolveUpstreamWsUrl, handleFetch } from './router.js';
import {
  RateLimiter,
  extractClientToken,
  createRateLimitErrorResponse,
} from './middleware.js';
import {
  verifyEphemeralToken,
  isScopeAllowedForPath,
  createAuthErrorResponse,
  createCanonicalErrorResponse,
} from './token.js';

export interface WorkerEnv {
  SARVAM_API_KEY: string;
  BFF_TOKEN_SECRET: string;
  UPSTREAM_API_BASE_URL?: string;
  UPSTREAM_DUBBING_BASE_URL?: string;
  UPSTREAM_WS_BASE_URL?: string;
  RATE_LIMIT_RPM?: string;
  TOKEN_TTL_SECONDS?: string;
}

// Global cached rate limiter across Worker invocations in the same isolate
let workerRateLimiter: RateLimiter | null = null;

export default {
  async fetch(request: Request, env: WorkerEnv): Promise<Response> {
    const config: ProxyConfig = {
      sarvamApiKey: env.SARVAM_API_KEY,
      tokenSecret: env.BFF_TOKEN_SECRET,
      upstreamApiBaseUrl: env.UPSTREAM_API_BASE_URL || 'https://api.sarvam.ai',
      upstreamDubbingBaseUrl: env.UPSTREAM_DUBBING_BASE_URL || 'https://api.sarvam.ai/dubbing',
      upstreamWsBaseUrl: env.UPSTREAM_WS_BASE_URL || 'wss://api.sarvam.ai',
      rateLimitRpm: env.RATE_LIMIT_RPM ? parseInt(env.RATE_LIMIT_RPM, 10) : 60,
      tokenTtlSeconds: env.TOKEN_TTL_SECONDS ? parseInt(env.TOKEN_TTL_SECONDS, 10) : 900,
    };

    if (!workerRateLimiter) {
      workerRateLimiter = new RateLimiter({ rpm: config.rateLimitRpm });
    }

    // Check for WebSocket upgrade request
    const upgradeHeader = request.headers.get('Upgrade');
    if (upgradeHeader && upgradeHeader.toLowerCase() === 'websocket') {
      return handleEdgeWebSocketUpgrade(request, config, workerRateLimiter);
    }

    return handleFetch(request, config, workerRateLimiter);
  },
};

/**
 * Handles bidirectional WebSocket upgrade proxy in Cloudflare Workers using WebSocketPair.
 */
async function handleEdgeWebSocketUpgrade(
  request: Request,
  config: ProxyConfig,
  rateLimiter: RateLimiter
): Promise<Response> {
  const url = new URL(request.url);
  const pathname = url.pathname;

  // 1. Authenticate WebSocket upgrade
  const { token, subprotocolToEcho } = extractClientToken(request.headers);
  if (!token) {
    return createAuthErrorResponse('Missing authentication credentials');
  }

  let payload;
  try {
    payload = await verifyEphemeralToken(token, config.tokenSecret);
  } catch (err: any) {
    return createAuthErrorResponse(err.message || 'Invalid or expired token');
  }

  // 2. Validate scope
  if (!isScopeAllowedForPath(payload.scopes, pathname)) {
    return createAuthErrorResponse('Token scope does not allow access to this endpoint');
  }

  // 3. Check rate limit
  const rateLimit = rateLimiter.check(payload.sub);
  if (!rateLimit.allowed) {
    return createRateLimitErrorResponse(rateLimit.retryAfterMs);
  }

  // 4. Connect to upstream WebSocket
  const upstreamWsUrl = resolveUpstreamWsUrl(pathname, url.search, config);
  let upstreamResponse: Response;
  try {
    upstreamResponse = await fetch(upstreamWsUrl, {
      headers: {
        Upgrade: 'websocket',
        'Api-Subscription-Key': config.sarvamApiKey,
      },
    });
  } catch (err: any) {
    return createCanonicalErrorResponse(
      502,
      'connection_error',
      `Failed to connect to upstream WebSocket: ${err.message}`
    );
  }

  // @ts-ignore - Cloudflare Workers fetch returns .webSocket on 101 Switching Protocols
  const upstreamWs = upstreamResponse.webSocket;
  if (!upstreamWs) {
    return createCanonicalErrorResponse(
      502,
      'connection_error',
      'Upstream server did not accept WebSocket upgrade'
    );
  }

  // 5. Create client-server WebSocketPair
  // @ts-ignore - Cloudflare Workers WebSocketPair
  const pair = new WebSocketPair();
  const [clientWs, serverWs] = Object.values(pair) as [any, any];

  serverWs.accept();
  upstreamWs.accept();

  // 6. Bidirectional piping
  serverWs.addEventListener('message', (event: any) => upstreamWs.send(event.data));
  upstreamWs.addEventListener('message', (event: any) => serverWs.send(event.data));

  serverWs.addEventListener('close', (event: any) => {
    try {
      if (event.code && event.code !== 1005 && event.code !== 1006) {
        upstreamWs.close(event.code, event.reason);
      } else {
        upstreamWs.close(1000);
      }
    } catch {
      // Ignore if already closed
    }
  });

  upstreamWs.addEventListener('close', (event: any) => {
    try {
      if (event.code && event.code !== 1005 && event.code !== 1006) {
        serverWs.close(event.code, event.reason);
      } else {
        serverWs.close(1000);
      }
    } catch {
      // Ignore if already closed
    }
  });

  serverWs.addEventListener('error', () => {
    try {
      upstreamWs.close(1011, 'Client socket error');
    } catch {}
  });

  upstreamWs.addEventListener('error', () => {
    try {
      serverWs.close(1011, 'Upstream socket error');
    } catch {}
  });

  const responseHeaders = new Headers();
  if (subprotocolToEcho) {
    responseHeaders.set('Sec-WebSocket-Protocol', subprotocolToEcho);
  }

  // Return 101 response with client websocket attached
  // @ts-ignore
  return new Response(null, {
    status: 101,
    // @ts-ignore
    webSocket: clientWs,
    headers: responseHeaders,
  });
}
