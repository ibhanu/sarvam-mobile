# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

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
