import 'dart:async';
import 'dart:typed_data';

/// Abstraction for microphone audio capture hardware or plugins.
abstract class AudioRecordDriver {
  /// Sampling rate of the audio input in Hz (e.g. 48000, 44100, 16000).
  int get sampleRate;

  /// Number of interleaved audio channels (1 for mono, 2 for stereo).
  int get channelCount;

  /// Whether the driver is currently capturing audio.
  bool get isRecording;

  /// Starts capturing audio, delivering raw PCM chunks to [onAudioData].
  FutureOr<void> startRecording(void Function(Uint8List pcmChunk) onAudioData);

  /// Stops audio capture and releases microphone hardware resources.
  FutureOr<void> stopRecording();
}

/// Abstraction for chunked audio playback drivers.
abstract class AudioPlayDriver {
  /// Whether the driver is currently playing audio.
  bool get isPlaying;

  /// Schedules or plays a raw PCM audio chunk.
  FutureOr<void> playChunk(Uint8List pcmBytes);

  /// Immediately halts audio playback.
  FutureOr<void> stop();

  /// Flushes any pending or queued audio data in hardware buffers.
  FutureOr<void> flush();
}

/// In-memory mock audio recording driver for unit testing or deterministic canned streaming.
class MemoryAudioRecordDriver implements AudioRecordDriver {
  final List<Uint8List> _chunks;
  final int _sampleRate;
  final int _channelCount;
  bool _isRecording = false;
  void Function(Uint8List pcmChunk)? _listener;

  MemoryAudioRecordDriver({
    List<Uint8List>? chunks,
    int sampleRate = 48000,
    int channelCount = 1,
  })  : _chunks = chunks ?? <Uint8List>[],
        _sampleRate = sampleRate,
        _channelCount = channelCount;

  @override
  int get sampleRate => _sampleRate;

  @override
  int get channelCount => _channelCount;

  @override
  bool get isRecording => _isRecording;

  @override
  FutureOr<void> startRecording(void Function(Uint8List pcmChunk) onAudioData) {
    _isRecording = true;
    _listener = onAudioData;
    for (final chunk in _chunks) {
      if (!_isRecording) break;
      onAudioData(chunk);
    }
  }

  /// Pushes a single audio chunk to the active listener.
  void feedChunk(Uint8List chunk) {
    if (_isRecording) {
      _listener?.call(chunk);
    }
  }

  @override
  FutureOr<void> stopRecording() {
    _isRecording = false;
    _listener = null;
  }
}

/// In-memory mock audio playback driver for unit testing.
class MemoryAudioPlayDriver implements AudioPlayDriver {
  final List<Uint8List> _playedChunks = <Uint8List>[];
  bool _isPlaying = false;
  bool _isFlushed = false;

  /// Read-only view of chunks received for playback.
  List<Uint8List> get playedChunks => List<Uint8List>.unmodifiable(_playedChunks);

  /// Whether [flush] was called.
  bool get isFlushed => _isFlushed;

  @override
  bool get isPlaying => _isPlaying;

  @override
  FutureOr<void> playChunk(Uint8List pcmBytes) {
    _isPlaying = true;
    _isFlushed = false;
    _playedChunks.add(pcmBytes);
  }

  @override
  FutureOr<void> flush() {
    _isFlushed = true;
    _playedChunks.clear();
  }

  @override
  FutureOr<void> stop() {
    _isPlaying = false;
  }
}
