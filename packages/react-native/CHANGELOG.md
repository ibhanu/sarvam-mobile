# Changelog

All notable changes to `@sarvam/react-native` will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [0.4.0](https://github.com/ibhanu/sarvam-mobile/compare/react-native-v0.3.0...react-native-v0.4.0) (2026-10-18)


### Features

* **core:** implement unified cross-platform Rust core engine and automated release pipeline ([7a450ea](https://github.com/ibhanu/sarvam-mobile/commit/7a450ea5185b7be44984d15f7d5ad2610b6de8a2))

## [0.3.0](https://github.com/ibhanu/sarvam-mobile/compare/react-native-v0.2.0...react-native-v0.3.0) (2026-10-18)


### Features

* **npm:** publish @sarvam-mobile/core and @sarvam-mobile/react-native to npm registry ([3ebbf79](https://github.com/ibhanu/sarvam-mobile/commit/3ebbf795afe218f8bc8ec729d16d87080c412a47))


### Bug Fixes

* **react-native:** support &gt;=0.2.0 &lt;1.0.0 dependency range for core package ([5fc3d55](https://github.com/ibhanu/sarvam-mobile/commit/5fc3d55fbfea5d9457e73332ffdef977a1f27e39))
* update repository and issue tracker URLs to ibhanu/sarvam-mobile and bump dart SDKs to 0.2.1 ([a2c1ab1](https://github.com/ibhanu/sarvam-mobile/commit/a2c1ab1f354719724e02c629f34a3a4f1efb7646))

## [0.2.0](https://github.com/ibhanu/sarvam-mobile/compare/react-native-v0.1.0...react-native-v0.2.0) (2026-10-16)


### Features

* initial commit of Sarvam Mobile SDKs monorepo ([8114f80](https://github.com/ibhanu/sarvam-mobile/commit/8114f80d555332f8fca3f3c84cd720543b42746c))
* **release:** configure multi-registry publishing, licenses, and GitHub Actions release pipeline ([3ab9d6b](https://github.com/ibhanu/sarvam-mobile/commit/3ab9d6bf3e1bcc39ce127d8c2a47298744adae7e))


### Bug Fixes

* **ci:** build conformance mock server, select Xcode 16 on macOS, and use flutter test in Dart CI ([5d733a9](https://github.com/ibhanu/sarvam-mobile/commit/5d733a917d4d8d11548212ce3a95a927c0c75ab7))

## [0.1.0] - 2026-10-16

### Added
- **Hermes-Native Client Architecture**: `SarvamReactNativeClient` subclassing `SarvamClient` with defaults optimized for React Native and Expo mobile environments.
- **Native Header-Capable WebSocket**: `ReactNativeWebSocketFactory` leveraging React Native's native 3-argument `WebSocket(url, protocols, { headers })` constructor on iOS/Android, with clean subprotocol fallback (`api-subscription-key.<key>` and `bearer.<token>`) on React Native Web and desktop browsers.
- **Zero Node Polyfills**: Complete elimination of Node.js built-ins (`buffer`, `stream`, `events`, `crypto`, `ws`). All binary operations run directly on standard typed arrays (`Uint8Array`, `Float32Array`, `Int16Array`).
- **Native File Upload Helper**: `fromReactNativeUri(uri, name, mimeType)` creating lightweight `{ uri, name, type }` descriptors with automatic audio MIME type inference.
- **Native FormData Adapter**: `ReactNativeFormDataAdapter` streaming local file URIs directly through React Native's native HTTP stack (RCTNetworking / OkHttp / NSURLSession) without reading files into JavaScript memory.
- **Pure TypeScript PCM Resampler**: `PcmResampler` utility converting 48kHz and 44.1kHz mono/stereo Float32/Int16 microphone chunks into Sarvam's required 16kHz mono linear16 PCM format in pure JavaScript/Hermes.
- **Audio Capture & Playback Utilities**:
  - `SarvamAudioRecorder`: Audio capture with configurable bounded queue and frame dropping under network backpressure, plus RMS volume calculation.
  - `SarvamAudioPlayer`: Chunked streaming audio player with instant `stopAndFlush()` playback abort.
- **Full-Duplex Conversational Turn-Taking**: `BargeInCoordinator` linking `SttRealtimeSession` Voice Activity Detection (VAD) events (`vad_speech_start`) directly to `SarvamAudioPlayer` to immediately cut off speech synthesis when the user speaks.
- **Interactive Example Application**: Standalone Expo / React Native sample application (`example/App.tsx`) showcasing live Indic captions, translation, streaming TTS, and barge-in interruption.
