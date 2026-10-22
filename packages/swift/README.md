<p align="center">
  <a href="https://sarvam.ai">
    <img src="https://raw.githubusercontent.com/ibhanu/sarvam-mobile/main/assets/sarvam-ai-website.png" alt="Sarvam AI - India's Sovereign AI Platform" width="100%" style="border-radius: 12px; max-width: 860px; box-shadow: 0 8px 30px rgba(0,0,0,0.12);" />
  </a>
</p>

# Sarvam AI Swift SDK (`Sarvam` & `SarvamAudio`)

[![Swift 6.0](https://img.shields.io/badge/Swift-6.0-orange.svg)](https://swift.org)
[![Platforms](https://img.shields.io/badge/Platforms-iOS%2015.0+%20|%20macOS%2012.0+-blue.svg)](https://developer.apple.com)
[![Rust Core C-FFI](https://img.shields.io/badge/Rust%20Core-C--FFI-DEA584.svg?logo=rust)](../rust-core)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)

Unofficial Swift SDK and Audio Companion for [Sarvam AI](https://sarvam.ai) — the leading foundation model platform for Indian languages. Built from the ground up in idiomatic Swift 6 with strict concurrency (`Sendable`), native `async/await`, `AsyncThrowingStream`, and production-grade network resilience.

---

## < 5 Minutes to First Call

### 1. Installation (Swift Package Manager)

Add the dependency in your `Package.swift`:

```swift
dependencies: [
    .package(url: "https://github.com/ibhanu/sarvam-mobile.git", from: "0.3.0")
],
targets: [
    .target(
        name: "YourApp",
        dependencies: [
            .product(name: "Sarvam", package: "sarvam-mobile"),
            .product(name: "SarvamAudio", package: "sarvam-mobile") // Optional: hardware mic capture, audio playback & VAD barge-in
        ]
    )
]
```

Or in Xcode:
1. Navigate to **File** > **Add Package Dependencies...**
2. Paste `https://github.com/ibhanu/sarvam-mobile.git` into the search bar.
3. Select your project target and choose `Sarvam` (and optionally `SarvamAudio`).

### 2. Mobile Authentication Setup

> [!CAUTION]
> **Mobile Security Rule**: **NEVER** hardcode or compile static API keys (`Api-Subscription-Key`) into your iOS/macOS application binaries. Static strings can be trivially extracted using `strings` or reverse engineering tools.

For production iOS apps, authenticate using either **Ephemeral Token Authentication** (`TokenAuth`) or a **Backend-For-Frontend Proxy** (`ProxyAuth`):

```swift
import Sarvam

// Option A: TokenAuth (Recommended for direct API access)
// Proactively refreshes expired tokens with a 60-second safety buffer and deduplicates concurrent refresh calls.
let auth = TokenAuth {
    // Call your secure backend endpoint to mint an ephemeral short-lived JWT or token
    let (data, _) = try await URLSession.shared.data(from: URL(string: "https://api.yourbackend.com/sarvam/token")!)
    let token = String(data: data, encoding: .utf8)!.trimmingCharacters(in: .whitespacesAndNewlines)
    return AuthToken(token: token, expiresAtEpochMs: Int64(Date().timeIntervalSince1970 * 1000) + 3600_000)
}

let client = SarvamClient(authProvider: auth)

// Option B: ProxyAuth (Recommended for BFF / Enterprise architectures)
let proxyAuth = ProxyAuth(proxyBaseUrl: "https://api.yourbackend.com/sarvam") {
    // Provide dynamic session headers (e.g. User Session Token)
    ["Authorization": "Bearer \(currentUserSessionToken)"]
}
let client = SarvamClient(
    authProvider: proxyAuth,
    environment: .proxy(baseUrl: "https://api.yourbackend.com/sarvam")
)
```

*(For local testing/sandbox debugging only, `let client = SarvamClient(apiKey: "your_sub_key")` is available).*

### 3. Translate Text in 3 Lines

```swift
import Sarvam

let request = TranslateRequest(
    input: "Good morning! Welcome to the state-of-the-art Indic voice assistant.",
    sourceLanguageCode: .enIn,
    targetLanguageCode: .hiIn
)

let response = try await client.text.translate(request)
print("Hindi Translation: \(response.translatedText)")
// Output: सुप्रभात! अत्याधुनिक इंडिक वॉयस असिस्टेंट में आपका स्वागत है।
```

---

## Core Capabilities & Quickstarts

### 1. Streaming Text-to-Speech (TTS)

Stream raw binary audio chunks over HTTP chunked transfer for ultra-low latency audio playback:

```swift
import Sarvam

let ttsRequest = TextToSpeechRequest(
    text: "नमस्ते, आप आज कैसे हैं? सर्वम एआई में आपका स्वागत है।",
    targetLanguageCode: .hiIn,
    speaker: .anushka,       // Anushka, Vidya, Arya, Karun, Manisha, etc.
    model: .bulbulV3
)

// Stream raw audio chunks using Swift AsyncThrowingStream:
for try await chunk in client.textToSpeech.stream(ttsRequest) {
    print("Received audio chunk: \(chunk.count) bytes")
    // Write directly to your audio hardware buffer or player
}
```

Or convert to a single buffered payload:

```swift
let response = try await client.textToSpeech.convert(ttsRequest)
if let audioData = response.audioBytes {
    print("Synthesized \(audioData.count) bytes of high-fidelity audio")
}
```

---

### 2. Realtime Speech-to-Text (STT) WebSocket

Stream microphone audio in real time over bidirectional WebSockets to the Saaras speech model family:

```swift
import Sarvam

// 1. Establish low-latency WebSocket connection
let config = SttRealtimeConfig(
    languageCode: .hiIn,
    model: .saarasV3Realtime,
    sampleRate: 16000
)
let session = try await client.speechToText.connect(config: config)

// 2. Consume typed real-time events concurrently
Task {
    for try await event in session.events {
        switch event {
        case .transcriptPartial(let idx, let text, let lang):
            print("Partial [\(idx ?? 0)]: \(text)")
        case .transcriptFinal(let idx, let text, let lang, let conf, let start, let end):
            print("Final Transcript [\(idx ?? 0)]: \(text) (\(lang?.rawValue ?? "auto"))")
        case .vadSpeechStart:
            print("User began speaking (VAD)")
        case .vadSpeechEnd:
            print("User finished speaking (VAD)")
        case .error(let code, let msg):
            print("STT Error [\(code ?? "")]: \(msg)")
        default:
            break
        }
    }
}

// 3. Send 16-bit 16kHz linear PCM audio chunks
try await session.sendAudio(pcmChunkData)

// 4. Signal completion
try await session.end()
```

---

### 3. Automated Barge-In (`BargeInCoordinator`)

When building conversational voice bots, user speech must instantly silence synthesizer playback. `SarvamAudio` provides `BargeInCoordinator` to stop and flush hardware buffers in **under 20 milliseconds**:

```swift
import Sarvam
import SarvamAudio

let player = SarvamAudioPlayer(driver: playbackDriver)
let coordinator = BargeInCoordinator {
    print("Barge-in detected! Output audio silenced.")
}

// Intercepts .vadSpeechStart on the STT session and automatically invokes player.stopAndFlush()
coordinator.attach(session: sttSession, player: player)

// Start playback of incoming TTS stream
try await player.playStream(client.textToSpeech.stream(ttsRequest))
```

---

### 4. Chat V2 with Stateful `ChatSession`

Manage multi-turn conversations with Sarvam's foundation models (`sarvam-105b`, `sarvam-m`, etc.) while ensuring session routing affinity:

```swift
import Sarvam

// Creates a stateful session bound to an affinity token
let session = client.chat.createSession()

let request = ChatCompletionRequest(
    model: .sarvam105b,
    messages: [
        ChatMessage(role: "user", content: "Explain quantum computing in Hindi in two sentences.")
    ]
)

// Stream token deltas via Server-Sent Events (SSE)
for try await chunk in session.completionsV2Stream(request) {
    if let delta = chunk.firstDeltaContent {
        print(delta, terminator: "")
    }
}
print()
```

---

### 5. Document AI (`digitiseAndWait`)

Upload documents (PDFs, images) and extract text or structured JSON with automatic job polling:

```swift
import Sarvam

guard let fileUrl = Bundle.main.url(forResource: "invoice", withExtension: "pdf") else { return }
let fileInput = FileInput(fileURL: fileUrl, mimeType: "application/pdf")

// Uploads multipart file, triggers processing, and polls until completed
let jobStatus = try await client.docAi.digitiseAndWait(file: fileInput)
print("Digitisation finished with status: \(jobStatus.status)")

// Retrieve presigned download URL for results:
let download = try await client.docAi.getDownloadUrl(jobId: jobStatus.jobId)
print("Results ready at: \(download.downloadUrl)")
```

---

## Overview of SDK Packages

| Package | Purpose | Platforms |
| :--- | :--- | :--- |
| **`Sarvam`** | Core SDK: Translation, Transliteration, LID, STT, TTS, Chat V1/V2, Doc AI, Dubbing, Document Translation, Pronunciation Dictionaries, Voice Cloning, WebSockets & Job Polling. | iOS 15.0+, macOS 12.0+ |
| **`SarvamAudio`** | Audio companion: Hardware abstraction, `SarvamMicStreamer` (48kHz/44.1kHz -> 16kHz resampler), `SarvamAudioPlayer`, `BargeInCoordinator`, and audio level meters. | iOS 15.0+, macOS 12.0+ |

---

## Production Reliability Features

- **Strict Concurrency (Swift 6)**: Every type is marked `Sendable` or modeled as an `actor`. Thread-safe by construction with zero data races.
- **Resilient Retry Mechanism (Google AIP-4221)**: Exponential backoff with full jitter for transient network drops and HTTP 408, 429, 500, 502, 503, 504 errors.
- **Rate-Limit Awareness**: Automatically reads `Retry-After` headers (supporting both integer seconds and millisecond values).
- **Job Creation Safety**: Non-idempotent job creations (Doc AI, Dubbing, Bulk STT) are never blindly retried on server 500s to prevent duplicate billing.
- **Privacy Manifest (`PrivacyInfo.xcprivacy`)**: Pre-configured in both SPM modules declaring zero tracking domains and required reason APIs for frictionless App Store validation.

---

## 🦀 Unified Rust Core Engine (C-FFI)

The Swift SDK binds directly to [`sarvam-rust-core`](../rust-core) via `SarvamRustBridge`, leveraging Clang C-interop without bridging headers:

- **SIMD DSP Audio Downsampling**: Hardware microphone audio recorded via `AVAudioEngine` (at native 48 kHz / 44.1 kHz) is resampled into 16 kHz mono linear-16 PCM using Rust SIMD instructions.
- **Single-Flight Refresh & Token Caching**: Deduplicates concurrent async tasks requesting new access tokens.
- **Deterministic Retry Matrix**: Computes exact exponential jitter curves matching all client platforms.

```swift
import Sarvam

let bridge = SarvamRustBridge.shared

// 1. Resample raw audio buffers to 16 kHz mono linear-16 PCM
let resampled = bridge.resampleAudio(
    inputPcm: rawPcmData,
    sourceSampleRate: 48000,
    channels: 1
)

// 2. Compute canonical retry delay (attempt 2, HTTP 429 with 3s Retry-After)
let delayMs = bridge.computeRetryDelay(attempt: 2, statusCode: 429, retryAfterSeconds: 3)
```

---

## Complete Example App

Explore a full SwiftUI voice assistant demonstrating live Indic captions, audio level visualizers, and instant barge-in under [`Examples/iOSApp`](Examples/iOSApp).

---

## License

Distributed under the MIT License. See `LICENSE` for details.
