# Sarvam AI Mobile SDKs

[![CI](https://github.com/ibhanu/sarvam-mobile/actions/workflows/ci.yml/badge.svg)](https://github.com/ibhanu/sarvam-mobile/actions/workflows/ci.yml)
[![codecov](https://codecov.io/gh/ibhanu/sarvam-mobile/branch/main/graph/badge.svg)](https://codecov.io/gh/ibhanu/sarvam-mobile)
[![Coverage](https://img.shields.io/badge/Coverage-97.8%25-brightgreen.svg)](#-code-coverage)
[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](https://opensource.org/licenses/MIT)
[![Release Please](https://img.shields.io/badge/Release-Please-orange.svg)](https://github.com/googleapis/release-please)
[![npm @sarvam-mobile/core](https://img.shields.io/npm/v/@sarvam-mobile/core.svg?label=npm%20%40sarvam-mobile%2Fcore)](https://www.npmjs.com/package/@sarvam-mobile/core)
[![npm @sarvam-mobile/react-native](https://img.shields.io/npm/v/@sarvam-mobile/react-native.svg?label=npm%20%40sarvam-mobile%2Freact-native)](https://www.npmjs.com/package/@sarvam-mobile/react-native)
[![pub.dev sarvam](https://img.shields.io/pub/v/sarvam.svg?label=pub.dev%20sarvam)](https://pub.dev/packages/sarvam)
[![pub.dev sarvam_flutter_audio](https://img.shields.io/pub/v/sarvam_flutter_audio.svg?label=pub.dev%20sarvam_flutter_audio)](https://pub.dev/packages/sarvam_flutter_audio)
[![SwiftPM compatible](https://img.shields.io/badge/SwiftPM-0.2.0-orange.svg)](https://github.com/ibhanu/sarvam-mobile)

## 📌 About

**Sarvam Mobile** provides the official, production-ready mobile client SDKs for [Sarvam AI](https://sarvam.ai)'s Indic-first speech, translation, and language APIs[cite: 1]. 

Designed from the ground up to support modern mobile client architectures across **Android (Kotlin)**, **iOS (Swift)**, **React Native**, and **Flutter (Dart)**, the monorepo separates core network communication from platform hardware[cite: 1]:

- **Decoupled Architecture**: Core client packages contain zero hardware or OS audio framework dependencies, making them lightweight, headless, and strictly cross-platform[cite: 1].
- **Companion Audio Engines**: Dedicated companion packages handle low-latency hardware audio capture, 16 kHz PCM conversion, and streaming playback per platform[cite: 1].
- **Mobile-First Security**: Built-in credential layers featuring `TokenAuth` (single-flight request coalescing, proactive refresh) and `ProxyAuth` to keep production API keys off the client binary[cite: 1].
- **Indic Language Pipeline**: First-class streaming and REST interfaces for translation, speech-to-text, text-to-speech, and dubbing pipelines across 11+ Indian languages[cite: 1].

---

## 🏛️ Architecture Overview

The Sarvam Mobile monorepo adheres strictly to **Clean Architecture**, **SOLID principles**, and **Separation of Concerns**. Core networking packages manage stateless API interactions, WebSocket streaming, resilient exponential backoff, and authentication token lifecycles with **zero hardware or audio framework dependencies**. Companion audio packages provide optional, platform-native microphone sampling, 16 kHz PCM conversion, and low-latency audio playback.

```mermaid
flowchart TD
    subgraph ClientApplications["Client Mobile Applications"]
        AppKotlin["Android App (Kotlin)"]
        AppSwift["iOS / macOS App (Swift)"]
        AppRN["React Native App (TS)"]
        AppFlutter["Flutter App (Dart)"]
    end

    subgraph CompanionAudio["Hardware Audio Layer (Optional Companion Packages)"]
        AudioKotlin["ai.sarvam:sarvam-android-audio<br/>(AudioRecord, 16kHz PCM, AudioTrack)"]
        AudioSwift["SarvamAudio<br/>(AVAudioEngine, 16kHz PCM, AudioQueue)"]
        AudioRN["@sarvam-mobile/react-native-audio<br/>(Nitro Modules, C++ JSI)"]
        AudioFlutter["sarvam_flutter_audio<br/>(Record, AudioPlayers)"]
    end

    subgraph CoreLayer["Core Networking SDKs (Zero Hardware Dependencies)"]
        CoreKotlin["ai.sarvam:sarvam-core"]
        CoreSwift["Sarvam (SwiftPM)"]
        CoreRN["@sarvam-mobile/react-native"]
        CoreTS["@sarvam-mobile/core (Zero Deps)"]
        CoreDart["sarvam (Dart/Flutter)"]
    end

    subgraph AuthSecurity["Security & Credential Layer"]
        TokenAuth["TokenAuth<br/>(Proactive refresh, single-flight dedupe)"]
        ProxyAuth["ProxyAuth<br/>(Backend-For-Frontend BFF)"]
        ApiKeyAuth["ApiKeyAuth<br/>(Dev only, release build warning)"]
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
    CoreKotlin --> AuthSecurity
    CoreSwift --> AuthSecurity
    CoreTS --> AuthSecurity
    CoreDart --> AuthSecurity

    AuthSecurity --> ApiBase
    AuthSecurity --> WsBase
    AuthSecurity --> DubbingBase
```

---

## 📦 Monorepo Packages

| Platform / Ecosystem | Package Identifier | Registry / Distribution | Directory | Description |
| :--- | :--- | :--- | :--- | :--- |
| **Flutter / Dart** | `sarvam` | [![pub package](https://img.shields.io/pub/v/sarvam.svg)](https://pub.dev/packages/sarvam) | [`packages/dart/sarvam`](packages/dart/sarvam) | Core Dart client (Sound Null Safety, Streams, http) |
| **Flutter / Dart** | `sarvam_flutter_audio` | [![pub package](https://img.shields.io/pub/v/sarvam_flutter_audio.svg)](https://pub.dev/packages/sarvam_flutter_audio) | [`packages/dart/sarvam_flutter_audio`](packages/dart/sarvam_flutter_audio) | Flutter audio capture and audio player companion |
| **TypeScript / Web** | `@sarvam-mobile/core` | [![npm version](https://img.shields.io/npm/v/@sarvam-mobile/core.svg)](https://www.npmjs.com/package/@sarvam-mobile/core) | [`packages/ts-core`](packages/ts-core) | Isomorphic zero-dependency TypeScript SDK (Fetch, WS, AsyncIterable) |
| **React Native** | `@sarvam-mobile/react-native` | [![npm version](https://img.shields.io/npm/v/@sarvam-mobile/react-native.svg)](https://www.npmjs.com/package/@sarvam-mobile/react-native) | [`packages/react-native`](packages/react-native) | React Native bindings with native WebSocket optimization |
| **iOS / Swift** | `Sarvam` | [![SwiftPM](https://img.shields.io/badge/SwiftPM-v0.2.0-orange.svg)](https://github.com/ibhanu/sarvam-mobile) | [`packages/swift/Sources/Sarvam`](packages/swift/Sources/Sarvam) | Core Swift Package (Swift 6 concurrency, URLSession, SSE) |
| **iOS / Swift** | `SarvamAudio` | [![SwiftPM](https://img.shields.io/badge/SwiftPM-v0.2.0-orange.svg)](https://github.com/ibhanu/sarvam-mobile) | [`packages/swift/Sources/SarvamAudio`](packages/swift/Sources/SarvamAudio) | AVAudioEngine streaming capture, 16 kHz resampling, playback |
| **Android / Kotlin** | `ai.sarvam:sarvam-core` | [![Maven Central](https://img.shields.io/badge/Maven-v0.2.0-blue.svg)](packages/kotlin/build/staging-repo) | [`packages/kotlin/sarvam-core`](packages/kotlin/sarvam-core) | Core Android/JVM client (Ktor/OkHttp, Coroutines, Serialization) |
| **Android / Kotlin** | `ai.sarvam:sarvam-android-audio` | [![Maven Central](https://img.shields.io/badge/Maven-v0.2.0-blue.svg)](packages/kotlin/build/staging-repo) | [`packages/kotlin/sarvam-android-audio`](packages/kotlin/sarvam-android-audio) | Microphone capture, 16 kHz PCM resampling, audio player |

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
    implementation("ai.sarvam:sarvam-core:0.2.0")
    implementation("ai.sarvam:sarvam-android-audio:0.2.0") // Optional
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
    .package(url: "https://github.com/ibhanu/sarvam-mobile.git", from: "0.2.0")
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
  sarvam: ^0.2.0
  sarvam_flutter_audio: ^0.2.0 # Optional
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
