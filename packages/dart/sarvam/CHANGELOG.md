# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [0.1.0] - 2026-10-16

### Added
- Initial release of the official Sarvam AI client SDK for Dart and Flutter (`sarvam`).
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
