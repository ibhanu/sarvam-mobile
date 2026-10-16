# Sarvam AI Dart & Flutter SDK: Quickstart Snippets

Complete, production-ready code snippets for integrating Sarvam AI's Indic language models, speech recognition (STT), speech synthesis (TTS), translation, and real-time conversational voice agents in Dart and Flutter.

---

## 1. Installation

Add the packages to your project:

```bash
# Core SDK (Pure Dart — works in Flutter Mobile, Web, Desktop, and Server Dart):
flutter pub add sarvam

# Companion audio package (Microphone streaming, 16 kHz resampling, and barge-in):
flutter pub add sarvam_flutter_audio
```

Or manually in `pubspec.yaml`:

```yaml
dependencies:
  sarvam: ^0.1.0
  sarvam_flutter_audio: ^0.1.0
```

---

## 2. Authentication Patterns

### A. Ephemeral Token Auth (Recommended for Mobile Apps)

In mobile applications, avoid compiling long-lived API keys into binaries. Instead, initialize the client with an asynchronous `tokenProvider`. The SDK automatically caches the token, refreshes it before expiry, and deduplicates concurrent refresh calls:

```dart
import 'package:sarvam/sarvam.dart';

final client = SarvamClient.withTokenProvider(() async {
  // Call your existing mobile backend to fetch a short-lived token
  final response = await myBackendService.getSarvamSessionToken();
  return AuthToken(
    token: response.token,
    expiresAt: DateTime.now().add(Duration(seconds: response.expiresInSeconds)),
  );
});
```

### B. Backend-For-Frontend (BFF) Proxy Auth (Enterprise Standard)

Route all API and WebSocket requests through your backend gateway with custom session headers:

```dart
import 'package:sarvam/sarvam.dart';

final client = SarvamClient.withProxy(
  'https://api.mycompany.com/sarvam-proxy',
  headersProvider: () => {
    'Authorization': 'Bearer ${userSession.accessToken}',
    'X-App-Version': '2.4.0',
  },
);
```

### C. Static API Key (CLI, Server & Rapid Prototyping)

For server-side Dart applications, tools, or local developer scripts:

```dart
import 'dart:io';
import 'package:sarvam/sarvam.dart';

final client = SarvamClient.withApiKey(
  Platform.environment['SARVAM_API_KEY']!,
);
```

---

## 3. Text Translation, Transliteration & Language ID

```dart
import 'package:sarvam/sarvam.dart';

// 1. Text Translation
final translation = await client.text.translate(
  const TranslateRequest(
    input: 'Where is the baggage claim area?',
    sourceLanguageCode: LanguageCode.enIn,
    targetLanguageCode: LanguageCode.hiIn,
    speakerGender: 'Female',
  ),
);
print('Hindi translation: ${translation.translatedText}');

// 2. Script Transliteration (Romanized script to Devanagari)
final transliteration = await client.text.transliterate(
  const TransliterateRequest(
    input: 'shubh prabhat',
    sourceLanguageCode: LanguageCode.enIn,
    targetLanguageCode: LanguageCode.hiIn,
  ),
);
print('Transliterated: ${transliteration.transliteratedText}');

// 3. Language Identification (LID)
final lid = await client.text.identifyLanguage(
  const IdentifyLanguageRequest(
    input: 'வணக்கம், நீங்கள் எப்படி இருக்கிறீர்கள்?',
  ),
);
print('Detected language: ${lid.languageCode?.value} (Confidence: ${lid.confidence})');
```

---

## 4. Speech-to-Text (STT) File Transcription

Transcribe recorded audio using `SarvamFileInput` (zero `dart:io` dependency):

```dart
import 'dart:typed_data';
import 'package:sarvam/sarvam.dart';

Future<void> transcribeAudio(Uint8List audioBytes) async {
  final response = await client.speechToText.transcribe(
    file: SarvamFileInput.fromBytes(
      'file',
      audioBytes,
      filename: 'recording.wav',
      contentType: 'audio/wav',
    ),
    model: SttModel.saarasV3,
    languageCode: LanguageCode.hiIn,
  );

  print('Transcription: ${response.transcript}');
}
```

---

## 5. Text-to-Speech (TTS) Synthesis & Streaming

### Unary Speech Generation

```dart
import 'dart:typed_data';
import 'package:sarvam/sarvam.dart';

final response = await client.textToSpeech.convert(
  const TextToSpeechRequest(
    text: 'सर्वम एआई में आपका स्वागत है।',
    targetLanguageCode: LanguageCode.hiIn,
    speaker: Speaker.anushka,
    model: TtsModel.bulbulV4Flash,
    outputAudioCodec: AudioCodec.mp3,
  ),
);

// Decoded raw bytes ready for audio player or disk storage
final Uint8List audioBytes = response.audioBytes;
```

### HTTP Chunked Binary Streaming

```dart
import 'dart:typed_data';
import 'package:sarvam/sarvam.dart';

final stream = client.textToSpeech.stream(
  const TextToSpeechRequest(
    text: 'A long article or notification message being synthesized continuously...',
    targetLanguageCode: LanguageCode.enIn,
    speaker: Speaker.rahul,
    outputAudioCodec: AudioCodec.wav,
  ),
);

await for (final Uint8List chunk in stream) {
  // Feed chunk to audio buffer for progressive playback
}
```

---

## 6. Realtime Bi-directional STT WebSocket Streaming

```dart
import 'dart:typed_data';
import 'package:sarvam/sarvam.dart';

Future<void> streamRealtimeStt() async {
  final session = await client.speechToText.connect(
    const SttRealtimeConfig(
      languageCode: LanguageCode.hiIn,
      model: SttModel.saarasV3Realtime,
      sampleRate: 16000,
      endpointing: true,
    ),
  );

  // Handle server events
  session.events.listen((event) {
    if (event is InterimTranscript) {
      print('Interim: ${event.transcript}');
    } else if (event is FinalTranscript) {
      print('Final: ${event.transcript}');
    } else if (event is VadSpeechStart) {
      print('User started speaking (VAD)');
    } else if (event is VadSpeechEnd) {
      print('User stopped speaking (VAD)');
    }
  });

  // Send 16 kHz mono linear16 audio chunks
  // session.sendAudio(pcm16kChunk);

  // Clean shutdown
  // session.end();
  // await session.close();
}
```

---

## 7. Chat Completions (Unary & SSE Streaming)

### Unary Completion

```dart
import 'package:sarvam/sarvam.dart';

final response = await client.chat.completions(
  const ChatCompletionRequest(
    model: 'sarvam-105b',
    messages: [
      ChatMessage(role: 'system', content: 'You are an Indic language AI assistant.'),
      ChatMessage(role: 'user', content: 'What are the main agricultural crops in Punjab?'),
    ],
    temperature: 0.5,
  ),
);

print(response.choices.first.message?.content);
```

### Streaming Token Deltas (SSE)

```dart
import 'dart:io';
import 'package:sarvam/sarvam.dart';

final stream = client.chat.completionsStream(
  const ChatCompletionRequest(
    model: 'sarvam-m',
    messages: [
      ChatMessage(role: 'user', content: 'Tell me a short story in Kannada.'),
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

---

## 8. Real-time Voice Agent Pipeline with Conversational Barge-In

Combine `sarvam` and `sarvam_flutter_audio` to build a sub-20ms latency conversational voice assistant:

```dart
import 'package:flutter/widgets.dart';
import 'package:sarvam/sarvam.dart';
import 'package:sarvam_flutter_audio/sarvam_flutter_audio.dart';

Future<void> runVoiceAssistant() async {
  final client = SarvamClient.withApiKey('YOUR_SARVAM_API_KEY');

  // 1. Audio drivers (plug in your hardware driver or in-memory mock)
  final recordDriver = MemoryAudioRecordDriver(sampleRate: 48000, channelCount: 1);
  final playDriver = MemoryAudioPlayDriver();

  // 2. Chunked audio player for playback
  final player = SarvamChunkedAudioPlayer(driver: playDriver);

  // 3. Connect STT WebSocket
  final sttSession = await client.speechToText.connect(
    const SttRealtimeConfig(
      languageCode: LanguageCode.hiIn,
      model: SttModel.saarasV3Realtime,
      sampleRate: 16000,
      endpointing: true,
    ),
  );

  // 4. Attach Barge-In Coordinator:
  // When user speaks (VadSpeechStart), player halts and flushes in < 20ms
  final coordinator = BargeInCoordinator(
    session: sttSession,
    player: player,
    onBargeIn: (event) {
      print('⚡ Barge-in: user interrupted assistant speech!');
    },
  )..start();

  // 5. Microphone streamer with resampling to 16 kHz and backpressure handling
  final micStreamer = SarvamMicStreamer(
    driver: recordDriver,
    session: sttSession,
    maxQueueSize: 10,
    onAudioLevel: (level) {
      // Animate microphone sound wave in UI:
      // level.rms (0.0 - 1.0), level.dbFs (-100 to 0 dBFS)
    },
  );

  await micStreamer.start();

  // 6. Handle finalized user speech and trigger streaming reply
  sttSession.events.listen((event) async {
    if (event is FinalTranscript) {
      print('User said: ${event.transcript}');

      // Open TTS WebSocket session
      final ttsSession = await client.textToSpeech.connect(
        const TtsStreamingConfig(
          languageCode: LanguageCode.hiIn,
          speaker: Speaker.anushka,
          model: TtsModel.bulbulV4Flash,
        ),
      );

      // Play audio chunks as they arrive
      player.attachSession(ttsSession);

      // Stream response text
      ttsSession.sendText('नमस्ते! आपकी क्या सहायता कर सकता हूँ?');
      ttsSession.flush();
    }
  });
}
```

---

## 9. Error Handling & Resilience

```dart
import 'package:sarvam/sarvam.dart';

try {
  final res = await client.text.translate(...);
} on AuthenticationException catch (e) {
  // Invalid or expired API token / key
  print('Auth error [${e.code}]: ${e.message}');
} on RateLimitException catch (e) {
  // HTTP 429: wait for retryAfterMs before retrying
  print('Rate limited! Retry after ${e.retryAfterMs} ms');
} on BadRequestException catch (e) {
  // Invalid input parameters or unsupported language code
  print('Bad request: ${e.message}');
} on NotFoundException catch (e) {
  // Endpoint or resource ID not found
  print('Not found: ${e.message}');
} on ServerException catch (e) {
  // HTTP 5xx server-side error
  print('Server error [${e.statusCode}]: ${e.message}');
} on NetworkException catch (e) {
  // Socket failure, offline, or DNS resolution failure
  print('Network failure: ${e.message}');
} on TimeoutException catch (e) {
  // Request timed out
  print('Timeout: ${e.message}');
} on SarvamException catch (e) {
  // Base exception for all SDK errors
  print('Sarvam SDK error: ${e.message}');
}
```
