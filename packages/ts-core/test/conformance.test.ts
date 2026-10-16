import { test, describe, before, after, beforeEach } from 'node:test';
import assert from 'node:assert/strict';
import { createMockServer } from '../../../conformance/mock-server/dist/src/server.js';
type MockServerInstance = ReturnType<typeof createMockServer>;
import WebSocket from '../../../conformance/mock-server/node_modules/ws/index.js';
import {
  SarvamClient,
  SarvamEnvironment,
  ApiKeyAuth,
  TokenAuth,
  AuthenticationError,
  PermissionDeniedError,
  ServerError,
  BadRequestError,
  DefaultWebSocketFactory,
  bytesToHex,
} from '../dist/esm/index.js';

describe('Sarvam Mobile SDK Conformance Suite (all 19 cases)', () => {
  let server: MockServerInstance;
  let wsFactory: DefaultWebSocketFactory;

  before(async () => {
    server = createMockServer({ port: 0 });
    await server.start();
    wsFactory = new DefaultWebSocketFactory(WebSocket);
  });

  after(async () => {
    await server.stop();
  });

  beforeEach(() => {
    server.resetState();
  });

  function createClient(options?: {
    apiKey?: string;
    authProvider?: any;
    maxRetries?: number;
  }): SarvamClient {
    return new SarvamClient({
      apiKey: options?.apiKey ?? 'test-api-key',
      authProvider: options?.authProvider,
      maxRetries: options?.maxRetries ?? 2,
      environment: {
        apiBaseUrl: server.url,
        dubbingBaseUrl: `${server.url}/dubbing`,
        wsBaseUrl: server.wsUrl,
      },
      wsFactory,
    });
  }

  // ==========================================
  // Category 1: REST Cases (12 total)
  // ==========================================

  test('Case 1: rest-auth-error-quirk (HTTP 403 with invalid_api_key_error)', async () => {
    const client = createClient({ apiKey: 'invalid-key', maxRetries: 0 });
    await assert.rejects(
      async () => {
        await client.text.translate(
          {
            input: 'Hello world',
            source_language_code: 'en-IN',
            target_language_code: 'hi-IN',
          },
          {
            headers: {
              'x-mock-scenario': 'auth-invalid-api-key',
            },
          }
        );
      },
      (err: any) => {
        assert.ok(err instanceof AuthenticationError, `Expected AuthenticationError, got ${err.name}`);
        assert.equal(err.statusCode, 403);
        assert.equal(err.code, 'invalid_api_key_error');
        assert.equal(err.requestId, 'req_auth_403');
        assert.equal(err.message, 'Invalid API key');
        return true;
      }
    );
  });

  test('Case 2: rest-idempotent-retry-500 (IDEMPOTENT GET Operation Retries on HTTP 500)', async () => {
    const client = createClient({ maxRetries: 2 });
    const res = await client.chat.listModels({
      headers: {
        'x-mock-scenario': 'server-error-retry',
      },
    });

    assert.ok(res.models);
    assert.equal(res.models.length, 2);
    assert.equal(res.models[0]?.id, 'sarvam-2b');
    assert.equal(res.models[1]?.id, 'saaras:v3');

    // Verify 2 attempts were executed on the server
    assert.equal(server.getAttemptCount('server-error-retry'), 2);
  });

  test('Case 3: rest-job-creation-safety-500 (Job Creation Safety on HTTP 500)', async () => {
    const client = createClient({ maxRetries: 2 });
    await assert.rejects(
      async () => {
        await client.docAi.digitise(
          {
            language: 'hi',
            output_format: 'md',
          },
          {
            headers: {
              'x-mock-scenario': 'job-create-500',
            },
          }
        );
      },
      (err: any) => {
        assert.ok(err instanceof ServerError, `Expected ServerError, got ${err.name}`);
        assert.equal(err.statusCode, 500);
        assert.equal(err.code, 'internal_server_error');
        assert.equal(err.requestId, 'req_job_500');
        return true;
      }
    );

    // Verify exactly 1 attempt (0 retries performed for JOB_CREATE on 500)
    const recorded = server.getRecordedRequests('/doc-ai/v1/job/digitise');
    assert.equal(recorded.length, 1);
  });

  test('Case 4: rest-permission-denied (HTTP 403 with authentication_error)', async () => {
    const client = createClient({ apiKey: 'tier-locked-key', maxRetries: 2 });
    await assert.rejects(
      async () => {
        await client.text.translate(
          {
            input: 'Hello world',
            source_language_code: 'en-IN',
            target_language_code: 'hi-IN',
          },
          {
            headers: {
              'x-mock-scenario': 'auth-permission-denied',
            },
          }
        );
      },
      (err: any) => {
        assert.ok(err instanceof PermissionDeniedError, `Expected PermissionDeniedError, got ${err.name}`);
        assert.equal(err.statusCode, 403);
        assert.equal(err.code, 'authentication_error');
        assert.equal(err.requestId, 'req_perm_403');
        return true;
      }
    );
  });

  test('Case 5: rest-rate-limit-retry (Rate Limit 429 Retry with retry-after-ms)', async () => {
    const client = createClient({ maxRetries: 2 });
    const res = await client.text.translate(
      {
        input: 'Hello retry',
        source_language_code: 'en-IN',
        target_language_code: 'hi-IN',
      },
      {
        headers: {
          'x-mock-scenario': 'rate-limit-retry',
        },
      }
    );

    assert.equal(res.translatedText, 'नमस्ते पुनः प्रयास');
    assert.equal(server.getAttemptCount('rate-limit-retry'), 2);
  });

  test('Case 6: rest-sas-blob-upload (Azure SAS Blob Upload Header Validation)', async () => {
    const client = createClient();
    const uploadUrl = `${server.url}/mock-sas-upload?scenario=sas-blob-upload`;
    const audioData = new TextEncoder().encode('mock-audio-binary-data');

    // Should succeed because jobs.uploadToSignedUrl automatically injects x-ms-blob-type: BlockBlob
    await client.jobs.uploadToSignedUrl(uploadUrl, audioData);
    assert.ok(true, 'Blob uploaded successfully');
  });

  test('Case 7: rest-text-identify-language-success (REST text.identifyLanguage Success)', async () => {
    const client = createClient();
    const res = await client.text.identifyLanguage({
      input: 'नमस्ते दुनिया',
    });

    assert.equal(res.detectedLanguage, 'hi-IN');
    assert.equal(res.confidence, 0.99);
  });

  test('Case 8: rest-text-translate-success (REST text.translate Success)', async () => {
    const client = createClient();
    const res = await client.text.translate({
      input: 'Hello world',
      source_language_code: 'en-IN',
      target_language_code: 'hi-IN',
      speaker_gender: 'Male',
      mode: 'formal',
      model: 'mayura:v1',
    });

    assert.equal(res.translatedText, 'नमस्ते दुनिया');
  });

  test('Case 9: rest-text-transliterate-success (REST text.transliterate Success)', async () => {
    const client = createClient();
    const res = await client.text.transliterate({
      input: 'namaste',
      source_language_code: 'en-IN',
      target_language_code: 'hi-IN',
    });

    assert.equal(res.transliteratedText, 'नमस्ते');
  });

  test('Case 10: rest-token-auth-refresh (TokenAuth Invalidation and Single Retry on 403)', async () => {
    let tokenCalls = 0;
    const authProvider = new TokenAuth(async () => {
      tokenCalls++;
      return tokenCalls === 1 ? 'expired-token' : 'refreshed-token';
    });

    const client = createClient({ authProvider, maxRetries: 2 });
    const res = await client.text.translate(
      {
        input: 'Hello world',
        source_language_code: 'en-IN',
        target_language_code: 'hi-IN',
      },
      {
        headers: {
          'x-mock-scenario': 'token-auth-refresh',
        },
      }
    );

    assert.equal(res.translatedText, 'नमस्ते दुनिया');
    assert.equal(tokenCalls, 2, 'TokenAuth must have refreshed token on 403 invalid_api_key_error');
    const recorded = server.getRecordedRequests('/translate');
    assert.equal(recorded.length, 2);
  });

  test('Case 11: rest-tts-chunked-stream (TTS HTTP Chunked Binary Audio Stream)', async () => {
    const client = createClient();
    const stream = await client.textToSpeech.stream(
      {
        text: 'नमस्ते भारत',
        target_language_code: 'hi-IN',
        speaker: 'meera',
      },
      {
        headers: {
          'x-mock-scenario': 'tts-chunked-stream',
        },
      }
    );

    const chunks: Uint8Array[] = [];
    for await (const chunk of stream) {
      chunks.push(chunk);
    }

    assert.equal(chunks.length, 3, 'Expected 3 chunks');
    const totalLength = chunks.reduce((acc, c) => acc + c.length, 0);
    assert.equal(totalLength, 48);

    const merged = new Uint8Array(totalLength);
    let offset = 0;
    for (const c of chunks) {
      merged.set(c, offset);
      offset += c.length;
    }

    const hex = bytesToHex(merged);
    assert.equal(
      hex,
      '0102030405060708090a0b0c0d0e0f101112131415161718191a1b1c1d1e1f202122232425262728292a2b2c2d2e2f30'
    );
  });

  test('Case 12: rest-tts-base64-decoding (TTS REST Base64 Audio Decoding)', async () => {
    const client = createClient();
    const res = await client.textToSpeech.convert(
      {
        text: 'नमस्ते दुनिया',
        target_language_code: 'hi-IN',
        speaker: 'meera',
        model: 'bulbul:v3',
      },
      {
        headers: {
          'x-mock-scenario': 'tts-rest-base64',
        },
      }
    );

    assert.equal(res.audios.length, 1);
    assert.equal(res.audioBytes.length, 44);
    assert.equal(bytesToHex(res.audioBytes.slice(0, 4)), '52494646'); // RIFF
    assert.equal(bytesToHex(res.audioBytes.slice(8, 12)), '57415645'); // WAVE
  });

  // ==========================================
  // Category 2: SSE Cases (3 total)
  // ==========================================

  test('Case 13: sse-chat-v1-stream (Chat V1 Standard SSE Streaming terminating on [DONE])', async () => {
    const client = createClient();
    const stream = await client.chat.completionsStream(
      {
        model: 'sarvam-2b',
        messages: [{ role: 'user', content: 'Hi' }],
      },
      {
        headers: {
          'x-mock-scenario': 'chat-v1-stream',
        },
      }
    );

    let accumulatedContent = '';
    let chunkCount = 0;
    for await (const chunk of stream) {
      chunkCount++;
      if (chunk.firstDeltaContent) {
        accumulatedContent += chunk.firstDeltaContent;
      }
    }

    assert.equal(chunkCount, 2);
    assert.equal(accumulatedContent, 'Hi there!');
  });

  test('Case 14: sse-chat-v2-empty-choices (Chat V2 SSE Stream with Empty Choices Usage Chunk)', async () => {
    const client = createClient();
    const stream = await client.chat.completionsV2Stream(
      {
        model: 'sarvam-2b',
        messages: [{ role: 'user', content: 'Hello' }],
      },
      {
        headers: {
          'x-mock-scenario': 'chat-v2-sse-empty-choices',
        },
      }
    );

    let accumulatedContent = '';
    let usageChunkReceived = false;
    let finalUsage: any = null;

    for await (const chunk of stream) {
      if (chunk.firstDeltaContent) {
        accumulatedContent += chunk.firstDeltaContent;
      }
      if (chunk.usage) {
        usageChunkReceived = true;
        finalUsage = chunk.usage;
      }
    }

    assert.equal(accumulatedContent, 'Namaste world');
    assert.ok(usageChunkReceived, 'Must have received usage chunk without index error');
    assert.equal(finalUsage.prompt_tokens, 8);
    assert.equal(finalUsage.completion_tokens, 2);
    assert.equal(finalUsage.total_tokens, 10);
  });

  test('Case 15: sse-responses-api-no-done (Responses API SSE Stream with No [DONE] Sentinel Line)', async () => {
    const client = createClient();
    const stream = await client.responses.createStream(
      {
        model: 'glm-5.3',
        input: 'Explain quantum computing briefly',
      },
      {
        headers: {
          'x-mock-scenario': 'responses-sse-no-done',
        },
      }
    );

    const events: any[] = [];
    for await (const ev of stream) {
      events.push(ev);
    }

    assert.equal(events.length, 4);
    assert.equal(events[0].event, 'response.created');
    assert.equal(events[1].event, 'response.output_item.added');
    assert.equal(events[2].event, 'response.content_part.added');
    assert.equal(events[3].event, 'response.completed');
    assert.equal(events[3].data?.response?.status, 'completed');
  });

  // ==========================================
  // Category 3: WebSocket Cases (4 total)
  // ==========================================

  test('Case 16: ws-stt-invalid-sample-rate (WebSocket STT Realtime Invalid Sample Rate Rejection)', async () => {
    const client = createClient();
    await assert.rejects(
      async () => {
        await client.speechToText.connect({
          language_code: 'hi-IN',
          sample_rate: 44100,
        });
      },
      (err: any) => {
        assert.ok(err instanceof BadRequestError, `Expected BadRequestError, got ${err.name}`);
        assert.ok(
          err.message.includes('sampleRate must be 16000 or 8000'),
          `Expected message to contain 'sampleRate must be 16000 or 8000', got ${err.message}`
        );
        return true;
      }
    );
  });

  test('Case 17: ws-stt-realtime (WebSocket STT Realtime Full Turn)', async () => {
    const client = createClient();
    const session = await client.speechToText.connect({
      language_code: 'hi-IN',
      model: 'saaras:v3-realtime',
      sample_rate: 16000,
    });

    session.sendAudio(new Uint8Array([0x00, 0x00, 0x00, 0x00])); // "AAAA"
    session.end();

    const events: any[] = [];
    for await (const ev of session.events) {
      events.push(ev);
      if (ev.type === 'session_end') {
        session.close();
      }
    }

    assert.ok(events.some((e) => e.type === 'session_begin'));
    assert.ok(events.some((e) => e.type === 'vad_speech_start'));
    assert.ok(events.some((e) => e.type === 'transcript_partial'));
    const finalEvent = events.find((e) => e.type === 'transcript_final');
    assert.ok(finalEvent);
    assert.equal(finalEvent.text, 'नमस्ते!');
    assert.equal(finalEvent.language, 'hi-IN');
    assert.ok(events.some((e) => e.type === 'session_end'));
  });

  test('Case 18: ws-stt-subprotocol-auth (WebSocket STT Realtime Subprotocol Authentication)', async () => {
    const client = createClient();
    const session = await client.speechToText.connect(
      {
        language_code: 'hi-IN',
        model: 'saaras:v3-realtime',
        sample_rate: 16000,
      },
      {
        headers: {
          'Sec-WebSocket-Protocol': 'api-subscription-key.test-api-key',
        },
      }
    );

    session.sendAudio(new Uint8Array([0x00, 0x00, 0x00, 0x00]));
    session.end();

    const events: any[] = [];
    for await (const ev of session.events) {
      events.push(ev);
      if (ev.type === 'session_end') {
        session.close();
      }
    }

    assert.ok(events.some((e) => e.type === 'session_begin'));
    const finalEvent = events.find((e) => e.type === 'transcript_final');
    assert.ok(finalEvent);
    assert.equal(finalEvent.text, 'नमस्ते!');
    assert.ok(events.some((e) => e.type === 'session_end'));
  });

  test('Case 19: ws-tts-streaming (WebSocket TTS Streaming Full Conversational Turn)', async () => {
    const client = createClient();
    const session = await client.textToSpeech.connect({
      language_code: 'hi-IN',
      speaker: 'simran_en_customer',
      model: 'bulbul:v4-flash',
      speech_sample_rate: 22050,
      output_audio_codec: 'mp3',
    });

    session.sendText('नमस्ते भारत');
    session.flush();

    const events: any[] = [];
    for await (const ev of session.events) {
      events.push(ev);
      if (ev.type === 'completed') {
        session.close();
      }
    }

    const audioFrames = events.filter((e) => e.type === 'audio');
    assert.equal(audioFrames.length, 2, 'Expected 2 audio frames');
    for (const frame of audioFrames) {
      assert.equal(frame.audioBytes.length, 44, 'Expected 44-byte decoded WAV audio');
    }
    assert.ok(events.some((e) => e.type === 'completed'), 'Expected completed event');
  });
});
