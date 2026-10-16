import { TtsStreamingSession } from '@sarvam/core';
import { ReactNativeAudioDriver, AudioPlayerDriver } from './driver.js';

export interface SarvamAudioPlayerConfig {
  /** The underlying audio driver responsible for playback. */
  driver: ReactNativeAudioDriver | AudioPlayerDriver;
}

export class SarvamAudioPlayer {
  private readonly driver: ReactNativeAudioDriver | AudioPlayerDriver;
  private active = false;
  private abortController: AbortController | null = null;
  private activeSession: TtsStreamingSession | null = null;

  constructor(config: SarvamAudioPlayerConfig) {
    this.driver = config.driver;
  }

  get isPlaying(): boolean {
    return this.active;
  }

  async playChunk(pcmBytes: Uint8Array): Promise<void> {
    this.active = true;
    if (this.driver.playChunk) {
      await this.driver.playChunk(pcmBytes);
    }
  }

  async playStream(stream: AsyncIterable<Uint8Array>): Promise<void> {
    this.active = true;
    if (this.abortController) {
      this.abortController.abort();
    }
    const ac = new AbortController();
    this.abortController = ac;

    try {
      for await (const chunk of stream) {
        if (ac.signal.aborted) break;
        await this.playChunk(chunk);
      }
    } finally {
      if (this.abortController === ac) {
        this.active = false;
        this.abortController = null;
      }
    }
  }

  attachSession(session: TtsStreamingSession): () => void {
    this.activeSession = session;
    let cancelled = false;

    const run = async () => {
      try {
        for await (const event of session.events) {
          if (cancelled) break;
          if (event.type === 'audio') {
            await this.playChunk(event.audioBytes);
          } else if (event.type === 'completed') {
            this.active = false;
          }
        }
      } catch {
        // Stream ended or cancelled
      }
    };

    run();

    return () => {
      cancelled = true;
      if (this.activeSession === session) {
        this.activeSession = null;
      }
    };
  }

  async stopAndFlush(): Promise<void> {
    this.active = false;
    if (this.abortController) {
      this.abortController.abort();
      this.abortController = null;
    }
    this.activeSession = null;

    if (this.driver.flushPlayback) {
      await this.driver.flushPlayback();
    } else if (this.driver.flush) {
      await this.driver.flush();
    }

    if (this.driver.stopPlayback) {
      await this.driver.stopPlayback();
    } else if (this.driver.stop) {
      await this.driver.stop();
    }
  }
}
