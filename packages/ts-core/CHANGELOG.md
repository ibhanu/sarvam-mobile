# Changelog

All notable changes to `@sarvam/core` will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [0.3.0](https://github.com/ibhanu/sarvam-mobile/compare/ts-core-v0.2.0...ts-core-v0.3.0) (2026-10-18)


### Features

* **npm:** publish @sarvam-mobile/core and @sarvam-mobile/react-native to npm registry ([3ebbf79](https://github.com/ibhanu/sarvam-mobile/commit/3ebbf795afe218f8bc8ec729d16d87080c412a47))


### Bug Fixes

* update repository and issue tracker URLs to ibhanu/sarvam-mobile and bump dart SDKs to 0.2.1 ([a2c1ab1](https://github.com/ibhanu/sarvam-mobile/commit/a2c1ab1f354719724e02c629f34a3a4f1efb7646))

## [0.2.0](https://github.com/ibhanu/sarvam-mobile/compare/ts-core-v0.1.0...ts-core-v0.2.0) (2026-10-16)


### Features

* initial commit of Sarvam Mobile SDKs monorepo ([8114f80](https://github.com/ibhanu/sarvam-mobile/commit/8114f80d555332f8fca3f3c84cd720543b42746c))
* **release:** configure multi-registry publishing, licenses, and GitHub Actions release pipeline ([3ab9d6b](https://github.com/ibhanu/sarvam-mobile/commit/3ab9d6bf3e1bcc39ce127d8c2a47298744adae7e))


### Bug Fixes

* **ci:** build conformance mock server, select Xcode 16 on macOS, and use flutter test in Dart CI ([5d733a9](https://github.com/ibhanu/sarvam-mobile/commit/5d733a917d4d8d11548212ce3a95a927c0c75ab7))

## [0.1.0] - 2026-10-16

### Added
- **Pure TypeScript Core**: Zero third-party runtime dependencies, zero Node.js built-ins (`fs`, `path`, `crypto`, `buffer`, `stream`). Works seamlessly in Node.js 18+, browsers, Bun, Deno, Edge runtimes, and React Native (Hermes).
- **Multi-Base-URL Architecture**: `SarvamEnvironment` supporting independent endpoints for core REST/streaming API (`https://api.sarvam.ai`), dubbing jobs (`https://api.sarvam.ai/dubbing`), and realtime WebSockets (`wss://api.sarvam.ai`), plus `SarvamEnvironment.proxy(...)` for Backend-For-Frontend (BFF) deployments.
- **Pluggable Authentication**:
  - `ApiKeyAuth`: Static `api-subscription-key` authentication with automated release-build warnings on mobile.
  - `TokenAuth`: Ephemeral JWT bearer token provider featuring in-memory caching, single-flight refresh deduplication, and proactive 60-second expiration buffer.
  - `ProxyAuth`: BFF proxy header provider with support for dynamic session tokens.
- **Canonical Error Taxonomy**: `SarvamError` base class with specialized subtypes: `AuthenticationError` (401 / 403 `invalid_api_key_error`), `PermissionDeniedError` (403), `BadRequestError` (400), `NotFoundError` (404), `RateLimitError` (429 with `retryAfterMs`), `ServerError` (5xx), `ConnectionError`, `TimeoutError`, and `RealtimeError`.
- **Resilient Middleware Pipeline**:
  - `UserAgentMiddleware`: RFC 7231 compliant telemetry header (`@sarvam/core/0.1.0`).
  - `AuthMiddleware`: Injects credentials and coordinates automated token refresh retry on auth failure.
  - `RetryMiddleware`: Exponential backoff with full jitter and `Retry-After` header parsing.
  - `LoggingMiddleware`: Redacts authorization tokens while logging latency and request IDs.
- **Resource Clients**:
  - `client.text`: High-performance Indic translation, phonetics transliteration, and language identification (LID).
  - `client.speechToText`: Batch file transcription, speech-to-text translation directly to English, and `SttRealtimeSession` WebSocket with VAD boundary events.
  - `client.textToSpeech`: REST speech synthesis (`bulbul:v4-flash`), chunked HTTP binary audio streaming, and bidirectional WebSocket streaming (`TtsStreamingSession`).
  - `client.chat`: OpenAI-compatible chat completions with Server-Sent Events (SSE) streaming.
  - `client.responses`: Streaming responses API client.
  - `client.jobs`: Long-running job management and generic polling utility (`pollUntilComplete`).
  - `client.docAi`, `client.voiceCloning`, `client.pronunciationDictionary`, `client.documentTranslation`, `client.dubbing`: Document OCR, entity extraction, voice cloning, and dubbing pipelines.
- **Pure Byte Utilities**: Built-in Base64 encode/decode and hex formatting operating on standard `Uint8Array`.
