import { test, describe } from 'node:test';
import assert from 'node:assert/strict';
import {
  SarvamClient,
  SarvamEnvironment,
  ApiKeyAuth,
  TokenAuth,
  ProxyAuth,
  SarvamError,
  AuthenticationError,
  PermissionDeniedError,
  BadRequestError,
  NotFoundError,
  PayloadTooLargeError,
  UnprocessableEntityError,
  RateLimitError,
  ServerError,
  ConnectionError,
  TimeoutError,
  RealtimeError,
  isAbortError,
  parseRetryAfterHeader,
  createHttpError,
  FetchHttpTransport,
  DefaultWebSocketFactory,
  createAuthMiddleware,
  createLoggingMiddleware,
  redactHeaders,
  createRetryMiddleware,
  isRetryableStatus,
  isRetryableError,
  parseSseStream,
  base64ToBytes,
  hexToBytes,
  defaultClock,
  defaultRandom,
  pollUntilComplete,
  isStandardJobComplete,
  isStandardJobFailed,
  getStandardJobFailureMessage,
  TextResource,
  SpeechToTextResource,
  TextToSpeechResource,
  ChatResource,
  ResponsesResource,
  JobsResource,
  DocAiResource,
  VoiceCloningResource,
  PronunciationDictionaryResource,
  SpeechToTextJobResource,
  SpeechToTextTranslateJobResource,
  DocumentTranslationResource,
  DubbingResource,
} from '../dist/esm/index.js';
import { appendFileInput } from '../dist/esm/resources/form.js';
import type {
  HttpRequest,
  HttpResponse,
  ClientDispatcher,
  WebSocketConnection,
} from '../dist/esm/index.js';

function makeMockResponse(status: number, body: unknown, headersMap: Record<string, string> = {}): HttpResponse {
  const rawText = typeof body === 'string' ? body : JSON.stringify(body);
  return {
    status,
    statusText: status === 200 ? 'OK' : 'Error',
    headers: {
      get: (name: string) => headersMap[name.toLowerCase()] ?? headersMap[name] ?? null,
      has: (name: string) => (name.toLowerCase() in headersMap) || (name in headersMap),
      entries: function* () {
        for (const [k, v] of Object.entries(headersMap)) {
          yield [k, v];
        }
      },
    },
    json: async <T = unknown>() => (typeof body === 'string' ? JSON.parse(body) : body) as T,
    text: async () => rawText,
    bytes: async () => new TextEncoder().encode(rawText),
    bodyStream: () => ({
      async *[Symbol.asyncIterator]() {
        yield new TextEncoder().encode(rawText);
      },
    }),
  };
}

describe('@sarvam/core Comprehensive Coverage Tests', () => {
  describe('1. Auth, Environment, Errors, Base64 & Timing', () => {
    test('ApiKeyAuth validation and __DEV__ release warning', () => {
      assert.throws(() => new ApiKeyAuth(''), /non-empty string/);
      assert.throws(() => new ApiKeyAuth('   '), /non-empty string/);

      const prevDev = (globalThis as any).__DEV__;
      const origWarn = console.warn;
      const warnings: string[] = [];
      console.warn = (msg: string) => warnings.push(msg);
      try {
        (globalThis as any).__DEV__ = false;
        (ApiKeyAuth as any).warned = false;
        new ApiKeyAuth('valid-key');
        assert.equal(warnings.length, 1);
      } finally {
        console.warn = origWarn;
        (globalThis as any).__DEV__ = prevDev;
      }
    });

    test('TokenAuth validation, string return, and error handling', async () => {
      assert.throws(() => new TokenAuth('invalid' as any), /must be a function/);

      const strAuth = new TokenAuth(async () => 'plain-jwt');
      const cred = await strAuth.getCredentials();
      assert.equal(cred.kind, 'bearerToken');
      if (cred.kind === 'bearerToken') assert.equal(cred.token, 'plain-jwt');
      // Second call uses cached token without expiry
      const credCached = await strAuth.getCredentials();
      assert.equal(credCached.kind, 'bearerToken');

      const badObjAuth = new TokenAuth(async () => ({} as any));
      await assert.rejects(() => badObjAuth.getCredentials(), /must return a string or an object/);

      const throwingAuth = new TokenAuth(async () => {
        throw new Error('fetch failed');
      });
      await assert.rejects(() => throwingAuth.getCredentials(), /fetch failed/);
    });

    test('ProxyAuth static, function, and empty headers', async () => {
      const p1 = new ProxyAuth('https://bff.example.com/');
      assert.deepEqual(await p1.getCredentials(), { kind: 'customHeaders', headers: {} });

      const p2 = new ProxyAuth('https://bff.example.com', { 'X-App': '1' });
      assert.deepEqual(await p2.getCredentials(), { kind: 'customHeaders', headers: { 'X-App': '1' } });

      const p3 = new ProxyAuth('https://bff.example.com', async () => ({ 'X-Func': '2' }));
      assert.deepEqual(await p3.getCredentials(), { kind: 'customHeaders', headers: { 'X-Func': '2' } });
    });

    test('SarvamEnvironment ws and custom edge cases', () => {
      const e1 = SarvamEnvironment.proxy('wss://ws.example.com/');
      assert.equal(e1.wsBaseUrl, 'wss://ws.example.com');

      const e2 = SarvamEnvironment.proxy('example.com');
      assert.equal(e2.wsBaseUrl, 'wss://example.com');

      const e3 = SarvamEnvironment.custom({
        apiBaseUrl: 'https://api.example.com/',
        dubbingBaseUrl: 'https://dub.example.com/',
        wsBaseUrl: 'wss://ws.example.com/',
      });
      assert.equal(e3.dubbingBaseUrl, 'https://dub.example.com');
      assert.equal(e3.wsBaseUrl, 'wss://ws.example.com');
    });

    test('Errors, parseRetryAfterHeader, and createHttpError edge cases', async () => {
      assert.equal(isAbortError(null), false);
      assert.equal(isAbortError('string'), false);

      // HTTP-date in retry-after (future and past)
      const futureDate = new Date(Date.now() + 5000).toUTCString();
      const dFuture = parseRetryAfterHeader((n) => (n === 'retry-after' ? futureDate : null));
      assert.ok(dFuture !== undefined && dFuture > 0);

      const pastDate = new Date(Date.now() - 5000).toUTCString();
      const dPast = parseRetryAfterHeader((n) => (n === 'retry-after' ? pastDate : null));
      assert.equal(dPast, 0);

      // x-ratelimit-reset (future and past)
      const futureEpoch = String(Math.floor(Date.now() / 1000) + 10);
      const rFuture = parseRetryAfterHeader((n) => (n === 'x-ratelimit-reset' ? futureEpoch : null));
      assert.ok(rFuture !== undefined && rFuture > 0);

      const pastEpoch = String(Math.floor(Date.now() / 1000) - 10);
      const rPast = parseRetryAfterHeader((n) => (n === 'x-ratelimit-reset' ? pastEpoch : null));
      assert.equal(rPast, 0);

      assert.equal(parseRetryAfterHeader(() => null), undefined);

      // createHttpError across all status codes and body shapes
      const e401 = await createHttpError(
        401,
        JSON.stringify({ error: { code: 'unauth', message: 'No auth', request_id: 'r1' } }),
        () => null
      );
      assert.ok(e401 instanceof AuthenticationError);
      assert.equal(e401.requestId, 'r1');

      const e400 = await createHttpError(
        400,
        JSON.stringify({ code: 'bad_req', message: 'Bad', request_id: 'r2' }),
        () => null
      );
      assert.ok(e400 instanceof BadRequestError);
      assert.equal(e400.requestId, 'r2');

      const e404 = await createHttpError(404, JSON.stringify({ detail: 'Not found detail' }), () => null);
      assert.ok(e404 instanceof NotFoundError);
      assert.equal(e404.message, 'Not found detail');

      const e413 = await createHttpError(413, '{malformed json', () => 'req_hdr');
      assert.ok(e413 instanceof PayloadTooLargeError);

      const e422 = await createHttpError(422, '', () => null);
      assert.ok(e422 instanceof UnprocessableEntityError);

      const e429 = await createHttpError(429, '', (n) => (n === 'retry-after-ms' ? '100' : null));
      assert.ok(e429 instanceof RateLimitError);
      assert.equal(e429.retryAfterMs, 100);

      const e503Rate = await createHttpError(
        503,
        JSON.stringify({ error: { code: 'rate_limit_exceeded_error' } }),
        (n) => (n === 'retry-after-ms' ? '200' : null)
      );
      assert.ok(e503Rate instanceof RateLimitError);

      const e503Server = await createHttpError(503, 'Service unavailable', () => null);
      assert.ok(e503Server instanceof ServerError);

      const e502 = await createHttpError(502, 'Bad gateway', () => null);
      assert.ok(e502 instanceof ServerError);

      const e418 = await createHttpError(418, 'Teapot', () => null);
      assert.ok(e418 instanceof SarvamError);
    });

    test('base64, hex, and timing utilities', async () => {
      // URL-safe base64 characters '-' and '_'
      const decoded = base64ToBytes('-_8=');
      assert.equal(decoded.length, 2);

      assert.throws(() => base64ToBytes('!!!!'), /Invalid base64 character/);
      assert.throws(() => hexToBytes('abc'), /even length/);

      assert.equal(typeof defaultClock.now(), 'number');
      await defaultClock.sleep(1);
      const r = defaultRandom.random();
      assert.ok(r >= 0 && r <= 1);
    });
  });

  describe('2. Middlewares & SarvamClient', () => {
    test('AuthMiddleware handles bearerToken, customHeaders, thrown AuthenticationError, and 403 PermissionDenied reconstruction', async () => {
      let invalidated = false;
      const customAuth = {
        getCredentials: async () => ({ kind: 'customHeaders' as const, headers: { 'X-Custom': 'val' } }),
        invalidate: () => {
          invalidated = true;
        },
      };
      const mw = createAuthMiddleware(customAuth);

      // 1. Thrown AuthenticationError triggers invalidate + retry
      let calls = 0;
      const res1 = await mw(
        { method: 'GET', url: 'https://api.sarvam.ai/test', headers: {} },
        async (req) => {
          calls++;
          assert.equal(req.headers['X-Custom'], 'val');
          if (calls === 1) throw new AuthenticationError('expired');
          return makeMockResponse(200, { ok: true });
        }
      );
      assert.equal(res1.status, 200);
      assert.equal(invalidated, true);

      // 2. Thrown non-AuthenticationError rethrows
      await assert.rejects(() =>
        mw({ method: 'GET', url: 'https://api.sarvam.ai/test', headers: {} }, async () => {
          throw new BadRequestError('bad');
        })
      );

      // 3. 403 PermissionDeniedError reconstructs HttpResponse with json, text, bytes, bodyStream
      const res403 = await mw(
        { method: 'GET', url: 'https://api.sarvam.ai/test', headers: {} },
        async () => makeMockResponse(403, { error: { code: 'authentication_error', message: 'Forbidden' } })
      );
      assert.equal(res403.status, 403);
      assert.equal(await res403.text(), JSON.stringify({ error: { code: 'authentication_error', message: 'Forbidden' } }));
      assert.deepEqual(await res403.json(), { error: { code: 'authentication_error', message: 'Forbidden' } });
      assert.ok((await res403.bytes()).length > 0);
      const chunks: Uint8Array[] = [];
      for await (const c of res403.bodyStream()!) {
        chunks.push(c);
      }
      assert.equal(chunks.length, 1);
    });

    test('LoggingMiddleware and redactHeaders cover all log levels and error paths', async () => {
      const redacted = redactHeaders({
        'api-subscription-key': 'secret1',
        Authorization: 'Bearer secret2',
        'content-type': 'application/json',
      });
      assert.equal(redacted['api-subscription-key'], '[REDACTED]');
      assert.equal(redacted['Authorization'], '[REDACTED]');
      assert.equal(redacted['content-type'], 'application/json');

      const logs: Array<{ level: string; msg: string }> = [];
      const logger = {
        info: (msg: string) => logs.push({ level: 'info', msg }),
        warn: (msg: string) => logs.push({ level: 'warn', msg }),
        error: (msg: string) => logs.push({ level: 'error', msg }),
      };
      const mw = createLoggingMiddleware(logger);
      const req: HttpRequest = { method: 'GET', url: 'https://api.sarvam.ai/test', headers: {} };

      await mw(req, async () => makeMockResponse(200, {}, { 'x-request-id': 'req_1' }));
      await mw(req, async () => makeMockResponse(400, {}));
      await mw(req, async () => makeMockResponse(500, {}));
      await assert.rejects(() =>
        mw(req, async () => {
          throw new Error('boom');
        })
      );
      await assert.rejects(() =>
        mw(req, async () => {
          throw 'string-error';
        })
      );

      assert.equal(logs[0]?.level, 'info');
      assert.equal(logs[1]?.level, 'warn');
      assert.equal(logs[2]?.level, 'error');
      assert.equal(logs[3]?.level, 'error');
      assert.equal(logs[4]?.level, 'error');
    });

    test('RetryMiddleware covers status & error retry matrices', async () => {
      assert.equal(isRetryableStatus(500, 'JOB_CREATE', true), true);
      assert.equal(isRetryableStatus(500, 'JOB_CREATE', false), false);
      assert.equal(isRetryableStatus(503, 'MULTIPART_COMPUTE', false), true);
      assert.equal(isRetryableStatus(500, 'MULTIPART_COMPUTE', false), false);
      assert.equal(isRetryableStatus(500, 'UNKNOWN' as any, false), false);

      assert.equal(isRetryableError(new RateLimitError('rate'), 'JOB_CREATE', false), true);
      assert.equal(isRetryableError(new ConnectionError('conn'), 'JOB_CREATE', false), false);
      assert.equal(isRetryableError(new ConnectionError('conn'), 'STATELESS_POST', false), true);
      assert.equal(isRetryableError(new Error('other'), 'STATELESS_POST', false), false);

      let attempts = 0;
      const mw = createRetryMiddleware({
        maxRetries: 2,
        clock: { now: () => 0, sleep: async () => {} },
      });
      const res = await mw(
        { method: 'POST', url: 'https://api.sarvam.ai/test', headers: {} },
        async () => {
          attempts++;
          if (attempts === 1) throw new RateLimitError('rate', { retryAfterMs: 10 });
          if (attempts === 2) throw new ConnectionError('reset');
          return makeMockResponse(200, { ok: true });
        }
      );
      assert.equal(res.status, 200);
      assert.equal(attempts, 3);
    });

    test('SarvamClient constructor validation and configurations', async () => {
      assert.throws(() => new SarvamClient({} as any), /requires either apiKey or authProvider/);

      const c1 = new SarvamClient({ apiKey: 'key1', baseUrl: 'https://custom.sarvam.ai' });
      assert.equal(c1.environment.apiBaseUrl, 'https://custom.sarvam.ai');

      const c2 = new SarvamClient({
        apiKey: 'key2',
        httpTransport: {
          execute: async () => makeMockResponse(200, { ok: true }),
        },
      });
      assert.equal(c2.environment.apiBaseUrl, 'https://api.sarvam.ai');
      const directRes = await c2.execute({ method: 'GET', url: 'https://api.sarvam.ai/ping', headers: {} });
      assert.equal(directRes.status, 200);
    });
  });

  describe('3. FetchHttpTransport, DefaultWebSocketFactory, SSE & Polling', () => {
    test('FetchHttpTransport handles timeouts, aborts, FormData, and bodyStream variants', async () => {
      const origFetch = globalThis.fetch;
      try {
        const transport = new FetchHttpTransport({ defaultTimeoutMs: 50 });

        // 1. Pre-aborted signal
        const preAborted = new AbortController();
        preAborted.abort(new Error('already aborted'));
        await assert.rejects(
          () => transport.execute({ method: 'GET', url: 'https://example.com', headers: {}, signal: preAborted.signal }),
          /already aborted/
        );

        // 2. Timeout
        globalThis.fetch = (async (_url: any, init: any) => {
          return new Promise((_resolve, reject) => {
            init.signal.addEventListener('abort', () => reject(init.signal.reason));
          });
        }) as any;
        await assert.rejects(
          () => transport.execute({ method: 'GET', url: 'https://example.com', headers: {}, timeoutMs: 10 }),
          (err: any) => err instanceof TimeoutError
        );

        // 3. Caller signal aborts mid-flight
        const callerAc = new AbortController();
        globalThis.fetch = (async (_url: any, init: any) => {
          setTimeout(() => callerAc.abort(new DOMException('Aborted', 'AbortError')), 5);
          return new Promise((_resolve, reject) => {
            init.signal.addEventListener('abort', () => reject(init.signal.reason));
          });
        }) as any;
        await assert.rejects(
          () => transport.execute({ method: 'GET', url: 'https://example.com', headers: {}, signal: callerAc.signal, timeoutMs: 0 }),
          (err: any) => isAbortError(err)
        );

        // 4. Network error wrapped into ConnectionError
        globalThis.fetch = (async () => {
          throw new TypeError('Failed to fetch');
        }) as any;
        await assert.rejects(
          () => transport.execute({ method: 'GET', url: 'https://example.com', headers: {} }),
          (err: any) => err instanceof ConnectionError
        );

        // 5. Response helpers: headers.has, headers.entries, bytes, and bodyStream with getReader() / null body / fallback
        globalThis.fetch = (async () => ({
          status: 200,
          statusText: 'OK',
          headers: new Headers({ 'x-test': '1' }),
          json: async () => ({ a: 1 }),
          text: async () => '{"a":1}',
          arrayBuffer: async () => new Uint8Array([1, 2, 3]).buffer,
          body: {
            getReader: () => {
              let read = false;
              return {
                read: async () => {
                  if (!read) {
                    read = true;
                    return { done: false, value: new Uint8Array([9, 8]) };
                  }
                  return { done: true, value: undefined };
                },
                releaseLock: () => {},
              };
            },
          },
        })) as any;

        const fd = new FormData();
        fd.append('k', 'v');
        const res = await transport.execute({
          method: 'POST',
          url: 'https://example.com',
          headers: { 'Content-Type': 'multipart/form-data' },
          body: fd,
        });
        assert.equal(res.headers.has('x-test'), true);
        assert.equal(Array.from(res.headers.entries()).length, 1);
        assert.equal((await res.bytes()).length, 3);
        const readerChunks: Uint8Array[] = [];
        for await (const c of res.bodyStream()!) {
          readerChunks.push(c);
        }
        assert.equal(readerChunks.length, 1);

        // Null body fallback and non-iterable object fallback
        globalThis.fetch = (async () => ({
          status: 200,
          statusText: 'OK',
          headers: { get: () => null, has: () => false },
          arrayBuffer: async () => new Uint8Array([7]).buffer,
          body: null,
        })) as any;
        const resNullBody = await transport.execute({ method: 'GET', url: 'https://example.com', headers: {} });
        assert.deepEqual(Array.from(resNullBody.headers.entries()), []);
        for await (const c of resNullBody.bodyStream()!) {
          assert.equal(c[0], 7);
        }

        globalThis.fetch = (async () => ({
          status: 200,
          statusText: 'OK',
          headers: new Headers(),
          arrayBuffer: async () => new Uint8Array([8]).buffer,
          body: {},
        })) as any;
        const resFallbackBody = await transport.execute({ method: 'GET', url: 'https://example.com', headers: {} });
        for await (const c of resFallbackBody.bodyStream()!) {
          assert.equal(c[0], 8);
        }
      } finally {
        globalThis.fetch = origFetch;
      }
    });

    test('DefaultWebSocketFactory and StandardWebSocketConnection cover all frame types and handshake errors', async () => {
      // Missing global WebSocket
      const prevWs = (globalThis as any).WebSocket;
      try {
        delete (globalThis as any).WebSocket;
        const emptyFactory = new DefaultWebSocketFactory();
        await assert.rejects(() => emptyFactory.connect('wss://example.com'), /not found in global scope/);
      } finally {
        (globalThis as any).WebSocket = prevWs;
      }

      // Handshake error before open
      class ErrorBeforeOpenWs {
        onerror: any;
        constructor() {
          setTimeout(() => this.onerror?.(new Error('handshake fail')), 2);
        }
      }
      await assert.rejects(
        () => new DefaultWebSocketFactory(ErrorBeforeOpenWs).connect('wss://example.com'),
        (err: any) => err instanceof RealtimeError
      );

      // Close before open
      class CloseBeforeOpenWs {
        onclose: any;
        constructor() {
          setTimeout(() => this.onclose?.({ code: 4001, reason: 'Unauthorized' }), 2);
        }
      }
      await assert.rejects(
        () => new DefaultWebSocketFactory(CloseBeforeOpenWs).connect('wss://example.com'),
        (err: any) => err instanceof RealtimeError && err.closeCode === 4001
      );

      // 3-arg constructor throwing falls back to 2-arg, plus message frame types
      let lastInstance: any;
      class TwoArgOnlyWs {
        onopen: any;
        onmessage: any;
        onerror: any;
        onclose: any;
        constructor(_url: string, _protocols?: any, extra?: any) {
          if (extra) throw new Error('Browser WebSocket does not accept 3rd arg');
          lastInstance = this;
          setTimeout(() => this.onopen?.(), 2);
        }
        send() {}
        close() {}
      }

      const conn = await new DefaultWebSocketFactory(TwoArgOnlyWs).connect('wss://example.com', {
        headers: { Authorization: 'Bearer tok' },
        protocols: 'proto1',
      });

      const received: any[] = [];
      const handler = (d: any) => received.push(d);
      conn.on('message', handler);

      // Listener that throws is caught safely
      const origErr = console.error;
      console.error = () => {};
      try {
        conn.on('message', () => {
          throw new Error('listener boom');
        });
        lastInstance.onmessage({ data: 'hello' });
        lastInstance.onmessage({ data: new Uint8Array([1, 2]) });
        lastInstance.onmessage({ data: new Uint8Array([3, 4]).buffer });
        lastInstance.onmessage({ data: new Blob([new Uint8Array([5, 6])]) });
        lastInstance.onmessage({ data: new Int16Array([7, 8]) });
        lastInstance.onmessage({ data: 42 });
        await new Promise((r) => setTimeout(r, 15));
      } finally {
        console.error = origErr;
      }

      assert.ok(received.length >= 6);
      conn.off?.('message', handler);
    });

    test('parseSseStream handles comments, id, retry, data.type termination, and trailing buffer', async () => {
      async function* makeStream(chunks: string[]) {
        for (const c of chunks) {
          yield new TextEncoder().encode(c);
        }
      }

      const events = [];
      for await (const ev of parseSseStream(
        makeStream([
          ': comment line\n\n',
          'id: msg_1\nretry: 500\nfield_without_colon\ndata: {"type":"response.completed"}\n\n',
          'data: {"ignored":true}\n\n',
        ]),
        { isResponsesApi: true }
      )) {
        events.push(ev);
      }
      assert.equal(events.length, 1);
      assert.equal(events[0]?.id, 'msg_1');
      assert.equal(events[0]?.retry, 500);

      // Trailing buffer without \n\n
      const trailingEvents = [];
      for await (const ev of parseSseStream(makeStream(['data: {"trailing":1}']))) {
        trailingEvents.push(ev);
      }
      assert.equal(trailingEvents.length, 1);

      // AbortSignal during stream
      const ac = new AbortController();
      ac.abort(new Error('stream aborted'));
      await assert.rejects(async () => {
        for await (const _ of parseSseStream(makeStream(['data: 1\n\n']), { signal: ac.signal })) {
          // no-op
        }
      }, /stream aborted/);
    });

    test('polling helpers cover edge cases and mid-sleep abort', async () => {
      assert.equal(isStandardJobComplete(null), false);
      assert.equal(isStandardJobFailed(null), false);
      assert.equal(getStandardJobFailureMessage(null), 'Job failed');
      assert.equal(getStandardJobFailureMessage({ status: 'FAILED' }), 'Job failed with state: FAILED');

      const ac = new AbortController();
      const clock = {
        now: () => 100,
        sleep: async () => {
          ac.abort();
          await new Promise((r) => setTimeout(r, 10));
        },
      };
      await assert.rejects(
        () =>
          pollUntilComplete({
            poll: async () => ({ status: 'PENDING' }),
            isComplete: isStandardJobComplete,
            signal: ac.signal,
            clock,
          }),
        (err: any) => err.name === 'AbortError'
      );
    });
  });

  describe('4. All Resource Methods & Error Branches', () => {
    function createTestDispatcher(handler: (req: HttpRequest) => HttpResponse | Promise<HttpResponse>): ClientDispatcher {
      return {
        execute: async (req) => handler(req),
        getApiBaseUrl: () => 'https://api.sarvam.ai',
        getDubbingBaseUrl: () => 'https://api.sarvam.ai/dubbing',
        getWsBaseUrl: () => 'wss://api.sarvam.ai',
        getAuthProvider: () => new ApiKeyAuth('test-key'),
        getWebSocketFactory: () => ({
          connect: async () => ({
            send: () => {},
            close: () => {},
            on: () => {},
          }),
        }),
        getClock: () => ({ now: () => 0, sleep: async () => {} }),
      };
    }

    test('appendFileInput and JobsResource handle Uint8Array, Blob, RN file object, and HTTP errors', async () => {
      const fd = new FormData();
      appendFileInput(fd, 'f1', new Uint8Array([1, 2]), 'a.bin');
      appendFileInput(fd, 'f2', new Blob(['hello']), 'b.bin');
      appendFileInput(fd, 'f3', { uri: 'file:///path.wav', name: 'path.wav', type: 'audio/wav' });
      appendFileInput(fd, 'f4', 'fallback' as any);

      const jobs = new JobsResource(
        createTestDispatcher((req) => {
          if (req.url.includes('fail')) return makeMockResponse(400, { message: 'Upload failed' });
          return makeMockResponse(200, {});
        })
      );

      await jobs.uploadToSignedUrl('https://blob.example.com/ok', new Blob(['abc']));
      await jobs.uploadToSignedUrl('https://blob.example.com/ok', { uri: 'file:///a', name: 'a', type: 'audio/wav' });
      await jobs.uploadToSignedUrl('https://blob.example.com/ok', 'raw' as any);
      await assert.rejects(() => jobs.uploadToSignedUrl('https://blob.example.com/fail', new Uint8Array([1])));
    });

    test('TextResource covers idempotencyKey and error responses', async () => {
      const okDisp = createTestDispatcher(() =>
        makeMockResponse(200, {
          translated_text: 't',
          transliterated_text: 'tl',
          detected_language: 'hi-IN',
          confidence: 1,
        })
      );
      const errDisp = createTestDispatcher(() => makeMockResponse(400, { message: 'bad' }));

      const textOk = new TextResource(okDisp);
      await textOk.translate({ input: 'a', target_language_code: 'hi-IN' }, { idempotencyKey: 'k1' });
      await textOk.transliterate({ input: 'a', target_language_code: 'hi-IN' }, { idempotencyKey: 'k2' });
      await textOk.identifyLanguage({ input: 'a' }, { idempotencyKey: 'k3' });

      const textErr = new TextResource(errDisp);
      await assert.rejects(() => textErr.translate({ input: 'a', target_language_code: 'hi-IN' }));
      await assert.rejects(() => textErr.transliterate({ input: 'a', target_language_code: 'hi-IN' }));
      await assert.rejects(() => textErr.identifyLanguage({ input: 'a' }));
    });

    test('ChatResource, ChatSession, and ResponsesResource cover all methods and error paths', async () => {
      const okDisp = createTestDispatcher((req) => {
        if (req.headers['Accept'] === 'text/event-stream') {
          return makeMockResponse(200, 'data: {"id":"1","choices":[{"index":0,"delta":{"content":"ok"}}]}\n\ndata: not-json\n\ndata: [DONE]\n\n');
        }
        return makeMockResponse(200, { id: '1', choices: [], models: [] });
      });

      const chat = new ChatResource(okDisp);
      const session = chat.createSession({ initialAffinity: 'aff-123' });
      assert.equal(session.getSessionAffinity(), 'aff-123');

      await session.completions({ model: 'sarvam-2b', messages: [{ role: 'user', content: 'hi' }] });
      const sessStream = await session.completionsStream({ model: 'sarvam-2b', messages: [{ role: 'user', content: 'hi' }] });
      for await (const _ of sessStream) {
        // consume
      }

      await chat.completions(
        { model: 'sarvam-2b', messages: [{ role: 'user', content: 'hi' }] },
        { idempotencyKey: 'ik' }
      );
      await chat.completionsV2(
        { model: 'sarvam-2b', messages: [{ role: 'user', content: 'hi' }], session_affinity: 's1' },
        { idempotencyKey: 'ik' }
      );
      const s1 = await chat.completionsStream(
        { model: 'sarvam-2b', messages: [{ role: 'user', content: 'hi' }] },
        { idempotencyKey: 'ik' }
      );
      for await (const _ of s1) {}
      const s2 = await chat.completionsV2Stream(
        { model: 'sarvam-2b', messages: [{ role: 'user', content: 'hi' }], session_affinity: 's1' },
        { idempotencyKey: 'ik' }
      );
      for await (const _ of s2) {}
      await chat.getModel('sarvam-2b');

      const responses = new ResponsesResource(okDisp);
      const rStream = await responses.createStream({ model: 'glm-5.3', input: 'hi' }, { idempotencyKey: 'ik' });
      for await (const _ of rStream) {}

      // Error paths
      const errDisp = createTestDispatcher(() => makeMockResponse(400, { message: 'err' }));
      const chatErr = new ChatResource(errDisp);
      await assert.rejects(() => chatErr.completions({ model: 'm', messages: [] }));
      await assert.rejects(() => chatErr.completionsStream({ model: 'm', messages: [] }));
      await assert.rejects(() => chatErr.completionsV2({ model: 'm', messages: [] }));
      await assert.rejects(() => chatErr.completionsV2Stream({ model: 'm', messages: [] }));
      await assert.rejects(() => chatErr.listModels());
      await assert.rejects(() => chatErr.getModel('m'));

      const respErr = new ResponsesResource(errDisp);
      await assert.rejects(() => respErr.createStream({ model: 'm', input: 'x' }));
    });

    test('SpeechToTextResource & SttRealtimeSession cover REST, WS events, and error branches', async () => {
      let wsListeners: Record<string, Function> = {};
      const sentFrames: string[] = [];
      const sttCtx = {
        execute: async (req: HttpRequest) => {
          if (req.headers['x-fail']) return makeMockResponse(400, { message: 'fail' });
          return makeMockResponse(200, { transcript: 'hello' });
        },
        getApiBaseUrl: () => 'https://api.sarvam.ai',
        getWsBaseUrl: () => 'wss://api.sarvam.ai',
        getAuthProvider: () => new TokenAuth(async () => 'tok-123'),
        getWebSocketFactory: () => ({
          connect: async () => ({
            send: (d: string) => sentFrames.push(d),
            close: () => {},
            on: (ev: string, fn: Function) => {
              wsListeners[ev] = fn;
            },
          }),
        }),
      };

      const stt = new SpeechToTextResource(sttCtx as any);
      await stt.transcribe(
        {
          file: new Blob(['audio']),
          model: 'saaras:v3',
          language_code: 'hi-IN',
          prompt: 'p',
          with_diarization: true,
        },
        { idempotencyKey: 'ik' }
      );
      await stt.transcribe({ file: { uri: 'file:///a.wav', name: 'a.wav', type: 'audio/wav' } });
      await assert.rejects(() => stt.transcribe({ file: new Uint8Array([1]) }, { headers: { 'x-fail': '1' } }));

      await stt.translate(
        { file: new Uint8Array([1, 2]), model: 'saaras:v3', prompt: 'p' },
        { idempotencyKey: 'ik' }
      );
      await stt.translate({ file: new Blob(['audio']) });
      await stt.translate({ file: { uri: 'file:///a.wav', name: 'a.wav', type: 'audio/wav' } });
      await assert.rejects(() => stt.translate({ file: new Uint8Array([1]) }, { headers: { 'x-fail': '1' } }));

      const session = await stt.connect({
        languageCode: 'hi-IN',
        model: 'saaras:v3-realtime',
        sampleRate: 16000,
        streamType: 'raw',
        mode: 'transcribe',
        encoding: 'pcm',
        returnTimestamps: true,
        endpointing: true,
        threshold: 0.5,
        prefixPaddingMs: 100,
        silenceDurationMs: 500,
        minSpeechDurationMs: 200,
        prompt: 'ctx',
        keyterms: ['sarvam', 'indic'],
      });

      session.updateConfig({ mode: 'translate', keyterms: ['a'], threshold: 0.6, silenceDurationMs: 400 });
      session.flush();
      session.ping();
      session.end();

      // Emit various WS messages
      wsListeners['message']?.(new TextEncoder().encode(JSON.stringify({ event: 'vad_speech_end', timestamp_ms: 100 })));
      wsListeners['message']?.(JSON.stringify({ event: 'error', code: 'err_1', message: 'bad audio' }));
      wsListeners['message']?.(JSON.stringify({ event: 'custom_event' }));
      wsListeners['message']?.('not-valid-json');
      wsListeners['close']?.(1000, 'Normal');

      const events = [];
      for await (const ev of session.events) {
        events.push(ev);
      }
      assert.equal(events.length, 4);

      // Test abnormal close error on session
      const sessionErr = await stt.connect({ sampleRate: 8000 });
      setTimeout(() => wsListeners['close']?.(1006, 'Abnormal'), 5);
      await assert.rejects(async () => {
        for await (const _ of sessionErr.events) {}
      }, (err: any) => err instanceof RealtimeError);
    });

    test('TextToSpeechResource & TtsStreamingSession cover REST, WS events, and error branches', async () => {
      let wsListeners: Record<string, Function> = {};
      const ttsCtx = {
        execute: async (req: HttpRequest) => {
          if (req.headers['x-fail']) return makeMockResponse(400, { message: 'fail' });
          return makeMockResponse(200, { audios: [{ audio: 'aGVsbG8=' }] });
        },
        getApiBaseUrl: () => 'https://api.sarvam.ai',
        getWsBaseUrl: () => 'wss://api.sarvam.ai',
        getAuthProvider: () => new ProxyAuth('https://bff.example.com', { 'X-Proxy': '1' }),
        getWebSocketFactory: () => ({
          connect: async () => ({
            send: () => {},
            close: () => {},
            on: (ev: string, fn: Function) => {
              wsListeners[ev] = fn;
            },
          }),
        }),
      };

      const tts = new TextToSpeechResource(ttsCtx as any);
      await tts.convert({ text: 'hi', target_language_code: 'hi-IN' }, { idempotencyKey: 'ik' });
      await tts. stream({ text: 'hi', target_language_code: 'hi-IN' }, { idempotencyKey: 'ik' });
      await assert.rejects(() => tts.convert({ text: 'hi', target_language_code: 'hi-IN' }, { headers: { 'x-fail': '1' } }));
      await assert.rejects(() => tts.stream({ text: 'hi', target_language_code: 'hi-IN' }, { headers: { 'x-fail': '1' } }));

      const session = await tts.connect({
        voiceId: 'v1',
        refAudio: 'base64ref',
        speaker: 'meera',
      });
      session.ping();

      wsListeners['message']?.(new TextEncoder().encode(JSON.stringify({ type: 'error', data: { message: 'tts err', code: 'c1' } })));
      wsListeners['message']?.(JSON.stringify({ type: 'other' }));
      wsListeners['message']?.('invalid-json');
      wsListeners['close']?.(1000, 'Normal');

      const events = [];
      for await (const ev of session.events) {
        events.push(ev);
      }
      assert.equal(events.length, 3);

      // Abnormal error event
      const sessionErr = await tts.connect({});
      setTimeout(() => wsListeners['error']?.(new Error('ws error')), 5);
      await assert.rejects(async () => {
        for await (const _ of sessionErr.events) {}
      }, (err: any) => err instanceof RealtimeError);
    });

    test('DocAi, DocumentTranslation, Dubbing, PronunciationDictionary, VoiceCloning, and STT Batch Jobs cover all methods', async () => {
      const okDisp = createTestDispatcher((req) => {
        if (req.headers['x-fail']) return makeMockResponse(400, { message: 'fail' });
        return makeMockResponse(200, {
          job_id: 'j1',
          status: 'COMPLETED',
          audio: 'aGVsbG8=',
          voices: [],
        });
      });

      // DocAi
      const docAi = new DocAiResource(okDisp);
      await docAi.digitise({ file: new Uint8Array([1]), language_code: 'hi-IN', page_count: 2 }, { idempotencyKey: 'ik' });
      await docAi.extract({ file: new Uint8Array([1]), schema: '{"a":"string"}', language_code: 'hi-IN', extra: true }, { idempotencyKey: 'ik' });
      await docAi.createUploadUrl({ file_name: 'a.pdf' }, { idempotencyKey: 'ik' });
      await docAi.getDownloadUrl('j1');
      await docAi.extractAndWait({ file: new Uint8Array([1]), schema: {} });

      await assert.rejects(() => docAi.digitise({}, { headers: { 'x-fail': '1' } }));
      await assert.rejects(() => docAi.extract({ schema: {} }, { headers: { 'x-fail': '1' } }));
      await assert.rejects(() => docAi.createUploadUrl({}, { headers: { 'x-fail': '1' } }));
      await assert.rejects(() => docAi.getStatus('j1', { headers: { 'x-fail': '1' } }));
      await assert.rejects(() => docAi.getResults('j1', { headers: { 'x-fail': '1' } }));
      await assert.rejects(() => docAi.getDownloadUrl('j1', { headers: { 'x-fail': '1' } }));

      // DocumentTranslation
      const docTrans = new DocumentTranslationResource(okDisp);
      await docTrans.create({ target_lang: 'hi-IN' }, { idempotencyKey: 'ik' });
      await docTrans.start('j1');
      await docTrans.getLiveStatus('j1');
      await docTrans.triggerExport('j1', { format: 'pdf' });
      await docTrans.getExportStatus('j1');
      await docTrans.waitUntilComplete('j1');

      await assert.rejects(() => docTrans.create({}, { headers: { 'x-fail': '1' } }));
      await assert.rejects(() => docTrans.start('j1', { headers: { 'x-fail': '1' } }));
      await assert.rejects(() => docTrans.getLiveStatus('j1', { headers: { 'x-fail': '1' } }));
      await assert.rejects(() => docTrans.triggerExport('j1', {}, { headers: { 'x-fail': '1' } }));
      await assert.rejects(() => docTrans.getExportStatus('j1', { headers: { 'x-fail': '1' } }));

      // Dubbing error branches
      const dubbing = new DubbingResource(okDisp);
      await dubbing.create({ src_lang: 'en-IN', target_langs: ['hi-IN'] }, { idempotencyKey: 'ik' });
      await assert.rejects(() => dubbing.create({}, { headers: { 'x-fail': '1' } }));
      await assert.rejects(() => dubbing.start('j1', { headers: { 'x-fail': '1' } }));
      await assert.rejects(() => dubbing.getLiveStatus('j1', { headers: { 'x-fail': '1' } }));
      await assert.rejects(() => dubbing.getExportStatus('j1', { headers: { 'x-fail': '1' } }));

      // PronunciationDictionary
      const dict = new PronunciationDictionaryResource(okDisp);
      await dict.list();
      await dict.create({ file: new Uint8Array([1]), language_code: 'hi-IN' }, { idempotencyKey: 'ik' });
      await dict.update('d1', { file: new Uint8Array([1]) }, { idempotencyKey: 'ik' });
      await dict.get('d1');
      await dict.delete('d1');

      await assert.rejects(() => dict.list({ headers: { 'x-fail': '1' } }));
      await assert.rejects(() => dict.create({ file: new Uint8Array([1]) }, { headers: { 'x-fail': '1' } }));
      await assert.rejects(() => dict.update('d1', { file: new Uint8Array([1]) }, { headers: { 'x-fail': '1' } }));
      await assert.rejects(() => dict.get('d1', { headers: { 'x-fail': '1' } }));
      await assert.rejects(() => dict.delete('d1', { headers: { 'x-fail': '1' } }));

      // VoiceCloning
      const vc = new VoiceCloningResource(okDisp);
      await vc.createVoice({ file: new Uint8Array([1]), name: 'v', reference_text: 'ref' }, { idempotencyKey: 'ik' });
      await vc.convert(
        {
          text: 'hello',
          voice_id: 'v1',
          ref_audio: new Uint8Array([1]),
          target_language_code: 'hi-IN',
          speaker: 'meera',
          model: 'bulbul:v3',
          speech_sample_rate: 22050,
          output_audio_codec: 'mp3',
          pace: 1.0,
          pitch: 0,
          loudness: 1.0,
          temperature: 0.5,
          enable_preprocessing: true,
        },
        { idempotencyKey: 'ik' }
      );
      const vcStream = await vc.stream(
        {
          text: 'hello',
          voice_id: 'v1',
          ref_audio: new Uint8Array([1]),
          target_language_code: 'hi-IN',
          speaker: 'meera',
          model: 'bulbul:v3',
          speech_sample_rate: 22050,
          output_audio_codec: 'mp3',
          pace: 1.0,
          pitch: 0,
          loudness: 1.0,
          temperature: 0.5,
          enable_preprocessing: true,
        },
        { idempotencyKey: 'ik' }
      );
      for await (const _ of vcStream) {}

      await assert.rejects(() => vc.listVoices({ headers: { 'x-fail': '1' } }));
      await assert.rejects(() => vc.createVoice({ file: new Uint8Array([1]) }, { headers: { 'x-fail': '1' } }));
      await assert.rejects(() => vc.getVoice('v1', { headers: { 'x-fail': '1' } }));
      await assert.rejects(() => vc.deleteVoice('v1', { headers: { 'x-fail': '1' } }));
      await assert.rejects(() => vc.convert({ text: 'hi' }, { headers: { 'x-fail': '1' } }));
      await assert.rejects(() => vc.stream({ text: 'hi' }, { headers: { 'x-fail': '1' } }));

      // STT Batch Jobs (both SpeechToTextJobResource & SpeechToTextTranslateJobResource)
      const sttJob = new SpeechToTextJobResource(okDisp);
      await sttJob.initialise({}, { idempotencyKey: 'ik' });
      await sttJob.getUploadLinks({ job_id: 'j1' });
      await sttJob.start('j1');
      await sttJob.getStatus('j1');
      await sttJob.getDownloadLinks({ job_id: 'j1' });
      await assert.rejects(() => sttJob.initialise({}, { headers: { 'x-fail': '1' } }));
      await assert.rejects(() => sttJob.getUploadLinks({}, { headers: { 'x-fail': '1' } }));
      await assert.rejects(() => sttJob.start('j1', { headers: { 'x-fail': '1' } }));
      await assert.rejects(() => sttJob.getStatus('j1', { headers: { 'x-fail': '1' } }));
      await assert.rejects(() => sttJob.getDownloadLinks({}, { headers: { 'x-fail': '1' } }));

      const sttTransJob = new SpeechToTextTranslateJobResource(okDisp);
      await sttTransJob.initialise({}, { idempotencyKey: 'ik' });
      await sttTransJob.getUploadLinks({ job_id: 'j1' });
      await sttTransJob.start('j1');
      await sttTransJob.getStatus('j1');
      await sttTransJob.getDownloadLinks({ job_id: 'j1' });
      await sttTransJob.waitUntilComplete('j1');
      await assert.rejects(() => sttTransJob.initialise({}, { headers: { 'x-fail': '1' } }));
      await assert.rejects(() => sttTransJob.getUploadLinks({}, { headers: { 'x-fail': '1' } }));
      await assert.rejects(() => sttTransJob.start('j1', { headers: { 'x-fail': '1' } }));
      await assert.rejects(() => sttTransJob.getStatus('j1', { headers: { 'x-fail': '1' } }));
      await assert.rejects(() => sttTransJob.getDownloadLinks({}, { headers: { 'x-fail': '1' } }));
    });
  });
});
