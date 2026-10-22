<p align="center">
  <a href="https://sarvam.ai">
    <img src="https://raw.githubusercontent.com/ibhanu/sarvam-mobile/main/assets/sarvam-ai-website.png" alt="Sarvam AI - India's Sovereign AI Platform" width="100%" style="border-radius: 12px; max-width: 860px; box-shadow: 0 8px 30px rgba(0,0,0,0.12);" />
  </a>
</p>

# Sarvam AI Mobile SDKs

[![CI](https://github.com/ibhanu/sarvam-mobile/actions/workflows/ci.yml/badge.svg)](https://github.com/ibhanu/sarvam-mobile/actions/workflows/ci.yml)
[![codecov](https://codecov.io/gh/ibhanu/sarvam-mobile/branch/main/graph/badge.svg)](https://codecov.io/gh/ibhanu/sarvam-mobile)
[![Coverage](https://img.shields.io/badge/Coverage-97.8%25-brightgreen.svg)](#-code-coverage)
[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](https://opensource.org/licenses/MIT)
[![Rust Core](https://img.shields.io/badge/Rust%20Core-0.3.0-DEA584.svg?logo=rust)](packages/rust-core)
[![Release Please](https://img.shields.io/badge/release--please-automated-orange.svg?logo=github)](https://github.com/googleapis/release-please)
[![npm @sarvam-mobile/core](https://img.shields.io/npm/v/@sarvam-mobile/core.svg?label=npm%20%40sarvam-mobile%2Fcore)](https://www.npmjs.com/package/@sarvam-mobile/core)
[![npm @sarvam-mobile/react-native](https://img.shields.io/npm/v/@sarvam-mobile/react-native.svg?label=npm%20%40sarvam-mobile%2Freact-native)](https://www.npmjs.com/package/@sarvam-mobile/react-native)
[![pub.dev sarvam](https://img.shields.io/pub/v/sarvam.svg?label=pub.dev%20sarvam)](https://pub.dev/packages/sarvam)
[![pub.dev sarvam_flutter_audio](https://img.shields.io/pub/v/sarvam_flutter_audio.svg?label=pub.dev%20sarvam_flutter_audio)](https://pub.dev/packages/sarvam_flutter_audio)
[![Maven Central](https://img.shields.io/maven-central/v/io.github.ibhanu/sarvam-core.svg?label=maven%20io.github.ibhanu%3Asarvam-core)](https://central.sonatype.com/artifact/io.github.ibhanu/sarvam-core)
[![SwiftPM compatible](https://img.shields.io/badge/SwiftPM-0.3.1-orange.svg)](https://github.com/ibhanu/sarvam-mobile)

## 📌 About

**Sarvam Mobile** provides unofficial, community-driven, production-ready mobile client SDKs for [Sarvam AI](https://sarvam.ai)'s Indic-first speech, translation, and language APIs.

> [!NOTE]
> This is an independent, community-driven open-source project and is not affiliated with, sponsored, or endorsed by Sarvam AI.

Designed from the ground up to support modern mobile client architectures across **Android (Kotlin)**, **iOS (Swift)**, **React Native**, and **Flutter (Dart)**, the monorepo pairs native platform ergonomics with a high-performance **Unified Rust Engine** (`sarvam-rust-core`):

- **Unified Rust Core Engine**: Critical auth caching, single-flight refresh coalescing, exponential jitter retry matrices, SSE parsing, and 16 kHz mono linear-16 PCM DSP audio resampling are powered by a single, memory-safe, ultra-compact (<600 KB) Rust library (`sarvam-rust-core`).
- **Host-Delegated Transport**: Networking and WebSocket I/O are handled by native platform engines (`OkHttp`, `URLSession`, `fetch`, `package:http`), guaranteeing 100% compliance with OS VPN configurations, enterprise proxies, cellular network transitions, and SSL certificate pinning.
- **Companion Audio Engines**: Dedicated companion packages handle low-latency hardware microphone capture, 16 kHz PCM conversion, and real-time streaming audio playback.
- **Mobile-First Security**: Built-in credential layers featuring `TokenAuth` (single-flight request coalescing, proactive refresh) and `ProxyAuth` to keep production API keys off the client binary.
- **Indic Language Pipeline**: First-class streaming and REST interfaces for translation, speech-to-text, text-to-speech, and dubbing pipelines across 11+ Indian languages.

---

## 🏛️ Architecture Overview

The Sarvam Mobile monorepo adheres strictly to **Clean Architecture**, **SOLID principles**, and **Separation of Concerns**. A shared core Rust engine coordinates stateful and computationally intensive logic across all targets via zero-overhead bindings:
- **Android / JVM**: Direct JNI native bindings (`System.loadLibrary("sarvam_rust_core")`)
- **iOS / macOS**: Direct C-FFI / Clang ABI linking (`libsarvam_rust_core.a` / `.dylib`)
- **Flutter / Dart**: Native Dynamic Library via `dart:ffi`
- **TypeScript / React Native**: Deterministic WebAssembly module (`sarvam_rust_core.wasm`)

```mermaid
flowchart TD
    subgraph ClientApplications["Client Mobile Applications"]
        AppKotlin["Android App (Kotlin)"]
        AppSwift["iOS / macOS App (Swift)"]
        AppRN["React Native App (TS)"]
        AppFlutter["Flutter App (Dart)"]
    end

    subgraph PlatformSDKs["Platform SDK Layers (Host-Delegated Networking)"]
        CoreKotlin["io.github.ibhanu:sarvam-core<br/>(OkHttp / Coroutines)"]
        CoreSwift["Sarvam (SwiftPM)<br/>(URLSession / Swift 6 Concurrency)"]
        CoreRN["@sarvam-mobile/react-native<br/>(Hermes Native WS / Fetch)"]
        CoreTS["@sarvam-mobile/core<br/>(Zero-dep Fetch / AsyncIterable)"]
        CoreDart["sarvam<br/>(package:http / Dart Streams)"]
    end

    subgraph RustCore["Unified Native Rust Engine (sarvam-rust-core <600 KB)"]
        SharedRust["sarvam-rust-core<br/>• Proactive Token Refresh & Single-Flight Coalescing<br/>• High-Throughput 16kHz PCM Audio Resampler (DSP)<br/>• Exponential Jitter Backoff & Retry Matrix<br/>• SSE / WebSocket Event State Machines"]
    end

    subgraph CompanionAudio["Hardware Audio Layer (Optional Companion Packages)"]
        AudioKotlin["io.github.ibhanu:sarvam-android-audio<br/>(AudioRecord, AudioTrack)"]
        AudioSwift["SarvamAudio<br/>(AVAudioEngine, AudioQueue)"]
        AudioRN["@sarvam-mobile/react-native-audio<br/>(Nitro Modules, C++ JSI)"]
        AudioFlutter["sarvam_flutter_audio<br/>(Record, AudioPlayers)"]
    end

    subgraph SarvamBackend["Sarvam AI Cloud Platform"]
        ApiBase["REST & SSE Endpoints<br/>api.sarvam.ai"]
        WsBase["Realtime Streaming (STT / TTS WS)<br/>wss://api.sarvam.ai"]
        DubbingBase["Dubbing Batch Pipeline<br/>api.sarvam.ai/dubbing"]
    end

    AppKotlin --> AudioKotlin
    AppKotlin --> CoreKotlin
    AppSwift --> AudioSwift
    AppSwift --> CoreSwift
    AppRN --> AudioRN
    AppRN --> CoreRN
    AppFlutter --> AudioFlutter
    AppFlutter --> CoreDart

    CoreRN --> CoreTS

    CoreKotlin -.->|JNI Native Call| SharedRust
    CoreSwift -.->|C-FFI Clang ABI| SharedRust
    CoreDart -.->|dart:ffi| SharedRust
    CoreTS -.->|WebAssembly Wasm| SharedRust

    CoreKotlin --> ApiBase
    CoreKotlin --> WsBase
    CoreSwift --> ApiBase
    CoreSwift --> WsBase
    CoreTS --> ApiBase
    CoreTS --> WsBase
    CoreDart --> ApiBase
    CoreDart --> WsBase
```

---

## 📦 Monorepo Packages

| Platform / Ecosystem | Package Identifier | Registry / Distribution | Directory | Description |
| :--- | :--- | :--- | :--- | :--- |
| **Shared Rust Core** | `sarvam-rust-core` | [![crates.io](https://img.shields.io/badge/crates.io-0.3.0-orange.svg)](packages/rust-core) | [`packages/rust-core`](packages/rust-core) | Shared high-performance engine (Auth, 16kHz DSP resampler, SSE, Retry) |
| **Flutter / Dart** | `sarvam` | [![pub package](https://img.shields.io/pub/v/sarvam.svg)](https://pub.dev/packages/sarvam) | [`packages/dart/sarvam`](packages/dart/sarvam) | Core Dart client with FFI Rust bridge & pure Dart fallback |
| **Flutter / Dart** | `sarvam_flutter_audio` | [![pub package](https://img.shields.io/pub/v/sarvam_flutter_audio.svg)](https://pub.dev/packages/sarvam_flutter_audio) | [`packages/dart/sarvam_flutter_audio`](packages/dart/sarvam_flutter_audio) | Flutter audio capture and audio player companion |
| **TypeScript / Web** | `@sarvam-mobile/core` | [![npm version](https://img.shields.io/npm/v/@sarvam-mobile/core.svg)](https://www.npmjs.com/package/@sarvam-mobile/core) | [`packages/ts-core`](packages/ts-core) | Isomorphic zero-dependency TypeScript SDK with Wasm core bridge |
| **React Native** | `@sarvam-mobile/react-native` | [![npm version](https://img.shields.io/npm/v/@sarvam-mobile/react-native.svg)](https://www.npmjs.com/package/@sarvam-mobile/react-native) | [`packages/react-native`](packages/react-native) | React Native bindings with native WebSocket optimization & Wasm bridge |
| **iOS / Swift** | `Sarvam` | [![SwiftPM](https://img.shields.io/badge/SwiftPM-0.3.1-orange.svg)](https://github.com/ibhanu/sarvam-mobile) | [`packages/swift/Sources/Sarvam`](packages/swift/Sources/Sarvam) | Core Swift Package with C-FFI Rust core bridge |
| **iOS / Swift** | `SarvamAudio` | [![SwiftPM](https://img.shields.io/badge/SwiftPM-0.3.1-orange.svg)](https://github.com/ibhanu/sarvam-mobile) | [`packages/swift/Sources/SarvamAudio`](packages/swift/Sources/SarvamAudio) | AVAudioEngine streaming capture, 16 kHz resampling, playback |
| **Android / Kotlin** | `io.github.ibhanu:sarvam-core` | [![Maven Central](https://img.shields.io/maven-central/v/io.github.ibhanu/sarvam-core.svg)](https://central.sonatype.com/artifact/io.github.ibhanu/sarvam-core) | [`packages/kotlin/sarvam-core`](packages/kotlin/sarvam-core) | Core Android/JVM client with JNI Rust core bridge |
| **Android / Kotlin** | `io.github.ibhanu:sarvam-android-audio` | [![Maven Central](https://img.shields.io/maven-central/v/io.github.ibhanu/sarvam-android-audio.svg)](https://central.sonatype.com/artifact/io.github.ibhanu/sarvam-android-audio) | [`packages/kotlin/sarvam-android-audio`](packages/kotlin/sarvam-android-audio) | Microphone capture, 16 kHz PCM resampling, audio player |

---

## 📊 Code Coverage

[![codecov](https://codecov.io/gh/ibhanu/sarvam-mobile/branch/main/graph/badge.svg)](https://codecov.io/gh/ibhanu/sarvam-mobile)
[![Coverage](https://img.shields.io/badge/Coverage-97.8%25-brightgreen.svg)](#-code-coverage)

The Sarvam Mobile SDK suite enforces strict test coverage gates across every language ecosystem:

| Package / Module | Ecosystem | Line Coverage | Function / Method Coverage | Branch Coverage | Test Report Format |
| :--- | :--- | :--- | :--- | :--- | :--- |
| **Android / Kotlin (`:sarvam-core`)** | Kotlin / JVM | **94.4%** (2,490 / 2,639) | 88.3% (930 / 1,053) | 70.1% (758 / 1,082) | JaCoCo XML / CSV |
| **Android Audio (`:sarvam-android-audio`)** | Kotlin / Android | **98.1%** (259 / 264) | 92.4% (61 / 66) | 90.7% (107 / 118) | JaCoCo XML / CSV |
| **iOS / Swift (`Sarvam` + `SarvamAudio`)** | Swift 6 / Apple | **98.2%** (5,302 / 5,398) | 93.9% (494 / 526) | N/A | LLVM Codecov (LCOV) |
| **TypeScript Core (`@sarvam-mobile/core`)** | Node.js / Web | **98.2%** (3,466 / 3,531) | 97.3% (322 / 331) | 91.0% (1,043 / 1,146) | Node LCOV |
| **React Native (`@sarvam-mobile/react-native`)** | React Native / Hermes | **99.3%** (556 / 560) | 100.0% (45 / 45) | 86.9% (159 / 183) | Node LCOV |
| **Flutter / Dart Core (`sarvam`)** | Dart 3 / Flutter | **100.0%** (2,114 / 2,114) | 100.0% | N/A | Dart LCOV |
| **Flutter Audio (`sarvam_flutter_audio`)** | Flutter Audio | **100.0%** (246 / 246) | 100.0% | N/A | Flutter LCOV |
| **Reference BFF Proxy (`@sarvam/bff-proxy`)** | Node.js / Express | **97.9%** (987 / 1,008) | 96.2% (51 / 53) | 89.4% (202 / 226) | Node LCOV |
| **Total Monorepo Suite** | **All Platforms** | **97.8% (15,420 / 15,760 lines)** | **94.2%** | **83.6%** | **Combined Unified LCOV** |

---

## 🔒 Security & Mobile Authentication Model

> [!WARNING]
> **Never compile static API subscription keys into mobile application binaries!**  
> Strings embedded in `.apk`, `.aab`, or `.ipa` bundles are trivially extracted using decompilers (`apktool`, `strings`, `class-dump`).

Every Sarvam mobile SDK implements the canonical `AuthProvider` contract with three distinct strategies:

1. **`TokenAuth(tokenFetcher)` (Recommended for Native Mobile)**:
   - Fetches a short-lived bearer token from your application's secure auth server.
   - Proactively refreshes the token in the background **60 seconds prior to expiration**.
   - Applies **single-flight request coalescing** so that multiple concurrent network requests await the same refresh task without triggering redundant auth roundtrips.
   - Automatically handles `401 Unauthorized` and `invalid_api_key_error` by invalidating cache and retrying exactly once.
2. **`ProxyAuth(proxyBaseUrl, headersProvider)` (Backend-For-Frontend BFF)**:
   - Routes all client requests through your application's secure proxy backend (`SarvamEnvironment.proxy(...)`).
   - Keeps Sarvam API credentials strictly server-side.
3. **`ApiKeyAuth(apiKey)` (Prototyping & CI Only)**:
   - For rapid prototyping, unit testing, and server environments.
   - Automatically emits a visible `WARN` log in mobile release configurations.

### Apple Privacy Manifests
Both `Sarvam` and `SarvamAudio` include bundled Apple Privacy Manifests (`PrivacyInfo.xcprivacy`):
- **Tracking**: Set to `false` (zero tracking across third-party apps or websites).
- **Domains**: Empty tracking domain list.
- **Audio Usage**: Explicitly declared for app functionality without linking to user identities.

---

## 🚀 Quickstarts

### 1. Android (Kotlin)
```kotlin
// build.gradle.kts
dependencies {
    implementation("io.github.ibhanu:sarvam-core:0.2.1")
    implementation("io.github.ibhanu:sarvam-android-audio:0.2.1") // Optional
}

// Instantiate client with TokenAuth
val client = SarvamClient(
    config = SarvamClientConfig(
        authProvider = TokenAuth { myAuthRepository.fetchSarvamToken() }
    )
)

// Translate text
val translation = client.text.translate(
    TranslateRequest(
        inputText = "Where is the nearest railway station?",
        sourceLanguageCode = LanguageCode.EN_IN,
        targetLanguageCode = LanguageCode.HI_IN
    )
)
println(translation.translatedText)
```

### 2. iOS (Swift)
```swift
// Package.swift
dependencies: [
    .package(url: "https://github.com/ibhanu/sarvam-mobile.git", from: "0.3.1")
]

import Sarvam

let client = SarvamClient(
    config: SarvamClientConfig(
        authProvider: TokenAuth { try await authService.getSarvamToken() }
    )
)

let result = try await client.text.translate(
    TranslateRequest(
        inputText: "Good morning, how are you?",
        sourceLanguageCode: .enIN,
        targetLanguageCode: .bnIN
    )
)
print(result.translatedText)
```

### 3. React Native (TypeScript)
```bash
npm install @sarvam-mobile/react-native @sarvam-mobile/core
```
```typescript
import { SarvamClient, TokenAuth } from '@sarvam-mobile/react-native';

const client = new SarvamClient({
  authProvider: new TokenAuth(async () => {
    const res = await fetch('https://api.mycompany.com/auth/sarvam-token');
    return res.json();
  })
});

const response = await client.text.translate({
  input: "Welcome to India",
  sourceLanguageCode: "en-IN",
  targetLanguageCode: "te-IN"
});
console.log(response.translatedText);
```

### 4. Flutter (Dart)
```yaml
# pubspec.yaml
dependencies:
  sarvam: ^0.4.1
  sarvam_flutter_audio: ^0.3.0 # Optional
```
```dart
import 'package:sarvam/sarvam.dart';

final client = SarvamClient(
  config: SarvamClientConfig(
    authProvider: TokenAuth(tokenProvider: () => authRepo.getSarvamToken()),
  ),
);

final result = await client.text.translate(
  TranslateRequest(
    inputText: 'Thank you for your assistance',
    sourceLanguageCode: LanguageCode.enIN,
    targetLanguageCode: LanguageCode.mrIN,
  ),
);
print(result.translatedText);
```

---

## 🛠️ Local Development & Monorepo Workflow

### Prerequisites
- **Node.js**: `v20.0.0+`
- **Java Development Kit**: JDK 21+
- **Xcode**: 16.0+ (Swift 6.0 toolchain)
- **Dart SDK**: `^3.4.0` / Flutter `3.24.x+`

### Common Commands

```bash
# Verify Swift packages and run test suite
swift test

# Build and typecheck TypeScript core & React Native
npm --prefix packages/ts-core install && npm --prefix packages/ts-core run build
npm --prefix packages/react-native install && npm --prefix packages/react-native run build

# Analyze and test Dart package
cd packages/dart/sarvam && dart pub get && dart analyze

# Start the local conformance mock server
npm --prefix conformance/mock-server install
npm --prefix conformance/mock-server start
```

---

## 📄 License

This monorepo is licensed under the [MIT License](LICENSE).
Copyright © 2026 Sarvam AI and contributors.
