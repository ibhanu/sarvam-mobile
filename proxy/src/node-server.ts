/**
 * Node.js Server implementation for Sarvam BFF Proxy.
 * Uses native Node http + ws WebSocket upgrade proxy.
 */

import * as http from 'node:http';
import * as stream from 'node:stream';
import { URL } from 'node:url';
import { WebSocketServer, WebSocket } from 'ws';
import { ProxyConfig, resolveUpstreamWsUrl, handleFetch } from './router.js';
import { RateLimiter, extractClientToken } from './middleware.js';
import { verifyEphemeralToken, isScopeAllowedForPath } from './token.js';

export interface NodeProxyServerInstance {
  httpServer: http.Server;
  wss: WebSocketServer;
  rateLimiter: RateLimiter;
  start(port?: number, host?: string): Promise<{ port: number; host: string; url: string; wsUrl: string }>;
  stop(): Promise<void>;
}

export function createNodeProxyServer(config: ProxyConfig): NodeProxyServerInstance {
  const rateLimiter = new RateLimiter({ rpm: config.rateLimitRpm });
  const wss = new WebSocketServer({ noServer: true });

  const httpServer = http.createServer(async (req, res) => {
    try {
      const host = req.headers.host || 'localhost';
      const fullUrl = new URL(req.url || '/', `http://${host}`);

      const headers = new Headers();
      for (const [key, val] of Object.entries(req.headers)) {
        if (Array.isArray(val)) {
          for (const v of val) headers.append(key, v);
        } else if (val !== undefined) {
          headers.set(key, val);
        }
      }

      const method = req.method || 'GET';
      const body =
        method !== 'GET' && method !== 'HEAD'
          ? new ReadableStream({
              start(controller) {
                req.on('data', (chunk) => controller.enqueue(chunk));
                req.on('end', () => controller.close());
                req.on('error', (err) => controller.error(err));
              },
            })
          : undefined;

      const abortController = new AbortController();
      req.on('aborted', () => abortController.abort());
      req.on('close', () => {
        if (!res.writableEnded) abortController.abort();
      });

      const webRequest = new Request(fullUrl, {
        method,
        headers,
        body,
        signal: abortController.signal,
        // @ts-ignore - duplex is needed for Node fetch request body streaming
        duplex: 'half',
      });

      const webResponse = await handleFetch(webRequest, config, rateLimiter);

      // Write status and headers
      const resHeaders: Record<string, string> = {};
      webResponse.headers.forEach((val, key) => {
        resHeaders[key] = val;
      });
      res.writeHead(webResponse.status, resHeaders);

      // Stream response body with zero buffering
      if (webResponse.body) {
        const reader = webResponse.body.getReader();
        try {
          while (true) {
            const { done, value } = await reader.read();
            if (done) break;
            res.write(value);
          }
        } finally {
          res.end();
        }
      } else {
        res.end();
      }
    } catch (err: any) {
      if (!res.headersSent) {
        res.writeHead(500, { 'Content-Type': 'application/json' });
        res.end(
          JSON.stringify({
            error: {
              code: 'server_error',
              message: err.message || 'Internal proxy error',
              request_id: `req_${Date.now()}`,
            },
          })
        );
      }
    }
  });

  // WebSocket upgrade handler
  httpServer.on('upgrade', async (req, socket, head) => {
    try {
      const host = req.headers.host || 'localhost';
      const reqUrl = new URL(req.url || '/', `http://${host}`);
      const pathname = reqUrl.pathname;

      // 1. Authenticate WebSocket upgrade request
      const { token } = extractClientToken(req.headers);
      if (!token) {
        sendUpgradeError(socket, 403, 'invalid_api_key_error', 'Missing authentication credentials');
        return;
      }

      let payload;
      try {
        payload = await verifyEphemeralToken(token, config.tokenSecret);
      } catch (err: any) {
        sendUpgradeError(socket, 403, 'invalid_api_key_error', err.message || 'Invalid or expired token');
        return;
      }

      // 2. Scope verification
      if (!isScopeAllowedForPath(payload.scopes, pathname)) {
        sendUpgradeError(socket, 403, 'invalid_api_key_error', 'Token scope does not allow access to this endpoint');
        return;
      }

      // 3. Rate limiting check
      const rateLimit = rateLimiter.check(payload.sub);
      if (!rateLimit.allowed) {
        sendUpgradeError(socket, 429, 'rate_limit_exceeded_error', 'Rate limit exceeded', rateLimit.retryAfterMs);
        return;
      }

      // 4. Accept client upgrade
      wss.handleUpgrade(req, socket, head, (clientWs) => {
        const upstreamWsUrl = resolveUpstreamWsUrl(pathname, reqUrl.search, config);

        const upstreamWs = new WebSocket(upstreamWsUrl, {
          headers: {
            'Api-Subscription-Key': config.sarvamApiKey,
          },
        });

        const pendingClientMessages: { data: any; isBinary: boolean }[] = [];
        let upstreamOpen = false;

        upstreamWs.on('open', () => {
          upstreamOpen = true;
          for (const item of pendingClientMessages) {
            upstreamWs.send(item.data, { binary: item.isBinary });
          }
          pendingClientMessages.length = 0;
        });

        clientWs.on('message', (data, isBinary) => {
          if (upstreamOpen && upstreamWs.readyState === WebSocket.OPEN) {
            upstreamWs.send(data, { binary: isBinary });
          } else {
            pendingClientMessages.push({ data, isBinary });
          }
        });

        upstreamWs.on('message', (data, isBinary) => {
          if (clientWs.readyState === WebSocket.OPEN) {
            clientWs.send(data, { binary: isBinary });
          }
        });

        clientWs.on('close', (code, reason) => {
          if (upstreamWs.readyState === WebSocket.OPEN || upstreamWs.readyState === WebSocket.CONNECTING) {
            if (code && code !== 1005 && code !== 1006) {
              upstreamWs.close(code, reason);
            } else {
              upstreamWs.close(1000);
            }
          }
        });

        upstreamWs.on('close', (code, reason) => {
          if (clientWs.readyState === WebSocket.OPEN || clientWs.readyState === WebSocket.CONNECTING) {
            if (code && code !== 1005 && code !== 1006) {
              clientWs.close(code, reason);
            } else {
              clientWs.close(1000);
            }
          }
        });

        clientWs.on('error', () => {
          upstreamWs.terminate();
        });

        upstreamWs.on('error', () => {
          clientWs.terminate();
        });
      });
    } catch (err: any) {
      sendUpgradeError(socket, 500, 'server_error', err.message || 'Internal error during WebSocket upgrade');
    }
  });

  return {
    httpServer,
    wss,
    rateLimiter,
    start(port = 0, host = '127.0.0.1') {
      return new Promise((resolve, reject) => {
        httpServer.listen(port, host, () => {
          const addr = httpServer.address();
          if (!addr || typeof addr === 'string') {
            reject(new Error('Failed to bind server address'));
            return;
          }
          const actualPort = addr.port;
          resolve({
            port: actualPort,
            host,
            url: `http://${host}:${actualPort}`,
            wsUrl: `ws://${host}:${actualPort}`,
          });
        });
      });
    },
    stop() {
      return new Promise((resolve) => {
        // Terminate any active WebSocket clients
        for (const ws of wss.clients) {
          ws.terminate();
        }
        wss.close(() => {
          if (typeof httpServer.closeAllConnections === 'function') {
            httpServer.closeAllConnections();
          }
          httpServer.close(() => {
            resolve();
          });
        });
      });
    },
  };
}

function sendUpgradeError(
  socket: stream.Duplex,
  statusCode: number,
  code: string,
  message: string,
  retryAfterMs?: number
) {
  if (socket.destroyed || !socket.writable) return;

  const reqId = `req_${Date.now().toString(36)}_${Math.random().toString(36).slice(2, 7)}`;
  const body = JSON.stringify({
    error: {
      code,
      message,
      request_id: reqId,
    },
  });

  const headers = [
    `HTTP/1.1 ${statusCode} ${statusCode === 429 ? 'Too Many Requests' : 'Forbidden'}`,
    'Content-Type: application/json',
    `Content-Length: ${Buffer.byteLength(body)}`,
    `x-request-id: ${reqId}`,
    'Connection: close',
  ];
  if (retryAfterMs !== undefined) {
    headers.push(`retry-after-ms: ${retryAfterMs}`);
    headers.push(`Retry-After: ${Math.ceil(retryAfterMs / 1000)}`);
  }

  socket.write(headers.join('\r\n') + '\r\n\r\n' + body);
  socket.destroy();
}
