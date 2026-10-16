# Changelog

All notable changes to `@sarvam/react-native` will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

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
