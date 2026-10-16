import 'dart:async';

import 'package:sarvam/sarvam.dart';

import 'sarvam_chunked_audio_player.dart';

/// Coordinates conversational barge-in between an active [SttRealtimeSession]
/// and a [SarvamChunkedAudioPlayer].
///
/// When the server detects user speech (emitting [VadSpeechStart] / [SttVadSpeechStart]),
/// the coordinator immediately invokes [SarvamChunkedAudioPlayer.stopAndFlush] to silence
/// ongoing synthetic speech and clear pending audio buffers.
class BargeInCoordinator {
  final SttRealtimeSession? _session;
  final SarvamChunkedAudioPlayer? _player;
  final void Function(SttRealtimeEvent event)? onBargeIn;

  StreamSubscription<SttRealtimeEvent>? _subscription;
  bool _isAttached = false;

  BargeInCoordinator({
    SttRealtimeSession? session,
    SarvamChunkedAudioPlayer? player,
    this.onBargeIn,
  })  : _session = session,
        _player = player;

  /// Whether the coordinator is currently actively listening to session events.
  bool get isAttached => _isAttached;

  /// Starts listening to the configured [SttRealtimeSession] and halts the [SarvamChunkedAudioPlayer]
  /// whenever [SttVadSpeechStart] is received.
  void start() {
    if (_isAttached || _session == null || _player == null) return;
    attach(session: _session, player: _player);
  }

  /// Attaches to [session] and interrupts [player] on VAD speech start.
  StreamSubscription<SttRealtimeEvent> attach({
    required SttRealtimeSession session,
    required SarvamChunkedAudioPlayer player,
  }) {
    stop();
    _isAttached = true;

    final sub = session.events.listen((event) async {
      if (event is VadSpeechStart) {
        await player.stopAndFlush();
        onBargeIn?.call(event);
      }
    });

    _subscription = sub;
    return sub;
  }

  /// Stops listening and detaches from the session.
  void stop() {
    _isAttached = false;
    _subscription?.cancel();
    _subscription = null;
  }
}
