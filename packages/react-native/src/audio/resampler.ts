export interface PcmResamplerOptions {
  /** Sampling rate of incoming audio in Hz (e.g., 48000, 44100). */
  sourceSampleRate: number;
  /** Desired output sampling rate in Hz. Defaults to 16000. */
  targetSampleRate?: number;
  /** Number of interleaved channels in the source audio (1 for mono, 2 for stereo). Defaults to 1. */
  channels?: number;
}

/**
 * Pure TypeScript PCM resampler and audio meter utility.
 * Downsamples 48kHz / 44.1kHz Float32, Int16, or raw PCM Uint8Array audio
 * into Sarvam's strict 16kHz mono linear16 (little-endian) format.
 *
 * Runs without Node.js built-ins or native dependencies.
 */
export class PcmResampler {
  readonly sourceSampleRate: number;
  readonly targetSampleRate: number;
  readonly channels: number;

  constructor(options: PcmResamplerOptions) {
    this.sourceSampleRate = options.sourceSampleRate;
    this.targetSampleRate = options.targetSampleRate ?? 16000;
    this.channels = options.channels ?? 1;
  }

  /**
   * Resamples PCM input into 16kHz mono linear16 (little-endian) Uint8Array bytes.
   */
  resample(input: Float32Array | Int16Array | Uint8Array): Uint8Array {
    return PcmResampler.resample(input, {
      sourceSampleRate: this.sourceSampleRate,
      targetSampleRate: this.targetSampleRate,
      channels: this.channels,
    });
  }

  /**
   * Static helper to resample PCM data without instantiating a class.
   */
  static resample(
    input: Float32Array | Int16Array | Uint8Array,
    options: PcmResamplerOptions
  ): Uint8Array {
    const sourceRate = options.sourceSampleRate;
    const targetRate = options.targetSampleRate ?? 16000;
    const channels = options.channels ?? 1;

    // 1. Convert input into normalized mono Float32Array in [-1.0, 1.0]
    const monoFloats = PcmResampler.toMonoFloat32(input, channels);

    // If source and target sample rates match, simply convert float to linear16
    if (sourceRate === targetRate) {
      return PcmResampler.float32ToLinear16(monoFloats);
    }

    // 2. Downsample/upsample via linear interpolation
    const ratio = sourceRate / targetRate;
    const outSampleCount = Math.floor(monoFloats.length / ratio);
    const outBytes = new Uint8Array(outSampleCount * 2);

    for (let i = 0; i < outSampleCount; i++) {
      const srcPos = i * ratio;
      const idx = Math.floor(srcPos);
      const frac = srcPos - idx;
      const s0 = monoFloats[idx] ?? 0;
      const s1 = monoFloats[idx + 1] ?? s0;
      const interp = s0 + frac * (s1 - s0);

      // Clamp to [-1.0, 1.0]
      const clamped = Math.max(-1.0, Math.min(1.0, interp));
      const int16Val = clamped < 0 ? Math.round(clamped * 32768) : Math.round(clamped * 32767);
      const boundedInt16 = Math.max(-32768, Math.min(32767, int16Val));

      const byteIdx = i * 2;
      outBytes[byteIdx] = boundedInt16 & 0xff;
      outBytes[byteIdx + 1] = (boundedInt16 >> 8) & 0xff;
    }

    return outBytes;
  }

  /**
   * Computes Root-Mean-Square (RMS) amplitude level of PCM input in range [0.0, 1.0].
   */
  static calculateRms(
    input: Float32Array | Int16Array | Uint8Array,
    channels = 1
  ): number {
    const monoFloats = PcmResampler.toMonoFloat32(input, channels);
    if (monoFloats.length === 0) return 0;

    let sumSquares = 0;
    for (let i = 0; i < monoFloats.length; i++) {
      const val = monoFloats[i]!;
      sumSquares += val * val;
    }

    return Math.sqrt(sumSquares / monoFloats.length);
  }

  private static toMonoFloat32(
    input: Float32Array | Int16Array | Uint8Array,
    channels: number
  ): Float32Array {
    if (input instanceof Float32Array) {
      if (channels === 1) return input;
      const monoLen = Math.floor(input.length / channels);
      const mono = new Float32Array(monoLen);
      for (let i = 0; i < monoLen; i++) {
        let sum = 0;
        for (let c = 0; c < channels; c++) {
          sum += input[i * channels + c] ?? 0;
        }
        mono[i] = sum / channels;
      }
      return mono;
    }

    if (input instanceof Int16Array) {
      const sampleCount = input.length;
      if (channels === 1) {
        const mono = new Float32Array(sampleCount);
        for (let i = 0; i < sampleCount; i++) {
          mono[i] = input[i]! / 32768.0;
        }
        return mono;
      }
      const monoLen = Math.floor(sampleCount / channels);
      const mono = new Float32Array(monoLen);
      for (let i = 0; i < monoLen; i++) {
        let sum = 0;
        for (let c = 0; c < channels; c++) {
          sum += input[i * channels + c] ?? 0;
        }
        mono[i] = sum / (channels * 32768.0);
      }
      return mono;
    }

    // Uint8Array: raw 16-bit signed LE bytes
    const totalSamples = Math.floor(input.byteLength / 2);
    if (channels === 1) {
      const mono = new Float32Array(totalSamples);
      for (let i = 0; i < totalSamples; i++) {
        const low = input[i * 2] ?? 0;
        const high = input[i * 2 + 1] ?? 0;
        let s16 = (high << 8) | low;
        if (s16 >= 0x8000) s16 -= 0x10000;
        mono[i] = s16 / 32768.0;
      }
      return mono;
    }

    const monoLen = Math.floor(totalSamples / channels);
    const mono = new Float32Array(monoLen);
    for (let i = 0; i < monoLen; i++) {
      let sum = 0;
      for (let c = 0; c < channels; c++) {
        const idx = (i * channels + c) * 2;
        const low = input[idx] ?? 0;
        const high = input[idx + 1] ?? 0;
        let s16 = (high << 8) | low;
        if (s16 >= 0x8000) s16 -= 0x10000;
        sum += s16;
      }
      mono[i] = sum / (channels * 32768.0);
    }
    return mono;
  }

  private static float32ToLinear16(floats: Float32Array): Uint8Array {
    const outBytes = new Uint8Array(floats.length * 2);
    for (let i = 0; i < floats.length; i++) {
      const clamped = Math.max(-1.0, Math.min(1.0, floats[i]!));
      const int16Val = clamped < 0 ? Math.round(clamped * 32768) : Math.round(clamped * 32767);
      const boundedInt16 = Math.max(-32768, Math.min(32767, int16Val));
      outBytes[i * 2] = boundedInt16 & 0xff;
      outBytes[i * 2 + 1] = (boundedInt16 >> 8) & 0xff;
    }
    return outBytes;
  }
}
