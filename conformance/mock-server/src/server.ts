import * as http from 'node:http';
import { URL } from 'node:url';
import { WebSocketServer, WebSocket } from 'ws';

export interface RecordedRequest {
  id: string;
  method: string;
  path: string;
  query: Record<string, string>;
  headers: http.IncomingHttpHeaders;
  body: string | null;
  scenario: string | null;
  timestamp: number;
}

export interface MockServerOptions {
  port?: number;
  host?: string;
  debug?: boolean;
}

export interface MockServerInstance {
  port: number;
  url: string;
  wsUrl: string;
  httpServer: http.Server;
  wss: WebSocketServer;
  start(): Promise<MockServerInstance>;
  stop(): Promise<void>;
  resetState(): void;
  getRecordedRequests(filterPath?: string): RecordedRequest[];
  getAttemptCount(key: string): number;
}

const WAV_SAMPLE_BASE64 = 'UklGRiQAAABXQVZFZm10IBAAAAABAAEAQB8AAEAfAAABAAgAZGF0YQAAAAA=';

export function createMockServer(options: MockServerOptions = {}): MockServerInstance {
  const host = options.host || '127.0.0.1';
  let port = options.port ?? (process.env.PORT ? parseInt(process.env.PORT, 10) : 0);
  const debug = options.debug ?? false;

  const recordedRequests: RecordedRequest[] = [];
  const attemptCounters = new Map<string, number>();

  function resetState() {
    recordedRequests.length = 0;
    attemptCounters.clear();
  }

  function getAttemptCount(key: string): number {
    return attemptCounters.get(key) || 0;
  }

  function incrementAttempt(key: string): number {
    const current = (attemptCounters.get(key) || 0) + 1;
    attemptCounters.set(key, current);
    return current;
  }

  const httpServer = http.createServer((req, res) => {
    const startTime = Date.now();
    const reqUrl = new URL(req.url || '/', `http://${req.headers.host || 'localhost'}`);
    const pathname = reqUrl.pathname;
    const queryParams: Record<string, string> = {};
    reqUrl.searchParams.forEach((val, key) => {
      queryParams[key] = val;
    });

    const scenarioHeader = req.headers['x-mock-scenario'] as string | undefined;
    const scenario = scenarioHeader || queryParams.scenario || null;

    // Buffer request body
    const chunks: Buffer[] = [];
    req.on('data', (chunk) => chunks.push(Buffer.isBuffer(chunk) ? chunk : Buffer.from(chunk)));
    req.on('end', () => {
      const rawBody = chunks.length > 0 ? Buffer.concat(chunks).toString('utf8') : null;

      const record: RecordedRequest = {
        id: `req_${Date.now()}_${Math.random().toString(36).slice(2, 7)}`,
        method: req.method || 'GET',
        path: pathname,
        query: queryParams,
        headers: req.headers,
        body: rawBody,
        scenario,
        timestamp: startTime,
      };
      recordedRequests.push(record);

      if (debug) {
        console.log(`[MockServer] ${req.method} ${pathname} (scenario: ${scenario})`);
      }

      // Handle CORS for browser testing
      res.setHeader('Access-Control-Allow-Origin', '*');
      res.setHeader('Access-Control-Allow-Methods', 'GET, POST, PUT, DELETE, OPTIONS');
      res.setHeader('Access-Control-Allow-Headers', '*');
      res.setHeader('Access-Control-Expose-Headers', '*');

      if (req.method === 'OPTIONS') {
        res.writeHead(204);
        res.end();
        return;
      }

      // Reset state route
      if (pathname === '/test/state/reset' && req.method === 'POST') {
        resetState();
        res.writeHead(200, { 'Content-Type': 'application/json' });
        res.end(JSON.stringify({ status: 'ok', message: 'State reset successfully' }));
        return;
      }

      // 1. SCENARIO OVERRIDES (can override any route based on x-mock-scenario)
      if (scenario === 'auth-invalid-api-key') {
        res.writeHead(403, { 'Content-Type': 'application/json' });
        res.end(
          JSON.stringify({
            error: {
              code: 'invalid_api_key_error',
              message: 'Invalid API key',
              request_id: 'req_auth_403',
            },
          }),
        );
        return;
      }

      if (scenario === 'auth-permission-denied') {
        res.writeHead(403, { 'Content-Type': 'application/json' });
        res.end(
          JSON.stringify({
            error: {
              code: 'authentication_error',
              message: 'Tier locked',
              request_id: 'req_perm_403',
            },
          }),
        );
        return;
      }

      if (scenario === 'rate-limit-retry') {
        const attempt = incrementAttempt('rate-limit-retry');
        if (attempt === 1) {
          res.writeHead(429, {
            'Content-Type': 'application/json',
            'retry-after-ms': '50',
          });
          res.end(
            JSON.stringify({
              error: {
                code: 'rate_limit_exceeded_error',
                message: 'Rate limit exceeded',
                request_id: 'req_rl_1',
              },
            }),
          );
          return;
        } else {
          res.writeHead(200, { 'Content-Type': 'application/json' });
          res.end(
            JSON.stringify({
              translated_text: 'नमस्ते पुनः प्रयास',
              attempt,
            }),
          );
          return;
        }
      }

      if (scenario === 'token-auth-refresh') {
        const authHeader = req.headers.authorization || '';
        if (authHeader.includes('expired-token')) {
          res.writeHead(403, { 'Content-Type': 'application/json' });
          res.end(
            JSON.stringify({
              error: {
                code: 'invalid_api_key_error',
                message: 'Bearer token expired',
                request_id: 'req_token_expired',
              },
            }),
          );
          return;
        }

        if (authHeader.includes('refreshed-token')) {
          res.writeHead(200, { 'Content-Type': 'application/json' });
          res.end(
            JSON.stringify({
              translated_text: 'नमस्ते दुनिया',
            }),
          );
          return;
        }

        // Default if unrecognized token
        res.writeHead(403, { 'Content-Type': 'application/json' });
        res.end(
          JSON.stringify({
            error: {
              code: 'invalid_api_key_error',
              message: 'Invalid token',
              request_id: 'req_token_invalid',
            },
          }),
        );
        return;
      }

      if (scenario === 'server-error-retry') {
        const attempt = incrementAttempt('server-error-retry');
        if (attempt === 1) {
          res.writeHead(500, { 'Content-Type': 'application/json' });
          res.end(
            JSON.stringify({
              error: {
                code: 'internal_server_error',
                message: 'Transient inference service failure',
                request_id: 'req_glitch_500',
              },
            }),
          );
          return;
        } else {
          res.writeHead(200, { 'Content-Type': 'application/json' });
          res.end(
            JSON.stringify({
              models: [{ id: 'sarvam-2b' }, { id: 'saaras:v3' }],
              attempt,
            }),
          );
          return;
        }
      }

      if (scenario === 'job-create-500') {
        res.writeHead(500, { 'Content-Type': 'application/json' });
        res.end(
          JSON.stringify({
            error: {
              code: 'internal_server_error',
              message: 'Internal server error',
              request_id: 'req_job_500',
            },
          }),
        );
        return;
      }

      // 2. ROUTE SPECIFIC HANDLERS

      // Azure SAS Blob Upload check
      if (pathname === '/mock-sas-upload' && req.method === 'PUT') {
        const blobTypeRaw = req.headers['x-ms-blob-type'];
        const blobType = Array.isArray(blobTypeRaw) ? blobTypeRaw[0] : blobTypeRaw;
        if (!blobType || blobType.toLowerCase() !== 'blockblob') {
          res.writeHead(400, { 'Content-Type': 'application/json' });
          res.end(
            JSON.stringify({
              error: {
                code: 'MissingRequiredHeader',
                message: 'Mandatory header x-ms-blob-type: BlockBlob missing',
              },
            }),
          );
          return;
        }

        res.writeHead(201, {
          'x-ms-request-id': 'mock-azure-req-1',
          'Content-Type': 'application/json',
        });
        res.end(JSON.stringify({ status: 'created' }));
        return;
      }

      // REST /translate
      if (pathname === '/translate' && req.method === 'POST') {
        res.writeHead(200, { 'Content-Type': 'application/json' });
        res.end(
          JSON.stringify({
            translated_text: 'नमस्ते दुनिया',
          }),
        );
        return;
      }

      // REST /transliterate
      if (pathname === '/transliterate' && req.method === 'POST') {
        res.writeHead(200, { 'Content-Type': 'application/json' });
        res.end(
          JSON.stringify({
            transliterated_text: 'नमस्ते',
          }),
        );
        return;
      }

      // REST /text-lid
      if (pathname === '/text-lid' && req.method === 'POST') {
        res.writeHead(200, { 'Content-Type': 'application/json' });
        res.end(
          JSON.stringify({
            detected_language: 'hi-IN',
            confidence: 0.99,
          }),
        );
        return;
      }

      // REST /text-to-speech (base64)
      if (pathname === '/text-to-speech' && req.method === 'POST') {
        res.writeHead(200, { 'Content-Type': 'application/json' });
        res.end(
          JSON.stringify({
            audios: [{ audio: WAV_SAMPLE_BASE64 }],
          }),
        );
        return;
      }

      // REST /text-to-speech/stream (HTTP chunked binary stream)
      if (pathname === '/text-to-speech/stream' && req.method === 'POST') {
        res.writeHead(200, {
          'Content-Type': 'application/octet-stream',
          'Transfer-Encoding': 'chunked',
        });

        // 3 binary chunks of 16 bytes each
        const chunk1 = Buffer.from([
          0x01, 0x02, 0x03, 0x04, 0x05, 0x06, 0x07, 0x08, 0x09, 0x0a, 0x0b, 0x0c, 0x0d, 0x0e,
          0x0f, 0x10,
        ]);
        const chunk2 = Buffer.from([
          0x11, 0x12, 0x13, 0x14, 0x15, 0x16, 0x17, 0x18, 0x19, 0x1a, 0x1b, 0x1c, 0x1d, 0x1e,
          0x1f, 0x20,
        ]);
        const chunk3 = Buffer.from([
          0x21, 0x22, 0x23, 0x24, 0x25, 0x26, 0x27, 0x28, 0x29, 0x2a, 0x2b, 0x2c, 0x2d, 0x2e,
          0x2f, 0x30,
        ]);

        res.write(chunk1);
        setTimeout(() => {
          res.write(chunk2);
          setTimeout(() => {
            res.write(chunk3);
            res.end();
          }, 10);
        }, 10);
        return;
      }

      // Chat V1: /v1/chat/completions
      if (pathname === '/v1/chat/completions' && req.method === 'POST') {
        let isStream = false;
        try {
          const bodyJson = JSON.parse(rawBody || '{}');
          isStream = Boolean(bodyJson.stream);
        } catch {
          // ignore
        }

        if (isStream || scenario === 'chat-v1-stream') {
          res.writeHead(200, {
            'Content-Type': 'text/event-stream',
            'Cache-Control': 'no-cache',
            Connection: 'keep-alive',
          });

          res.write('data: {"id":"chatcmpl-v1-1","choices":[{"index":0,"delta":{"content":"Hi"}}]}\n\n');
          res.write('data: {"id":"chatcmpl-v1-1","choices":[{"index":0,"delta":{"content":" there!"}}]}\n\n');
          res.write('data: [DONE]\n\n');
          res.end();
          return;
        }

        res.writeHead(200, { 'Content-Type': 'application/json' });
        res.end(
          JSON.stringify({
            id: 'chatcmpl-v1-1',
            choices: [{ index: 0, message: { role: 'assistant', content: 'Hi there!' } }],
          }),
        );
        return;
      }

      // Chat V2: /v2/chat/completions
      if (pathname === '/v2/chat/completions' && req.method === 'POST') {
        let isStream = false;
        try {
          const bodyJson = JSON.parse(rawBody || '{}');
          isStream = Boolean(bodyJson.stream);
        } catch {
          // ignore
        }

        if (isStream || scenario === 'chat-v2-sse-empty-choices') {
          res.writeHead(200, {
            'Content-Type': 'text/event-stream',
            'Cache-Control': 'no-cache',
            Connection: 'keep-alive',
          });

          res.write('data: {"id":"chatcmpl-1","choices":[{"index":0,"delta":{"content":"Namaste"}}]}\n\n');
          res.write('data: {"id":"chatcmpl-1","choices":[{"index":0,"delta":{"content":" world"}}]}\n\n');
          // Gotcha test: choices: [] on usage chunk!
          res.write('data: {"id":"chatcmpl-1","choices":[],"usage":{"prompt_tokens":8,"completion_tokens":2,"total_tokens":10}}\n\n');
          res.write('data: [DONE]\n\n');
          res.end();
          return;
        }

        res.writeHead(200, { 'Content-Type': 'application/json' });
        res.end(
          JSON.stringify({
            id: 'chatcmpl-1',
            choices: [{ index: 0, message: { role: 'assistant', content: 'Namaste world' } }],
          }),
        );
        return;
      }

      // Responses API: /v2/responses (No [DONE] line!)
      if (pathname === '/v2/responses' && req.method === 'POST') {
        res.writeHead(200, {
          'Content-Type': 'text/event-stream',
          'Cache-Control': 'no-cache',
          Connection: 'keep-alive',
        });

        res.write('event: response.created\ndata: {"id":"resp_001","type":"response.created"}\n\n');
        res.write(
          'event: response.output_item.added\ndata: {"id":"resp_001","type":"response.output_item.added","item":{"id":"item_001","type":"message","role":"assistant"}}\n\n',
        );
        res.write(
          'event: response.content_part.added\ndata: {"id":"resp_001","type":"response.content_part.added","item_id":"item_001","part":{"type":"text","text":"Quantum computers use qubits."}}\n\n',
        );
        res.write(
          'event: response.completed\ndata: {"id":"resp_001","type":"response.completed","response":{"status":"completed"}}\n\n',
        );
        // Clean termination without [DONE]!
        res.end();
        return;
      }

      // Models: GET /v2/models
      if (pathname === '/v2/models' && req.method === 'GET') {
        res.writeHead(200, { 'Content-Type': 'application/json' });
        res.end(
          JSON.stringify({
            models: [{ id: 'sarvam-2b' }, { id: 'saaras:v3' }],
          }),
        );
        return;
      }

      // Doc AI Job Digitise: POST /doc-ai/v1/job/digitise
      if (pathname === '/doc-ai/v1/job/digitise' && req.method === 'POST') {
        res.writeHead(200, { 'Content-Type': 'application/json' });
        res.end(
          JSON.stringify({
            job_id: 'job_doc_001',
            status: 'pending',
          }),
        );
        return;
      }

      // 404 fallback for unmatched paths
      res.writeHead(404, { 'Content-Type': 'application/json' });
      res.end(
        JSON.stringify({
          error: {
            code: 'not_found_error',
            message: `Route ${req.method} ${pathname} not found on mock server`,
            request_id: 'req_404',
          },
        }),
      );
    });
  });

  // WebSocket Server Setup
  const wss = new WebSocketServer({ noServer: true });

  httpServer.on('upgrade', (request, socket, head) => {
    const reqUrl = new URL(request.url || '/', `http://${request.headers.host || 'localhost'}`);
    const pathname = reqUrl.pathname;
    const queryParams: Record<string, string> = {};
    reqUrl.searchParams.forEach((v, k) => {
      queryParams[k] = v;
    });

    const subprotocolsHeader = request.headers['sec-websocket-protocol'];
    const offeredProtocols = subprotocolsHeader
      ? subprotocolsHeader.split(',').map((p) => p.trim())
      : [];

    let selectedProtocol: string | undefined = undefined;
    for (const proto of offeredProtocols) {
      if (proto.startsWith('api-subscription-key.') || proto.startsWith('bearer.')) {
        selectedProtocol = proto;
        break;
      }
    }

    if (pathname === '/speech-to-text-realtime/ws') {
      // Validate sample_rate
      const sampleRate = queryParams.sample_rate;
      if (sampleRate && sampleRate !== '16000' && sampleRate !== '8000') {
        wss.handleUpgrade(request, socket, head, (ws) => {
          ws.close(4000, 'Invalid sample_rate: must be 16000 or 8000');
        });
        return;
      }

      wss.handleUpgrade(request, socket, head, (ws) => {
        handleSttWsConnection(ws, queryParams);
      });
      return;
    }

    if (pathname === '/text-to-speech/ws' || pathname === '/voices/clone/ws') {
      wss.handleUpgrade(request, socket, head, (ws) => {
        handleTtsWsConnection(ws, queryParams);
      });
      return;
    }

    // Unhandled WS path: reject
    socket.write('HTTP/1.1 404 Not Found\r\n\r\n');
    socket.destroy();
  });

  function handleSttWsConnection(ws: WebSocket, queryParams: Record<string, string>) {
    let sessionStarted = false;
    const sessionId = `sess_${Date.now()}`;
    const lang = queryParams.language_code || 'hi-IN';

    ws.on('message', (data) => {
      let parsed: { event?: string; audio?: string } = {};
      try {
        parsed = JSON.parse(data.toString());
      } catch {
        return;
      }

      if (parsed.event === 'ping') {
        ws.send(JSON.stringify({ event: 'pong' }));
        return;
      }

      if (parsed.event === 'audio_input') {
        if (!sessionStarted) {
          sessionStarted = true;
          ws.send(JSON.stringify({ event: 'session_begin', session_id: sessionId }));
          ws.send(JSON.stringify({ event: 'vad_speech_start', timestamp_ms: 100 }));
          ws.send(
            JSON.stringify({
              event: 'transcript_partial',
              utterance_idx: 0,
              text: 'नमस्ते',
              language: lang,
            }),
          );
        }
        return;
      }

      if (parsed.event === 'flush' || parsed.event === 'end') {
        ws.send(
          JSON.stringify({
            event: 'transcript_final',
            utterance_idx: 0,
            text: 'नमस्ते!',
            language: lang,
            language_confidence: 0.99,
            start_s: 0.1,
            end_s: 1.5,
          }),
        );
        ws.send(JSON.stringify({ event: 'session_end' }));
      }
    });
  }

  function handleTtsWsConnection(ws: WebSocket, _queryParams: Record<string, string>) {
    ws.on('message', (data) => {
      let parsed: { type?: string; data?: { text?: string } } = {};
      try {
        parsed = JSON.parse(data.toString());
      } catch {
        return;
      }

      if (parsed.type === 'ping') {
        ws.send(JSON.stringify({ type: 'pong' }));
        return;
      }

      if (parsed.type === 'config') {
        // Config acknowledged silently
        return;
      }

      if (parsed.type === 'text') {
        // Text buffered
        return;
      }

      if (parsed.type === 'flush') {
        // Send 2 audio frames + final event
        ws.send(
          JSON.stringify({
            type: 'audio',
            data: { audio: WAV_SAMPLE_BASE64 },
          }),
        );
        ws.send(
          JSON.stringify({
            type: 'audio',
            data: { audio: WAV_SAMPLE_BASE64 },
          }),
        );
        ws.send(
          JSON.stringify({
            type: 'event',
            data: { event: 'final' },
          }),
        );
      }
    });
  }

  const serverInstance: MockServerInstance = {
    port: 0,
    url: '',
    wsUrl: '',
    httpServer,
    wss,
    start(): Promise<MockServerInstance> {
      return new Promise((resolve, reject) => {
        httpServer.once('error', reject);
        httpServer.listen(port, host, () => {
          const address = httpServer.address();
          if (address && typeof address === 'object') {
            serverInstance.port = address.port;
            serverInstance.url = `http://${host}:${address.port}`;
            serverInstance.wsUrl = `ws://${host}:${address.port}`;
          }
          if (debug) {
            console.log(`[MockServer] Running at ${serverInstance.url} (${serverInstance.wsUrl})`);
          }
          resolve(serverInstance);
        });
      });
    },
    stop(): Promise<void> {
      return new Promise((resolve) => {
        for (const client of wss.clients) {
          try {
            client.terminate();
          } catch {
            // ignore
          }
        }
        wss.close(() => {
          httpServer.close(() => {
            resolve();
          });
        });
      });
    },
    resetState,
    getRecordedRequests(filterPath?: string): RecordedRequest[] {
      if (filterPath) {
        return recordedRequests.filter((r) => r.path === filterPath);
      }
      return [...recordedRequests];
    },
    getAttemptCount,
  };

  return serverInstance;
}
