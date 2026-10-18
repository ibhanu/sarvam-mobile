# Sarvam AI Mobile SDKs — Cross-Platform Architecture & API Contract

> **Status:** Authoritative Specification (Phase 0.1)  
> **Applies to:** Android (`io.github.ibhanu:sarvam-core`), iOS (`Sarvam`), TypeScript/React Native (`@sarvam/core`, `@sarvam/react-native`), Flutter/Dart (`sarvam`)  
> **Companion Skill:** [`.agents/skills/sdk-development/SKILL.md`](../../.agents/skills/sdk-development/SKILL.md)

---

## 1. Guiding Principles (SOLID & DRY)

1. **Single Responsibility (SRP):**
   - `HttpTransport` & `WebSocketFactory` handle low-level socket I/O only.
   - `Middleware` components each handle a single cross-cutting concern (`UserAgent`, `Auth`, `Retry`, `Timeout`, `Logging`, `Telemetry`).
   - Resource classes (`TextResource`, `SpeechToTextResource`, `TextToSpeechResource`, `ChatResource`, etc.) are pure, stateless request builders and response decoders.
   - Companion audio packages (`sarvam-android-audio`, `SarvamAudio`, `@sarvam/react-native-audio`, `sarvam_flutter_audio`) own hardware microphone capture, 16 kHz resampling, and audio playback. Core packages have **zero** audio hardware or permission dependencies.
2. **Open/Closed (OCP):**
   - Developers extend behavior by supplying custom `AuthProvider`, `Middleware`, `HttpTransport`, or `LoggerAdapter` instances without modifying SDK internals.
3. **Liskov Substitution (LSP):**
   - Every `HttpTransport` and `WebSocketFactory` implementation (production or mock) satisfies the same contract and passes the shared `conformance/` test suite.
4. **Interface Segregation (ISP):**
   - Interfaces are minimal single-method or dual-method contracts (`execute`, `connect`, `credentials`).
5. **Dependency Inversion (DIP):**
   - High-level resources depend exclusively on abstract runtime interfaces injected via `SarvamClientConfig`.

---

## 2. Multi-Base-URL Environment (`SarvamEnvironment`)

Sarvam routes API calls across three distinct hosts. Every SDK provides an immutable `SarvamEnvironment` type with `production` defaults and a `proxy(baseUrl)` factory for Backend-For-Frontend (BFF) deployments:

| Property | Default Production Value | Used By |
| :--- | :--- | :--- |
| `apiBaseUrl` | `https://api.sarvam.ai` | All REST & HTTP streaming endpoints except Dubbing |
| `dubbingBaseUrl` | `https://api.sarvam.ai/dubbing` | `client.dubbing.*` endpoints (`/jobs/*`) |
| `wsBaseUrl` | `wss://api.sarvam.ai` | All WebSocket channels (`/speech-to-text-realtime/ws`, `/text-to-speech/ws`, `/voices/clone/ws`) |

When `SarvamEnvironment.proxy("https://api.myapp.com/sarvam")` is used:
- `apiBaseUrl` = `https://api.myapp.com/sarvam`
- `dubbingBaseUrl` = `https://api.myapp.com/sarvam/dubbing`
- `wsBaseUrl` = `wss://api.myapp.com/sarvam`

---

## 3. Authentication & Mobile Security Contract (`AuthProvider`)

### 3.1 Credentials Union
An `AuthProvider` produces `SarvamCredentials`:
1. `SubscriptionKey(key: String)`
   - **REST Header:** `api-subscription-key: <key>`
   - **WebSocket (Native):** Header `Api-Subscription-Key: <key>`
   - **WebSocket (Web / RN Fallback):** Subprotocol `api-subscription-key.<key>`
2. `BearerToken(token: String, expiresAtEpochMs: Long?)`
   - **REST Header:** `Authorization: Bearer <token>`
   - **WebSocket (Native):** Header `Authorization: Bearer <token>`
   - **WebSocket (Web / RN Fallback):** Subprotocol `bearer.<token>` (or query/proxy header)
3. `CustomHeaders(headers: Map<String, String>)`
   - Used with `ProxyAuth` to attach app session tokens.

### 3.2 Built-in `AuthProvider` Implementations
1. **`ApiKeyAuth(apiKey)`**:
   - Static `api-subscription-key`. Intended for local development, prototyping, or server-side usage.
   - Emits a one-time `WARN` log if initialized in a mobile release build, reminding developers to use `TokenAuth` or `ProxyAuth` in production.
2. **`TokenAuth(tokenProvider: async () -> AuthToken)`**:
   - Caches the returned token in memory.
   - Proactively refreshes 60 seconds prior to `expiresAt`.
   - Uses **single-flight deduplication** so concurrent requests share a single in-flight refresh call.
   - When the server returns `AuthenticationError` (HTTP `401` OR HTTP `403` with `error.code == "invalid_api_key_error"`), `AuthMiddleware` calls `authProvider.invalidate()` and retries the request **at most once** with a freshly fetched token.
3. **`ProxyAuth(proxyBaseUrl, headersProvider)`**:
   - Configures `SarvamEnvironment.proxy(proxyBaseUrl)` and injects custom BFF headers on each request.

---

## 4. Canonical Error Hierarchy (`SarvamError`)

All errors thrown by the SDK inherit from a sealed/discriminated base class `SarvamError` (or `SarvamException` in Kotlin/Dart):

| Error Subtype | Trigger Condition | Retryable? | Special Fields |
| :--- | :--- | :---: | :--- |
| `AuthenticationError` | HTTP `401` OR HTTP `403` with `error.code == "invalid_api_key_error"` | Once via `TokenAuth` refresh; never via backoff | `statusCode`, `code`, `requestId`, `message` |
| `PermissionDeniedError` | HTTP `403` with `error.code != "invalid_api_key_error"` (e.g. `authentication_error` tier lock) | No | `statusCode`, `code`, `requestId` |
| `BadRequestError` | HTTP `400` | No | `statusCode`, `code`, `requestId`, `rawBody` |
| `NotFoundError` | HTTP `404` | No | `statusCode`, `code`, `requestId` |
| `PayloadTooLargeError` | HTTP `413` | No | `statusCode`, `code`, `requestId` |
| `UnprocessableEntityError` | HTTP `422` | No | `statusCode`, `code`, `requestId`, `rawBody` |
| `RateLimitError` | HTTP `429` OR HTTP `503` with `error.code == "rate_limit_exceeded_error"` | **Yes** | `retryAfterMs: Long?`, `code`, `requestId` |
| `ServerError` | HTTP `500`, `502`, `503`, `504` (and `408`, `409`) | **Yes** (per Retry Matrix) | `statusCode`, `code`, `requestId` |
| `ConnectionError` | DNS failure, TLS error, socket reset | **Yes** (per Retry Matrix) | `cause` |
| `TimeoutError` | Connect, read, or total request timeout exceeded | **Yes** (if idempotent/stateless) | `Phase` (`connect` / `read` / `total`) |
| `StreamError` | Unexpected EOF or malformed SSE frame mid-stream | No (stream already started) | `requestId` |
| `RealtimeError` | WebSocket error frame or abnormal close (`1003`, `1008`, `1011`, `4000`) | No | `closeCode: Int?`, `code: String?` |
| `DecodingError` | Response JSON failed schema deserialization | No | `rawBody`, `cause` |

- **Cancellation:** Native cancellation (`CancellationException` in Kotlin, `CancellationError` in Swift, `AbortError` in TS, stream cancel in Dart) is **never** caught or wrapped into `SarvamError`.

---

## 5. Network Resilience & Safe Retry Matrix

### 5.1 Backoff & `Retry-After` Parsing
- **Default `maxRetries`:** `2` (up to 3 total attempts).
- **Header Precedence on `429` / `503`:**
  1. `retry-after-ms`: parse integer milliseconds.
  2. `Retry-After`: parse integer seconds (`* 1000`) or HTTP-date delta.
  3. `X-RateLimit-Reset`: parse Unix epoch seconds delta.
- **Computed Full-Jitter Backoff (when no header present):**
  - `ceilingMs = min(maxBackoffMs (8000), baseBackoffMs (500) * 2^attempt)`
  - `sleepMs = random(0, ceilingMs)` (using injectable `Random` + `Clock` for deterministic unit tests).

### 5.2 Operation Retry Classification (`OperationKind`)
Every generated resource method tags its `HttpRequest` with an `OperationKind`:
1. `IDEMPOTENT` (`GET`, `DELETE`, `PUT` dictionary): Retry on `ConnectionError`, `TimeoutError`, `408`, `409`, `429`, `500`, `502`, `503`, `504`.
2. `STATELESS_POST` (`/translate`, `/transliterate`, `/text-lid`, `/text-to-speech`, `/v1/chat/completions`, `/v2/chat/completions`): Retry on `ConnectionError`, `408`, `409`, `429`, `500`, `502`, `503`, `504` **before** response streaming starts.
3. `MULTIPART_COMPUTE` (`/speech-to-text`, `/speech-to-text-translate`, `/voices/clone`): Retry on `429` and `503` **only** if all attached `FileInput` sources are replayable (`isReplayable == true`).
4. `JOB_CREATE` (`/doc-ai/v1/job/*`, `/voices/create`, `/speech-to-text/job/v1`, `/translate/document/jobs`, `/dubbing/jobs`): Retry **only on `429`** (rate-limited before job creation) unless `Idempotency-Key` header is set.

---

## 6. Cross-Language Naming & Signature Matrix

### 6.1 Client & Resource Hierarchy
All four SDKs expose the exact same resource tree on `SarvamClient`:

| Resource Property | Endpoint Group | P0 / P1 / P2 |
| :--- | :--- | :---: |
| `client.text` | `translate`, `transliterate`, `identifyLanguage` | **P0** |
| `client.speechToText` | `transcribe`, `translate`, `connect` (Realtime WS) | **P0** |
| `client.textToSpeech` | `convert`, `stream` (HTTP chunked), `connect` (WS) | **P0** |
| `client.chat` | `completions` (v1), `completionsStream` (v1 SSE), `completionsV2`, `completionsV2Stream` (v2 SSE), `listModels`, `getModel`, `createSession` | **P0** |
| `client.voiceCloning` | `listVoices`, `createVoice`, `getVoice`, `deleteVoice`, `convert`, `stream` (HTTP chunked), `connect` (WS) | **P1** |
| `client.docAi` | `digitise`, `extract`, `createUploadUrl`, `getStatus`, `getResults`, `getDownloadUrl`, `digitiseAndWait`, `extractAndWait` | **P1** |
| `client.pronunciationDictionary` | `list`, `create`, `update`, `get`, `delete` | **P1** |
| `client.responses` | `createStream` (`/v2/responses` SSE) | **P2** |
| `client.speechToTextJob` | `initialise`, `getUploadLinks`, `start`, `getStatus`, `getDownloadLinks`, `waitUntilComplete` | **P2** |
| `client.speechToTextTranslateJob` | `initialise`, `getUploadLinks`, `start`, `getStatus`, `getDownloadLinks`, `waitUntilComplete` | **P2** |
| `client.documentTranslation` | `create`, `start`, `getLiveStatus`, `triggerExport`, `getExportStatus`, `waitUntilComplete` | **P2** |
| `client.dubbing` | `create`, `start`, `getLiveStatus`, `getExportStatus`, `waitUntilComplete` | **P2** |
| `client.jobs` | `uploadToSignedUrl(uploadUrl, fileInput)` (injects `x-ms-blob-type: BlockBlob`) | **P2** |

### 6.2 Async & Streaming Return Types by Language

| Pattern | Kotlin (`ai.sarvam`) | Swift (`Sarvam`) | TypeScript (`@sarvam/core`) | Dart (`package:sarvam`) |
| :--- | :--- | :--- | :--- | :--- |
| **Unary Call** | `suspend fun op(req, opts?): Res` | `func op(_ req: Req, options: RequestOptions?) async throws -> Res` | `op(req: Req, options?: RequestOptions): Promise<Res>` | `Future<Res> op(Req req, {RequestOptions? options})` |
| **Binary Stream** | `fun stream(req, opts?): Flow<ByteArray>` | `func stream(_ req: Req, options: RequestOptions?) -> AsyncThrowingStream<Data, Error>` | `stream(req: Req, options?: RequestOptions): AsyncIterable<Uint8Array>` | `Stream<Uint8List> stream(Req req, {RequestOptions? options})` |
| **SSE Stream** | `fun completionsStream(req, opts?): Flow<ChatChunk>` | `func completionsStream(_ req: Req, options: RequestOptions?) -> AsyncThrowingStream<ChatChunk, Error>` | `completionsStream(req: Req, options?: RequestOptions): AsyncIterable<ChatChunk>` | `Stream<ChatChunk> completionsStream(Req req, {RequestOptions? options})` |
| **WebSocket** | `suspend fun connect(config, opts?): Session` | `func connect(_ config: Config, options: RequestOptions?) async throws -> Session` | `connect(config: Config, options?: RequestOptions): Promise<Session>` | `Future<Session> connect(Config config, {RequestOptions? options})` |

### 6.3 Open Enums Contract
Every enum (`LanguageCode`, `TtsModel`, `SttModel`, `ChatModel`, `Speaker`, `AudioCodec`, `SttMode`, `JobStatus`) is generated as an **Open Enum**:
- **Kotlin:** `@Serializable(with = ...)` value class or sealed class with `data class Unknown(override val value: String)` so unrecognized server strings never fail deserialization.
- **Swift:** `enum LanguageCode: RawRepresentable, Codable, Sendable, Hashable` with known static cases (`.hiIN`, `.enIN`, ...) plus `.unknown(String)`.
- **TypeScript:** String literal union widened with `(string & {})`: `type LanguageCode = 'hi-IN' | 'en-IN' | ... | (string & {})`.
- **Dart:** `extension type const LanguageCode(String value)` or class with static constants (`LanguageCode.hiIN`) allowing arbitrary string values from the wire.

---

## 7. Streaming & Realtime Session Contracts

### 7.1 SSE Parser Rules (`SseStream`)
1. Parses standard `event:`, `data:`, `id:`, `retry:` lines split by `\n\n` or `\r\n\r\n` across arbitrary TCP chunk boundaries.
2. **Chat Completions (`/v1/chat/completions`, `/v2/chat/completions`):**
   - Terminates cleanly when `data: [DONE]` is received.
   - **V2 Usage Guard:** `ChatCompletionChunk.choices` defaults to an empty list `[]` if omitted or empty on final `usage` chunks; convenience property `chunk.firstDeltaContent` returns `null`/`nil` safely when `choices` is empty.
3. **Responses API (`/v2/responses`):**
   - Does **not** wait for `[DONE]`. Terminates stream upon receiving `event: response.completed`, `event: response.failed`, or `event: response.incomplete` (or matching JSON `"type"` field).

### 7.2 `SttRealtimeSession` (`/speech-to-text-realtime/ws`)
- **Handshake:** Connects to `${wsBaseUrl}/speech-to-text-realtime/ws` with query parameters (`language_code`, `model`, `stream_type`, `mode`, `encoding`, `sample_rate`, `return_timestamps`, `endpointing`, `threshold`, `prefix_padding_ms`, `silence_duration_ms`, `min_speech_duration_ms`, `prompt`, `keyterms`).
- **Sample Rate Validation:** Validates client-side before connecting that `sampleRate` is `16000` or `8000` (throwing `BadRequestError` immediately if invalid, avoiding opaque WS close `4000`).
- **Outbound Methods:**
  - `sendAudio(pcmBytes: ByteArray / Data / Uint8Array / Uint8List)` → Base64-encodes bytes and sends `{"event": "audio_input", "audio": "<base64>"}`.
  - `updateConfig(mode?, keyterms?, threshold?, silenceDurationMs?)` → sends `{"event": "config_update", ...}`.
  - `flush()` → sends `{"event": "flush"}`.
  - `ping()` → sends `{"event": "ping"}` (also sent automatically every 20s by session heartbeat timer).
  - `end()` → sends `{"event": "end"}`.
  - `close()` → closes the WebSocket cleanly (`1000`).
- **Inbound Event Union (`SttRealtimeEvent`):**
  - `SessionBegin(sessionId: String)` (`event == "session_begin"`)
  - `VadSpeechStart(timestampMs: Long?)` (`event == "vad_speech_start"` or `"speech_start"`)
  - `VadSpeechEnd(timestampMs: Long?)` (`event == "vad_speech_end"` or `"speech_end"`)
  - `TranscriptPartial(utteranceIdx: Int?, text: String, language: LanguageCode?)` (`event == "transcript_partial"`)
  - `TranscriptFinal(utteranceIdx: Int?, text: String, language: LanguageCode?, languageConfidence: Double?, startS: Double?, endS: Double?)` (`event == "transcript_final"` or `"transcript"`)
  - `SessionEnd(durationSeconds: Double?)` (`event == "session_end"`)
  - `Error(code: String?, message: String)` (`event == "error"`)
  - `Unknown(rawJson: String)`

### 7.3 `TtsStreamingSession` (`/text-to-speech/ws` & `/voices/clone/ws`)
- **Handshake & Auto-Config:** Connects to `${wsBaseUrl}/text-to-speech/ws?model=${model}&send_completion_event=true` (or `/voices/clone/ws?send_completion_event=true`) and immediately sends the initial `{"type": "config", "data": {...}}` JSON frame before any `sendText` frames.
- **Outbound Methods:**
  - `sendText(text: String)` → sends `{"type": "text", "data": {"text": text}}`.
  - `flush()` → sends `{"type": "flush"}`.
  - `ping()` → sends `{"type": "ping"}`.
  - `close()` → closes the WebSocket cleanly (`1000`).
- **Inbound Event Union (`TtsStreamEvent`):**
  - `AudioChunk(audioBytes: ByteArray / Data / Uint8Array / Uint8List, contentType: String?, requestId: String?)` (`type == "audio"`, with `data.audio` automatically Base64-decoded into `audioBytes`).
  - `Completed(requestId: String?)` (`type == "event"` where `data.event == "final"` or `data.event_type == "completion"`).
  - `Error(message: String, code: String?)` (`type == "error"`).
  - `Unknown(rawJson: String)`

---

## 8. Observability & User-Agent Contract

Every SDK sends a standardized `User-Agent` header (and `X-Sarvam-SDK-Version` header):
```
sarvam-<platform>/<sdk-version> (spec/<spec-version>; <os>/<os-version>; <runtime>)
```
Examples:
- `sarvam-kotlin/0.1.0 (spec/2026-10-16; android/15; jvm/21)`
- `sarvam-swift/0.1.0 (spec/2026-10-16; ios/18.0; swift/6.0)`
- `sarvam-react-native/0.1.0 (spec/2026-10-16; ios/18.0; hermes)`
- `sarvam-dart/0.1.0 (spec/2026-10-16; flutter; dart/3.5)`

`LoggingMiddleware` redacts `api-subscription-key`, `Authorization`, and Base64 audio payloads at `INFO`/`DEBUG` levels by default.
