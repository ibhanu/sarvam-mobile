<p align="center">
  <a href="https://sarvam.ai">
    <img src="https://assets.sarvam.ai/tr:q-70,f-auto,dpr-auto/assets/og-images/home-og.png" alt="Sarvam AI - India's Sovereign AI Platform" width="100%" style="border-radius: 12px; max-width: 800px;" />
  </a>
</p>

# @sarvam-mobile/react-native

Official React Native & Expo SDK for **Sarvam AI** Indic language models, speech recognition, speech synthesis, and real-time conversational agents.

[![npm version](https://img.shields.io/npm/v/@sarvam-mobile/react-native.svg)](https://www.npmjs.com/package/@sarvam-mobile/react-native)
[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](LICENSE)
[![Rust Core Engine](https://img.shields.io/badge/Rust%20Core-WebAssembly-DEA584.svg?logo=rust)](../rust-core)
[![Hermes Ready](https://img.shields.io/badge/Hermes-100%25%20Compatible-brightgreen.svg)](https://reactnative.dev/docs/hermes)
[![Expo Ready](https://img.shields.io/badge/Expo-SDK%2050%2B-black.svg)](https://expo.dev/)

**Engineered natively for React Native and Hermes. Zero Node polyfills. Zero binary dependencies.**

---

## < 5 Minutes to First Call

### 1. Installation

Install [`@sarvam-mobile/react-native`](https://www.npmjs.com/package/@sarvam-mobile/react-native) and the core package [`@sarvam-mobile/core`](https://www.npmjs.com/package/@sarvam-mobile/core):

```bash
# In Expo projects:
npx expo install @sarvam-mobile/react-native @sarvam-mobile/core

# In React Native CLI projects:
npm install @sarvam-mobile/react-native @sarvam-mobile/core
# or
pnpm add @sarvam-mobile/react-native @sarvam-mobile/core
# or
yarn add @sarvam-mobile/react-native @sarvam-mobile/core
```

### 2. First Call (< 60 Seconds)

Initialize `SarvamReactNativeClient` and perform text translation across Indic languages:

```typescript
import { SarvamReactNativeClient, LanguageCode } from '@sarvam-mobile/react-native';

const client = new SarvamReactNativeClient({
  apiKey: 'YOUR_DEVELOPMENT_API_KEY', // For production, see TokenAuth below!
});

async function run() {
  const result = await client.text.translate({
    input: 'Where is the nearest railway station?',
    source_language_code: LanguageCode.EN_IN,
    target_language_code: LanguageCode.HI_IN, // Hindi
  });

  console.log(result.translated_text);
  // "निकटतम रेलवे स्टेशन कहाँ है?"
}

run();
```

---

## Why It Works on Hermes (Without Node `ws` or `Buffer`)

Many existing AI SDKs are designed for Node.js servers and immediately crash in React Native because they depend on Node built-ins (`buffer`, `crypto`, `stream`, `events`, `http`, `net`, and the third-party `ws` package).

`@sarvam-mobile/react-native` was built from the ground up for modern React Native:

1. **Zero Node `Buffer` Reliance**:
   - All binary audio manipulation, Base64 conversion, PCM downsampling, and RMS calculation run entirely on standard JavaScript typed arrays (`Uint8Array`, `Float32Array`, `Int16Array`, `DataView`).
   - No `buffer` polyfills or `rn-nodeify` hacks required.

2. **Native WebSocket Header Injection (No `ws` Dependency)**:
   - On native iOS and Android, React Native's native WebSocket bridge supports a 3-argument constructor: `new WebSocket(url, protocols, { headers })`.
   - `ReactNativeWebSocketFactory` detects the native Hermes/JSI runtime and automatically forwards custom headers (`Api-Subscription-Key`, `Authorization`) directly to native networking without requiring Node's `ws` library.
   - On **React Native Web** or browsers (where the W3C WebSocket standard forbids custom headers), it seamlessly falls back to subprotocol authentication (`api-subscription-key.<key>` or `bearer.<token>`).

3. **Zero Native Build Steps for Core SDK**:
   - Pure TypeScript with zero compiled C++ or native Java/Objective-C code in the core SDK.
   - 100% compatible with Expo Go and custom Expo Dev Clients without native config plugins.

---

## Mobile Authentication: `TokenAuth` & `ProxyAuth`

> [!CAUTION]
> **Never ship static API keys in mobile apps!**  
> Any string compiled into an APK or IPA can be trivially extracted in seconds using `strings` or decompilers. `ApiKeyAuth` logs an explicit warning in mobile release builds (`__DEV__ === false`).

### Recommended Mobile Pattern: `TokenAuth`

Generate short-lived ephemeral tokens from your backend server. The mobile SDK automatically handles:
- In-memory token caching.
- Proactive background refresh **60 seconds** before expiration.
- Single-flight deduplication (multiple concurrent requests wait on a single refresh call).
- Automatic invalidation and retry if an HTTP 401 or 403 occurs.

```typescript
import { SarvamReactNativeClient, TokenAuth } from '@sarvam-mobile/react-native';

const authProvider = new TokenAuth(async () => {
  // Fetch an ephemeral token from your existing backend API:
  const response = await fetch('https://api.yourcompany.com/mobile/sarvam-token', {
    headers: { Authorization: `Bearer ${userSessionToken}` },
  });
  const data = await response.json();

  return {
    token: data.ephemeralToken,
    expiresAtEpochMs: data.expiresAtMs, // e.g., Date.now() + 15 * 60 * 1000
  };
});

export const sarvam = new SarvamReactNativeClient({ authProvider });
```

### Alternative Mobile Pattern: `ProxyAuth` (BFF)

If you route requests through a Backend-For-Frontend (BFF) or API Gateway:

```typescript
import { SarvamReactNativeClient, ProxyAuth } from '@sarvam-mobile/react-native';

const authProvider = new ProxyAuth('https://api.yourcompany.com/sarvam-gateway', async () => ({
  'X-Mobile-Session': userSessionToken,
  'X-App-Version': '1.2.0',
}));

export const sarvam = new SarvamReactNativeClient({ authProvider });
```

---

## Native File Uploads: `fromReactNativeUri`

Standard browser code expects `File` or `Blob` objects for multipart uploads. In React Native, audio files recorded to disk exist as native file URIs (`file:///data/user/0/.../audio.wav` on Android or `file:///var/mobile/.../audio.m4a` on iOS).

`@sarvam-mobile/react-native` provides `fromReactNativeUri` and `ReactNativeFormDataAdapter`:

```typescript
import { SarvamReactNativeClient, fromReactNativeUri, SttModel, LanguageCode } from '@sarvam-mobile/react-native';

// 1. Point directly to a native file URI produced by expo-av, react-native-fs, etc.
const audioFile = fromReactNativeUri('file:///path/to/recorded_audio.wav');

// 2. Transcribe directly without reading the file into JS memory:
const result = await client.speechToText.transcribe({
  file: audioFile,
  model: SttModel.SAARAS_V4,
  language_code: LanguageCode.HI_IN,
});

console.log('Transcript:', result.transcript);
```

### Why this matters:
- **Zero Memory Overhead**: Large recordings stream directly from the filesystem into the native HTTP socket (OkHttp on Android, NSURLSession on iOS).
- **Automatic MIME Inference**: Automatically recognizes `.wav`, `.mp3`, `.m4a`, `.aac`, `.ogg`, and `.opus` extensions.

---

## Realtime Speech-to-Text WebSocket

Stream live microphone audio over a low-latency bidirectional WebSocket with Voice Activity Detection (VAD) and live partial transcripts.

```typescript
import {
  SarvamReactNativeClient,
  SttModel,
  LanguageCode,
  SttRealtimeEvent,
} from '@sarvam-mobile/react-native';

const client = new SarvamReactNativeClient({ authProvider });

// 1. Connect to Realtime STT WebSocket
const session = await client.speechToText.connect({
  model: SttModel.SAARAS_V3_REALTIME,
  language_code: LanguageCode.HI_IN,
  sample_rate: 16000,
  mode: 'transcribe',
  endpointing: true,       // Enable server-side VAD
  threshold: 0.5,
  silence_duration_ms: 600,
});

// 2. Consume events asynchronously
(async () => {
  for await (const event of session.events) {
    if (event.type === 'transcript_partial') {
      console.log('Listening...', event.text);
    } else if (event.type === 'transcript_final') {
      console.log('Final utterance:', event.text);
    } else if (event.type === 'vad_speech_start') {
      console.log('User started speaking');
    } else if (event.type === 'vad_speech_end') {
      console.log('User finished speaking');
    }
  }
})();

// 3. Send 16kHz linear16 PCM audio chunks (Uint8Array)
session.sendAudio(pcmChunkUint8Array);

// 4. Close session when done
session.end();
```

---

## Streaming Text-to-Speech (TTS)

Generate ultra-low-latency synthesized speech in 11+ Indic languages using `bulbul:v4-flash`.

### 1. HTTP Binary Stream
```typescript
import { Speaker, LanguageCode } from '@sarvam-mobile/react-native';

const audioStream = await client.textToSpeech.stream({
  text: 'नमस्ते, आप कैसे हैं?',
  target_language_code: LanguageCode.HI_IN,
  speaker: Speaker.ANUSHKA,
});

for await (const chunk of audioStream) {
  // Feed raw audio bytes directly into your native audio player
  myAudioPlayer.playChunk(chunk);
}
```

### 2. Bidirectional Conversational WebSocket TTS
Push text tokens as your LLM generates them and receive audio frames immediately:

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
      console.log('Playback finished');
    }
  }
})();

// Stream text incrementally
ttsSession.sendText('नमस्ते! ');
ttsSession.sendText('सर्वम एआई में आपका स्वागत है।');
ttsSession.flush();
```

---

## Audio Pipeline & Conversational Turn-Taking (`BargeInCoordinator`)

Building a voice agent on mobile requires solving two critical audio engineering challenges:
1. **Resampling**: Mobile hardware captures audio at 48kHz or 44.1kHz, while Sarvam's speech models require strict 16kHz mono linear16 PCM.
2. **Barge-In (Interruption)**: When the bot is speaking and the user begins talking, the bot must stop speaking immediately.

`@sarvam-mobile/react-native` provides built-in utilities for both:

### 1. Pure TypeScript `PcmResampler`
Downsamples 48kHz/44.1kHz mono or stereo Float32/Int16 microphone data to 16kHz mono linear16 in pure JavaScript/Hermes:

```typescript
import { PcmResampler } from '@sarvam-mobile/react-native';

const resampler = new PcmResampler({
  sourceSampleRate: 48000,
  targetSampleRate: 16000,
  channels: 1,
});

// Resample incoming audio chunks from mic driver:
const pcm16kBytes = resampler.resample(rawMicChunk);
session.sendAudio(pcm16kBytes);
```

### 2. Conversational Interruption with `BargeInCoordinator`

`BargeInCoordinator` links your active `SttRealtimeSession` directly to `SarvamAudioPlayer`. When the server-side VAD detects the user's voice (`vad_speech_start`), it instantly halts and flushes ongoing TTS playback:

```typescript
import {
  SarvamReactNativeClient,
  SarvamAudioPlayer,
  BargeInCoordinator,
} from '@sarvam-mobile/react-native';

const player = new SarvamAudioPlayer({ driver: myAudioDriver });
const session = await client.speechToText.connect({ ... });

// Set up barge-in coordinator
const coordinator = new BargeInCoordinator({
  session,
  player,
  onBargeIn: () => {
    console.log('User interrupted! Audio playback stopped instantly.');
  },
});

coordinator.start();
```

---

## Audio Driver Interface

`@sarvam-mobile/react-native` provides a clean driver interface (`ReactNativeAudioDriver`) compatible with popular audio libraries such as `react-native-audio-api`, `expo-audio`, or custom TurboModules:

```typescript
import { ReactNativeAudioDriver } from '@sarvam-mobile/react-native';

export class MyCustomAudioDriver implements ReactNativeAudioDriver {
  startRecording(onAudioData: (chunk: Float32Array) => void): void {
    // Start microphone capture and emit chunks
  }

  stopRecording(): void {
    // Stop microphone capture
  }

  playChunk(pcmBytes: Uint8Array): void {
    // Play PCM audio chunk
  }

  stopPlayback(): void {
    // Stop playback
  }

  flushPlayback(): void {
    // Flush buffered audio
  }

  getSampleRate(): number {
    return 48000;
  }
}
```

---

## Canonical Error Handling

```typescript
import {
  SarvamError,
  AuthenticationError,
  RateLimitError,
  ServerError,
  RealtimeError,
} from '@sarvam-mobile/react-native';

try {
  await client.text.translate({ ... });
} catch (error) {
  if (error instanceof RateLimitError) {
    Alert.alert('Too Many Requests', `Please wait ${error.retryAfterMs}ms`);
  } else if (error instanceof AuthenticationError) {
    Alert.alert('Session Expired', 'Please re-authenticate with your server.');
  } else if (error instanceof RealtimeError) {
    console.error('WebSocket disconnected with code:', error.closeCode);
  } else if (error instanceof SarvamError) {
    Alert.alert('Sarvam Error', error.message);
  }
}
```

---

## Example App

Check out the fully functional sample application in [`example/App.tsx`](example/App.tsx) demonstrating:
- Live Indic real-time captions with VAD.
- Translate-and-Speak screen with streaming TTS.
- Voice activity meter.
- Conversational turn-taking with `BargeInCoordinator`.

---

## 🦀 Shared Rust Core Integration (Hermes & WebAssembly)

`@sarvam-mobile/react-native` inherits the shared native [`sarvam-rust-core`](../rust-core) engine via WebAssembly integration in `@sarvam-mobile/core`:

- **Zero Hermes Degradation**: 16 kHz mono linear-16 PCM audio downsampling uses the SIMD-optimized Rust DSP resampler without requiring native C++ CocoaPods or Android Gradle native linking.
- **Identical Mobile Resilience**: Token expiration, single-flight request coalescing, and exponential jitter backoff match the iOS Swift and Android Kotlin SDK implementations to the exact millisecond.
- **Expo & Bare React Native**: Works seamlessly in Expo managed workflows, Bare React Native, and new architecture (Fabric/TurboModules) without native pod compilation steps.

---

## License

MIT © [Sarvam AI](https://sarvam.ai)
