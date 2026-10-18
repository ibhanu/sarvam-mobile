<p align="center">
  <a href="https://sarvam.ai">
    <img src="https://raw.githubusercontent.com/ibhanu/sarvam-mobile/main/assets/sarvam-ai-website.png" alt="Sarvam AI - India's Sovereign AI Platform" width="100%" style="border-radius: 12px; max-width: 860px; box-shadow: 0 8px 30px rgba(0,0,0,0.12);" />
  </a>
</p>

# sarvam

[![pub package](https://img.shields.io/pub/v/sarvam.svg)](https://pub.dev/packages/sarvam)
[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](https://opensource.org/licenses/MIT)
[![Rust Core FFI](https://img.shields.io/badge/Rust%20Core-dart%3Affi-DEA584.svg?logo=rust)](../../rust-core)
[![Platforms: Flutter & Dart](https://img.shields.io/badge/Platforms-Android%20%7C%20iOS%20%7C%20macOS%20%7C%20Windows%20%7C%20Linux%20%7C%20Web-blue)](https://pub.dev/packages/sarvam)

The official Dart and Flutter client SDK for [Sarvam AI](https://sarvam.ai)'s Indic language models, speech recognition (STT), speech synthesis (TTS), text translation, transliteration, and conversational AI.

Designed from the ground up for high-performance mobile and cross-platform applications:
- **Pure Dart Core**: Zero `dart:io` runtime dependencies in the core pipeline — works seamlessly on **Flutter Web**, iOS, Android, macOS, Windows, Linux, and server-side Dart runtimes.
- **Mobile-Ready Security**: First-class support for short-lived token auth with proactive refresh and Backend-For-Frontend (BFF) proxy architecture.
- **Enterprise Resilience**: Automatic exponential backoff with full jitter, Rate Limit (`429`) `Retry-After` header parsing, and connection reuse.
- **Full Spectrum Indic Support**: State-of-the-art models for 22+ Indic languages and English (including `Saaras V3`, `Bulbul V4`, `Sarvam 105B`, and `Sarvam-M`).

---

## < 5 Minutes to First Call

### 1. Install

Add `sarvam` to your `pubspec.yaml`:

```bash
# For Flutter projects:
flutter pub add sarvam

# For standalone Dart / Server-side projects:
dart pub add sarvam
```

### 2. Quickstart Code

```dart
import 'package:sarvam/sarvam.dart';

void main() async {
  // 1. Initialize the client (use API key for scripts/CLI, or TokenAuth for mobile)
  final client = SarvamClient.withApiKey('YOUR_SARVAM_API_KEY');

  try {
    // 2. Translate text into Hindi
    final translation = await client.text.translate(
      const TranslateRequest(
        input: 'Welcome to Sarvam AI voice and language services!',
        targetLanguageCode: LanguageCode.hiIn,
      ),
    );
    print('Hindi Translation: ${translation.translatedText}');

    // 3. Synthesize speech in an Indic language (Bulbul V4)
    final ttsResponse = await client.textToSpeech.convert(
      const TextToSpeechRequest(
        text: 'नमस्ते! सर्वम एआई में आपका स्वागत है।',
        targetLanguageCode: LanguageCode.hiIn,
        speaker: Speaker.anushka,
        model: TtsModel.bulbulV4Flash,
      ),
    );
    print('Generated audio size: ${ttsResponse.firstAudioByteLength} bytes');

    // 4. Stream chat completion tokens (OpenAI-compatible)
    final stream = client.chat.completionsStream(
      const ChatCompletionRequest(
        model: 'sarvam-m',
        messages: [
          ChatMessage(role: 'user', content: 'What is the capital of Karnataka?'),
        ],
      ),
    );

    await for (final chunk in stream) {
      final delta = chunk.firstDeltaContent;
      if (delta != null) {
        print(delta);
      }
    }
  } on SarvamException catch (e) {
    print('Sarvam error [${e.code}]: ${e.message}');
  } finally {
    // 5. Clean up connection pool resources
    client.close();
  }
}
```

---

## Authentication & Mobile Security

In accordance with modern mobile application security best practices, **never compile long-lived API keys directly into mobile client binaries** (`apk`, `ipa`). Sarvam provides three distinct authentication strategies:

### 1. Ephemeral Token Auth (Recommended for Mobile Apps)

Initialize the client with an asynchronous token provider that fetches short-lived credentials from your backend server. The SDK automatically caches the token, refreshes it proactively before expiry, and deduplicates concurrent refresh requests:

```dart
final client = SarvamClient.withTokenProvider(() async {
  // Call your existing backend service to retrieve a short-lived token
  final response = await myBackend.fetchSarvamSessionToken();
  return AuthToken(
    token: response.token,
    expiresAt: DateTime.now().add(Duration(seconds: response.expiresInSeconds)),
  );
});
```

### 2. Backend-For-Frontend (BFF) Proxy (Recommended for Enterprise)

Route all API calls through your existing application gateway. No Sarvam credentials ever exist on the client device:

```dart
final client = SarvamClient.withProxy(
  'https://api.mycompany.com/sarvam-proxy',
  headersProvider: () => {
    'Authorization': 'Bearer ${myAppSession.jwtToken}',
  },
);
```

### 3. Static API Key (CLI, Server & Rapid Prototyping)

For server-side Dart services, local debugging, or CI environments:

```dart
final client = SarvamClient.withApiKey(Platform.environment['SARVAM_API_KEY']!);
```

---

## Core Capabilities & Features

### 1. Text Translation, Transliteration & Language Identification (`client.text`)

```dart
// Text Translation
final translation = await client.text.translate(
  const TranslateRequest(
    input: 'Where can I find the nearest metro station?',
    sourceLanguageCode: LanguageCode.enIn,
    targetLanguageCode: LanguageCode.taIn,
    speakerGender: 'Female',
  ),
);
print(translation.translatedText);

// Script Transliteration (e.g. English script to Devanagari script)
final translit = await client.text.transliterate(
  const TransliterateRequest(
    input: 'namaste dosto',
    sourceLanguageCode: LanguageCode.enIn,
    targetLanguageCode: LanguageCode.hiIn,
  ),
);
print(translit.transliteratedText);

// Language Identification (LID)
final lid = await client.text.identifyLanguage(
  const IdentifyLanguageRequest(
    input: 'ఎలా ఉన్నారు మీరు?',
  ),
);
print('Detected language: ${lid.languageCode?.value} (Confidence: ${lid.confidence})');
```

---

### 2. Speech-to-Text (STT) (`client.speechToText`)

#### Unary File Transcription

Transcribe audio files in any standard audio format (`wav`, `mp3`, `m4a`, `flac`, etc.) using `SarvamFileInput`:

```dart
import 'dart:io';

final audioBytes = await File('sample.wav').readAsBytes();

final result = await client.speechToText.transcribe(
  file: SarvamFileInput.fromBytes(
    'file',
    audioBytes,
    filename: 'sample.wav',
    contentType: 'audio/wav',
  ),
  model: SttModel.saarasV3,
  languageCode: LanguageCode.hiIn,
);
print('Transcript: ${result.transcript}');
```

#### Realtime Bi-directional Streaming STT (WebSocket)

Connect to low-latency bi-directional speech recognition with server-side Voice Activity Detection (VAD) events:

```dart
final session = await client.speechToText.connect(
  const SttRealtimeConfig(
    languageCode: LanguageCode.hiIn,
    model: SttModel.saarasV3Realtime,
    sampleRate: 16000,
    endpointing: true,
  ),
);

// Listen to server events
session.events.listen((event) {
  if (event is InterimTranscript) {
    print('Interim: ${event.transcript}');
  } else if (event is FinalTranscript) {
    print('Final: ${event.transcript}');
  } else if (event is VadSpeechStart) {
    print('User started speaking (VAD Speech Start)');
  } else if (event is VadSpeechEnd) {
    print('User finished speaking (VAD Speech End)');
  }
});

// Stream 16 kHz mono linear16 PCM audio frames
session.sendAudio(pcmChunk16k);

// Terminate session
session.end();
await session.close();
```

> **Tip:** For turn-key microphone streaming, real-time 16 kHz resampling, and audio playback in Flutter, install the companion package [`sarvam_flutter_audio`](https://pub.dev/packages/sarvam_flutter_audio).

---

### 3. Text-to-Speech (TTS) (`client.textToSpeech`)

#### Unary Speech Synthesis

Generate natural Indic voices powered by `Bulbul V4`:

```dart
final response = await client.textToSpeech.convert(
  const TextToSpeechRequest(
    text: 'Sarvam AI is empowering every Indian language on mobile.',
    targetLanguageCode: LanguageCode.enIn,
    speaker: Speaker.anushka,
    model: TtsModel.bulbulV4Flash,
    outputAudioCodec: AudioCodec.mp3,
  ),
);

// Access raw audio bytes
final Uint8List audioBytes = response.audioBytes;
```

#### Chunked HTTP Audio Streaming

Receive audio chunks progressively for immediate playback without waiting for complete synthesis:

```dart
final audioStream = client.textToSpeech.stream(
  const TextToSpeechRequest(
    text: 'A very long story or news article to be read aloud...',
    targetLanguageCode: LanguageCode.hiIn,
    speaker: Speaker.rahul,
    outputAudioCodec: AudioCodec.wav,
  ),
);

await for (final Uint8List chunk in audioStream) {
  // Feed chunk directly to your audio player
}
```

#### Low-Latency WebSocket TTS Streaming

Stream text incrementally and synthesize speech in real time with sub-second time-to-first-byte (TTFB):

```dart
final ttsSession = await client.textToSpeech.connect(
  const TtsStreamingConfig(
    languageCode: LanguageCode.hiIn,
    speaker: Speaker.anushka,
    model: TtsModel.bulbulV4Flash,
  ),
);

ttsSession.events.listen((event) {
  if (event is TtsAudioChunk) {
    // Play received PCM audio chunk
  } else if (event is TtsCompleted) {
    print('Audio generation complete');
  }
});

// Send text tokens as LLM outputs them
ttsSession.sendText('नमस्ते, ');
ttsSession.sendText('सर्वम एआई में ');
ttsSession.sendText('आपका स्वागत है।');
ttsSession.flush();
```

---

### 4. Conversational Chat Completions (`client.chat`)

#### Unary Completions

```dart
final completion = await client.chat.completions(
  const ChatCompletionRequest(
    model: 'sarvam-105b',
    messages: [
      ChatMessage(role: 'system', content: 'You are a helpful Indic assistant.'),
      ChatMessage(role: 'user', content: 'Explain quantum computing in Hindi.'),
    ],
    temperature: 0.7,
  ),
);
print(completion.choices.first.message?.content);
```

#### SSE Streaming Token Deltas

```dart
final stream = client.chat.completionsStream(
  const ChatCompletionRequest(
    model: 'sarvam-105b',
    messages: [
      ChatMessage(role: 'user', content: 'Write a poem about monsoons in Marathi.'),
    ],
  ),
);

await for (final chunk in stream) {
  final text = chunk.firstDeltaContent;
  if (text != null) {
    stdout.write(text);
  }
}
```

#### Multi-Turn Session Affinity

Maintain session stickiness across geographically distributed clusters:

```dart
final chatSession = client.chat.session();

final res1 = await chatSession.completions(
  const ChatCompletionRequest(
    model: 'sarvam-m',
    messages: [ChatMessage(role: 'user', content: 'My name is Rahul.')],
  ),
);

final res2 = await chatSession.completions(
  const ChatCompletionRequest(
    model: 'sarvam-m',
    messages: [ChatMessage(role: 'user', content: 'What is my name?')],
  ),
);
```

---

### 5. Enterprise Async Jobs & Document AI

For long-running tasks, the SDK provides built-in Azure Blob SAS uploading, status tracking, and automated exponential polling via `JobPoller`:

- **Document AI (`client.docAi`)**: Extract structured content, tables, and text from PDFs and scanned documents.
- **Batch STT (`client.speechToTextJob`)**: Transcribe hours of recorded audio asynchronously.
- **Document Translation (`client.documentTranslation`)**: Translate full PDF, DOCX, and PPTX documents while preserving layout.
- **Dubbing (`client.dubbing`)**: Multi-lingual video and audio dubbing pipelines.
- **Custom Voices (`client.voiceCloning`)**: Register custom speaker profiles for personalized TTS.

---

## Error Handling

All errors thrown by the SDK inherit from `SarvamException`, providing machine-readable error codes and HTTP metadata:

```dart
try {
  await client.text.translate(...);
} on AuthenticationException catch (e) {
  print('Invalid or expired authentication credentials: ${e.message}');
} on RateLimitException catch (e) {
  print('Rate limited! Retry after ${e.retryAfterMs} ms');
} on BadRequestException catch (e) {
  print('Invalid request parameters: ${e.message}');
} on NotFoundException catch (e) {
  print('Resource not found: ${e.message}');
} on ServerException catch (e) {
  print('Server error [${e.statusCode}]: ${e.message}');
} on NetworkException catch (e) {
  print('Network connection failure: ${e.message}');
} on TimeoutException catch (e) {
  print('Operation timed out: ${e.message}');
} on SarvamException catch (e) {
  print('Generic Sarvam error: ${e.message}');
}
```

---

## 🦀 Unified Rust Core Engine (`dart:ffi`)

The `sarvam` package integrates with [`packages/rust-core`](../../rust-core) via `dart:ffi` (`SarvamRustBridge`):

- **Zero-Copy Native Audio Downsampling**: Hardware microphone buffers are downsampled to 16 kHz mono linear-16 PCM via SIMD-optimized Rust DSP algorithms (`libsarvam_rust_core.so` on Android/Linux, `libsarvam_rust_core.dylib` on macOS/iOS).
- **Synchronized Exponential Jitter Backoff**: Exactly mirrors the canonical retry curves of the cloud platform and native sister SDKs.
- **Graceful Web & Pure-Dart Fallback**: When running on Flutter Web or constrained environments where dynamic C libraries cannot be loaded, `SarvamRustBridge` automatically and silently falls back to pure Dart resampling and backoff math with zero runtime exceptions.

```dart
import 'dart:typed_data';
import 'package:sarvam/src/rust/sarvam_rust_bridge.dart';

final bridge = SarvamRustBridge.instance;

// 1. Resample 48 kHz microphone stream to 16 kHz mono linear-16 PCM
final Uint8List resampledPcm = bridge.resampleAudio(
  rawMicrophoneBytes,
  sourceSampleRate: 48000,
  channels: 1,
);

// 2. Evaluate retry backoff with full jitter
final int delayMs = bridge.computeRetryDelay(
  attempt: 2,
  statusCode: 429,
  retryAfterSeconds: 3,
);
```

---

## Companion Packages

- [`sarvam_flutter_audio`](https://pub.dev/packages/sarvam_flutter_audio): Microphone capture, pure Dart 16 kHz linear16 resampling, chunked audio playback, and sub-20ms conversational barge-in coordination.

---

## License

This SDK is distributed under the [MIT License](LICENSE).
