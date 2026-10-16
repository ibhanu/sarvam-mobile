# Changelog

All notable changes to the Sarvam AI Swift SDK will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [0.2.1](https://github.com/ibhanu/sarvam-mobile/compare/swift-v0.2.0...swift-v0.2.1) (2026-10-16)


### Bug Fixes

* update repository and issue tracker URLs to ibhanu/sarvam-mobile and bump dart SDKs to 0.2.1 ([a2c1ab1](https://github.com/ibhanu/sarvam-mobile/commit/a2c1ab1f354719724e02c629f34a3a4f1efb7646))

## [0.2.0](https://github.com/ibhanu/sarvam-mobile/compare/swift-v0.1.0...swift-v0.2.0) (2026-10-16)


### Features

* initial commit of Sarvam Mobile SDKs monorepo ([8114f80](https://github.com/ibhanu/sarvam-mobile/commit/8114f80d555332f8fca3f3c84cd720543b42746c))
* **release:** configure multi-registry publishing, licenses, and GitHub Actions release pipeline ([3ab9d6b](https://github.com/ibhanu/sarvam-mobile/commit/3ab9d6bf3e1bcc39ce127d8c2a47298744adae7e))

## [0.1.0] - 2026-10-16

### Added

- **Core `Sarvam` Library (`packages/swift/Sources/Sarvam`)**:
  - Implemented `SarvamClient` thread-safe, immutable facade conforming to Swift 6 strict concurrency (`Sendable`).
  - Added multi-base URL routing across REST (`apiBaseUrl`), Dubbing (`dubbingBaseUrl`), and WebSockets (`wsBaseUrl`).
  - Added **Mobile Authentication Architecture**:
    - `TokenAuth`: Actor-backed dynamic token auth provider with single-flight refresh deduplication and 60-second proactive expiry buffer.
    - `ProxyAuth`: Backend-For-Frontend (BFF) proxy authentication supporting custom authorization headers and URL routing.
    - `ApiKeyAuth`: Static subscription key provider for sandbox development.
  - **Text Operations (`TextResource`)**:
    - `translate`: High-accuracy translation across 11 Indic languages and English.
    - `transliterate`: Script transliteration into native Indic scripts.
    - `identifyLanguage`: Text language identification (LID) with confidence scoring.
  - **Speech-to-Text (`SpeechToTextResource`)**:
    - `transcribe` & `translate`: Saaras speech file transcription and direct English translation via multipart streaming.
    - `connect`: Real-time bidirectional WebSocket session (`SttRealtimeSession`) supporting partial/final transcripts, VAD speech boundaries, and dynamic config updates.
  - **Text-to-Speech (`TextToSpeechResource`)**:
    - `convert`: Speech synthesis returning raw audio bytes and base64 payloads.
    - `stream`: Real-time HTTP chunked binary audio streaming via `AsyncThrowingStream<Data, Error>`.
    - `connect`: WebSocket TTS streaming session (`TtsStreamingSession`) with audio chunk events.
  - **Chat Completions (`ChatResource` & `ChatSession`)**:
    - V1 OpenAI-compatible unary and SSE streaming completions.
    - V2 Sarvam foundation model completions (`sarvam-105b`, `sarvam-m`, etc.).
    - `ChatSession`: Actor-managed stateful conversations with `x-session-affinity` header routing.
    - Chat model metadata retrieval and discovery (`listModels`, `getModel`).
  - **Document AI (`DocAiResource`)**:
    - Digitisation and structured JSON extraction jobs.
    - Polling coordinators (`digitiseAndWait`, `extractAndWait`) leveraging `JobPoller` with cooperative task cancellation.
    - Presigned direct upload and download URL generation.
  - **Additional Indic AI Resources**:
    - `DubbingResource`: Video and audio dubbing pipeline with multi-language target generation and export tracking.
    - `DocumentTranslationResource`: Large document translation tracking and export.
    - `PronunciationDictionaryResource`: Custom pronunciation lexicon management (CRUD).
    - `VoiceCloningResource`: Voice sample registration, deletion, and cloned synthesis.
    - `SpeechToTextJobResource` & `SpeechToTextTranslateJobResource`: Asynchronous bulk speech processing.
    - `JobsResource`: Azure SAS blob storage uploads and job status tracking.
  - **Networking & Reliability**:
    - Exponential backoff with full jitter (Google AIP-4221).
    - Rate limit backoff honoring `Retry-After` headers in integer seconds or milliseconds.
    - Non-idempotent job creation safety rules preventing duplicate execution on HTTP 500.
    - Server-Sent Events (SSE) streaming parser (`SSEParser`) supporting multiline payloads and chunk boundary fragmentation.

- **Audio Companion `SarvamAudio` Library (`packages/swift/Sources/SarvamAudio`)**:
  - `SarvamMicStreamer`: Actor managing hardware microphone audio capture, automatic downsampling/resampling to 16kHz mono PCM, broadcast streams, and live level metering.
  - `PcmResampler`: Linear PCM resampler supporting Float32, stereo-to-mono downmixing, and 48kHz/44.1kHz to 16kHz conversion.
  - `AudioLevel`: Metric calculator computing RMS, peak amplitude, and dBFS for real-time waveform UI meters.
  - `SarvamAudioPlayer`: Low-latency audio playback actor with sub-20ms `stopAndFlush()` for instant interruption.
  - `BargeInCoordinator`: Automated conversational coordinator linking STT VAD speech starts (`.vadSpeechStart`) directly to player hardware buffer flushes.
  - `AudioCaptureDriver` and `AudioPlaybackDriver`: Hardware abstraction protocols with in-memory implementations (`BufferAudioCaptureDriver`, `MemoryAudioPlaybackDriver`).

- **Security & Privacy**:
  - Added Apple Privacy Manifest (`PrivacyInfo.xcprivacy`) to both `Sarvam` and `SarvamAudio` targets, declaring zero data tracking and required system API reasons.
