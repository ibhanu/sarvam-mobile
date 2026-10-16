# Changelog

All notable changes to the Sarvam AI Kotlin & Android SDK will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

---

## [0.1.0] - 2026-10-16

### Added

#### `ai.sarvam:sarvam-core`
- **Core Architecture & Client Builder**:
  - `SarvamClient`: Main entry point with fluent `Builder` and Kotlin DSL factory `sarvamClient { ... }`.
  - `SarvamEnvironment`: Multi-host endpoint routing for REST API (`https://api.sarvam.ai`), Dubbing API (`https://api.sarvam.ai/dubbing`), and WebSocket services (`wss://api.sarvam.ai`). Support for Backend-For-Frontend (BFF) URL redirection.
  - `OkHttpTransport`: Clean HTTP transport with connection pooling and coroutine integration.
  - `OkHttpWebSocketFactory`: Full WebSocket lifecycle factory supporting subprotocols and binary/text frames.
  - Interceptor pipeline with extensible `Middleware` interface.

- **Mobile Security & Authentication**:
  - `AuthProvider` abstraction decoupling credential resolution from networking.
  - `TokenAuth`: Ephemeral bearer token provider with single-flight mutex deduplication and proactive background refresh (60 seconds prior to expiration). Automatic invalidation and single-retry recovery on HTTP 401/403.
  - `ProxyAuth`: BFF proxy authentication forwarding app-specific session headers to self-hosted proxies.
  - `ApiKeyAuth`: Static subscription key provider for prototyping and backend environments.

- **Resilience & Network Robustness**:
  - `RetryMiddleware`: Exponential backoff with full jitter (Google AIP-4221), configurable retry ceilings, and strict adherence to idempotency rules.
  - Automated retry on HTTP 429 (Rate Limit) and 503 (Service Unavailable) parsing RFC 7231 `Retry-After` header delays.
  - `UserAgentMiddleware`: RFC 7231 compliant telemetry agent reporting SDK version, runtime, and platform architecture.
  - `LoggingMiddleware`: Configurable request/response logging across `NONE`, `BASIC`, `HEADERS`, and `BODY`.

- **Indic Text AI (`TextResource`)**:
  - `translate`: High-accuracy text translation across 22+ Indic languages (`LanguageCode`).
  - `transliterate`: Cross-script phonetic transliteration.
  - `identifyLanguage`: Multilingual language identification (LID) with confidence scoring.

- **Speech-to-Text (`SpeechToTextResource` & `SttRealtimeSession`)**:
  - Batch audio transcription (`transcribe`) and translation (`translate`) via multipart file uploads (`FileInput`).
  - Sub-word timestamps and speaker diarization support.
  - Real-time bidirectional WebSocket session (`connect` returning `SttRealtimeSession`).
  - Real-time VAD events (`VadSpeechStart`, `VadSpeechEnd`), partial transcripts (`TranscriptPartial`), and finalized transcripts (`TranscriptFinal`).
  - In-flight session configuration updates (`updateConfig`) for mode, silence thresholds, and custom keyterms.
  - Client-side sample rate guard (enforcing 8 kHz or 16 kHz).

- **Text-to-Speech (`TextToSpeechResource` & `TtsStreamingSession`)**:
  - Batch synthesis (`convert`) returning decoded `ByteArray` audio buffers.
  - Chunked HTTP streaming (`stream`) returning reactive coroutine `Flow<ByteArray>`.
  - Full-duplex WebSocket session (`connect` returning `TtsStreamingSession`) with Bulbul v4 Flash and v3 models.
  - Configurable pitch, pace, loudness, and custom speaker profiles (`Speaker`).

- **Conversational AI (`ChatResource` & `ChatSession`)**:
  - Support for `sarvam-105b`, `sarvam-m`, `gemma4`, and `deepseek-v4.1-flash` models.
  - Chat completions (`completions` and `completionsV2`) with SSE streaming (`completionsV2Stream`).
  - `ChatSession` abstraction with automated session affinity routing (`x-session-affinity` header).
  - Model catalog endpoints (`listModels`, `getModel`).

- **Document AI (`DocAiResource`)**:
  - Multilingual document digitisation (`digitise`) and structured data extraction (`extract`).
  - Presigned upload URL generation (`createUploadUrl`).
  - Built-in polling helpers (`digitiseAndWait`, `extractAndWait`) with configurable backoff and timeout ceilings.

- **Enterprise & Job Workflows**:
  - `VoiceCloningResource`: Voice creation, conversion, and stream cloning.
  - `PronunciationDictionaryResource`: Custom pronunciation dictionary management.
  - `SpeechToTextJobResource` & `SpeechToTextTranslateJobResource`: Async batch audio processing.
  - `DocumentTranslationResource` & `DubbingResource`: Long-running video dubbing and document translation jobs.

- **Typed Error Hierarchy (`SarvamException`)**:
  - Sealed class taxonomy: `AuthenticationException`, `PermissionDeniedException`, `BadRequestException`, `NotFoundException`, `PayloadTooLargeException`, `UnprocessableEntityException`, `RateLimitException`, `ServerException`, `ConnectionException`, `TimeoutException`, `StreamException`, `RealtimeException`.
  - Request IDs, status codes, and unparsed body payloads exposed for debugging.

#### `ai.sarvam:sarvam-android-audio`
- **Microphone Streaming (`SarvamMicStreamer`)**:
  - Continuous audio capture via `AudioCaptureDriver`.
  - Backpressure protection with bounded channel capacity and `DROP_OLDEST` strategy.
  - Continuous audio level and RMS calculations (`AudioLevel`) for UI visualizers.
- **Resampling (`PcmResampler`)**:
  - Linear interpolation resampler converting arbitrary device sample rates (e.g., 44.1 kHz, 48 kHz) to 16 kHz mono PCM.
- **Audio Playback (`SarvamAudioPlayer`)**:
  - Direct PCM audio chunk and `Flow<ByteArray>` stream playback via `AudioPlaybackDriver`.
  - Ultra-fast `stopAndFlush()` for sub-20ms audio track halt and buffer purge.
- **Full-Duplex Interruption (`BargeInCoordinator`)**:
  - Coordinates `SttRealtimeSession` VAD events (`VadSpeechStart`) with `SarvamAudioPlayer.stopAndFlush()`.
- **Runtime Reflection Drivers**:
  - `AndroidAudioRecordCaptureDriver` and `AndroidAudioTrackPlaybackDriver` resolve Android SDK APIs dynamically at runtime, allowing pure JVM unit tests without android.jar dependencies.
  - `ByteArrayAudioCaptureDriver` and `MemoryAudioPlaybackDriver` for automated testing.

### Security
- Zero static credentials bundled in SDK packages.
- Strict TLS 1.3/1.2 transport enforcement.
- Proactive token renewal with automatic single-flight retry on token expiration.
