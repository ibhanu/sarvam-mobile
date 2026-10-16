import { test, describe, before, after, beforeEach } from 'node:test';
import assert from 'node:assert/strict';
import * as fs from 'node:fs';
import * as path from 'node:path';
import { fileURLToPath } from 'node:url';
import WebSocket from 'ws';
import { createMockServer, MockServerInstance } from '../src/server.js';
import { buildConformanceBundle, outputFile } from '../src/bundle-cases.js';

const __filename = fileURLToPath(import.meta.url);
const __dirname = path.dirname(__filename);

describe('Sarvam Conformance Mock Server & Cases', () => {
  let server: MockServerInstance;

  before(async () => {
    // Start server on dynamic port (port: 0)
    server = createMockServer({ port: 0 });
    await server.start();
    assert.ok(server.port > 0, `Expected server port > 0, got ${server.port}`);
  });

  after(async () => {
    await server.stop();
  });

  beforeEach(() => {
    server.resetState();
  });

  describe('1. Conformance Cases Bundle', () => {
    test('builds and validates all-cases.json from YAML cases', () => {
      const bundle = buildConformanceBundle();
      assert.ok(bundle.totalCases >= 15, `Expected >= 15 cases, got ${bundle.totalCases}`);
      assert.ok(bundle.categories.rest >= 10, 'Expected at least 10 REST cases');
      assert.ok(bundle.categories.sse >= 2, 'Expected at least 2 SSE cases');
      assert.ok(bundle.categories.ws >= 3, 'Expected at least 3 WS cases');

      const bundlePath = outputFile;
      assert.ok(fs.existsSync(bundlePath), 'all-cases.json must exist');
      const loaded = JSON.parse(fs.readFileSync(bundlePath, 'utf8'));
      assert.equal(loaded.totalCases, bundle.totalCases);
    });
  });

  describe('2. REST Endpoints (Happy Paths & Decoding)', () => {
    test('POST /translate returns 200 with translated_text', async () => {
      const res = await fetch(`${server.url}/translate`, {
        method: 'POST',
        headers: {
          'api-subscription-key': 'test-api-key',
          'content-type': 'application/json',
        },
        body: JSON.stringify({
          input: 'Hello world',
          source_language_code: 'en-IN',
          target_language_code: 'hi-IN',
          speaker_gender: 'Male',
          mode: 'formal',
          model: 'mayura:v1',
        }),
      });

      assert.equal(res.status, 200);
      const json = await res.json() as any;
      assert.equal(json.translated_text, 'नमस्ते दुनिया');

      const recorded = server.getRecordedRequests('/translate');
      assert.equal(recorded.length, 1);
      assert.equal(recorded[0].headers['api-subscription-key'], 'test-api-key');
    });

    test('POST /transliterate returns 200 with transliterated_text', async () => {
      const res = await fetch(`${server.url}/transliterate`, {
        method: 'POST',
        headers: {
          'api-subscription-key': 'test-api-key',
          'content-type': 'application/json',
        },
        body: JSON.stringify({
          input: 'namaste',
          source_language_code: 'en-IN',
          target_language_code: 'hi-IN',
        }),
      });

      assert.equal(res.status, 200);
      const json = await res.json() as any;
      assert.equal(json.transliterated_text, 'नमस्ते');
    });

    test('POST /text-lid returns 200 with detected_language', async () => {
      const res = await fetch(`${server.url}/text-lid`, {
        method: 'POST',
        headers: {
          'api-subscription-key': 'test-api-key',
          'content-type': 'application/json',
        },
        body: JSON.stringify({
          input: 'नमस्ते दुनिया',
        }),
      });

      assert.equal(res.status, 200);
      const json = await res.json() as any;
      assert.equal(json.detected_language, 'hi-IN');
      assert.equal(json.confidence, 0.99);
    });

    test('POST /text-to-speech returns base64 and decodes to valid WAV bytes', async () => {
      const res = await fetch(`${server.url}/text-to-speech`, {
        method: 'POST',
        headers: {
          'api-subscription-key': 'test-api-key',
          'content-type': 'application/json',
          'x-mock-scenario': 'tts-rest-base64',
        },
        body: JSON.stringify({
          text: 'नमस्ते',
          target_language_code: 'hi-IN',
          speaker: 'meera',
        }),
      });

      assert.equal(res.status, 200);
      const json = await res.json() as any;
      assert.ok(Array.isArray(json.audios));
      assert.equal(json.audios.length, 1);

      const base64Audio = json.audios[0].audio;
      const buffer = Buffer.from(base64Audio, 'base64');
      assert.equal(buffer.length, 44, 'Expected standard 44-byte WAV header');
      assert.equal(buffer.subarray(0, 4).toString('ascii'), 'RIFF');
      assert.equal(buffer.subarray(8, 12).toString('ascii'), 'WAVE');
    });

    test('POST /text-to-speech/stream returns 3 binary chunks concatenating to 48 bytes', async () => {
      const res = await fetch(`${server.url}/text-to-speech/stream`, {
        method: 'POST',
        headers: {
          'api-subscription-key': 'test-api-key',
          'content-type': 'application/json',
        },
        body: JSON.stringify({
          text: 'नमस्ते भारत',
        }),
      });

      assert.equal(res.status, 200);
      assert.equal(res.headers.get('content-type'), 'application/octet-stream');

      const arrayBuffer = await res.arrayBuffer();
      const fullBuffer = Buffer.from(arrayBuffer);
      assert.equal(fullBuffer.length, 48, 'Expected exactly 48 bytes across 3 chunks');

      // Verify chunk 1 header (0x01, 0x02, ...)
      assert.equal(fullBuffer[0], 0x01);
      assert.equal(fullBuffer[15], 0x10);
      // Chunk 2 (0x11, ...)
      assert.equal(fullBuffer[16], 0x11);
      assert.equal(fullBuffer[31], 0x20);
      // Chunk 3 (0x21, ...)
      assert.equal(fullBuffer[32], 0x21);
      assert.equal(fullBuffer[47], 0x30);
    });
  });

  describe('3. Auth Error Quirk & Permission Denied', () => {
    test('Auth Error Quirk: HTTP 403 with invalid_api_key_error', async () => {
      const res = await fetch(`${server.url}/translate`, {
        method: 'POST',
        headers: {
          'x-mock-scenario': 'auth-invalid-api-key',
        },
      });

      assert.equal(res.status, 403);
      const json = await res.json() as any;
      assert.equal(json.error.code, 'invalid_api_key_error');
      assert.equal(json.error.message, 'Invalid API key');
      assert.equal(json.error.request_id, 'req_auth_403');
    });

    test('Permission Denied: HTTP 403 with authentication_error', async () => {
      const res = await fetch(`${server.url}/translate`, {
        method: 'POST',
        headers: {
          'x-mock-scenario': 'auth-permission-denied',
        },
      });

      assert.equal(res.status, 403);
      const json = await res.json() as any;
      assert.equal(json.error.code, 'authentication_error');
      assert.equal(json.error.message, 'Tier locked');
      assert.equal(json.error.request_id, 'req_perm_403');
    });

    test('TokenAuth Invalidation & Retry: 403 on expired token, 200 on refreshed token', async () => {
      // Attempt 1: expired token
      const res1 = await fetch(`${server.url}/translate`, {
        method: 'POST',
        headers: {
          Authorization: 'Bearer expired-token',
          'x-mock-scenario': 'token-auth-refresh',
        },
      });
      assert.equal(res1.status, 403);
      const errJson = await res1.json() as any;
      assert.equal(errJson.error.code, 'invalid_api_key_error');

      // Attempt 2: refreshed token
      const res2 = await fetch(`${server.url}/translate`, {
        method: 'POST',
        headers: {
          Authorization: 'Bearer refreshed-token',
          'x-mock-scenario': 'token-auth-refresh',
        },
      });
      assert.equal(res2.status, 200);
      const okJson = await res2.json() as any;
      assert.equal(okJson.translated_text, 'नमस्ते दुनिया');
    });
  });

  describe('4. Resiliency, Rate Limits & Job Creation Safety', () => {
    test('Rate Limit Retry: 429 on attempt 1 with retry-after-ms, 200 on attempt 2', async () => {
      // Attempt 1
      const res1 = await fetch(`${server.url}/translate`, {
        method: 'POST',
        headers: {
          'x-mock-scenario': 'rate-limit-retry',
        },
      });
      assert.equal(res1.status, 429);
      assert.equal(res1.headers.get('retry-after-ms'), '50');
      const json1 = await res1.json() as any;
      assert.equal(json1.error.code, 'rate_limit_exceeded_error');

      // Attempt 2
      const res2 = await fetch(`${server.url}/translate`, {
        method: 'POST',
        headers: {
          'x-mock-scenario': 'rate-limit-retry',
        },
      });
      assert.equal(res2.status, 200);
      const json2 = await res2.json() as any;
      assert.equal(json2.translated_text, 'नमस्ते पुनः प्रयास');
    });

    test('Job Creation Safety: docAi.digitise returns 500 without retrying', async () => {
      const res = await fetch(`${server.url}/doc-ai/v1/job/digitise`, {
        method: 'POST',
        headers: {
          'x-mock-scenario': 'job-create-500',
        },
      });
      assert.equal(res.status, 500);
      const json = await res.json() as any;
      assert.equal(json.error.code, 'internal_server_error');
      assert.equal(json.error.request_id, 'req_job_500');
    });

    test('Idempotent GET /v2/models retries on 500 and succeeds on attempt 2', async () => {
      const res1 = await fetch(`${server.url}/v2/models`, {
        headers: { 'x-mock-scenario': 'server-error-retry' },
      });
      assert.equal(res1.status, 500);

      const res2 = await fetch(`${server.url}/v2/models`, {
        headers: { 'x-mock-scenario': 'server-error-retry' },
      });
      assert.equal(res2.status, 200);
      const json2 = await res2.json() as any;
      assert.equal(json2.models.length, 2);
    });
  });

  describe('5. Azure SAS Blob Upload Header Validation', () => {
    test('PUT /mock-sas-upload returns 400 if x-ms-blob-type is missing', async () => {
      const res = await fetch(`${server.url}/mock-sas-upload`, {
        method: 'PUT',
        headers: {
          'content-type': 'application/octet-stream',
        },
        body: 'binary-payload',
      });
      assert.equal(res.status, 400);
      const json = await res.json() as any;
      assert.equal(json.error.code, 'MissingRequiredHeader');
    });

    test('PUT /mock-sas-upload returns 201 if x-ms-blob-type: BlockBlob is present', async () => {
      const res = await fetch(`${server.url}/mock-sas-upload`, {
        method: 'PUT',
        headers: {
          'x-ms-blob-type': 'BlockBlob',
          'content-type': 'application/octet-stream',
        },
        body: 'binary-payload',
      });
      assert.equal(res.status, 201);
      assert.equal(res.headers.get('x-ms-request-id'), 'mock-azure-req-1');
    });
  });

  describe('6. Server-Sent Events (SSE) Streams', () => {
    test('Chat V2 SSE Stream handles choices: [] usage chunk and terminates on [DONE]', async () => {
      const res = await fetch(`${server.url}/v2/chat/completions`, {
        method: 'POST',
        headers: {
          'content-type': 'application/json',
          'x-mock-scenario': 'chat-v2-sse-empty-choices',
        },
        body: JSON.stringify({
          model: 'sarvam-2b',
          stream: true,
          messages: [{ role: 'user', content: 'Hello' }],
        }),
      });

      assert.equal(res.status, 200);
      assert.equal(res.headers.get('content-type'), 'text/event-stream');

      const text = await res.text();
      assert.ok(text.includes('Namaste'), 'Contains first delta');
      assert.ok(text.includes('world'), 'Contains second delta');
      assert.ok(text.includes('"choices":[]'), 'Contains usage chunk with empty choices');
      assert.ok(text.includes('data: [DONE]'), 'Terminates on [DONE]');
    });

    test('Responses API SSE Stream terminates on event: response.completed without [DONE]', async () => {
      const res = await fetch(`${server.url}/v2/responses`, {
        method: 'POST',
        headers: {
          'content-type': 'application/json',
          'x-mock-scenario': 'responses-sse-no-done',
        },
        body: JSON.stringify({
          model: 'glm-5.3',
          input: 'Explain something',
        }),
      });

      assert.equal(res.status, 200);
      assert.equal(res.headers.get('content-type'), 'text/event-stream');

      const text = await res.text();
      assert.ok(text.includes('event: response.created'));
      assert.ok(text.includes('event: response.output_item.added'));
      assert.ok(text.includes('event: response.content_part.added'));
      assert.ok(text.includes('event: response.completed'));
      assert.ok(!text.includes('[DONE]'), 'Must NOT contain [DONE]');
    });
  });

  describe('7. WebSockets (Realtime STT & Streaming TTS)', () => {
    test('WebSocket STT Realtime with Api-Subscription-Key header', async () => {
      const wsUrl = `${server.wsUrl}/speech-to-text-realtime/ws?language_code=hi-IN&sample_rate=16000`;
      const ws = new WebSocket(wsUrl, {
        headers: {
          'Api-Subscription-Key': 'test-api-key',
        },
      });

      const receivedEvents: any[] = [];

      await new Promise<void>((resolve, reject) => {
        ws.on('open', () => {
          ws.send(JSON.stringify({ event: 'audio_input', audio: 'AAAA' }));
          setTimeout(() => {
            ws.send(JSON.stringify({ event: 'end' }));
          }, 30);
        });

        ws.on('message', (data) => {
          const msg = JSON.parse(data.toString());
          receivedEvents.push(msg);
          if (msg.event === 'session_end') {
            ws.close();
            resolve();
          }
        });

        ws.on('error', reject);
      });

      const eventNames = receivedEvents.map((e) => e.event);
      assert.deepEqual(eventNames, [
        'session_begin',
        'vad_speech_start',
        'transcript_partial',
        'transcript_final',
        'session_end',
      ]);
    });

    test('WebSocket STT Realtime with Subprotocol Authentication', async () => {
      const subprotocol = 'api-subscription-key.test-subprotocol-key';
      const wsUrl = `${server.wsUrl}/speech-to-text-realtime/ws?language_code=hi-IN`;
      const ws = new WebSocket(wsUrl, subprotocol);

      const receivedEvents: any[] = [];

      await new Promise<void>((resolve, reject) => {
        ws.on('open', () => {
          ws.send(JSON.stringify({ event: 'audio_input', audio: 'AAAA' }));
          ws.send(JSON.stringify({ event: 'flush' }));
        });

        ws.on('message', (data) => {
          const msg = JSON.parse(data.toString());
          receivedEvents.push(msg);
          if (msg.event === 'session_end') {
            ws.close();
            resolve();
          }
        });

        ws.on('error', reject);
      });

      assert.ok(receivedEvents.some((e) => e.event === 'session_begin'));
      assert.ok(receivedEvents.some((e) => e.event === 'transcript_final'));
    });

    test('WebSocket STT Realtime rejects invalid sample_rate with code 4000', async () => {
      const wsUrl = `${server.wsUrl}/speech-to-text-realtime/ws?sample_rate=44100`;
      const ws = new WebSocket(wsUrl);

      const closeCode = await new Promise<number>((resolve) => {
        ws.on('close', (code) => {
          resolve(code);
        });
        ws.on('error', () => {
          // ignore expected error on close
        });
      });

      assert.equal(closeCode, 4000, 'Expected close code 4000 for invalid sample_rate');
    });

    test('WebSocket TTS Streaming: config -> text -> flush -> 2 audio frames + final event', async () => {
      const wsUrl = `${server.wsUrl}/text-to-speech/ws?model=bulbul:v4-flash`;
      const ws = new WebSocket(wsUrl);

      const receivedFrames: any[] = [];

      await new Promise<void>((resolve, reject) => {
        ws.on('open', () => {
          // Frame 1: config
          ws.send(
            JSON.stringify({
              type: 'config',
              data: {
                language_code: 'hi-IN',
                speaker: 'simran_en_customer',
                model: 'bulbul:v4-flash',
              },
            }),
          );

          // Frame 2: text
          ws.send(
            JSON.stringify({
              type: 'text',
              data: {
                text: 'नमस्ते भारत',
              },
            }),
          );

          // Frame 3: flush
          ws.send(JSON.stringify({ type: 'flush' }));
        });

        ws.on('message', (data) => {
          const frame = JSON.parse(data.toString());
          receivedFrames.push(frame);
          if (frame.type === 'event' && frame.data?.event === 'final') {
            ws.close();
            resolve();
          }
        });

        ws.on('error', reject);
      });

      assert.equal(receivedFrames.length, 3);
      assert.equal(receivedFrames[0].type, 'audio');
      assert.ok(receivedFrames[0].data?.audio);
      assert.equal(receivedFrames[1].type, 'audio');
      assert.ok(receivedFrames[1].data?.audio);
      assert.equal(receivedFrames[2].type, 'event');
      assert.equal(receivedFrames[2].data?.event, 'final');
    });
  });
});
