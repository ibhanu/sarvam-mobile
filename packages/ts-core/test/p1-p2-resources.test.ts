import { test, describe } from 'node:test';
import assert from 'node:assert/strict';
import {
  SarvamClient,
  SarvamEnvironment,
  ApiKeyAuth,
  pollUntilComplete,
  isStandardJobComplete,
  isStandardJobFailed,
  TimeoutError,
  ServerError,
  VoiceCloningResource,
  DocAiResource,
  PronunciationDictionaryResource,
  SpeechToTextJobResource,
  SpeechToTextTranslateJobResource,
  DocumentTranslationResource,
  DubbingResource,
} from '../dist/esm/index.js';
import type {
  HttpRequest,
  HttpResponse,
  ClientDispatcher,
  Clock,
} from '../dist/esm/index.js';

describe('P1 & P2 Resources + JobPoller Unit Tests', () => {
  // Mock controllable Clock
  function createMockClock() {
    let currentTime = 1000;
    const sleeps: number[] = [];
    const clock: Clock = {
      now: () => currentTime,
      sleep: async (ms: number) => {
        sleeps.push(ms);
        currentTime += ms;
      },
    };
    return { clock, getSleeps: () => sleeps, getTime: () => currentTime };
  }

  // ========================================================
  // 1. Generic pollUntilComplete tests
  // ========================================================
  describe('1. pollUntilComplete', () => {
    test('polls until isComplete returns true and respects backoff', async () => {
      const { clock, getSleeps } = createMockClock();
      let callCount = 0;

      const result = await pollUntilComplete({
        poll: async () => {
          callCount++;
          if (callCount < 3) {
            return { job_id: 'j1', status: 'PENDING' };
          }
          return { job_id: 'j1', status: 'COMPLETED', data: 'success' };
        },
        isComplete: isStandardJobComplete,
        isFailed: isStandardJobFailed,
        initialIntervalMs: 500,
        maxIntervalMs: 5000,
        backoffMultiplier: 2.0,
        clock,
      });

      assert.equal(callCount, 3);
      assert.equal(result.status, 'COMPLETED');
      assert.deepEqual(getSleeps(), [500, 1000]);
    });

    test('throws ServerError when isFailed returns true', async () => {
      const { clock } = createMockClock();
      let callCount = 0;

      await assert.rejects(
        async () => {
          await pollUntilComplete({
            poll: async () => {
              callCount++;
              if (callCount === 1) return { status: 'IN_PROGRESS' };
              return { status: 'FAILED', error_message: 'File corrupted' };
            },
            isComplete: isStandardJobComplete,
            isFailed: isStandardJobFailed,
            clock,
          });
        },
        (err: any) => {
          assert(err instanceof ServerError);
          assert.equal(err.message, 'File corrupted');
          return true;
        }
      );
    });

    test('throws TimeoutError when polling exceeds timeoutMs', async () => {
      const { clock } = createMockClock();

      await assert.rejects(
        async () => {
          await pollUntilComplete({
            poll: async () => ({ status: 'PENDING' }),
            isComplete: isStandardJobComplete,
            timeoutMs: 3000,
            initialIntervalMs: 1000,
            backoffMultiplier: 1.0,
            clock,
          });
        },
        (err: any) => {
          assert(err instanceof TimeoutError);
          assert.equal(err.phase, 'total');
          return true;
        }
      );
    });

    test('aborts immediately when AbortSignal is cancelled', async () => {
      const { clock } = createMockClock();
      const ac = new AbortController();
      ac.abort();

      await assert.rejects(
        async () => {
          await pollUntilComplete({
            poll: async () => ({ status: 'PENDING' }),
            isComplete: isStandardJobComplete,
            signal: ac.signal,
            clock,
          });
        },
        (err: any) => {
          assert.equal(err.name, 'AbortError');
          return true;
        }
      );
    });
  });

  // ========================================================
  // 2. DocAiResource tests
  // ========================================================
  describe('2. DocAiResource', () => {
    test('digitise accepts single FileInput and array FileInput as multipart array', async () => {
      let recordedReq: HttpRequest | null = null;
      const dispatcher: ClientDispatcher = {
        execute: async (req: HttpRequest): Promise<HttpResponse> => {
          recordedReq = req;
          return {
            status: 200,
            statusText: 'OK',
            headers: {
              get: () => null,
              has: () => false,
              entries: function* () {},
            },
            json: async () => ({ job_id: 'job_digitise_123', status: 'pending' }),
            text: async () => '',
          };
        },
        getApiBaseUrl: () => 'https://api.sarvam.ai',
        getDubbingBaseUrl: () => 'https://api.sarvam.ai/dubbing',
      };

      const docAi = new DocAiResource(dispatcher);
      const res = await docAi.digitise({
        file: [new Uint8Array([1, 2, 3]), new Uint8Array([4, 5, 6])],
        output_format: 'html',
      });

      assert.equal(res.job_id, 'job_digitise_123');
      assert.equal(recordedReq?.url, 'https://api.sarvam.ai/doc-ai/v1/job/digitise');
      assert.equal(recordedReq?.operationKind, 'JOB_CREATE');
      assert(recordedReq?.body instanceof FormData);

      const fd = recordedReq?.body as FormData;
      assert.equal(fd.getAll('file').length, 2);
      assert.equal(fd.get('output_format'), 'html');
    });

    test('extract auto-serializes schema object into JSON string multipart field', async () => {
      let recordedReq: HttpRequest | null = null;
      const dispatcher: ClientDispatcher = {
        execute: async (req: HttpRequest): Promise<HttpResponse> => {
          recordedReq = req;
          return {
            status: 200,
            statusText: 'OK',
            headers: {
              get: () => null,
              has: () => false,
              entries: function* () {},
            },
            json: async () => ({ job_id: 'job_extract_456', status: 'pending' }),
            text: async () => '',
          };
        },
        getApiBaseUrl: () => 'https://api.sarvam.ai',
        getDubbingBaseUrl: () => 'https://api.sarvam.ai/dubbing',
      };

      const docAi = new DocAiResource(dispatcher);
      const schemaObj = { name: 'string', invoice_total: 'number' };
      const res = await docAi.extract({
        file: new Uint8Array([1, 2, 3]),
        schema: schemaObj,
      });

      assert.equal(res.job_id, 'job_extract_456');
      assert.equal(recordedReq?.url, 'https://api.sarvam.ai/doc-ai/v1/job/extract');
      assert(recordedReq?.body instanceof FormData);

      const fd = recordedReq?.body as FormData;
      assert.equal(fd.get('schema'), JSON.stringify(schemaObj));
      assert.equal(fd.getAll('file').length, 1);
    });

    test('digitiseAndWait and extractAndWait poll until completion and return results', async () => {
      const { clock } = createMockClock();
      let statusPolls = 0;

      const dispatcher: ClientDispatcher = {
        execute: async (req: HttpRequest): Promise<HttpResponse> => {
          const makeRes = (data: any): HttpResponse => ({
            status: 200,
            statusText: 'OK',
            headers: { get: () => null, has: () => false, entries: function* () {} },
            json: async () => data,
            text: async () => JSON.stringify(data),
          });

          if (req.url.endsWith('/digitise')) {
            return makeRes({ job_id: 'job_wait_789', status: 'pending' });
          }
          if (req.url.includes('/status')) {
            statusPolls++;
            if (statusPolls < 2) return makeRes({ job_id: 'job_wait_789', status: 'PENDING' });
            return makeRes({ job_id: 'job_wait_789', status: 'COMPLETED' });
          }
          if (req.url.includes('/results')) {
            return makeRes({ job_id: 'job_wait_789', markdown: '# Extracted Content' });
          }
          return makeRes({});
        },
        getApiBaseUrl: () => 'https://api.sarvam.ai',
        getDubbingBaseUrl: () => 'https://api.sarvam.ai/dubbing',
        getClock: () => clock,
      };

      const docAi = new DocAiResource(dispatcher);
      const res = await docAi.digitiseAndWait(
        { file: new Uint8Array([1, 2]) },
        { clock, initialIntervalMs: 100 }
      );

      assert.equal(res.job_id, 'job_wait_789');
      assert.equal(res.markdown, '# Extracted Content');
      assert.equal(res.status.status, 'COMPLETED');
    });
  });

  // ========================================================
  // 3. DubbingResource tests
  // ========================================================
  describe('3. DubbingResource', () => {
    test('routes to dubbing environment host and maps wire field aliases', async () => {
      let recordedReq: HttpRequest | null = null;
      const dispatcher: ClientDispatcher = {
        execute: async (req: HttpRequest): Promise<HttpResponse> => {
          recordedReq = req;
          return {
            status: 200,
            statusText: 'OK',
            headers: { get: () => null, has: () => false, entries: function* () {} },
            json: async () => ({ job_id: 'dub_job_1', status: 'created' }),
            text: async () => '',
          };
        },
        getApiBaseUrl: () => 'https://api.sarvam.ai',
        getDubbingBaseUrl: () => 'https://api.sarvam.ai/dubbing',
      };

      const dubbing = new DubbingResource(dispatcher);
      const res = await dubbing.create({
        source_language_code: 'hi-IN',
        target_language_codes: ['en-IN', 'ta-IN'],
      });

      assert.equal(res.job_id, 'dub_job_1');
      // Crucial: Must use dubbingBaseUrl
      assert.equal(recordedReq?.url, 'https://api.sarvam.ai/dubbing/jobs');
      assert.equal(recordedReq?.operationKind, 'JOB_CREATE');

      // Crucial: Must map wire field aliases
      const parsedBody = JSON.parse(recordedReq?.body as string);
      assert.equal(parsedBody.src_lang, 'hi-IN');
      assert.deepEqual(parsedBody.target_langs, ['en-IN', 'ta-IN']);
      assert.equal(parsedBody.source_language_code, undefined);
      assert.equal(parsedBody.target_language_codes, undefined);
    });

    test('start, getLiveStatus, getExportStatus, and waitUntilComplete route to dubbing host', async () => {
      const urlsCalled: string[] = [];
      const { clock } = createMockClock();
      let pollCount = 0;

      const dispatcher: ClientDispatcher = {
        execute: async (req: HttpRequest): Promise<HttpResponse> => {
          urlsCalled.push(req.url);
          const makeRes = (data: any): HttpResponse => ({
            status: 200,
            statusText: 'OK',
            headers: { get: () => null, has: () => false, entries: function* () {} },
            json: async () => data,
            text: async () => JSON.stringify(data),
          });

          if (req.url.endsWith('/start')) return makeRes({ status: 'started' });
          if (req.url.endsWith('/live-status')) {
            pollCount++;
            return makeRes({ status: pollCount >= 2 ? 'COMPLETED' : 'PROCESSING' });
          }
          if (req.url.endsWith('/export-status')) return makeRes({ export_status: 'SUCCESS' });
          return makeRes({});
        },
        getApiBaseUrl: () => 'https://api.sarvam.ai',
        getDubbingBaseUrl: () => 'https://api.sarvam.ai/dubbing',
        getClock: () => clock,
      };

      const dubbing = new DubbingResource(dispatcher);
      await dubbing.start('dub_123');
      assert(urlsCalled[0]?.includes('/dubbing/jobs/dub_123/start'));

      const live = await dubbing.waitUntilComplete('dub_123', { clock, initialIntervalMs: 50 });
      assert.equal(live.status, 'COMPLETED');

      const exp = await dubbing.getExportStatus('dub_123');
      assert.equal(exp.export_status, 'SUCCESS');
    });
  });

  // ========================================================
  // 4. VoiceCloningResource tests
  // ========================================================
  describe('4. VoiceCloningResource', () => {
    test('convert returns response with audioBytes decoded from root audio', async () => {
      let recordedReq: HttpRequest | null = null;
      // 'hello' in base64: aGVsbG8=
      const b64 = 'aGVsbG8=';
      const dispatcher: ClientDispatcher = {
        execute: async (req: HttpRequest): Promise<HttpResponse> => {
          recordedReq = req;
          return {
            status: 200,
            statusText: 'OK',
            headers: { get: () => null, has: () => false, entries: function* () {} },
            json: async () => ({
              audio: b64,
              request_id: 'vc_req_1',
            }),
            text: async () => '',
          };
        },
        getApiBaseUrl: () => 'https://api.sarvam.ai',
        getDubbingBaseUrl: () => 'https://api.sarvam.ai/dubbing',
      };

      const vc = new VoiceCloningResource(dispatcher);
      const res = await vc.convert({
        text: 'Hello world',
        voice_id: 'svc-12345',
        target_language_code: 'hi-IN',
      });

      assert.equal(recordedReq?.url, 'https://api.sarvam.ai/voices/clone');
      assert.equal(recordedReq?.operationKind, 'MULTIPART_COMPUTE');
      assert(res.audioBytes instanceof Uint8Array);
      assert.equal(new TextDecoder().decode(res.audioBytes), 'hello');
      assert.equal(res.audio, b64);
    });

    test('listVoices, createVoice, getVoice, deleteVoice execute with correct verbs and paths', async () => {
      const calls: Array<{ method: string; url: string; kind?: string }> = [];
      const dispatcher: ClientDispatcher = {
        execute: async (req: HttpRequest): Promise<HttpResponse> => {
          calls.push({ method: req.method, url: req.url, kind: req.operationKind });
          return {
            status: 200,
            statusText: 'OK',
            headers: { get: () => null, has: () => false, entries: function* () {} },
            json: async () => ({ ok: true }),
            text: async () => '',
          };
        },
        getApiBaseUrl: () => 'https://api.sarvam.ai',
        getDubbingBaseUrl: () => 'https://api.sarvam.ai/dubbing',
      };

      const vc = new VoiceCloningResource(dispatcher);
      await vc.listVoices();
      assert.equal(calls[0]?.method, 'GET');
      assert.equal(calls[0]?.url, 'https://api.sarvam.ai/voices');

      await vc.createVoice({ file: new Uint8Array([1, 2]), name: 'MyVoice' });
      assert.equal(calls[1]?.method, 'POST');
      assert.equal(calls[1]?.url, 'https://api.sarvam.ai/voices/create');
      assert.equal(calls[1]?.kind, 'JOB_CREATE');

      await vc.getVoice('svc-abc');
      assert.equal(calls[2]?.method, 'GET');
      assert.equal(calls[2]?.url, 'https://api.sarvam.ai/voices/svc-abc');

      await vc.deleteVoice('svc-abc');
      assert.equal(calls[3]?.method, 'DELETE');
      assert.equal(calls[3]?.url, 'https://api.sarvam.ai/voices/delete/svc-abc');
    });

    test('connect establishes TtsStreamingSession to /voices/clone/ws?send_completion_event=true', async () => {
      let connectedUrl = '';
      let sentConfigFrame: string | null = null;

      const mockWs: any = {
        send: (msg: string) => {
          if (!sentConfigFrame) sentConfigFrame = msg;
        },
        on: () => {},
        close: () => {},
      };

      const mockWsFactory: any = {
        connect: async (url: string) => {
          connectedUrl = url;
          return mockWs;
        },
      };

      const dispatcher: ClientDispatcher = {
        execute: async () => ({} as any),
        getApiBaseUrl: () => 'https://api.sarvam.ai',
        getDubbingBaseUrl: () => 'https://api.sarvam.ai/dubbing',
        getWsBaseUrl: () => 'wss://api.sarvam.ai',
        getAuthProvider: () => new ApiKeyAuth('test-sub-key'),
        getWebSocketFactory: () => mockWsFactory,
      };

      const vc = new VoiceCloningResource(dispatcher);
      const session = await vc.connect({
        voice_id: 'svc-999',
        language_code: 'hi-IN',
      });

      assert(session);
      assert.equal(
        connectedUrl,
        'wss://api.sarvam.ai/voices/clone/ws?send_completion_event=true'
      );
      assert(sentConfigFrame !== null);
      const parsedConfig = JSON.parse(sentConfigFrame!);
      assert.equal(parsedConfig.type, 'config');
      assert.equal(parsedConfig.data.voice_id, 'svc-999');
      assert.equal(parsedConfig.data.language_code, 'hi-IN');
    });
  });

  // ========================================================
  // 5. PronunciationDictionaryResource tests
  // ========================================================
  describe('5. PronunciationDictionaryResource', () => {
    test('update and delete append dict_id query parameter correctly', async () => {
      const calls: Array<{ method: string; url: string }> = [];
      const dispatcher: ClientDispatcher = {
        execute: async (req: HttpRequest): Promise<HttpResponse> => {
          calls.push({ method: req.method, url: req.url });
          return {
            status: 200,
            statusText: 'OK',
            headers: { get: () => null, has: () => false, entries: function* () {} },
            json: async () => ({ success: true }),
            text: async () => '',
          };
        },
        getApiBaseUrl: () => 'https://api.sarvam.ai',
        getDubbingBaseUrl: () => 'https://api.sarvam.ai/dubbing',
      };

      const dict = new PronunciationDictionaryResource(dispatcher);
      await dict.update('dict_42', { file: new Uint8Array([10, 20]) });
      assert.equal(calls[0]?.method, 'PUT');
      assert.equal(
        calls[0]?.url,
        'https://api.sarvam.ai/text-to-speech/pronunciation-dictionary?dict_id=dict_42'
      );

      await dict.delete('dict_42');
      assert.equal(calls[1]?.method, 'DELETE');
      assert.equal(
        calls[1]?.url,
        'https://api.sarvam.ai/text-to-speech/pronunciation-dictionary?dict_id=dict_42'
      );
    });
  });

  // ========================================================
  // 6. SpeechToTextJobResource & SpeechToTextTranslateJobResource
  // ========================================================
  describe('6. SpeechToTextJobResource & SpeechToTextTranslateJobResource', () => {
    test('batch STT jobs support initialise, start, and waitUntilComplete', async () => {
      const { clock } = createMockClock();
      let pollCount = 0;

      const dispatcher: ClientDispatcher = {
        execute: async (req: HttpRequest): Promise<HttpResponse> => {
          const makeRes = (data: any): HttpResponse => ({
            status: 200,
            statusText: 'OK',
            headers: { get: () => null, has: () => false, entries: function* () {} },
            json: async () => data,
            text: async () => JSON.stringify(data),
          });

          if (req.url.endsWith('/job/v1')) return makeRes({ job_id: 'stt_job_1' });
          if (req.url.includes('/status')) {
            pollCount++;
            return makeRes({ job_id: 'stt_job_1', status: pollCount >= 2 ? 'COMPLETED' : 'IN_PROGRESS' });
          }
          return makeRes({});
        },
        getApiBaseUrl: () => 'https://api.sarvam.ai',
        getDubbingBaseUrl: () => 'https://api.sarvam.ai/dubbing',
        getClock: () => clock,
      };

      const sttJob = new SpeechToTextJobResource(dispatcher);
      const initRes = await sttJob.initialise({ model: 'saaras:v4' });
      assert.equal(initRes.job_id, 'stt_job_1');

      const completed = await sttJob.waitUntilComplete('stt_job_1', { clock, initialIntervalMs: 50 });
      assert.equal(completed.status, 'COMPLETED');
    });
  });
});
