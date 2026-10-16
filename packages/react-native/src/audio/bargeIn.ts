import { SttRealtimeSession, SttRealtimeEvent } from '@sarvam/core';
import { SarvamAudioPlayer } from './player.js';

export interface BargeInCoordinatorConfig {
  /** The real-time speech-to-text session emitting VAD boundaries. */
  session: SttRealtimeSession;
  /** The audio player playing TTS responses. */
  player: SarvamAudioPlayer;
  /** Optional callback fired when barge-in is triggered by vad_speech_start. */
  onBargeIn?: (event: SttRealtimeEvent) => void;
}

/**
 * Coordinates barge-in between an active SttRealtimeSession and SarvamAudioPlayer.
 * When the server detects user speech (vad_speech_start event), it immediately
 * stops and flushes ongoing TTS audio playback.
 */
export class BargeInCoordinator {
  private readonly session: SttRealtimeSession;
  private readonly player: SarvamAudioPlayer;
  private readonly onBargeIn?: (event: SttRealtimeEvent) => void;
  private active = false;
  private cancelled = false;

  constructor(config: BargeInCoordinatorConfig) {
    this.session = config.session;
    this.player = config.player;
    this.onBargeIn = config.onBargeIn;
  }

  get isAttached(): boolean {
    return this.active;
  }

  start(): void {
    if (this.active) return;
    this.active = true;
    this.cancelled = false;

    const listen = async () => {
      try {
        for await (const event of this.session.events) {
          if (this.cancelled) break;
          if (event.type === 'vad_speech_start') {
            await this.player.stopAndFlush();
            this.onBargeIn?.(event);
          }
        }
      } catch {
        // Session closed or disconnected
      } finally {
        this.active = false;
      }
    };

    listen();
  }

  stop(): void {
    this.cancelled = true;
    this.active = false;
  }
}
