# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [0.2.1](https://github.com/ibhanu/sarvam-mobile/compare/dart-audio-v0.2.0...dart-audio-v0.2.1) (2026-10-18)


### Bug Fixes

* **dart:** loosen sarvam dependency constraint to ^0.2.0 in sarvam_flutter_audio ([f7d3717](https://github.com/ibhanu/sarvam-mobile/commit/f7d3717d952a771c4cf780c165c4e601478d13b4))
* update repository and issue tracker URLs to ibhanu/sarvam-mobile and bump dart SDKs to 0.2.1 ([a2c1ab1](https://github.com/ibhanu/sarvam-mobile/commit/a2c1ab1f354719724e02c629f34a3a4f1efb7646))

## [0.2.1] - 2026-10-16

### Fixed
- Fixed repository and issue tracker URLs in `pubspec.yaml` to point to valid, reachable GitHub URLs for pub.dev automated scoring.
- Updated dependency on `sarvam` to `^0.2.1`.

## [0.2.0](https://github.com/ibhanu/sarvam-mobile/compare/dart-audio-v0.1.0...dart-audio-v0.2.0) (2026-10-16)


### Features

* initial commit of Sarvam Mobile SDKs monorepo ([8114f80](https://github.com/ibhanu/sarvam-mobile/commit/8114f80d555332f8fca3f3c84cd720543b42746c))
* **release:** configure multi-registry publishing, licenses, and GitHub Actions release pipeline ([3ab9d6b](https://github.com/ibhanu/sarvam-mobile/commit/3ab9d6bf3e1bcc39ce127d8c2a47298744adae7e))


### Bug Fixes

* update CI Flutter action, upgrade Gradle wrapper, and resolve mic streamer concurrency race ([c23af7d](https://github.com/ibhanu/sarvam-mobile/commit/c23af7d3c1138dbbc93f6462bf3584d2844eb0cb))

## [0.1.0] - 2026-10-16

### Added
- Initial release of `sarvam_flutter_audio` companion package for Sarvam AI Flutter applications.
- **PcmResampler**:
  - High-performance pure Dart linear interpolation audio resampler.
  - Supports converting 48 kHz, 44.1 kHz, or arbitrary input sampling rates to Sarvam's standard 16 kHz mono `linear16` little-endian format.
  - Supports both signed 16-bit PCM bytes (`resamplePcm16`) and 32-bit floating point buffers (`resampleFloat32`).
  - Automatic mono downmixing for stereo audio inputs.
  - Real-time audio metering (`calculateLevels`, `calculateRms`, `calculatePeak`) emitting RMS amplitude, Peak amplitude, and dBFS values.
- **SarvamMicStreamer**:
  - Microphone capture streamer wrapping `AudioRecordDriver`.
  - Built-in bounded queue backpressure mechanism with configurable `maxQueueSize` (dropping oldest frames when saturated to maintain low conversational latency).
  - Direct piping into active `SttRealtimeSession` via `attachSession` and `pipeTo`.
  - Level metering callbacks (`onAudioLevel`, `onRmsLevel`, `onDroppedFrame`).
  - Seamless stream pausing and resuming via `setPaused`.
- **SarvamChunkedAudioPlayer**:
  - Gapless, chunked PCM audio playback driver.
  - Support for playing discrete chunks (`playChunk`), streaming chunk sequences (`playStream`), and direct binding to `TtsStreamingSession` (`attachSession`).
  - Immediate audio cutoff and buffer clearing via `stopAndFlush`.
- **BargeInCoordinator**:
  - Conversational barge-in coordinator connecting `SttRealtimeSession` to `SarvamChunkedAudioPlayer`.
  - Automatic sub-20ms interruption on `VadSpeechStart` events.
  - Dynamic runtime binding and detachment with `attach` and `stop`.
- **Hardware Driver Contracts & In-Memory Mocks**:
  - `AudioRecordDriver` and `AudioPlayDriver` abstraction interfaces.
  - Pre-built `MemoryAudioRecordDriver` and `MemoryAudioPlayDriver` for deterministic, zero-hardware automated unit testing in CI.
