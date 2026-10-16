import 'dart:math';
import 'dart:typed_data';

/// Audio meter metrics representing volume and dynamic range.
class AudioLevel {
  /// Root-Mean-Square amplitude in normalized range [0.0, 1.0].
  final double rms;

  /// Absolute peak amplitude in normalized range [0.0, 1.0].
  final double peak;

  /// Decibels relative to Full Scale in range [-100.0, 0.0] dBFS.
  final double dbFs;

  const AudioLevel({
    required this.rms,
    required this.peak,
    required this.dbFs,
  });

  @override
  String toString() => 'AudioLevel(rms: $rms, peak: $peak, dbFs: $dbFs)';

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is AudioLevel &&
          runtimeType == other.runtimeType &&
          rms == other.rms &&
          peak == other.peak &&
          dbFs == other.dbFs;

  @override
  int get hashCode => Object.hash(rms, peak, dbFs);
}

/// High-performance pure Dart PCM audio resampler and audio meter utility.
///
/// Converts 48kHz, 44.1kHz, or other sampling rates in PCM16 or Float32 (mono or stereo)
/// into Sarvam's strict 16kHz mono `linear16` little-endian format.
class PcmResampler {
  /// Target sampling rate required by Sarvam AI speech models (16000 Hz).
  static const int targetSampleRate = 16000;

  /// Source sampling rate of the incoming audio in Hz. Defaults to 48000.
  final int sourceSampleRate;

  /// Number of channels in the incoming audio (1 for mono, 2 for stereo). Defaults to 1.
  final int channels;

  const PcmResampler({
    this.sourceSampleRate = 48000,
    this.channels = 1,
  });

  /// Convenience instance method resampling incoming PCM16 bytes using configured rates.
  Uint8List resample(Uint8List inputBytes) {
    return resamplePcm16(
      inputBytes,
      inputSampleRate: sourceSampleRate,
      channelCount: channels,
    );
  }

  /// Resamples little-endian signed 16-bit PCM [inputBytes] into 16kHz mono linear16 [Uint8List].
  static Uint8List resamplePcm16(
    Uint8List inputBytes, {
    int inputSampleRate = 48000,
    int channelCount = 1,
  }) {
    if (inputBytes.isEmpty) return Uint8List(0);
    if (channelCount < 1 || channelCount > 2) {
      throw ArgumentError('channelCount must be 1 (mono) or 2 (stereo)');
    }

    final bytesPerFrame = 2 * channelCount;
    final numFrames = inputBytes.lengthInBytes ~/ bytesPerFrame;
    if (numFrames == 0) return Uint8List(0);

    final byteData = ByteData.sublistView(inputBytes);
    final monoSamples = Int16List(numFrames);

    if (channelCount == 1) {
      for (var i = 0; i < numFrames; i++) {
        monoSamples[i] = byteData.getInt16(i * 2, Endian.little);
      }
    } else {
      for (var i = 0; i < numFrames; i++) {
        final offset = i * 4;
        final left = byteData.getInt16(offset, Endian.little);
        final right = byteData.getInt16(offset + 2, Endian.little);
        monoSamples[i] = ((left + right) ~/ 2).clamp(-32768, 32767);
      }
    }

    if (inputSampleRate == targetSampleRate) {
      final out = Uint8List(numFrames * 2);
      final outData = ByteData.sublistView(out);
      for (var i = 0; i < numFrames; i++) {
        outData.setInt16(i * 2, monoSamples[i], Endian.little);
      }
      return out;
    }

    return _resampleMonoSamples(monoSamples, inputSampleRate);
  }

  /// Resamples [inputFloats] (normalized in [-1.0, 1.0]) into 16kHz mono linear16 [Uint8List].
  static Uint8List resampleFloat32(
    Float32List inputFloats, {
    int inputSampleRate = 48000,
    int channelCount = 1,
  }) {
    if (inputFloats.isEmpty) return Uint8List(0);
    if (channelCount < 1 || channelCount > 2) {
      throw ArgumentError('channelCount must be 1 (mono) or 2 (stereo)');
    }

    final numFrames = inputFloats.length ~/ channelCount;
    if (numFrames == 0) return Uint8List(0);

    final monoSamples = Int16List(numFrames);
    for (var i = 0; i < numFrames; i++) {
      double monoFloat;
      if (channelCount == 1) {
        monoFloat = inputFloats[i];
      } else {
        monoFloat = (inputFloats[i * 2] + inputFloats[i * 2 + 1]) / 2.0;
      }
      final clamped = monoFloat.clamp(-1.0, 1.0);
      final int16Val = (clamped < 0 ? clamped * 32768.0 : clamped * 32767.0)
          .round()
          .clamp(-32768, 32767);
      monoSamples[i] = int16Val;
    }

    if (inputSampleRate == targetSampleRate) {
      final out = Uint8List(numFrames * 2);
      final outData = ByteData.sublistView(out);
      for (var i = 0; i < numFrames; i++) {
        outData.setInt16(i * 2, monoSamples[i], Endian.little);
      }
      return out;
    }

    return _resampleMonoSamples(monoSamples, inputSampleRate);
  }

  /// Resamples raw Float32 [inputBytes] (little-endian 4-byte IEEE floats) into 16kHz mono linear16 [Uint8List].
  static Uint8List resampleFloat32Bytes(
    Uint8List inputBytes, {
    int inputSampleRate = 48000,
    int channelCount = 1,
  }) {
    if (inputBytes.isEmpty) return Uint8List(0);
    final bytesPerFrame = 4 * channelCount;
    final numFrames = inputBytes.lengthInBytes ~/ bytesPerFrame;
    if (numFrames == 0) return Uint8List(0);

    final byteData = ByteData.sublistView(inputBytes);
    final floatList = Float32List(numFrames * channelCount);
    for (var i = 0; i < floatList.length; i++) {
      floatList[i] = byteData.getFloat32(i * 4, Endian.little);
    }

    return resampleFloat32(
      floatList,
      inputSampleRate: inputSampleRate,
      channelCount: channelCount,
    );
  }

  static Uint8List _resampleMonoSamples(
    Int16List monoSamples,
    int inputSampleRate,
  ) {
    final numInput = monoSamples.length;
    final outSampleCount =
        ((numInput * targetSampleRate + (inputSampleRate ~/ 2)) ~/ inputSampleRate);
    final out = Uint8List(outSampleCount * 2);
    final outData = ByteData.sublistView(out);
    final ratio = inputSampleRate / targetSampleRate;

    for (var i = 0; i < outSampleCount; i++) {
      final srcPos = i * ratio;
      final idx = srcPos.floor();
      final frac = srcPos - idx;

      final s0 = monoSamples[idx.clamp(0, numInput - 1)].toDouble();
      final s1 = monoSamples[(idx + 1).clamp(0, numInput - 1)].toDouble();
      final interp =
          ((1.0 - frac) * s0 + frac * s1).round().clamp(-32768, 32767);

      outData.setInt16(i * 2, interp, Endian.little);
    }
    return out;
  }

  /// Computes comprehensive audio levels (RMS, peak, and dBFS) of signed 16-bit PCM [pcm16Bytes].
  static AudioLevel calculateLevels(Uint8List pcm16Bytes) {
    final numSamples = pcm16Bytes.lengthInBytes ~/ 2;
    if (numSamples == 0) {
      return const AudioLevel(rms: 0.0, peak: 0.0, dbFs: -100.0);
    }

    final byteData = ByteData.sublistView(pcm16Bytes);
    var peak = 0.0;
    var sumSquares = 0.0;

    for (var i = 0; i < numSamples; i++) {
      final sample = byteData.getInt16(i * 2, Endian.little);
      final normalized = sample.abs() / 32768.0;
      if (normalized > peak) peak = normalized;
      sumSquares += normalized * normalized;
    }

    final rms = sqrt(sumSquares / numSamples);
    final dbFs =
        rms > 0.0 ? (20.0 * (log(rms) / ln10)).clamp(-100.0, 0.0) : -100.0;

    return AudioLevel(
      rms: rms,
      peak: peak,
      dbFs: dbFs,
    );
  }

  /// Computes Root-Mean-Square (RMS) amplitude level of PCM16 audio in range [0.0, 1.0].
  static double calculateRms(Uint8List pcm16Bytes) =>
      calculateLevels(pcm16Bytes).rms;

  /// Computes Peak amplitude level of PCM16 audio in range [0.0, 1.0].
  static double calculatePeak(Uint8List pcm16Bytes) =>
      calculateLevels(pcm16Bytes).peak;
}
