import 'dart:async';
import 'dart:typed_data';

import 'package:sarvam/sarvam.dart';

import 'audio_drivers.dart';

/// Plays chunked PCM audio received from TTS streams via [AudioPlayDriver].
/// Supports immediate barge-in interruption via [stopAndFlush].
class SarvamChunkedAudioPlayer {
  final AudioPlayDriver _driver;
  bool _isPlaying = false;
  StreamSubscription<dynamic>? _activeSubscription;

  SarvamChunkedAudioPlayer({
    required AudioPlayDriver driver,
  }) : _driver = driver;

  /// Whether the player is currently playing audio.
  bool get isPlaying => _isPlaying;

  /// Plays a single chunk of PCM audio.
  Future<void> playChunk(Uint8List pcmBytes) async {
    _isPlaying = true;
    await _driver.playChunk(pcmBytes);
  }

  /// Plays a stream of PCM audio chunks sequentially.
  Future<void> playStream(Stream<Uint8List> stream) async {
    await stopAndFlush();
    _isPlaying = true;

    final completer = Completer<void>();
    _activeSubscription = stream.listen(
      (chunk) async {
        if (!_isPlaying) return;
        await _driver.playChunk(chunk);
      },
      onError: (Object error, StackTrace stackTrace) {
        _isPlaying = false;
        if (!completer.isCompleted) completer.completeError(error, stackTrace);
      },
      onDone: () {
        _isPlaying = false;
        if (!completer.isCompleted) completer.complete();
      },
      cancelOnError: true,
    );

    return completer.future;
  }

  /// Subscribes to a [TtsStreamingSession] and plays audio chunks as they arrive.
  StreamSubscription<TtsStreamEvent> attachSession(TtsStreamingSession session) {
    _isPlaying = true;
    final sub = session.events.listen(
      (event) async {
        if (event is TtsAudioChunk) {
          if (_isPlaying) {
            await _driver.playChunk(event.audioBytes);
          }
        } else if (event is TtsCompleted) {
          _isPlaying = false;
        }
      },
      onError: (Object error) {
        _isPlaying = false;
      },
      onDone: () {
        _isPlaying = false;
      },
    );
    _activeSubscription = sub;
    return sub;
  }

  /// Convenience alias for [attachSession].
  StreamSubscription<TtsStreamEvent> playSession(TtsStreamingSession session) =>
      attachSession(session);

  /// Immediately halts audio playback and flushes hardware/software buffers.
  /// Designed for sub-20ms barge-in latency.
  Future<void> stopAndFlush() async {
    _isPlaying = false;
    await _activeSubscription?.cancel();
    _activeSubscription = null;

    await _driver.flush();
    await _driver.stop();
  }

  /// Releases resources and halts playback.
  Future<void> close() async {
    await stopAndFlush();
  }
}
