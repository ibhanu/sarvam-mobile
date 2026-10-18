import { test, describe } from 'node:test';
import assert from 'node:assert/strict';
import * as fs from 'node:fs';
import * as path from 'node:path';
import { fileURLToPath } from 'node:url';
import { SarvamRustCore } from '../dist/esm/index.js';

const __filename = fileURLToPath(import.meta.url);
const __dirname = path.dirname(__filename);
const wasmPath = path.resolve(
  __dirname,
  '../../rust-core/target/wasm32-unknown-unknown/release/sarvam_rust_core.wasm'
);

describe('SarvamRustCore WebAssembly Bridge (TS / Web / React Native)', () => {
  test('loads sarvam_rust_core.wasm and executes auth, retry, SSE, WS, and 16kHz PCM DSP', async () => {
    const wasmBytes = fs.readFileSync(wasmPath);
    const rustCore = await SarvamRustCore.instantiate(wasmBytes);

    // 1. Version & Environment
    const ver = rustCore.version();
    assert.equal(ver.rustCoreVersion, '0.2.0');
    assert.equal(ver.specVersion, '2026-10-16');

    const proxyEnv = rustCore.resolveEnvironment('https://proxy.example.com/sarvam/');
    assert.equal(proxyEnv.apiBaseUrl, 'https://proxy.example.com/sarvam');
    assert.equal(proxyEnv.dubbingBaseUrl, 'https://proxy.example.com/sarvam/dubbing');
    assert.equal(proxyEnv.wsBaseUrl, 'wss://proxy.example.com/sarvam');

    // 2. HTTP 403 invalid_api_key_error Quirk -> AuthenticationError
    const err403 = rustCore.classifyHttpError(
      403,
      { 'x-request-id': 'req_wasm_403' },
      JSON.stringify({ error: { code: 'invalid_api_key_error', message: 'Expired key' } })
    );
    assert.equal(err403.type, 'AuthenticationError');
    assert.equal(err403.shouldTriggerTokenRefresh, true);
    assert.equal(err403.requestId, 'req_wasm_403');

    // 3. Safe Retry Matrix: JOB_CREATE on 500 vs STATELESS_POST on 429
    const jobDecision = rustCore.evaluateRetry({
      operationKind: 'JOB_CREATE',
      attempt: 0,
      maxRetries: 2,
      statusCode: 500
    });
    assert.equal(jobDecision.action, 'doNotRetry');

    const rlDecision = rustCore.evaluateRetry({
      operationKind: 'STATELESS_POST',
      attempt: 0,
      maxRetries: 2,
      statusCode: 429,
      headers: { 'retry-after-ms': '75' }
    });
    assert.deepEqual(rlDecision, { action: 'backoffAndRetry', delayMs: 75 });

    // 4. SSE Chat V2 with empty choices usage chunk & Responses API without [DONE]
    const chatSse = rustCore.parseChatSse(
      'data: {"id":"1","choices":[{"index":0,"delta":{"content":"Hello"}}]}\n\n' +
        'data: {"id":"1","choices":[],"usage":{"prompt_tokens":4,"completion_tokens":1,"total_tokens":5}}\n\n' +
        'data: [DONE]\n'
    );
    assert.equal(chatSse.accumulatedContent, 'Hello');
    assert.equal(chatSse.terminatedOnDone, true);
    assert.equal(chatSse.finalUsage?.total_tokens, 5);

    const respSse = rustCore.parseResponsesSse(
      'event: response.created\ndata: {"id":"r1","type":"response.created"}\n\n' +
        'event: response.completed\ndata: {"id":"r1","type":"response.completed","response":{"status":"completed"}}\n'
    );
    assert.equal(respSse.terminatedOnEvent, 'response.completed');
    assert.equal(respSse.finalResponseStatus, 'completed');

    // 5. STT sample rate validation
    assert.equal(rustCore.validateSttSampleRate(16000), true);
    assert.throws(() => rustCore.validateSttSampleRate(44100), /sampleRate must be 16000 or 8000/);

    // 6. Zero-JSON-overhead Wasm 16kHz PCM16 Resampler & Audio Levels
    const input48k = new Uint8Array(480 * 2);
    const view = new DataView(input48k.buffer);
    for (let i = 0; i < 480; i++) {
      view.setInt16(i * 2, i % 2 === 0 ? 16384 : -16384, true);
    }
    const resampled16k = rustCore.resamplePcm16(input48k, 48000, 1);
    assert.equal(resampled16k.byteLength, 160 * 2);
    assert.equal(rustCore.resamplePcm16(new Uint8Array(0), 48000, 1).byteLength, 0);

    const levels = rustCore.calculateAudioLevels(resampled16k);
    assert.ok(levels.peak > 0.49 && levels.peak <= 0.51);
    assert.ok(levels.rms > 0.49 && levels.rms <= 0.51);
  });
});
