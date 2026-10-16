# @sarvam-mobile/core

Official TypeScript Core SDK for **Sarvam AI** Indic language models, speech recognition, speech synthesis, and document intelligence services.

[![npm version](https://img.shields.io/npm/v/@sarvam-mobile/core.svg)](https://www.npmjs.com/package/@sarvam-mobile/core)
[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](LICENSE)
[![Zero Dependencies](https://img.shields.io/badge/dependencies-0-success.svg)](package.json)
[![TypeScript](https://img.shields.io/badge/TypeScript-5.7+-blue.svg)](tsconfig.json)

**Zero runtime dependencies. Pure TypeScript. Zero Node.js built-ins.**  
Runs out of the box in Node.js 18+, browsers, Bun, Deno, Edge runtimes, Cloudflare Workers, and React Native (Hermes).

---

## < 5 Minutes to First Call

### 1. Installation

Install [`@sarvam-mobile/core`](https://www.npmjs.com/package/@sarvam-mobile/core):

```bash
npm install @sarvam-mobile/core
# or
pnpm add @sarvam-mobile/core
# or
yarn add @sarvam-mobile/core
# or
bun add @sarvam-mobile/core
```

### 2. Quickstart

Translate text between English and 11+ Indic languages in less than 5 lines of code:

```typescript
import { SarvamClient, LanguageCode } from '@sarvam-mobile/core';

const client = new SarvamClient({
  apiKey: process.env.SARVAM_API_KEY!,
});

const response = await client.text.translate({
  input: 'Welcome to India! How can I help you today?',
  source_language_code: LanguageCode.EN_IN,
  target_language_code: LanguageCode.HI_IN,
});

console.log(response.translated_text);
// "भारत में आपका स्वागत है! आज मैं आपकी क्या मदद कर सकता हूँ?"
```

---

## Authentication & Mobile Security

`@sarvam-mobile/core` provides three pluggable authentication mechanisms conforming to modern client and mobile security standards:

### 1. `ApiKeyAuth` (Server / CLI / Local Prototyping)
Static API key passed via the `api-subscription-key` header:

```typescript
import { SarvamClient, ApiKeyAuth } from '@sarvam-mobile/core';

// Convenience constructor shortcut:
const client = new SarvamClient({ apiKey: 'YOUR_API_KEY' });

// Or explicit provider:
const client = new SarvamClient({
  authProvider: new ApiKeyAuth('YOUR_API_KEY'),
});
```

> [!WARNING]
> Bundling static API keys into mobile release builds is insecure. `ApiKeyAuth` automatically logs a warning when run in release builds (`__DEV__ === false`). Use `TokenAuth` or `ProxyAuth` for production client applications.

### 2. `TokenAuth` (Client & Mobile Production Flow)
Short-lived ephemeral JWTs or bearer tokens fetched from your backend server. Includes **in-memory caching**, **single-flight deduplication** to eliminate stampedes, and **proactive refresh 60 seconds before expiration**:

```typescript
import { SarvamClient, TokenAuth } from '@sarvam-mobile/core';

const authProvider = new TokenAuth(async () => {
  const res = await fetch('https://api.yourbackend.com/auth/sarvam-token');
  const data = await res.json();
  return {
    token: data.jwtToken,
    expiresAtEpochMs: data.expiresAtMs, // e.g. Date.now() + 15 * 60 * 1000
  };
});

const client = new SarvamClient({ authProvider });
```

If an HTTP 401 or 403 (`invalid_api_key_error`) occurs mid-session, `TokenAuth` automatically invalidates the cached token and retries the request once with a freshly fetched token.

### 3. `ProxyAuth` (Backend-For-Frontend / BFF Deployments)
Routes all client traffic through your application's proxy server, appending custom session or CSRF headers without exposing Sarvam endpoints directly:

```typescript
import { SarvamClient, ProxyAuth } from '@sarvam-mobile/core';

const authProvider = new ProxyAuth('https://api.yourbackend.com/sarvam-proxy', async () => ({
  'X-User-Session': 'session-token-xyz',
}));

const client = new SarvamClient({ authProvider });
```

---

## Core Capabilities & Examples

### 1. Indic Text Services (`client.text`)

#### Translation across 11+ Indic Languages
```typescript
import { SarvamClient, LanguageCode } from '@sarvam-mobile/core';

const client = new SarvamClient({ apiKey: process.env.SARVAM_API_KEY });

const result = await client.text.translate({
  input: 'The train will arrive at platform number 3 shortly.',
  source_language_code: LanguageCode.EN_IN,
  target_language_code: LanguageCode.TA_IN, // Tamil
  speaker_gender: 'Female',
  mode: 'formal',
});

console.log(result.translated_text);
```

#### Script Transliteration
Convert Latin English phonetics to native Indic scripts (e.g., Hinglish to Devanagari):
```typescript
const result = await client.text.transliterate({
  input: 'aap kaise ho?',
  source_language_code: LanguageCode.EN_IN,
  target_language_code: LanguageCode.HI_IN,
});

console.log(result.transliterated_text); // "आप कैसे हो?"
```

#### Language Identification (LID)
```typescript
const result = await client.text.identifyLanguage({
  input: 'নমস্কার, আপনি কেমন আছেন?',
});

console.log(result.detected_language); // "bn-IN"
console.log(result.confidence);        // 0.99
```

---

### 2. Speech-to-Text (`client.speechToText`)

#### Batch Audio Transcription
Transcribe pre-recorded audio files (`Uint8Array`, `Blob`, or React Native file descriptors):
```typescript
import { SarvamClient, SttModel, LanguageCode } from '@sarvam-mobile/core';

// Pass Uint8Array binary bytes directly (browser, Node, or mobile):
const audioBytes = new Uint8Array([...]);

const response = await client.speechToText.transcribe({
  file: audioBytes,
  model: SttModel.SAARAS_V4,
  language_code: LanguageCode.HI_IN,
  with_diarization: false,
});

console.log('Transcript:', response.transcript);
```

#### Direct Speech-to-Text Translation
Translate spoken audio in any Indic language directly to English text:
```typescript
const response = await client.speechToText.translate({
  file: audioBytes,
  model: SttModel.SAARAS_V4,
});

console.log('English translation:', response.transcript);
```

#### Realtime STT Streaming via WebSocket
Stream 16kHz mono linear16 audio chunks over a low-latency bidirectional WebSocket:
```typescript
import { SarvamClient, SttModel, LanguageCode } from '@sarvam-mobile/core';

const client = new SarvamClient({ apiKey: process.env.SARVAM_API_KEY });

const session = await client.speechToText.connect({
  model: SttModel.SAARAS_V3_REALTIME,
  language_code: LanguageCode.HI_IN,
  sample_rate: 16000,
  mode: 'transcribe',
  endpointing: true,
  threshold: 0.5,
});

// 1. Consume realtime events asynchronously
(async () => {
  for await (const event of session.events) {
    switch (event.type) {
      case 'transcript_partial':
        console.log('Partial:', event.text);
        break;
      case 'transcript_final':
        console.log('Final Utterance:', event.text);
        break;
      case 'vad_speech_start':
        console.log('User began speaking');
        break;
      case 'vad_speech_end':
        console.log('User paused speaking');
        break;
      case 'session_end':
        console.log('Session complete');
        break;
    }
  }
})();

// 2. Stream raw 16kHz linear16 PCM audio frames
session.sendAudio(pcmChunkUint8Array);

// 3. Close when finished
session.end();
```

---

### 3. Text-to-Speech (`client.textToSpeech`)

#### REST Speech Synthesis
Convert Indic text to audio bytes (`bulbul:v4-flash` / `bulbul:v3`):
```typescript
import { SarvamClient, Speaker, LanguageCode } from '@sarvam-mobile/core';

const response = await client.textToSpeech.convert({
  text: 'नमस्ते, आपका स्वागत है।',
  target_language_code: LanguageCode.HI_IN,
  speaker: Speaker.ANUSHKA,
  pace: 1.0,
});

// Raw audio binary bytes ready to play or save:
const wavBytes = response.audioBytes; // Uint8Array
```

#### HTTP Binary Audio Streaming
Consume synthesized audio as an `AsyncIterable<Uint8Array>` with low time-to-first-byte:
```typescript
const audioStream = await client.textToSpeech.stream({
  text: 'यह एक लंबा पाठ है जिसे तुरंत बजाया जा सकता है।',
  target_language_code: LanguageCode.HI_IN,
  speaker: Speaker.SIMRAN,
});

for await (const chunk of audioStream) {
  // Feed raw chunk directly to audio output stream
  audioPlayer.write(chunk);
}
```

#### WebSocket Conversational TTS Streaming
Stream incremental text tokens and receive synchronized audio frames:
```typescript
const session = await client.textToSpeech.connect({
  language_code: LanguageCode.HI_IN,
  speaker: Speaker.PRIYA,
});

// Listen for audio chunks
(async () => {
  for await (const event of session.events) {
    if (event.type === 'audio') {
      audioPlayer.playChunk(event.audioBytes);
    } else if (event.type === 'completed') {
      console.log('TTS utterance finished');
    }
  }
})();

// Push text chunks dynamically as LLM tokens generate
session.sendText('नमस्ते! ');
session.sendText('आज का मौसम बहुत अच्छा है।');
session.flush();
```

---

### 4. Chat & Large Language Models (`client.chat`)

OpenAI-compatible chat completions interface powered by Indic-specialized foundation models:

```typescript
import { SarvamClient, ChatModel } from '@sarvam-mobile/core';

const client = new SarvamClient({ apiKey: process.env.SARVAM_API_KEY });

// Standard completion:
const response = await client.chat.completions.create({
  model: ChatModel.SARVAM_M,
  messages: [
    { role: 'system', content: 'You are an Indic cultural and linguistic assistant.' },
    { role: 'user', content: 'Explain Pongal festival in Tamil and English.' },
  ],
  temperature: 0.7,
});

console.log(response.choices[0]?.message?.content);
```

#### Server-Sent Events (SSE) Streaming
```typescript
const stream = await client.chat.completions.create({
  model: ChatModel.SARVAM_M,
  messages: [{ role: 'user', content: 'Tell me a folk tale in Marathi.' }],
  stream: true,
});

for await (const chunk of stream) {
  const content = chunk.choices[0]?.delta?.content;
  if (content) {
    process.stdout.write(content);
  }
}
```

---

### 5. Document AI, Voice Cloning & Long-Running Jobs

`@sarvam-mobile/core` includes first-class support for P1/P2 asynchronous batch workloads:

- **`client.docAi`**: Digitize and structured entity extraction from multilingual documents (`digitiseAndWait`, `extractAndWait`).
- **`client.voiceCloning`**: Clone custom speaker profiles and convert voice samples.
- **`client.pronunciationDictionary`**: Manage custom phonetic mappings.
- **`client.dubbing`**: Multi-speaker video and audio dubbing pipelines with automated polling.
- **`client.speechToTextJob`**: Asynchronous batch STT jobs.

---

## Canonical Error Hierarchy

All SDK errors inherit from `SarvamError`, guaranteeing consistent, actionable debugging across every service:

```typescript
import {
  SarvamError,
  AuthenticationError,
  PermissionDeniedError,
  BadRequestError,
  RateLimitError,
  ServerError,
  TimeoutError,
  RealtimeError,
} from '@sarvam-mobile/core';

try {
  await client.text.translate({ ... });
} catch (error) {
  if (error instanceof RateLimitError) {
    console.warn(`Rate limited! Retry after ${error.retryAfterMs}ms`);
  } else if (error instanceof AuthenticationError) {
    console.error(`Invalid API Key or expired token (Request ID: ${error.requestId})`);
  } else if (error instanceof ServerError) {
    console.error(`Upstream 5xx error (${error.statusCode}): ${error.message}`);
  } else if (error instanceof SarvamError) {
    console.error(`Sarvam API error [${error.code}]: ${error.message}`);
  }
}
```

---

## Advanced Client Configuration

Customize timeouts, retries, logging, and transports:

```typescript
import { SarvamClient, FetchHttpTransport } from '@sarvam-mobile/core';

const client = new SarvamClient({
  apiKey: process.env.SARVAM_API_KEY,
  maxRetries: 3,         // Exponential backoff with full jitter
  timeoutMs: 30000,      // Request timeout
  logger: {
    debug: (msg, meta) => console.debug(`[SARVAM DEBUG] ${msg}`, meta),
    info:  (msg, meta) => console.info(`[SARVAM INFO] ${msg}`, meta),
    warn:  (msg, meta) => console.warn(`[SARVAM WARN] ${msg}`, meta),
    error: (msg, meta) => console.error(`[SARVAM ERROR] ${msg}`, meta),
  },
  // Custom fetch transport if needed (e.g. proxying or custom SSL):
  httpTransport: new FetchHttpTransport({ defaultTimeoutMs: 30000 }),
});
```

---

## License

MIT © [Sarvam AI](https://sarvam.ai)
