import 'dart:async';
import 'dart:collection';
import 'dart:typed_data';

import 'package:sarvam/sarvam.dart';

import 'audio_drivers.dart';
import 'pcm_resampler.dart';

/// Captures microphone audio via [AudioRecordDriver], resamples incoming PCM frames
/// to 16 kHz mono linear16 format via [PcmResampler], and buffers/streams them with
/// bounded queue backpressure (dropping oldest frames when saturated).
class SarvamMicStreamer {
  final AudioRecordDriver _driver;
  final PcmResampler _resampler;
  final int maxQueueSize;
  final void Function(AudioLevel level)? onAudioLevel;
  final void Function(double rms)? onRmsLevel;
  final void Function(int droppedCount)? onDroppedFrame;

  final Queue<Uint8List> _frameQueue = Queue<Uint8List>();
  final StreamController<Uint8List> _audioStreamController =
      StreamController<Uint8List>.broadcast();

  SttRealtimeSession? _session;
  bool _isActive = false;
  bool _isPaused = false;

  SarvamMicStreamer({
    required AudioRecordDriver driver,
    PcmResampler? resampler,
    this.maxQueueSize = 10,
    this.onAudioLevel,
    this.onRmsLevel,
    this.onDroppedFrame,
    SttRealtimeSession? session,
  })  : _driver = driver,
        _resampler = resampler ??
            PcmResampler(
              sourceSampleRate: driver.sampleRate,
              channels: driver.channelCount,
            ) {
    if (session != null) {
      attachSession(session);
    }
  }

  /// Broadcast stream emitting resampled 16 kHz mono linear16 audio frames.
  Stream<Uint8List> get audioStream => _audioStreamController.stream;

  /// Whether microphone capture is currently active.
  bool get isCapturing => _isActive;

  /// Alias for [isCapturing].
  bool get isRecording => _isActive;

  /// Whether streaming to the attached session is paused.
  bool get isPaused => _isPaused;

  /// Number of frames currently queued in the backpressure buffer.
  int get queuedFramesCount => _frameQueue.length;

  /// Attaches or updates the active [SttRealtimeSession] to receive audio frames.
  void attachSession(SttRealtimeSession? session) {
    _session = session;
    _drainQueue();
  }

  /// Alias for [attachSession].
  void pipeTo(SttRealtimeSession? session) => attachSession(session);

  /// Pauses or resumes streaming frames to the attached session.
  void setPaused(bool paused) {
    _isPaused = paused;
    if (!paused) {
      _drainQueue();
    }
  }

  /// Starts capturing audio from the driver.
  Future<void> start([SttRealtimeSession? session]) async {
    if (_isActive) return;
    if (session != null) {
      attachSession(session);
    }
    _isActive = true;

    await _driver.startRecording(_handleIncomingAudio);
  }

  /// Stops audio capture and clears the frame queue.
  Future<void> stop() async {
    if (!_isActive) return;
    _isActive = false;
    await _driver.stopRecording();
    _frameQueue.clear();
  }

  void _handleIncomingAudio(Uint8List chunk) {
    if (!_isActive) return;

    // Resample incoming audio chunk to 16 kHz mono linear16
    final resampled = _resampler.resample(chunk);

    if (resampled.isEmpty) return;

    if (onAudioLevel != null) {
      onAudioLevel!(PcmResampler.calculateLevels(resampled));
    }
    if (onRmsLevel != null) {
      onRmsLevel!(PcmResampler.calculateRms(resampled));
    }

    // Bounded backpressure: drop oldest frame if saturated
    if (_frameQueue.length >= maxQueueSize) {
      _frameQueue.removeFirst();
      onDroppedFrame?.call(1);
    }

    _frameQueue.add(resampled);
    if (!_audioStreamController.isClosed) {
      _audioStreamController.add(resampled);
    }

    _drainQueue();
  }

  void _drainQueue() {
    if (_session == null || _isPaused) return;

    while (_frameQueue.isNotEmpty) {
      final frame = _frameQueue.removeFirst();
      _session!.sendAudio(frame);
    }
  }

  /// Releases resources held by the streamer.
  Future<void> close() async {
    await stop();
    await _audioStreamController.close();
    _session = null;
  }
}
