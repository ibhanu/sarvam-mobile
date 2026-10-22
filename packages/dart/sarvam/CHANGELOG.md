# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [0.4.1](https://github.com/ibhanu/sarvam-mobile/compare/dart-v0.4.0...dart-v0.4.1) (2026-10-18)


### Bug Fixes

* **release:** add Rust build to publish-swift and make bridge version assertions resilient to version bumps ([2569b26](https://github.com/ibhanu/sarvam-mobile/commit/2569b26d8d8b5f76b17d5386020778042600e4da))

## [0.4.0](https://github.com/ibhanu/sarvam-mobile/compare/dart-v0.3.0...dart-v0.4.0) (2026-10-18)


### Features

* **core:** implement unified cross-platform Rust core engine and automated release pipeline ([7a450ea](https://github.com/ibhanu/sarvam-mobile/commit/7a450ea5185b7be44984d15f7d5ad2610b6de8a2))
* initial commit of Sarvam Mobile SDKs monorepo ([8114f80](https://github.com/ibhanu/sarvam-mobile/commit/8114f80d555332f8fca3f3c84cd720543b42746c))
* **release:** configure multi-registry publishing, licenses, and GitHub Actions release pipeline ([3ab9d6b](https://github.com/ibhanu/sarvam-mobile/commit/3ab9d6bf3e1bcc39ce127d8c2a47298744adae7e))


### Bug Fixes

* **dart:** resolve cross-platform native library extension (.so, .dylib, .dll) in bridge test ([f39ef3f](https://github.com/ibhanu/sarvam-mobile/commit/f39ef3f0645cec84f3a132e2fcf03cc8a1b0b629))
* **dart:** resolve use_super_parameters linter errors in SpeechToTextJobResource ([a35bce2](https://github.com/ibhanu/sarvam-mobile/commit/a35bce2821a75aba998ebb8a4af01351de11882c))
* update CI Flutter action, upgrade Gradle wrapper, and resolve mic streamer concurrency race ([c23af7d](https://github.com/ibhanu/sarvam-mobile/commit/c23af7d3c1138dbbc93f6462bf3584d2844eb0cb))
* update repository and issue tracker URLs to ibhanu/sarvam-mobile and bump dart SDKs to 0.2.1 ([a2c1ab1](https://github.com/ibhanu/sarvam-mobile/commit/a2c1ab1f354719724e02c629f34a3a4f1efb7646))

## [0.3.0](https://github.com/ibhanu/sarvam-mobile/compare/dart-v0.2.1...dart-v0.3.0) (2026-10-18)


### Features

* initial commit of Sarvam Mobile SDKs monorepo ([8114f80](https://github.com/ibhanu/sarvam-mobile/commit/8114f80d555332f8fca3f3c84cd720543b42746c))
* **release:** configure multi-registry publishing, licenses, and GitHub Actions release pipeline ([3ab9d6b](https://github.com/ibhanu/sarvam-mobile/commit/3ab9d6bf3e1bcc39ce127d8c2a47298744adae7e))


### Bug Fixes

* **dart:** resolve use_super_parameters linter errors in SpeechToTextJobResource ([a35bce2](https://github.com/ibhanu/sarvam-mobile/commit/a35bce2821a75aba998ebb8a4af01351de11882c))
* update CI Flutter action, upgrade Gradle wrapper, and resolve mic streamer concurrency race ([c23af7d](https://github.com/ibhanu/sarvam-mobile/commit/c23af7d3c1138dbbc93f6462bf3584d2844eb0cb))
* update repository and issue tracker URLs to ibhanu/sarvam-mobile and bump dart SDKs to 0.2.1 ([a2c1ab1](https://github.com/ibhanu/sarvam-mobile/commit/a2c1ab1f354719724e02c629f34a3a4f1efb7646))

## [0.2.1](https://github.com/ibhanu/sarvam-mobile/compare/dart-v0.2.0...dart-v0.2.1) (2026-10-18)


### Bug Fixes

* update repository and issue tracker URLs to ibhanu/sarvam-mobile and bump dart SDKs to 0.2.1 ([a2c1ab1](https://github.com/ibhanu/sarvam-mobile/commit/a2c1ab1f354719724e02c629f34a3a4f1efb7646))

## [0.2.1] - 2026-10-16

### Fixed
- Fixed repository and issue tracker URLs in `pubspec.yaml` to point to valid, reachable GitHub URLs for pub.dev automated scoring.

## [0.2.0](https://github.com/ibhanu/sarvam-mobile/compare/dart-v0.1.0...dart-v0.2.0) (2026-10-16)


### Features

* initial commit of Sarvam Mobile SDKs monorepo ([8114f80](https://github.com/ibhanu/sarvam-mobile/commit/8114f80d555332f8fca3f3c84cd720543b42746c))
* **release:** configure multi-registry publishing, licenses, and GitHub Actions release pipeline ([3ab9d6b](https://github.com/ibhanu/sarvam-mobile/commit/3ab9d6bf3e1bcc39ce127d8c2a47298744adae7e))


### Bug Fixes

* **dart:** resolve use_super_parameters linter errors in SpeechToTextJobResource ([a35bce2](https://github.com/ibhanu/sarvam-mobile/commit/a35bce2821a75aba998ebb8a4af01351de11882c))
* update CI Flutter action, upgrade Gradle wrapper, and resolve mic streamer concurrency race ([c23af7d](https://github.com/ibhanu/sarvam-mobile/commit/c23af7d3c1138dbbc93f6462bf3584d2844eb0cb))

## [0.1.0] - 2026-10-16

### Added
- Initial release of the unofficial Sarvam AI client SDK for Dart and Flutter (`sarvam`).
- **Text & Language Resource (`client.text`)**:
  - `translate`: High-accuracy neural translation supporting 22+ Indic languages and English.
  - `transliterate`: Script transliteration between Indic scripts and Latin representations.
  - `identifyLanguage`: Fast, accurate language identification (LID).
- **Speech-to-Text Resource (`client.speechToText`)**:
  - `transcribe`: Unary audio file transcription (`Saaras V3`) with `SarvamFileInput`.
  - `translate`: Direct speech-to-text audio translation.
  - `connect`: Real-time bi-directional streaming STT over WebSocket with server-side Voice Activity Detection (VAD) events (`VadSpeechStart`, `VadSpeechEnd`, interim transcript deltas).
  - Subprotocol and bearer-token WebSocket authentication support for browser and mobile environments.
- **Text-to-Speech Resource (`client.textToSpeech`)**:
  - `convert`: Unary speech synthesis returning decoded audio bytes (`Bulbul V4 Flash` & `Bulbul:v2`).
  - `stream`: Chunked binary HTTP streaming for immediate low-latency playback.
  - `connect`: Low-latency WebSocket TTS streaming with initial configuration negotiation and incremental text delivery.
- **Chat Completions Resource (`client.chat`)**:
  - `completions` & `completionsV2`: Unary OpenAI-compatible chat completions (`sarvam-105b`, `sarvam-m`).
  - `completionsStream`: Real-time Server-Sent Events (SSE) streaming token deltas.
  - `session`: Stateful session affinity management via `Sarvam-Session-Affinity` headers.
  - Model discovery endpoints (`listModels`, `getModel`).
- **Responses Resource (`client.responses`)**:
  - `createStream`: Streaming response deltas for `/v2/responses`.
- **Async Batch Jobs & Enterprise Resources**:
  - `client.docAi`: Document AI parsing with automated polling and status retrieval.
  - `client.speechToTextJob` & `client.speechToTextTranslateJob`: Long-form audio processing with Azure Blob SAS upload workflows.
  - `client.documentTranslation`: Multi-page document translation with export tracking.
  - `client.dubbing`: Video and audio dubbing with automated lifecycle tracking.
  - `client.voiceCloning`: Speaker voice cloning with profile management and WebSocket streaming.
  - `client.pronunciationDictionary`: Phonetic pronunciation dictionary overrides.
  - `JobPoller`: Resilient exponential polling for long-running asynchronous tasks.
- **Authentication & Security Architecture**:
  - `ApiKeyAuth`: Static subscription key header injection (`api-subscription-key`).
  - `TokenAuth`: Ephemeral token auth with proactive refresh before expiry and single-flight in-flight deduplication.
  - `ProxyAuth`: Backend-For-Frontend (BFF) proxy support with dynamic custom headers.
- **Transport Pipeline & Resilience**:
  - `PackageHttpTransport`: Pure Dart HTTP transport with zero `dart:io` dependency for complete Flutter Web compatibility.
  - `RetryMiddleware`: Exponential backoff with full jitter, configurable retries, and `Retry-After` header adherence on HTTP 429/503.
  - `UserAgentMiddleware`: RFC 7231 compliant telemetry header injection.
  - `LoggingMiddleware`: Pluggable structured logging with sensitive token masking.
  - `SarvamException` hierarchy: `AuthenticationException`, `RateLimitException`, `BadRequestException`, `NotFoundException`, `ServerException`, `NetworkException`, `TimeoutException`.
