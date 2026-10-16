/**
 * Generic audio driver abstraction for React Native runtimes.
 * Compatible with react-native-audio-api (JSI AudioContext/AudioRecorder),
 * expo-audio, and custom Turbo/Nitro C++ audio modules.
 */

export interface AudioRecorderDriver {
  /**
   * Starts recording from the microphone and streams captured audio chunks
   * (Float32Array, Int16Array, or Uint8Array) to the provided callback.
   */
  startRecording(
    onAudioData: (pcmChunk: Float32Array | Int16Array | Uint8Array) => void
  ): Promise<void> | void;

  /**
   * Stops recording and releases hardware microphone resources.
   */
  stopRecording(): Promise<void> | void;

  /**
   * Hardware native sampling rate (e.g. 48000 or 44100).
   */
  getSampleRate?(): number;

  /**
   * Hardware channel count (1 for mono, 2 for stereo).
   */
  getChannels?(): number;
}

export interface AudioPlayerDriver {
  /**
   * Schedules or plays a raw PCM audio chunk.
   */
  playChunk(pcmBytes: Uint8Array): Promise<void> | void;

  /**
   * Immediately stops audio playback.
   */
  stop(): Promise<void> | void;

  /**
   * Flushes any queued audio data pending playback.
   */
  flush?(): Promise<void> | void;

  /**
   * Alternative alias for stop.
   */
  stopPlayback?(): Promise<void> | void;

  /**
   * Alternative alias for flush.
   */
  flushPlayback?(): Promise<void> | void;
}

/**
 * Universal composite audio driver supporting recording, playback, or both.
 */
export interface ReactNativeAudioDriver {
  startRecording?(
    onAudioData: (pcmChunk: Float32Array | Int16Array | Uint8Array) => void
  ): Promise<void> | void;
  stopRecording?(): Promise<void> | void;
  playChunk?(pcmBytes: Uint8Array): Promise<void> | void;
  stopPlayback?(): Promise<void> | void;
  flushPlayback?(): Promise<void> | void;
  stop?(): Promise<void> | void;
  flush?(): Promise<void> | void;
  getSampleRate?(): number;
  getChannels?(): number;
}
