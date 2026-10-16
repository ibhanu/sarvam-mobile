import { describe, it, before, after } from 'node:test';
import * as assert from 'node:assert/strict';
import * as http from 'node:http';
import { WebSocketServer, WebSocket } from 'ws';
import {
  createNodeProxyServer,
  NodeProxyServerInstance,
} from '../src/node-server.js';
import {
  createEphemeralToken,
  ProxyConfig,
} from '../src/index.js';

const MASTER_API_KEY = 'test-sarvam-master-secret-key-xyz';
const TOKEN_SECRET = 'super-secret-hmac-sha256-signing-key-12345';

interface RecordedRequest {
  method: string;
  url: string;
  headers: http.IncomingHttpHeaders;
  body: string;
}

describe('Sarvam AI Mobile BFF & Ephemeral Token Proxy', () => {
  let apiMockServer: http.Server;
  let apiWss: WebSocketServer;
  let apiMockUrl: string;
  let apiMockWsUrl: string;
  const apiRecordedRequests: RecordedRequest[] = [];
  let apiWsRecordedHeaders: http.IncomingHttpHeaders | null = null;

  let dubbingMockServer: http.Server;
  let dubbingMockUrl: string;
  const dubbingRecordedRequests: RecordedRequest[] = [];

  let proxyInstance: NodeProxyServerInstance;
  let proxyUrl: string;
  let proxyWsUrl: string;

  before(async () => {
    // 1. Upstream API & WebSocket Mock Server
    apiWss = new WebSocketServer({ noServer: true });
    apiMockServer = http.createServer((req, res) => {
      const chunks: Buffer[] = [];
      req.on('data', (c) => chunks.push(c));
      req.on('end', () => {
        const body = Buffer.concat(chunks).toString('utf-8');
        apiRecordedRequests.push({
          method: req.method || 'GET',
          url: req.url || '/',
          headers: req.headers,
          body,
        });

        if (req.url === '/translate' && req.method === 'POST') {
          res.writeHead(200, { 'Content-Type': 'application/json' });
          res.end(JSON.stringify({ translated_text: 'नमस्ते मित्र' }));
          return;
        }

        if (req.url === '/v2/chat/completions' && req.method === 'POST') {
          res.writeHead(200, {
            'Content-Type': 'text/event-stream; charset=utf-8',
            'Cache-Control': 'no-cache',
            'Connection': 'keep-alive',
          });
          res.write('data: {"choices":[{"delta":{"content":"Namaste"}}]}\n\n');
          setTimeout(() => {
            res.write('data: {"choices":[{"delta":{"content":" India"}}]}\n\n');
            setTimeout(() => {
              res.write('data: [DONE]\n\n');
              res.end();
            }, 30);
          }, 30);
          return;
        }

        res.writeHead(404, { 'Content-Type': 'application/json' });
        res.end(JSON.stringify({ error: { code: 'not_found', message: 'Not found' } }));
      });
    });

    apiMockServer.on('upgrade', (req, socket, head) => {
      apiWsRecordedHeaders = req.headers;
      apiWss.handleUpgrade(req, socket, head, (ws) => {
        ws.on('message', (msg) => {
          try {
            const data = JSON.parse(msg.toString());
            if (data.event === 'ping') {
              ws.send(JSON.stringify({ event: 'pong' }));
            }
          } catch {
            ws.send(msg);
          }
        });
      });
    });

    await new Promise<void>((resolve) => {
      apiMockServer.listen(0, '127.0.0.1', () => {
        const port = (apiMockServer.address() as any).port;
        apiMockUrl = `http://127.0.0.1:${port}`;
        apiMockWsUrl = `ws://127.0.0.1:${port}`;
        resolve();
      });
    });

    // 2. Upstream Dubbing Mock Server
    dubbingMockServer = http.createServer((req, res) => {
      const chunks: Buffer[] = [];
      req.on('data', (c) => chunks.push(c));
      req.on('end', () => {
        const body = Buffer.concat(chunks).toString('utf-8');
        dubbingRecordedRequests.push({
          method: req.method || 'GET',
          url: req.url || '/',
          headers: req.headers,
          body,
        });

        if (req.url?.startsWith('/dubbing/jobs') || req.url?.startsWith('/jobs')) {
          res.writeHead(200, { 'Content-Type': 'application/json' });
          res.end(JSON.stringify({ job_id: 'dub_999', status: 'PENDING' }));
          return;
        }

        res.writeHead(404, { 'Content-Type': 'application/json' });
        res.end(JSON.stringify({ error: { code: 'not_found', message: 'Not found' } }));
      });
    });

    await new Promise<void>((resolve) => {
      dubbingMockServer.listen(0, '127.0.0.1', () => {
        const port = (dubbingMockServer.address() as any).port;
        dubbingMockUrl = `http://127.0.0.1:${port}/dubbing`;
        resolve();
      });
    });

    // 3. Start BFF Proxy Server
    const proxyConfig: ProxyConfig = {
      sarvamApiKey: MASTER_API_KEY,
      tokenSecret: TOKEN_SECRET,
      upstreamApiBaseUrl: apiMockUrl,
      upstreamDubbingBaseUrl: dubbingMockUrl,
      upstreamWsBaseUrl: apiMockWsUrl,
      rateLimitRpm: 60,
    };

    proxyInstance = createNodeProxyServer(proxyConfig);
    const startInfo = await proxyInstance.start(0, '127.0.0.1');
    proxyUrl = startInfo.url;
    proxyWsUrl = startInfo.wsUrl;
  });

  after(async () => {
    await proxyInstance?.stop();
    for (const ws of apiWss.clients) {
      ws.terminate();
    }
    await new Promise<void>((resolve) => {
      apiWss.close(() => {
        if (typeof apiMockServer.closeAllConnections === 'function') {
          apiMockServer.closeAllConnections();
        }
        apiMockServer.close(() => resolve());
      });
    });
    await new Promise<void>((resolve) => {
      if (typeof dubbingMockServer.closeAllConnections === 'function') {
        dubbingMockServer.closeAllConnections();
      }
      dubbingMockServer.close(() => resolve());
    });
  });

  // =========================================================================
  // Test 1: POST /auth/token & Canonical Error Envelopes on Invalid/Expired
  // =========================================================================
  it('1. POST /auth/token mints valid token, and expired/tampered tokens are rejected with HTTP 403 invalid_api_key_error', async () => {
    // 1.1 Mint token
    const mintRes = await fetch(`${proxyUrl}/auth/token`, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({
        sub: 'client-user-42',
        scopes: ['text', 'chat', 'stt'],
        ttlSeconds: 60,
      }),
    });

    assert.equal(mintRes.status, 200);
    const mintData = await mintRes.json() as any;
    assert.ok(typeof mintData.token === 'string' && mintData.token.length > 20);
    assert.ok(typeof mintData.expiresAtEpochMs === 'number');
    assert.ok(mintData.expiresAtEpochMs > Date.now());

    // 1.2 Access with valid token succeeds
    const validRes = await fetch(`${proxyUrl}/translate`, {
      method: 'POST',
      headers: {
        'Authorization': `Bearer ${mintData.token}`,
        'Content-Type': 'application/json',
      },
      body: JSON.stringify({ input: 'hello' }),
    });
    assert.equal(validRes.status, 200);

    // 1.3 Missing token -> HTTP 403 invalid_api_key_error
    const noAuthRes = await fetch(`${proxyUrl}/translate`, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ input: 'hello' }),
    });
    assert.equal(noAuthRes.status, 403);
    const noAuthBody = await noAuthRes.json() as any;
    assert.equal(noAuthBody.error.code, 'invalid_api_key_error');
    assert.ok(noAuthBody.error.request_id);

    // 1.4 Tampered token -> HTTP 403 invalid_api_key_error
    const tamperedToken = mintData.token.slice(0, -6) + 'xxxxxx';
    const tamperedRes = await fetch(`${proxyUrl}/translate`, {
      method: 'POST',
      headers: {
        'Authorization': `Bearer ${tamperedToken}`,
        'Content-Type': 'application/json',
      },
      body: JSON.stringify({ input: 'hello' }),
    });
    assert.equal(tamperedRes.status, 403);
    const tamperedBody = await tamperedRes.json() as any;
    assert.equal(tamperedBody.error.code, 'invalid_api_key_error');

    // 1.5 Expired token -> HTTP 403 invalid_api_key_error
    const { token: expiredToken } = await createEphemeralToken({
      secret: TOKEN_SECRET,
      sub: 'client-user-expired',
      ttlSeconds: -10, // already expired
    });
    const expiredRes = await fetch(`${proxyUrl}/translate`, {
      method: 'POST',
      headers: {
        'Authorization': `Bearer ${expiredToken}`,
        'Content-Type': 'application/json',
      },
      body: JSON.stringify({ input: 'hello' }),
    });
    assert.equal(expiredRes.status, 403);
    const expiredBody = await expiredRes.json() as any;
    assert.equal(expiredBody.error.code, 'invalid_api_key_error');
    assert.match(expiredBody.error.message, /expired/i);

    // 1.6 Disallowed scope -> HTTP 403 invalid_api_key_error
    const { token: sttOnlyToken } = await createEphemeralToken({
      secret: TOKEN_SECRET,
      sub: 'client-user-stt',
      scopes: ['stt'], // does NOT allow 'text'
      ttlSeconds: 60,
    });
    const scopeRes = await fetch(`${proxyUrl}/translate`, {
      method: 'POST',
      headers: {
        'Authorization': `Bearer ${sttOnlyToken}`,
        'Content-Type': 'application/json',
      },
      body: JSON.stringify({ input: 'hello' }),
    });
    assert.equal(scopeRes.status, 403);
    const scopeBody = await scopeRes.json() as any;
    assert.equal(scopeBody.error.code, 'invalid_api_key_error');
    assert.match(scopeBody.error.message, /scope/i);
  });

  // =========================================================================
  // Test 2: Proxied REST /translate Injects Upstream Key and Hides It
  // =========================================================================
  it('2. Proxied REST /translate injects upstream api-subscription-key and hides it from the client', async () => {
    const { token } = await createEphemeralToken({
      secret: TOKEN_SECRET,
      sub: 'user-translate-test',
      scopes: ['text'],
      ttlSeconds: 60,
    });

    apiRecordedRequests.length = 0;

    const res = await fetch(`${proxyUrl}/translate`, {
      method: 'POST',
      headers: {
        'Authorization': `Bearer ${token}`,
        'Content-Type': 'application/json',
      },
      body: JSON.stringify({
        input: 'hello friend',
        source_language_code: 'en-IN',
        target_language_code: 'hi-IN',
      }),
    });

    assert.equal(res.status, 200);
    const resData = await res.json() as any;
    assert.equal(resData.translated_text, 'नमस्ते मित्र');

    // Verify upstream received the master key and client token was stripped
    assert.equal(apiRecordedRequests.length, 1);
    const recorded = apiRecordedRequests[0];
    assert.equal(recorded.headers['api-subscription-key'], MASTER_API_KEY);
    assert.equal(recorded.headers['authorization'], undefined);

    // Verify master key is NOT exposed in response headers to client
    assert.equal(res.headers.get('api-subscription-key'), null);
  });

  // =========================================================================
  // Test 3: Proxied /dubbing/jobs Routes to Dubbing Upstream Host
  // =========================================================================
  it('3. Proxied /dubbing/jobs routes to the dubbing upstream host', async () => {
    const { token } = await createEphemeralToken({
      secret: TOKEN_SECRET,
      sub: 'user-dubbing-test',
      scopes: ['dubbing'],
      ttlSeconds: 60,
    });

    apiRecordedRequests.length = 0;
    dubbingRecordedRequests.length = 0;

    const res = await fetch(`${proxyUrl}/dubbing/jobs`, {
      method: 'POST',
      headers: {
        'Authorization': `Bearer ${token}`,
        'Content-Type': 'application/json',
      },
      body: JSON.stringify({ name: 'Dubbing Project 1' }),
    });

    assert.equal(res.status, 200);
    const resData = await res.json() as any;
    assert.equal(resData.job_id, 'dub_999');
    assert.equal(resData.status, 'PENDING');

    // Verify dubbing mock received the request and api mock did NOT
    assert.equal(dubbingRecordedRequests.length, 1);
    assert.equal(apiRecordedRequests.length, 0);

    const recorded = dubbingRecordedRequests[0];
    assert.equal(recorded.headers['api-subscription-key'], MASTER_API_KEY);
    assert.match(recorded.url, /\/dubbing\/jobs/);
  });

  // =========================================================================
  // Test 4: Proxied SSE /v2/chat/completions Streams Chunks in Real Time
  // =========================================================================
  it('4. Proxied SSE /v2/chat/completions streams chunks through in real time', async () => {
    const { token } = await createEphemeralToken({
      secret: TOKEN_SECRET,
      sub: 'user-sse-test',
      scopes: ['chat'],
      ttlSeconds: 60,
    });

    const res = await fetch(`${proxyUrl}/v2/chat/completions`, {
      method: 'POST',
      headers: {
        'Authorization': `Bearer ${token}`,
        'Content-Type': 'application/json',
      },
      body: JSON.stringify({
        messages: [{ role: 'user', content: 'Tell me a story' }],
        stream: true,
      }),
    });

    assert.equal(res.status, 200);
    assert.match(res.headers.get('content-type') || '', /text\/event-stream/);
    assert.equal(res.headers.get('cache-control'), 'no-cache');
    assert.equal(res.headers.get('x-accel-buffering'), 'no');

    // Read stream chunks
    assert.ok(res.body);
    const reader = res.body.getReader();
    const decoder = new TextDecoder();
    let receivedText = '';

    while (true) {
      const { done, value } = await reader.read();
      if (done) break;
      receivedText += decoder.decode(value, { stream: true });
    }

    assert.ok(receivedText.includes('Namaste'));
    assert.ok(receivedText.includes('India'));
    assert.ok(receivedText.includes('[DONE]'));
  });

  // =========================================================================
  // Test 5: Proxied WebSocket /speech-to-text-realtime/ws Authenticates
  // =========================================================================
  it('5. Proxied WebSocket /speech-to-text-realtime/ws authenticates via bearer.<token> subprotocol and pipes bidirectional frames to upstream with Api-Subscription-Key header', async () => {
    const { token } = await createEphemeralToken({
      secret: TOKEN_SECRET,
      sub: 'user-ws-test',
      scopes: ['stt'],
      ttlSeconds: 60,
    });

    apiWsRecordedHeaders = null;

    // Connect to proxy WebSocket passing subprotocol: bearer.<token>
    const clientWs = new WebSocket(`${proxyWsUrl}/speech-to-text-realtime/ws`, [
      `bearer.${token}`,
    ]);

    await new Promise<void>((resolve, reject) => {
      clientWs.on('open', () => resolve());
      clientWs.on('error', (err) => reject(err));
    });

    // Send a frame from client to proxy -> upstream
    const messagePromise = new Promise<string>((resolve) => {
      clientWs.on('message', (data) => resolve(data.toString()));
    });

    clientWs.send(JSON.stringify({ event: 'ping' }));

    const reply = await messagePromise;
    const parsed = JSON.parse(reply);
    assert.equal(parsed.event, 'pong');

    // Verify upstream mock WebSocket received Api-Subscription-Key header
    assert.ok(apiWsRecordedHeaders);
    assert.equal(apiWsRecordedHeaders['api-subscription-key'], MASTER_API_KEY);

    clientWs.close();
  });

  // =========================================================================
  // Test 6: Rate Limiter Returns HTTP 429 with retry-after-ms
  // =========================================================================
  it('6. Rate limiter returns HTTP 429 with retry-after-ms when limit is exceeded', async () => {
    // Create a dedicated proxy server instance with RPM = 2
    const rateLimitedConfig: ProxyConfig = {
      sarvamApiKey: MASTER_API_KEY,
      tokenSecret: TOKEN_SECRET,
      upstreamApiBaseUrl: apiMockUrl,
      upstreamDubbingBaseUrl: dubbingMockUrl,
      upstreamWsBaseUrl: apiMockWsUrl,
      rateLimitRpm: 2, // Only 2 requests per minute!
    };

    const rateLimitedProxy = createNodeProxyServer(rateLimitedConfig);
    const { url } = await rateLimitedProxy.start(0, '127.0.0.1');

    try {
      const { token } = await createEphemeralToken({
        secret: TOKEN_SECRET,
        sub: 'rate-limited-user',
        scopes: ['text'],
        ttlSeconds: 60,
      });

      // Request 1: Allowed
      const res1 = await fetch(`${url}/translate`, {
        method: 'POST',
        headers: {
          'Authorization': `Bearer ${token}`,
          'Content-Type': 'application/json',
        },
        body: JSON.stringify({ input: 'req 1' }),
      });
      assert.equal(res1.status, 200);

      // Request 2: Allowed
      const res2 = await fetch(`${url}/translate`, {
        method: 'POST',
        headers: {
          'Authorization': `Bearer ${token}`,
          'Content-Type': 'application/json',
        },
        body: JSON.stringify({ input: 'req 2' }),
      });
      assert.equal(res2.status, 200);

      // Request 3: Rate limit exceeded -> 429
      const res3 = await fetch(`${url}/translate`, {
        method: 'POST',
        headers: {
          'Authorization': `Bearer ${token}`,
          'Content-Type': 'application/json',
        },
        body: JSON.stringify({ input: 'req 3' }),
      });

      assert.equal(res3.status, 429);
      const retryAfterMs = res3.headers.get('retry-after-ms');
      assert.ok(retryAfterMs, 'Expected retry-after-ms header to be present');
      assert.ok(parseInt(retryAfterMs, 10) > 0);

      const errBody = await res3.json() as any;
      assert.equal(errBody.error.code, 'rate_limit_exceeded_error');
      assert.ok(errBody.error.request_id);
    } finally {
      await rateLimitedProxy.stop();
    }
  });

  // =========================================================================
  // Test 7: Token & Crypto Utilities Comprehensive Coverage
  // =========================================================================
  it('7. token.ts edge cases: validation, bad signatures, tampering, and scopes', async () => {
    const {
      base64UrlEncode,
      base64UrlDecode,
      verifyEphemeralToken,
      isScopeAllowedForPath,
      createCanonicalErrorResponse,
      createAuthErrorResponse,
    } = await import('../src/token.js');

    // base64Url encoding / decoding with various lengths
    const testBytes1 = new Uint8Array([1, 2, 3, 4, 5]);
    const encoded1 = base64UrlEncode(testBytes1);
    const decoded1 = base64UrlDecode(encoded1);
    assert.deepEqual(Array.from(decoded1), [1, 2, 3, 4, 5]);

    // Error on empty secret in createEphemeralToken
    await assert.rejects(
      async () => createEphemeralToken({ secret: '' }),
      /Token secret must be a non-empty string/
    );

    // Error on non-string token in verifyEphemeralToken
    await assert.rejects(
      async () => verifyEphemeralToken('' as any, TOKEN_SECRET),
      /Token must be a non-empty string/
    );

    // Error on malformed token (not 3 parts)
    await assert.rejects(
      async () => verifyEphemeralToken('only-one-part', TOKEN_SECRET),
      /Malformed token structure/
    );

    // Error on invalid signature encoding
    await assert.rejects(
      async () => verifyEphemeralToken('header.payload.invalid!!!signature', TOKEN_SECRET),
      /Invalid signature encoding|Invalid token signature/
    );

    // Error on invalid payload encoding
    const validHeader = base64UrlEncode(new TextEncoder().encode(JSON.stringify({ alg: 'HS256', typ: 'JWT' })));
    const invalidPayload = base64UrlEncode(new TextEncoder().encode('not-json'));
    // Sign with valid key
    const enc = new TextEncoder();
    const key = await crypto.subtle.importKey(
      'raw',
      enc.encode(TOKEN_SECRET),
      { name: 'HMAC', hash: 'SHA-256' },
      false,
      ['sign']
    );
    const sig = await crypto.subtle.sign(
      'HMAC',
      key,
      enc.encode(`${validHeader}.${invalidPayload}`)
    );
    const validSigStr = base64UrlEncode(new Uint8Array(sig));
    const tokenWithBadPayloadJson = `${validHeader}.${invalidPayload}.${validSigStr}`;

    await assert.rejects(
      async () => verifyEphemeralToken(tokenWithBadPayloadJson, TOKEN_SECRET),
      /Invalid token payload encoding/
    );

    // isScopeAllowedForPath branches
    assert.equal(isScopeAllowedForPath(null as any, '/translate'), false);
    assert.equal(isScopeAllowedForPath(['*'], '/anything'), true);
    assert.equal(isScopeAllowedForPath(['all'], '/anything'), true);
    assert.equal(isScopeAllowedForPath(['stt'], 'speech-to-text'), true);
    assert.equal(isScopeAllowedForPath(['tts'], '/voices/clone'), true);
    assert.equal(isScopeAllowedForPath(['text'], '/transliterate'), true);
    assert.equal(isScopeAllowedForPath(['text'], '/text-lid'), true);
    assert.equal(isScopeAllowedForPath(['chat'], '/v1/chat/completions'), true);
    assert.equal(isScopeAllowedForPath(['chat'], '/models'), true);
    assert.equal(isScopeAllowedForPath(['chat'], '/v2/responses'), true);
    assert.equal(isScopeAllowedForPath(['doc_ai'], '/doc-ai/digitise'), true);
    assert.equal(isScopeAllowedForPath(['tts'], '/pronunciation-dictionaries/123'), true);
    assert.equal(isScopeAllowedForPath(['text'], '/pronunciation-dictionaries/123'), true);
    assert.equal(isScopeAllowedForPath(['unknown'], '/custom-unmapped'), true);

    // createCanonicalErrorResponse with extraHeaders
    const errRes = createCanonicalErrorResponse(418, 'teapot_error', 'I am a teapot', {
      'x-custom-tea': 'earl-grey',
    });
    assert.equal(errRes.status, 418);
    assert.equal(errRes.headers.get('x-custom-tea'), 'earl-grey');

    // createAuthErrorResponse default message
    const defaultAuthErr = createAuthErrorResponse();
    assert.equal(defaultAuthErr.status, 403);
    const defaultBody = await defaultAuthErr.json() as any;
    assert.equal(defaultBody.error.message, 'Invalid or expired token');
  });

  // =========================================================================
  // Test 8: Middleware & RateLimiter Coverage
  // =========================================================================
  it('8. middleware.ts edge cases: header extraction varieties & RateLimiter cleanup', async () => {
    const { extractClientToken, RateLimiter } = await import('../src/middleware.js');

    // Case-insensitive record headers
    const auth1 = extractClientToken({ 'API-SUBSCRIPTION-KEY': 'sub-key-123' });
    assert.equal(auth1.token, 'sub-key-123');
    assert.equal(auth1.authType, 'subscription-key');

    // Array header value in record
    const auth2 = extractClientToken({ 'authorization': ['Bearer token-abc', 'Bearer token-def'] });
    assert.equal(auth2.token, 'token-abc');
    assert.equal(auth2.authType, 'bearer');

    // Subprotocol: api-subscription-key.<token>
    const auth3 = extractClientToken({ 'sec-websocket-protocol': 'chat, api-subscription-key.secret-tok' });
    assert.equal(auth3.token, 'secret-tok');
    assert.equal(auth3.authType, 'subscription-key');
    assert.equal(auth3.subprotocolToEcho, 'api-subscription-key.secret-tok');

    // No auth
    const authNone = extractClientToken({});
    assert.equal(authNone.token, null);
    assert.equal(authNone.authType, null);

    // RateLimiter reset and cleanup
    const limiter = new RateLimiter({ rpm: 60 });
    const r1 = limiter.check('user-1');
    assert.equal(r1.allowed, true);
    limiter.reset();

    // Trigger cleanup by manually advancing lastCleanup
    (limiter as any).lastCleanup = Date.now() - 130000;
    (limiter as any).buckets.set('old-user', { tokens: 10, lastRefill: Date.now() - 130000 });
    limiter.check('new-user');
    assert.equal((limiter as any).buckets.has('old-user'), false);
  });

  // =========================================================================
  // Test 9: Router Edge Cases (CORS, Health, Dubbing URL, Upstream Failure)
  // =========================================================================
  it('9. router.ts edge cases: OPTIONS, /health, custom URL prefixes, upstream errors', async () => {
    const { resolveUpstreamUrl, resolveUpstreamWsUrl } = await import('../src/router.js');

    // resolveUpstreamUrl when upstreamDubbingBaseUrl does NOT end in /dubbing
    const dubbingResolved = resolveUpstreamUrl('/dubbing/projects', '?page=1', {
      sarvamApiKey: 'key',
      tokenSecret: 'sec',
      upstreamDubbingBaseUrl: 'https://dubbing.internal.sarvam.ai',
    });
    assert.equal(dubbingResolved, 'https://dubbing.internal.sarvam.ai/dubbing/projects?page=1');

    // resolveUpstreamWsUrl
    const wsResolved = resolveUpstreamWsUrl('/ws/stream', '', {
      sarvamApiKey: 'key',
      tokenSecret: 'sec',
      upstreamWsBaseUrl: 'wss://custom.ws.sarvam.ai/',
    });
    assert.equal(wsResolved, 'wss://custom.ws.sarvam.ai/ws/stream');

    // 9.1 CORS preflight OPTIONS
    const optionsRes = await fetch(`${proxyUrl}/translate`, {
      method: 'OPTIONS',
      headers: { 'Origin': 'https://app.example.com' },
    });
    assert.equal(optionsRes.status, 204);
    assert.equal(optionsRes.headers.get('Access-Control-Allow-Origin'), '*');

    // 9.2 Health check endpoint /health and GET /
    const healthRes = await fetch(`${proxyUrl}/health`);
    assert.equal(healthRes.status, 200);
    const healthData = await healthRes.json() as any;
    assert.equal(healthData.service, 'sarvam-bff-proxy');

    const rootRes = await fetch(`${proxyUrl}/`);
    assert.equal(rootRes.status, 200);

    // 9.3 Invalid JSON in POST /auth/token
    const badJsonRes = await fetch(`${proxyUrl}/auth/token`, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: 'invalid-json{{{',
    });
    assert.equal(badJsonRes.status, 400);
    const badJsonBody = await badJsonRes.json() as any;
    assert.equal(badJsonBody.error.code, 'bad_request_error');

    // 9.4 Empty body in POST /auth/token
    const emptyBodyRes = await fetch(`${proxyUrl}/auth/token`, {
      method: 'POST',
    });
    assert.equal(emptyBodyRes.status, 200);

    // 9.5 Upstream failure (HTTP 502)
    const deadProxy = createNodeProxyServer({
      sarvamApiKey: MASTER_API_KEY,
      tokenSecret: TOKEN_SECRET,
      upstreamApiBaseUrl: 'http://127.0.0.1:54321', // No server running here
    });
    const deadStart = await deadProxy.start(0, '127.0.0.1');
    try {
      const { token } = await createEphemeralToken({
        secret: TOKEN_SECRET,
        sub: 'user-fail',
        scopes: ['text'],
      });
      const failRes = await fetch(`${deadStart.url}/translate`, {
        method: 'POST',
        headers: {
          'Authorization': `Bearer ${token}`,
          'Content-Type': 'application/json',
        },
        body: JSON.stringify({ input: 'test' }),
      });
      assert.equal(failRes.status, 502);
      const failBody = await failRes.json() as any;
      assert.equal(failBody.error.code, 'connection_error');
    } finally {
      await deadProxy.stop();
    }
  });

  // =========================================================================
  // Test 10: WebSocket Upgrade Edge Cases
  // =========================================================================
  it('10. node-server.ts WebSocket upgrade edge cases: missing token, invalid token, disallowed scope, rate limit', async () => {
    // 10.1 Upgrade without token -> upgrade rejected
    await assert.rejects(
      () =>
        new Promise<void>((resolve, reject) => {
          const ws = new WebSocket(`${proxyWsUrl}/speech-to-text-realtime/ws`);
          ws.on('open', () => {
            ws.close();
            reject(new Error('Should not have opened'));
          });
          ws.on('error', (err) => reject(err));
        })
    );

    // 10.2 Upgrade with invalid token
    await assert.rejects(
      () =>
        new Promise<void>((resolve, reject) => {
          const ws = new WebSocket(`${proxyWsUrl}/speech-to-text-realtime/ws`, [
            'bearer.invalid-token-123',
          ]);
          ws.on('open', () => {
            ws.close();
            reject(new Error('Should not have opened'));
          });
          ws.on('error', (err) => reject(err));
        })
    );

    // 10.3 Upgrade with disallowed scope
    const { token: textOnlyToken } = await createEphemeralToken({
      secret: TOKEN_SECRET,
      sub: 'ws-text-user',
      scopes: ['text'], // Not allowed for /speech-to-text-realtime/ws
    });
    await assert.rejects(
      () =>
        new Promise<void>((resolve, reject) => {
          const ws = new WebSocket(`${proxyWsUrl}/speech-to-text-realtime/ws`, [
            `bearer.${textOnlyToken}`,
          ]);
          ws.on('open', () => {
            ws.close();
            reject(new Error('Should not have opened'));
          });
          ws.on('error', (err) => reject(err));
        })
    );

    // 10.4 Binary WebSocket frames and queuing before upstream open
    const { token: sttToken } = await createEphemeralToken({
      secret: TOKEN_SECRET,
      sub: 'ws-binary-user',
      scopes: ['stt'],
    });

    const clientWs = new WebSocket(`${proxyWsUrl}/speech-to-text-realtime/ws`, [
      `bearer.${sttToken}`,
    ]);

    await new Promise<void>((resolve, reject) => {
      clientWs.on('open', () => resolve());
      clientWs.on('error', (err) => reject(err));
    });

    const binaryReceivedPromise = new Promise<Buffer>((resolve) => {
      clientWs.on('message', (data, isBinary) => {
        if (isBinary) resolve(data as Buffer);
      });
    });

    // Send binary audio frame
    const audioChunk = Buffer.from([0x01, 0x02, 0x03, 0x04]);
    clientWs.send(audioChunk, { binary: true });

    const receivedBinary = await binaryReceivedPromise;
    assert.deepEqual(receivedBinary, audioChunk);

    clientWs.close(1000, 'Normal closure');
  });

  // =========================================================================
  // Test 11: WebSocket Upgrade Rate Limit, Close Codes, and Error Handlers
  // =========================================================================
  it('11. node-server.ts WS rate limiting, error forwarding, close codes', async () => {
    // 11.1 WS Upgrade Rate Limiting
    const rateLimitedConfig: ProxyConfig = {
      sarvamApiKey: MASTER_API_KEY,
      tokenSecret: TOKEN_SECRET,
      upstreamApiBaseUrl: apiMockUrl,
      upstreamDubbingBaseUrl: dubbingMockUrl,
      upstreamWsBaseUrl: apiMockWsUrl,
      rateLimitRpm: 1, // Only 1 request allowed!
    };
    const rateLimitedProxy = createNodeProxyServer(rateLimitedConfig);
    const { wsUrl } = await rateLimitedProxy.start(0, '127.0.0.1');

    try {
      const { token } = await createEphemeralToken({
        secret: TOKEN_SECRET,
        sub: 'ws-rate-limit-user',
        scopes: ['stt'],
        ttlSeconds: 60,
      });

      // Connection 1: Allowed
      const ws1 = new WebSocket(`${wsUrl}/speech-to-text-realtime/ws`, [`bearer.${token}`]);
      await new Promise<void>((resolve, reject) => {
        ws1.on('open', () => resolve());
        ws1.on('error', (err) => reject(err));
      });
      ws1.close();

      // Connection 2: Rate limit exceeded -> rejected with 429
      await assert.rejects(
        () =>
          new Promise<void>((resolve, reject) => {
            const ws2 = new WebSocket(`${wsUrl}/speech-to-text-realtime/ws`, [`bearer.${token}`]);
            ws2.on('open', () => {
              ws2.close();
              reject(new Error('Should have been rejected'));
            });
            ws2.on('error', (err) => reject(err));
          })
      );
    } finally {
      await rateLimitedProxy.stop();
    }

    // 11.2 Error handlers & close forwarding
    const { token: wsTok } = await createEphemeralToken({
      secret: TOKEN_SECRET,
      sub: 'ws-error-user',
      scopes: ['stt'],
    });

    const clientWs = new WebSocket(`${proxyWsUrl}/speech-to-text-realtime/ws`, [`bearer.${wsTok}`]);
    await new Promise<void>((resolve, reject) => {
      clientWs.on('open', () => resolve());
      clientWs.on('error', (err) => reject(err));
    });

    // Close without code (tests default 1000 fallback)
    clientWs.close();
    await new Promise((r) => setTimeout(r, 50));

    // 11.3 handleFetch directly for OPTIONS
    const { handleFetch } = await import('../src/router.js');
    const { RateLimiter } = await import('../src/middleware.js');
    const directOptions = await handleFetch(
      new Request('http://localhost/translate', { method: 'OPTIONS' }),
      { sarvamApiKey: 'k', tokenSecret: 's' },
      new RateLimiter()
    );
    assert.equal(directOptions.status, 204);
  });

  // =========================================================================
  // Test 12: node-server.ts WebSocket Error Listeners & Upstream Close
  // =========================================================================
  it('12. node-server.ts error listeners and close events', async () => {
    const { token } = await createEphemeralToken({
      secret: TOKEN_SECRET,
      sub: 'ws-err-cov',
      scopes: ['stt'],
    });

    const clientWs = new WebSocket(`${proxyWsUrl}/speech-to-text-realtime/ws`, [`bearer.${token}`]);
    await new Promise<void>((resolve, reject) => {
      clientWs.on('open', () => resolve());
      clientWs.on('error', (err) => reject(err));
    });

    // Find the server-side client WebSocket and upstream WebSocket
    const serverClientWs = Array.from(proxyInstance.wss.clients)[0];
    if (serverClientWs) {
      serverClientWs.emit('error', new Error('client err'));
    }

    const upstreamWs = Array.from(apiWss.clients)[0];
    if (upstreamWs) {
      upstreamWs.emit('error', new Error('upstream err'));
    }

    clientWs.close();
    await new Promise((r) => setTimeout(r, 50));
  });
});




