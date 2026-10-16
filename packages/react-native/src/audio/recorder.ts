import { SttRealtimeSession } from '@sarvam/core';
import { PcmResampler } from './resampler.js';
import { ReactNativeAudioDriver, AudioRecorderDriver } from './driver.js';

export interface SarvamAudioRecorderConfig {
  /** The underlying audio driver responsible for microphone capture. */
  driver: ReactNativeAudioDriver | AudioRecorderDriver;
  /** Optional active STT realtime session to pipe resampled 16kHz PCM frames to. */
  session?: SttRealtimeSession;
  /** Hardware source sampling rate. Defaults to driver.getSampleRate?.() or 48000. */
  sourceSampleRate?: number;
  /** Hardware source channels (1 for mono, 2 for stereo). Defaults to driver.getChannels?.() or 1. */
  channels?: number;
  /** Maximum number of 16kHz audio frames to retain under backpressure. Defaults to 10. */
  maxQueueSize?: number;
  /** Optional callback receiving computed RMS level in [0.0, 1.0] for volume visualizers. */
  onRmsLevel?: (rms: number) => void;
  /** Callback fired whenever the oldest audio frame is dropped due to queue saturation. */
  onDroppedFrame?: (droppedCount: number) => void;
}

export class SarvamAudioRecorder {
  private readonly driver: ReactNativeAudioDriver | AudioRecorderDriver;
  private session: SttRealtimeSession | null = null;
  private readonly resampler: PcmResampler;
  private readonly maxQueueSize: number;
  private readonly frameQueue: Uint8Array[] = [];
  private readonly onRmsLevel?: (rms: number) => void;
  private readonly onDroppedFrame?: (droppedCount: number) => void;
  private active = false;
  private paused = false;

  constructor(config: SarvamAudioRecorderConfig) {
    this.driver = config.driver;
    this.session = config.session ?? null;
    const rate = config.sourceSampleRate ?? this.driver.getSampleRate?.() ?? 48000;
    const channels = config.channels ?? this.driver.getChannels?.() ?? 1;
    this.resampler = new PcmResampler({ sourceSampleRate: rate, targetSampleRate: 16000, channels });
    this.maxQueueSize = config.maxQueueSize ?? 10;
    this.onRmsLevel = config.onRmsLevel;
    this.onDroppedFrame = config.onDroppedFrame;
  }

  get isRecording(): boolean {
    return this.active;
  }

  get queuedFramesCount(): number {
    return this.frameQueue.length;
  }

  pipeTo(session: SttRealtimeSession | null): void {
    this.session = session;
    this.drainQueue();
  }

  setPaused(paused: boolean): void {
    this.paused = paused;
    if (!paused) {
      this.drainQueue();
    }
  }

  async start(): Promise<void> {
    if (this.active) return;
    this.active = true;

    const onData = (chunk: Float32Array | Int16Array | Uint8Array) => {
      this.handleIncomingAudio(chunk);
    };

    if (this.driver.startRecording) {
      await this.driver.startRecording(onData);
    }
  }

  async stop(): Promise<void> {
    if (!this.active) return;
    this.active = false;
    if (this.driver.stopRecording) {
      await this.driver.stopRecording();
    }
    this.frameQueue.length = 0;
  }

  private handleIncomingAudio(chunk: Float32Array | Int16Array | Uint8Array): void {
    if (!this.active) return;

    // Resample incoming audio chunk to 16kHz mono linear16
    const resampledBytes = this.resampler.resample(chunk);

    if (this.onRmsLevel) {
      const rms = PcmResampler.calculateRms(chunk, this.resampler.channels);
      this.onRmsLevel(rms);
    }

    // Bounded queue backpressure: drop oldest frame if saturated
    if (this.frameQueue.length >= this.maxQueueSize) {
      this.frameQueue.shift();
      this.onDroppedFrame?.(1);
    }

    this.frameQueue.push(resampledBytes);
    this.drainQueue();
  }

  private drainQueue(): void {
    if (!this.session || this.paused) return;
    while (this.frameQueue.length > 0) {
      const frame = this.frameQueue.shift()!;
      this.session.sendAudio(frame);
    }
  }
}
