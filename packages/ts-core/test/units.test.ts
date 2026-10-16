import { test, describe } from 'node:test';
import assert from 'node:assert/strict';
import {
  base64ToBytes,
  bytesToBase64,
  hexToBytes,
  bytesToHex,
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
  StreamError,
  RealtimeError,
  DecodingError,
  isAbortError,
  parseRetryAfterHeader,
  createHttpError,
  parseSseStream,
  ChatCompletionChunk,
} from '../dist/esm/index.js';

describe('@sarvam/core Unit Tests', () => {
  describe('1. Pure Base64 & Hex Utilities', () => {
    test('encodes and decodes empty buffer', () => {
      const bytes = new Uint8Array(0);
      const b64 = bytesToBase64(bytes);
      assert.equal(b64, '');
      const decoded = base64ToBytes(b64);
      assert.equal(decoded.length, 0);
    });

    test('encodes and decodes 1, 2, and 3 byte sequences with correct padding', () => {
      // 1 byte -> 4 chars with '=='
      const b1 = new Uint8Array([0x41]); // 'A'
      const b64_1 = bytesToBase64(b1);
      assert.equal(b64_1, 'QQ==');
      assert.deepEqual(base64ToBytes(b64_1), b1);

      // 2 bytes -> 4 chars with '='
      const b2 = new Uint8Array([0x41, 0x42]); // 'AB'
      const b64_2 = bytesToBase64(b2);
      assert.equal(b64_2, 'QUI=');
      assert.deepEqual(base64ToBytes(b64_2), b2);

      // 3 bytes -> 4 chars without padding
      const b3 = new Uint8Array([0x41, 0x42, 0x43]); // 'ABC'
      const b64_3 = bytesToBase64(b3);
      assert.equal(b64_3, 'QUJD');
      assert.deepEqual(base64ToBytes(b64_3), b3);
    });

    test('decodes standard WAV sample base64', () => {
      const wavB64 = 'UklGRiQAAABXQVZFZm10IBAAAAABAAEAQB8AAEAfAAABAAgAZGF0YQAAAAA=';
      const bytes = base64ToBytes(wavB64);
      assert.equal(bytes.length, 44);
      assert.equal(bytesToBase64(bytes), wavB64);

      // Magic bytes: RIFF (0x52494646) and WAVE (0x57415645)
      const hex = bytesToHex(bytes.slice(0, 4));
      assert.equal(hex, '52494646');
      const waveHex = bytesToHex(bytes.slice(8, 12));
      assert.equal(waveHex, '57415645');
    });

    test('hex conversions roundtrip', () => {
      const hex = '0102030405060708090a0b0c0d0e0f10';
      const bytes = hexToBytes(hex);
      assert.equal(bytes.length, 16);
      assert.equal(bytesToHex(bytes), hex);
    });
  });

  describe('2. SarvamEnvironment', () => {
    test('production environment defaults match specification', () => {
      assert.equal(SarvamEnvironment.production.apiBaseUrl, 'https://api.sarvam.ai');
      assert.equal(SarvamEnvironment.production.dubbingBaseUrl, 'https://api.sarvam.ai/dubbing');
      assert.equal(SarvamEnvironment.production.wsBaseUrl, 'wss://api.sarvam.ai');
    });

    test('proxy factory derives correct base URLs for BFF deployment', () => {
      const env = SarvamEnvironment.proxy('https://api.myapp.com/sarvam');
      assert.equal(env.apiBaseUrl, 'https://api.myapp.com/sarvam');
      assert.equal(env.dubbingBaseUrl, 'https://api.myapp.com/sarvam/dubbing');
      assert.equal(env.wsBaseUrl, 'wss://api.myapp.com/sarvam');
    });

    test('custom factory trims trailing slashes and handles http->ws conversion', () => {
      const env = SarvamEnvironment.custom({
        apiBaseUrl: 'http://localhost:8080/api/',
      });
      assert.equal(env.apiBaseUrl, 'http://localhost:8080/api');
      assert.equal(env.dubbingBaseUrl, 'http://localhost:8080/api/dubbing');
      assert.equal(env.wsBaseUrl, 'ws://localhost:8080/api');
    });
  });

  describe('3. AuthProvider & TokenAuth', () => {
    test('ApiKeyAuth returns subscriptionKey credentials', async () => {
      const auth = new ApiKeyAuth('my-test-key');
      const creds = await auth.getCredentials();
      assert.equal(creds.kind, 'subscriptionKey');
      if (creds.kind === 'subscriptionKey') {
        assert.equal(creds.key, 'my-test-key');
      }
    });

    test('TokenAuth single-flight deduplication shares in-flight promise', async () => {
      let fetchCalls = 0;
      const auth = new TokenAuth(async () => {
        fetchCalls++;
        await new Promise((r) => setTimeout(r, 20));
        return {
          token: `token-${fetchCalls}`,
          expiresAtEpochMs: Date.now() + 300_000, // 5 min
        };
      });

      // Fire 5 concurrent getCredentials calls
      const results = await Promise.all([
        auth.getCredentials(),
        auth.getCredentials(),
        auth.getCredentials(),
        auth.getCredentials(),
        auth.getCredentials(),
      ]);

      assert.equal(fetchCalls, 1, 'Only 1 fetch call should be executed due to single-flight deduplication');
      for (const res of results) {
        assert.equal(res.kind, 'bearerToken');
        if (res.kind === 'bearerToken') {
          assert.equal(res.token, 'token-1');
        }
      }
    });

    test('TokenAuth proactively refreshes when within 60s buffer', async () => {
      let callCount = 0;
      const auth = new TokenAuth(async () => {
        callCount++;
        return {
          token: `token-${callCount}`,
          // First token expires in 30s (which is < 60s buffer, so considered expired)
          expiresAtEpochMs: callCount === 1 ? Date.now() + 30_000 : Date.now() + 600_000,
        };
      });

      const cred1 = await auth.getCredentials();
      if (cred1.kind === 'bearerToken') {
        assert.equal(cred1.token, 'token-1');
      }

      // Next call sees it within buffer and refreshes
      const cred2 = await auth.getCredentials();
      assert.equal(callCount, 2);
      if (cred2.kind === 'bearerToken') {
        assert.equal(cred2.token, 'token-2');
      }
    });

    test('TokenAuth invalidate clears cache and forces fresh fetch', async () => {
      let callCount = 0;
      const auth = new TokenAuth(async () => {
        callCount++;
        return {
          token: `token-${callCount}`,
          expiresAtEpochMs: Date.now() + 600_000,
        };
      });

      await auth.getCredentials();
      assert.equal(callCount, 1);

      // Calling invalidate
      auth.invalidate();

      const cred = await auth.getCredentials();
      assert.equal(callCount, 2);
      if (cred.kind === 'bearerToken') {
        assert.equal(cred.token, 'token-2');
      }
    });
  });

  describe('4. Canonical SarvamError Hierarchy', () => {
    test('all error subclasses inherit from SarvamError and Error', () => {
      const errs: SarvamError[] = [
        new AuthenticationError('auth'),
        new PermissionDeniedError('perm'),
        new BadRequestError('bad'),
        new NotFoundError('not found'),
        new PayloadTooLargeError('large'),
        new UnprocessableEntityError('unproc'),
        new RateLimitError('rate', { retryAfterMs: 100 }),
        new ServerError('server'),
        new ConnectionError('conn'),
        new TimeoutError('timeout', { phase: 'read' }),
        new StreamError('stream'),
        new RealtimeError('realtime', { closeCode: 4000 }),
        new DecodingError('decode'),
      ];

      for (const err of errs) {
        assert.ok(err instanceof SarvamError);
        assert.ok(err instanceof Error);
        assert.equal(err.name, err.constructor.name);
      }
    });

    test('RateLimitError exposes retryAfterMs', () => {
      const err = new RateLimitError('slow down', { retryAfterMs: 1500 });
      assert.equal(err.retryAfterMs, 1500);
    });

    test('TimeoutError exposes phase', () => {
      const err = new TimeoutError('timed out', { phase: 'connect' });
      assert.equal(err.phase, 'connect');
    });

    test('isAbortError identifies DOMException / AbortError', () => {
      const abort = new DOMException('aborted', 'AbortError');
      assert.equal(isAbortError(abort), true);
      assert.equal(isAbortError(new Error('regular')), false);
      assert.equal(isAbortError(new AuthenticationError('auth')), false);
    });

    test('createHttpError correctly maps HTTP 403 invalid_api_key_error vs authentication_error', async () => {
      // invalid_api_key_error -> AuthenticationError
      const authErr = await createHttpError(
        403,
        JSON.stringify({ error: { code: 'invalid_api_key_error', message: 'Invalid key' } }),
        () => null
      );
      assert.ok(authErr instanceof AuthenticationError);
      assert.equal(authErr.statusCode, 403);
      assert.equal(authErr.code, 'invalid_api_key_error');

      // other code -> PermissionDeniedError
      const permErr = await createHttpError(
        403,
        JSON.stringify({ error: { code: 'authentication_error', message: 'Tier locked' } }),
        () => null
      );
      assert.ok(permErr instanceof PermissionDeniedError);
      assert.equal(permErr.statusCode, 403);
      assert.equal(permErr.code, 'authentication_error');
    });

    test('parseRetryAfterHeader respects precedence', () => {
      // 1. retry-after-ms takes highest priority
      const delay1 = parseRetryAfterHeader((n) => {
        if (n === 'retry-after-ms') return '250';
        if (n === 'retry-after') return '5';
        return null;
      });
      assert.equal(delay1, 250);

      // 2. Retry-After seconds
      const delay2 = parseRetryAfterHeader((n) => {
        if (n === 'retry-after') return '3';
        return null;
      });
      assert.equal(delay2, 3000);
    });
  });

  describe('5. ChatCompletionChunk firstDeltaContent guard', () => {
    test('returns first delta content when choices is present', () => {
      const chunk = new ChatCompletionChunk({
        id: '1',
        choices: [{ index: 0, delta: { content: 'hello' } }],
      });
      assert.equal(chunk.firstDeltaContent, 'hello');
    });

    test('returns null safely when choices is empty array (e.g. usage chunk)', () => {
      const chunk = new ChatCompletionChunk({
        id: '1',
        choices: [],
        usage: { prompt_tokens: 5, completion_tokens: 2, total_tokens: 7 },
      });
      assert.equal(chunk.firstDeltaContent, null);
      assert.equal(chunk.usage?.total_tokens, 7);
    });
  });

  describe('6. SSE Parser', () => {
    test('parses chat SSE stream and cleanly terminates on [DONE]', async () => {
      const textChunks = [
        'data: {"id":"1","choices":[{"index":0,"delta":{"content":"Hi"}}]}\n\n',
        'data: {"id":"1","choices":[{"index":0,"delta":{"content":" there"}}]}\n\n',
        'data: [DONE]\n\n',
      ];

      async function* generateStream() {
        for (const t of textChunks) {
          yield new TextEncoder().encode(t);
        }
      }

      const events = [];
      for await (const ev of parseSseStream(generateStream())) {
        events.push(ev);
      }

      assert.equal(events.length, 2);
      assert.equal(JSON.parse(events[0]!.data).choices[0].delta.content, 'Hi');
      assert.equal(JSON.parse(events[1]!.data).choices[0].delta.content, ' there');
    });

    test('parses responses API SSE stream and terminates on response.completed without [DONE]', async () => {
      const payload =
        'event: response.created\ndata: {"id":"r1","type":"response.created"}\n\n' +
        'event: response.completed\ndata: {"id":"r1","type":"response.completed"}\n\n' +
        'event: response.never_reached\ndata: {}\n\n';

      async function* generateStream() {
        yield new TextEncoder().encode(payload);
      }

      const events = [];
      for await (const ev of parseSseStream(generateStream(), { isResponsesApi: true })) {
        events.push(ev);
      }

      assert.equal(events.length, 2);
      assert.equal(events[0]!.event, 'response.created');
      assert.equal(events[1]!.event, 'response.completed');
    });
  });
});
