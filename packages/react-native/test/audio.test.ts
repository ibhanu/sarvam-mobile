import { test, describe } from 'node:test';
import assert from 'node:assert/strict';
import {
  PcmResampler,
  SarvamAudioRecorder,
  SarvamAudioPlayer,
  BargeInCoordinator,
} from '../dist/esm/index.js';
import type {
  ReactNativeAudioDriver,
  AudioRecorderDriver,
  AudioPlayerDriver,
} from '../dist/esm/index.js';

describe('React Native Audio Companion Module Tests', () => {
  // ========================================================
  // 1. PcmResampler Tests
  // ========================================================
  describe('1. PcmResampler', () => {
    test('downsamples 48kHz mono Float32 (100ms) to 16kHz mono linear16 Uint8Array', () => {
      const sampleRate = 48000;
      const targetRate = 16000;
      const durationS = 0.1; // 100ms
      const inputSamples = Math.floor(sampleRate * durationS); // 4800 samples

      // Create 440 Hz test tone in Float32
      const input = new Float32Array(inputSamples);
      for (let i = 0; i < inputSamples; i++) {
        input[i] = Math.sin((2 * Math.PI * 440 * i) / sampleRate);
      }

      const resampler = new PcmResampler({
        sourceSampleRate: 48000,
        targetSampleRate: 16000,
        channels: 1,
      });

      const output = resampler.resample(input);

      // 4800 / 3 = 1600 samples * 2 bytes per sample = 3200 bytes
      const expectedSamples = Math.floor(targetRate * durationS);
      const expectedBytes = expectedSamples * 2;
      assert.equal(output.length, expectedBytes);

      // Verify samples are non-zero and within valid 16-bit range
      let nonZeroCount = 0;
      for (let i = 0; i < output.length; i += 2) {
        const low = output[i]!;
        const high = output[i + 1]!;
        let val = (high << 8) | low;
        if (val >= 0x8000) val -= 0x10000;
        if (val !== 0) nonZeroCount++;
        assert(val >= -32768 && val <= 32767);
      }
      assert(nonZeroCount > 1000);
    });

    test('downsamples 44.1kHz stereo Int16 (100ms) to 16kHz mono linear16 Uint8Array', () => {
      const sampleRate = 44100;
      const durationS = 0.1;
      const frames = Math.floor(sampleRate * durationS); // 4410 frames
      const input = new Int16Array(frames * 2); // stereo = 8820 samples

      for (let i = 0; i < frames; i++) {
        const val = Math.round(Math.sin((2 * Math.PI * 440 * i) / sampleRate) * 16000);
        input[i * 2] = val; // Left
        input[i * 2 + 1] = val; // Right
      }

      const resampler = new PcmResampler({
        sourceSampleRate: 44100,
        targetSampleRate: 16000,
        channels: 2,
      });

      const output = resampler.resample(input);

      // 4410 / (44100/16000) = 1600 samples * 2 bytes = 3200 bytes
      const expectedSamples = Math.floor(frames / (44100 / 16000));
      assert.equal(output.length, expectedSamples * 2);
    });

    test('calculates accurate RMS level for silence and sine waves', () => {
      const samples = 1000;

      // Silence
      const silence = new Float32Array(samples);
      const silenceRms = PcmResampler.calculateRms(silence);
      assert.equal(silenceRms, 0);

      // Full-scale sine wave RMS should be ~ 1/sqrt(2) = 0.7071
      const sine = new Float32Array(samples);
      for (let i = 0; i < samples; i++) {
        sine[i] = Math.sin((2 * Math.PI * 10 * i) / samples);
      }
      const sineRms = PcmResampler.calculateRms(sine);
      assert(Math.abs(sineRms - 0.707) < 0.05);

      // Full-scale square wave RMS should be exactly 1.0
      const square = new Float32Array(samples);
      for (let i = 0; i < samples; i++) {
        square[i] = i % 2 === 0 ? 1.0 : -1.0;
      }
      const squareRms = PcmResampler.calculateRms(square);
      assert(Math.abs(squareRms - 1.0) < 0.001);
    });
  });

  // ========================================================
  // 2. SarvamAudioRecorder Tests
  // ========================================================
  describe('2. SarvamAudioRecorder', () => {
    test('captures frames and handles bounded queue backpressure (drop oldest)', async () => {
      let dataCallback: ((chunk: Float32Array) => void) | null = null;
      let stopCalled = false;

      const mockDriver: AudioRecorderDriver = {
        startRecording: (cb) => {
          dataCallback = cb as any;
        },
        stopRecording: () => {
          stopCalled = true;
        },
        getSampleRate: () => 48000,
        getChannels: () => 1,
      };

      let droppedCount = 0;
      const recorder = new SarvamAudioRecorder({
        driver: mockDriver,
        sourceSampleRate: 48000,
        channels: 1,
        maxQueueSize: 3,
        onDroppedFrame: (n) => {
          droppedCount += n;
        },
      });

      // Pause piping to simulate downstream socket backpressure
      recorder.setPaused(true);
      await recorder.start();
      assert(recorder.isRecording);
      assert(dataCallback !== null);

      // Emit 5 chunks of 480 samples each
      for (let i = 0; i < 5; i++) {
        const chunk = new Float32Array(480).fill(i + 1);
        dataCallback!(chunk);
      }

      // Max queue size is 3, so 2 frames should have been dropped
      assert.equal(recorder.queuedFramesCount, 3);
      assert.equal(droppedCount, 2);

      // Attach a mock session and resume: remaining 3 frames should be piped
      const sentAudio: Uint8Array[] = [];
      const mockSession: any = {
        sendAudio: (bytes: Uint8Array) => {
          sentAudio.push(bytes);
        },
      };

      recorder.pipeTo(mockSession);
      recorder.setPaused(false);

      assert.equal(sentAudio.length, 3);
      assert.equal(recorder.queuedFramesCount, 0);

      await recorder.stop();
      assert(!recorder.isRecording);
      assert(stopCalled);
    });
  });

  // ========================================================
  // 3. SarvamAudioPlayer Tests
  // ========================================================
  describe('3. SarvamAudioPlayer', () => {
    test('plays chunked streams and instantly stops and flushes', async () => {
      const playedChunks: Uint8Array[] = [];
      let flushCalled = false;
      let stopCalled = false;

      const mockDriver: AudioPlayerDriver = {
        playChunk: async (bytes) => {
          playedChunks.push(bytes);
        },
        stop: async () => {
          stopCalled = true;
        },
        flush: async () => {
          flushCalled = true;
        },
      };

      const player = new SarvamAudioPlayer({ driver: mockDriver });

      // Create an async generator of 5 chunks
      async function* generateChunks() {
        for (let i = 0; i < 5; i++) {
          yield new Uint8Array([i, i + 1]);
        }
      }

      const playPromise = player.playStream(generateChunks());
      assert(player.isPlaying);

      await playPromise;
      assert.equal(playedChunks.length, 5);
      assert(!player.isPlaying);

      // Test stopAndFlush
      await player.playChunk(new Uint8Array([1, 2]));
      assert(player.isPlaying);

      await player.stopAndFlush();
      assert(!player.isPlaying);
      assert(stopCalled);
      assert(flushCalled);
    });
  });

  // ========================================================
  // 4. BargeInCoordinator Tests
  // ========================================================
  describe('4. BargeInCoordinator', () => {
    test('automatically stops and flushes audio player when vad_speech_start arrives', async () => {
      let stoppedFlushed = false;
      const mockDriver: AudioPlayerDriver = {
        playChunk: async () => {},
        stop: async () => {
          stoppedFlushed = true;
        },
        flush: async () => {},
      };

      const player = new SarvamAudioPlayer({ driver: mockDriver });
      await player.playChunk(new Uint8Array([10, 20]));
      assert(player.isPlaying);

      // Mock STT realtime session with an event stream
      let eventResolver: ((result: IteratorResult<any>) => void) | null = null;
      const mockSession: any = {
        events: {
          [Symbol.asyncIterator]: () => ({
            next: () =>
              new Promise<IteratorResult<any>>((resolve) => {
                eventResolver = resolve;
              }),
          }),
        },
      };

      let bargeInFired = false;
      const coordinator = new BargeInCoordinator({
        session: mockSession,
        player,
        onBargeIn: () => {
          bargeInFired = true;
          coordinator.stop();
        },
      });

      coordinator.start();
      assert(coordinator.isAttached);

      // Emit vad_speech_start
      eventResolver!({
        value: {
          type: 'vad_speech_start',
          timestampMs: 1250,
          raw: { event: 'vad_speech_start' },
        },
        done: false,
      });

      // Allow microtask ticks for async loop to process event
      await new Promise((r) => setTimeout(r, 10));

      // Emit second event to trigger `if (this.cancelled) break;`
      eventResolver!({
        value: { type: 'vad_speech_end', timestampMs: 2000, raw: {} },
        done: false,
      });
      await new Promise((r) => setTimeout(r, 10));

      assert(bargeInFired);
      assert(stoppedFlushed);
      assert(!player.isPlaying);
      assert(!coordinator.isAttached);
    });

    test('BargeInCoordinator edge cases: double start, session error, and cancellation', async () => {
      const mockDriver: AudioPlayerDriver = {
        playChunk: async () => {},
        stop: async () => {},
        flush: async () => {},
      };
      const player = new SarvamAudioPlayer({ driver: mockDriver });

      // Mock session that yields one non-vad event and then throws
      const mockSession: any = {
        events: {
          [Symbol.asyncIterator]: async function* () {
            yield { type: 'recognition', transcript: 'hello' };
            throw new Error('Connection lost');
          },
        },
      };

      const coordinator = new BargeInCoordinator({
        session: mockSession,
        player,
      });

      coordinator.start();
      assert(coordinator.isAttached);
      // Double start is a no-op
      coordinator.start();

      await new Promise((r) => setTimeout(r, 10));
      assert(!coordinator.isAttached);

      // Stop after finished
      coordinator.stop();
      assert(!coordinator.isAttached);
    });
  });

  // ========================================================
  // 5. PcmResampler Full Edge Case Coverage
  // ========================================================
  describe('5. PcmResampler Edge Cases', () => {
    test('resamples with sourceSampleRate === targetSampleRate (passthrough)', () => {
      const resampler = new PcmResampler({
        sourceSampleRate: 16000,
        targetSampleRate: 16000,
      });
      const input = new Float32Array([0.0, 0.5, -0.5, 1.0, -1.0]);
      const output = resampler.resample(input);
      assert.equal(output.length, input.length * 2);
    });

    test('resamples Uint8Array mono and stereo raw PCM bytes', () => {
      // 16-bit LE bytes for mono
      const monoBytes = new Uint8Array([0x00, 0x00, 0x00, 0x40, 0x00, 0x80]); // 0, 16384, -32768
      const resamplerMono = new PcmResampler({
        sourceSampleRate: 32000,
        targetSampleRate: 16000,
        channels: 1,
      });
      const outMono = resamplerMono.resample(monoBytes);
      assert.ok(outMono.length > 0);

      // 16-bit LE bytes for stereo
      const stereoBytes = new Uint8Array([
        0x00, 0x20, 0x00, 0x20, // frame 1 L & R
        0x00, 0x40, 0x00, 0x40, // frame 2 L & R
        0x00, 0x10, 0x00, 0x10, // frame 3 L & R
        0x00, 0x00, 0x00, 0x00, // frame 4 L & R
      ]);
      const resamplerStereo = new PcmResampler({
        sourceSampleRate: 32000,
        targetSampleRate: 16000,
        channels: 2,
      });
      const outStereo = resamplerStereo.resample(stereoBytes);
      assert.ok(outStereo.length > 0);
    });

    test('resamples Float32Array stereo and clamps extreme values', () => {
      const stereoFloats = new Float32Array([
        2.5, 3.0,   // clamped to 1.0
        -2.5, -3.0, // clamped to -1.0
        0.0, 0.0,
        0.5, 0.5,
      ]);
      const resampler = new PcmResampler({
        sourceSampleRate: 48000,
        targetSampleRate: 16000,
        channels: 2,
      });
      const out = resampler.resample(stereoFloats);
      assert.ok(out.length > 0);
    });

    test('calculateRms handles empty array, Int16Array, and Uint8Array', () => {
      assert.equal(PcmResampler.calculateRms(new Float32Array(0)), 0);

      const int16s = new Int16Array([1000, -1000, 2000, -2000]);
      const rmsInt16 = PcmResampler.calculateRms(int16s);
      assert(rmsInt16 > 0);

      const uint8s = new Uint8Array([0x00, 0x10, 0x00, 0x20]);
      const rmsUint8 = PcmResampler.calculateRms(uint8s);
      assert(rmsUint8 > 0);
    });
  });

  // ========================================================
  // 6. SarvamAudioPlayer & Recorder Additional Coverage
  // ========================================================
  describe('6. Player & Recorder Extended Coverage', () => {
    test('SarvamAudioPlayer attachSession streams audio and completes', async () => {
      const playedChunks: Uint8Array[] = [];
      const mockDriver: ReactNativeAudioDriver = {
        playChunk: async (bytes) => {
          playedChunks.push(bytes);
        },
        flushPlayback: async () => {},
        stopPlayback: async () => {},
      };

      const player = new SarvamAudioPlayer({ driver: mockDriver });

      // Mock TtsStreamingSession
      async function* eventGen() {
        yield { type: 'audio', audioBytes: new Uint8Array([1, 2, 3]) };
        yield { type: 'completed' };
      }
      const mockSession: any = { events: eventGen() };

      const detach = player.attachSession(mockSession);
      await new Promise((r) => setTimeout(r, 20));

      assert.equal(playedChunks.length, 1);
      assert(!player.isPlaying);

      detach();
    });

    test('SarvamAudioPlayer handles concurrent playStream, abort on stopAndFlush, and session errors', async () => {
      let flushPlaybackCalled = false;
      let stopPlaybackCalled = false;

      const mockDriver: ReactNativeAudioDriver = {
        playChunk: async () => {},
        flushPlayback: async () => {
          flushPlaybackCalled = true;
        },
        stopPlayback: async () => {
          stopPlaybackCalled = true;
        },
      };

      const player = new SarvamAudioPlayer({ driver: mockDriver });

      // 1. Session error catch in attachSession
      async function* errorEventGen() {
        yield { type: 'audio', audioBytes: new Uint8Array([9, 9]) };
        throw new Error('TTS stream network failure');
      }
      player.attachSession({ events: errorEventGen() } as any);
      await new Promise((r) => setTimeout(r, 20));

      // 2. Play stream and call stopAndFlush while it is still running (triggers abortController.abort())
      async function* slowStream() {
        yield new Uint8Array([1, 2]);
        await new Promise((r) => setTimeout(r, 50));
        yield new Uint8Array([3, 4]);
      }
      const streamPromise1 = player.playStream(slowStream());
      assert(player.isPlaying);

      // Concurrent playStream triggers `if (this.abortController) { this.abortController.abort(); }`
      const streamPromise2 = player.playStream(slowStream());

      await player.stopAndFlush();
      await Promise.all([streamPromise1, streamPromise2]);
      assert(!player.isPlaying);
      assert(flushPlaybackCalled);
      assert(stopPlaybackCalled);
    });

    test('SarvamAudioRecorder handles RMS callback, double start/stop, and default rates', async () => {
      let recordedRms = -1;
      let dataCallback: any = null;

      const mockDriver: AudioRecorderDriver = {
        startRecording: async (cb) => {
          dataCallback = cb;
        },
        stopRecording: async () => {},
        getSampleRate: () => 44100,
        getChannels: () => 1,
      };

      const recorder = new SarvamAudioRecorder({
        driver: mockDriver,
        onRmsLevel: (rms) => {
          recordedRms = rms;
        },
      });

      await recorder.start();
      assert(recorder.isRecording);
      // Double start
      await recorder.start();

      // Emit audio chunk
      dataCallback(new Float32Array([0.5, -0.5, 0.5, -0.5]));
      assert(recordedRms > 0);

      await recorder.stop();
      assert(!recorder.isRecording);
      // Double stop
      await recorder.stop();
    });
  });
});

