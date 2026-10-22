# TypeScript & React Native Quickstart Guide

This guide walks you through installing, configuring, and building applications with the unofficial **Sarvam AI TypeScript SDKs**:
- **`@sarvam/core`**: Pure TypeScript core SDK with zero dependencies for Node.js 18+, browser, edge runtimes, and Cloudflare Workers.
- **`@sarvam/react-native`**: Hermes-native mobile SDK with native WebSocket header forwarding, zero-copy file uploads (`fromReactNativeUri`), and conversational audio utilities (`PcmResampler`, `BargeInCoordinator`).

---

## 1. Installation

### For Node.js, Web, or Edge Projects:
```bash
npm install @sarvam/core
# or
pnpm add @sarvam/core
# or
bun add @sarvam/core
```

### For React Native & Expo Projects:
```bash
# In Expo projects:
npx expo install @sarvam/react-native @sarvam/core

# In React Native CLI projects:
npm install @sarvam/react-native @sarvam/core
```

---

## 2. Client Initialization & Authentication

### A. Server-Side / CLI / Local Development (`ApiKeyAuth`)
```typescript
import { SarvamClient, LanguageCode } from '@sarvam/core';

const client = new SarvamClient({
  apiKey: process.env.SARVAM_API_KEY!,
});
```

### B. Mobile / Client Production Flow (`TokenAuth`)
Never bundle static API keys into client apps. Fetch short-lived tokens from your backend server:

```typescript
import { SarvamReactNativeClient, TokenAuth } from '@sarvam/react-native';

const authProvider = new TokenAuth(async () => {
  const res = await fetch('https://api.yourcompany.com/auth/sarvam-ephemeral-token', {
    headers: { Authorization: `Bearer ${userSessionToken}` },
  });
  const data = await res.json();
  return {
    token: data.token,
    expiresAtEpochMs: data.expiresAtMs, // Proactively refreshed 60s before expiration
  };
});

const client = new SarvamReactNativeClient({ authProvider });
```

### C. Backend-For-Frontend (BFF) Proxy Flow (`ProxyAuth`)
Route traffic through an API gateway:

```typescript
import { SarvamClient, ProxyAuth } from '@sarvam/core';

const authProvider = new ProxyAuth('https://api.yourcompany.com/sarvam-proxy', async () => ({
  'X-Session-ID': 'user-session-12345',
}));

const client = new SarvamClient({ authProvider });
```

---

## 3. Indic Text Services

### Translate Text
Translate across 11+ Indic languages (Hindi, Bengali, Tamil, Telugu, Kannada, Marathi, Gujarati, etc.):

```typescript
import { LanguageCode } from '@sarvam/core';

const response = await client.text.translate({
  input: 'Welcome! How may I assist you today?',
  source_language_code: LanguageCode.EN_IN,
  target_language_code: LanguageCode.HI_IN,
  speaker_gender: 'Female',
  mode: 'formal',
});

console.log(response.translated_text);
// "स्वागत है! आज मैं आपकी क्या सहायता कर सकती हूँ?"
```

### Transliterate Script
Convert Latin/English phonetics into native Indic script:

```typescript
const response = await client.text.transliterate({
  input: 'shukriya aapka bahut bahut',
  source_language_code: LanguageCode.EN_IN,
  target_language_code: LanguageCode.HI_IN,
});

console.log(response.transliterated_text);
// "शुक्रिया आपका बहुत बहुत"
```

### Language Identification (LID)
Detect the language of text with confidence scoring:

```typescript
const response = await client.text.identifyLanguage({
  input: 'நீங்கள் எப்படி இருக்கிறீர்கள்?',
});

console.log(response.detected_language); // "ta-IN" (Tamil)
console.log(response.confidence);        // 0.99
```

---

## 4. Speech-to-Text (STT)

### Batch Audio Transcription
Supports `Uint8Array`, standard `Blob`, or React Native `{ uri, name, type }` file descriptors:

```typescript
import { SttModel, LanguageCode } from '@sarvam/core';

// Pass raw audio bytes directly:
const audioBytes = new Uint8Array([...]);

const response = await client.speechToText.transcribe({
  file: audioBytes,
  model: SttModel.SAARAS_V4,
  language_code: LanguageCode.HI_IN,
});

console.log('Transcript:', response.transcript);
```

### React Native Native File Upload (`fromReactNativeUri`)
Streams local recordings directly from disk to native network sockets without reading into JavaScript memory:

```typescript
import { fromReactNativeUri, SttModel, LanguageCode } from '@sarvam/react-native';

const audioFile = fromReactNativeUri('file:///data/user/0/app/cache/recording.wav');

const response = await client.speechToText.transcribe({
  file: audioFile,
  model: SttModel.SAARAS_V4,
  language_code: LanguageCode.HI_IN,
});

console.log('Transcript:', response.transcript);
```

### Realtime STT Streaming via WebSocket
Stream 16kHz linear16 PCM audio with server-side Voice Activity Detection (VAD):

```typescript
import { SttModel, LanguageCode } from '@sarvam/core';

const session = await client.speechToText.connect({
  model: SttModel.SAARAS_V3_REALTIME,
  language_code: LanguageCode.HI_IN,
  sample_rate: 16000,
  endpointing: true,
  threshold: 0.5,
});

// 1. Consume streaming events
(async () => {
  for await (const event of session.events) {
    if (event.type === 'transcript_partial') {
      console.log('Partial:', event.text);
    } else if (event.type === 'transcript_final') {
      console.log('Final:', event.text);
    } else if (event.type === 'vad_speech_start') {
      console.log('User started speaking');
    } else if (event.type === 'vad_speech_end') {
      console.log('User finished speaking');
    }
  }
})();

// 2. Send 16kHz audio chunk
session.sendAudio(pcmChunkUint8Array);

// 3. Close when finished
session.end();
```

---

## 5. Text-to-Speech (TTS)

### REST Speech Synthesis
Generate audio bytes ready to play or save:

```typescript
import { Speaker, LanguageCode } from '@sarvam/core';

const response = await client.textToSpeech.convert({
  text: 'नमस्ते, आपका स्वागत है।',
  target_language_code: LanguageCode.HI_IN,
  speaker: Speaker.ANUSHKA,
  pace: 1.0,
});

const wavBytes = response.audioBytes; // Uint8Array
```

### HTTP Chunked Streaming Audio
Stream synthesized audio with low time-to-first-byte:

```typescript
const audioStream = await client.textToSpeech.stream({
  text: 'यह एक लंबा पाठ है जिसे तुरंत बजाया जा सकता है।',
  target_language_code: LanguageCode.HI_IN,
  speaker: Speaker.SIMRAN,
});

for await (const chunk of audioStream) {
  myAudioPlayer.playChunk(chunk);
}
```

### Bidirectional Conversational WebSocket TTS
Send text tokens dynamically as your LLM generates them:

```typescript
const ttsSession = await client.textToSpeech.connect({
  language_code: LanguageCode.HI_IN,
  speaker: Speaker.PRIYA,
});

(async () => {
  for await (const event of ttsSession.events) {
    if (event.type === 'audio') {
      myAudioPlayer.playChunk(event.audioBytes);
    } else if (event.type === 'completed') {
      console.log('Speech complete');
    }
  }
})();

ttsSession.sendText('नमस्ते! ');
ttsSession.sendText('सर्वम एआई में आपका स्वागत है।');
ttsSession.flush();
```

---

## 6. Conversational Turn-Taking (`BargeInCoordinator`)

In voice agents, if the assistant is speaking and the user interrupts, TTS audio playback must stop immediately:

```typescript
import {
  SarvamReactNativeClient,
  SarvamAudioPlayer,
  BargeInCoordinator,
} from '@sarvam/react-native';

const player = new SarvamAudioPlayer({ driver: myAudioDriver });
const sttSession = await client.speechToText.connect({ ... });

const coordinator = new BargeInCoordinator({
  session: sttSession,
  player: player,
  onBargeIn: () => {
    console.log('Barge-in detected! Ongoing audio playback cut off instantly.');
  },
});

coordinator.start();
```

---

## 7. Chat Completions & SSE Streaming

OpenAI-compatible interface powered by Sarvam Indic foundation models:

```typescript
import { ChatModel } from '@sarvam/core';

// Non-streaming:
const response = await client.chat.completions.create({
  model: ChatModel.SARVAM_M,
  messages: [
    { role: 'system', content: 'You are an Indic cultural expert.' },
    { role: 'user', content: 'Describe Diwali festival in Hindi.' },
  ],
});
console.log(response.choices[0]?.message?.content);

// Server-Sent Events (SSE) streaming:
const stream = await client.chat.completions.create({
  model: ChatModel.SARVAM_M,
  messages: [{ role: 'user', content: 'Write a poem in Bengali.' }],
  stream: true,
});

for await (const chunk of stream) {
  const token = chunk.choices[0]?.delta?.content;
  if (token) process.stdout.write(token);
}
```

---

## 8. Error Handling

Every SDK error inherits from `SarvamError`:

```typescript
import {
  SarvamError,
  AuthenticationError,
  RateLimitError,
  ServerError,
  RealtimeError,
} from '@sarvam/core';

try {
  await client.text.translate({ ... });
} catch (error) {
  if (error instanceof RateLimitError) {
    console.warn(`Rate limited. Retry after ${error.retryAfterMs}ms`);
  } else if (error instanceof AuthenticationError) {
    console.error(`Invalid API Key or expired token (Request ID: ${error.requestId})`);
  } else if (error instanceof ServerError) {
    console.error(`Sarvam server error (${error.statusCode}): ${error.message}`);
  } else if (error instanceof RealtimeError) {
    console.error(`WebSocket closed abnormally: ${error.closeCode}`);
  } else if (error instanceof SarvamError) {
    console.error(`Sarvam API error: ${error.message}`);
  }
}
```
