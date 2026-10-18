<p align="center">
  <a href="https://sarvam.ai">
    <img src="https://raw.githubusercontent.com/ibhanu/sarvam-mobile/main/assets/sarvam-ai-website.png" alt="Sarvam AI - India's Sovereign AI Platform" width="100%" style="border-radius: 12px; max-width: 860px; box-shadow: 0 8px 30px rgba(0,0,0,0.12);" />
  </a>
</p>

# sarvam-rust-core

[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](../../LICENSE)
[![Rust](https://img.shields.io/badge/Rust-2021%20Edition-DEA584.svg?logo=rust)](Cargo.toml)
[![Wasm](https://img.shields.io/badge/Wasm-379%20KB-654FF0.svg?logo=webassembly)](target/wasm32-unknown-unknown/release)
[![Dylib](https://img.shields.io/badge/Native%20Dylib-557%20KB-blue.svg)](target/release)

**Unified Native Core Engine for Sarvam AI Mobile and Client SDKs.**

`sarvam-rust-core` is an ultra-compact (<600 KB), memory-safe, cross-platform engine written in Rust. It encapsulates shared logic across the entire Sarvam SDK ecosystem—powering **Android (Kotlin)**, **iOS/macOS (Swift)**, **Flutter (Dart)**, and **TypeScript / React Native**.

---

## 🏛️ Why a Unified Rust Core?

| Capability | Platform Implementations Without Core | With `sarvam-rust-core` |
| :--- | :--- | :--- |
| **Auth Token Refresh** | 4 separate implementations; risk of cache race conditions and redundant network stampedes. | Single lock-free state machine with proactive refresh and single-flight request coalescing. |
| **16 kHz PCM DSP Resampler** | Variable floating-point math across Hermes JS, Dart, JVM, and Swift; potential audio distortion. | SIMD-accelerated, band-limited linear-16 interpolation resampler producing bit-exact identical audio. |
| **Retry & Jitter Matrix** | Discrepancies in HTTP status handling, exponential backoff curves, and full-jitter algorithms. | Canonical retry evaluator matching the Sarvam Cloud specification to the millisecond. |
| **Streaming SSE Parser** | Fragmented buffer parsers with edge-case vulnerabilities on multi-byte UTF-8 boundaries. | Zero-allocation byte-level SSE chunk state machine. |
| **Binary Footprint** | Bloated third-party runtime dependencies. | **557 KB** native dynamic library, **379 KB** WebAssembly binary. |

---

## ⚡ Host-Delegated Transport Architecture

A common antipattern in multi-platform SDKs is bundling a full HTTP/WebSocket client (e.g. `reqwest` + `tokio`) inside a compiled shared library. This inflates binary sizes by 15–20 MB and breaks OS-level platform integration.

`sarvam-rust-core` deliberately uses a **Host-Delegated Transport** model:
- **Rust Core owns**: State machines, token expiration tracking, single-flight coalescing, retry evaluation, and high-performance audio DSP.
- **Host Platform owns**: Network sockets (`URLSession` on iOS, `OkHttp` on Android, `package:http` on Flutter, `fetch` in JS/RN).

### Benefits:
1. **Zero-Friction OS Integration**: Inherits platform VPN tunnels, carrier network handoffs (Wi-Fi to 5G), enterprise proxies, and custom SSL certificate pinning.
2. **Minimal Footprint**: No bundled asynchronous runtime or TLS stack.
3. **Hermes & Web Support**: Compiles directly to pure WebAssembly without requiring Node or OS socket polyfills.

---

## 🔌 Cross-Platform FFI Bindings

`sarvam-rust-core` exposes clean, zero-copy FFI interfaces tailored for each ecosystem:

```mermaid
flowchart TD
    RustCore["sarvam-rust-core (Rust Core Engine)"]

    subgraph NativeAndroid["Android / JVM"]
        KotlinBridge["SarvamRustBridge.kt"]
        JNIExport["JNI Exports (Java_ai_sarvam_rust_SarvamRustBridge_*)"]
    end

    subgraph AppleEcosystem["iOS / macOS"]
        SwiftBridge["SarvamRustBridge.swift"]
        C_ABI["C ABI Exports (extern \"C\")"]
    end

    subgraph FlutterEcosystem["Flutter / Dart"]
        DartBridge["sarvam_rust_bridge.dart"]
        DartFFI["dart:ffi Dynamic Library"]
    end

    subgraph WebMobile["TypeScript / React Native"]
        TSBridge["rustCoreBridge.ts"]
        WasmModule["sarvam_rust_core.wasm (379 KB)"]
    end

    RustCore --> JNIExport --> KotlinBridge
    RustCore --> C_ABI --> SwiftBridge
    RustCore --> C_ABI --> DartFFI --> DartBridge
    RustCore --> WasmModule --> TSBridge
```

### 1. Android / Kotlin (Direct JNI)
Exported via native JNI symbols in [`src/ffi.rs`](src/ffi.rs):
- `Java_ai_sarvam_rust_SarvamRustBridge_nativeVersion`
- `Java_ai_sarvam_rust_SarvamRustBridge_nativeComputeRetryDelay`
- `Java_ai_sarvam_rust_SarvamRustBridge_nativeResampleAudio`

Loaded automatically with zero third-party JNA dependencies:
```kotlin
System.loadLibrary("sarvam_rust_core")
```

### 2. iOS / macOS / Swift (Direct C-FFI)
Exposes an ISO C header in [`include/sarvam_rust_core.h`](include/sarvam_rust_core.h). Swift imports the symbols directly via Clang C-interop without bridging headers:
```swift
import Sarvam

let resampled = SarvamRustBridge.shared.resampleAudio(
    inputPcm: rawPcm,
    sourceSampleRate: 48000,
    channels: 1
)
```

### 3. Flutter / Dart (`dart:ffi`)
Links dynamically to `libsarvam_rust_core.dylib` / `.so` via `dart:ffi`:
```dart
import 'package:sarvam/src/rust/sarvam_rust_bridge.dart';

final bridge = SarvamRustBridge.instance;
final pcm16k = bridge.resampleAudio(inputPcm, sourceSampleRate: 48000);
```
*(If the native library is not present in runtime environments like Flutter Web, the bridge falls back gracefully to pure Dart).*

### 4. TypeScript & React Native (WebAssembly)
Compiles to `wasm32-unknown-unknown` and loads synchronously or asynchronously via WebAssembly instances:
```typescript
import { SarvamRustBridge } from '@sarvam-mobile/core';

const bridge = new SarvamRustBridge();
await bridge.init();
const delayMs = bridge.computeRetryDelay(1, 429, 3);
```

---

## 🛠️ Building & Testing

### Prerequisites
- **Rust Toolchain**: `rustup` 1.80+ (Stable)
- **Wasm Target**: `rustup target add wasm32-unknown-unknown`

### Compile All Artifacts
Run the unified build script from the repository root:
```bash
./scripts/build-rust-core.sh
```
This produces:
- `target/release/libsarvam_rust_core.dylib` (macOS shared library)
- `target/release/libsarvam_rust_core.a` (static library for iOS/SPM)
- `target/wasm32-unknown-unknown/release/sarvam_rust_core.wasm` (WebAssembly binary)

### Run Test Suite
```bash
cd packages/rust-core
cargo test
```
Verifies all 7 core modules:
- `auth`: Proactive expiration and refresh scheduling.
- `audio`: 48 kHz / 44.1 kHz to 16 kHz mono downsampling fidelity.
- `retry`: Exponential backoff with full jitter and `Retry-After` parsing.
- `sse`: Chunk boundary reconstruction and error frame extraction.
- `realtime`: Conversational speech events and state transitions.
- `ffi`: C-ABI and JNI interface integrity.

---

## 📄 License

Licensed under the [MIT License](../../LICENSE). Copyright © 2026 Sarvam AI and contributors.
