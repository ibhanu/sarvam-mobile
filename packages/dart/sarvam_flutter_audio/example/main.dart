// ignore_for_file: avoid_print
import 'dart:async';
import 'dart:math';
import 'dart:typed_data';

import 'package:flutter/widgets.dart';
import 'package:sarvam_flutter_audio/sarvam_flutter_audio.dart';

/// Synthetic 48 kHz PCM sine wave generator for audio testing without hardware.
Uint8List generateSinePcm48k({
  required double frequency,
  required double durationSeconds,
}) {
  const sampleRate = 48000;
  final sampleCount = (sampleRate * durationSeconds).round();
  final bytes = Uint8List(sampleCount * 2);
  final byteData = ByteData.sublistView(bytes);

  for (var i = 0; i < sampleCount; i++) {
    final t = i / sampleRate;
    final val = sin(2 * pi * frequency * t);
    final sample = (val * 32767.0).round().clamp(-32768, 32767);
    byteData.setInt16(i * 2, sample, Endian.little);
  }
  return bytes;
}

/// Simulated in-memory WebSocket session for offline demonstration.
class SimulatedWebSocketSession implements WebSocketSession {
  final StreamController<dynamic> _controller =
      StreamController<dynamic>.broadcast();
  final List<dynamic> sentFrames = <dynamic>[];

  @override
  Stream<dynamic> get incoming => _controller.stream;

  @override
  void send(dynamic data) {
    sentFrames.add(data);
  }

  void emitServerEvent(String jsonString) {
    _controller.add(jsonString);
  }

  @override
  Future<void> close([int? code, String? reason]) async {
    await _controller.close();
  }
}

/// Clean, runnable Flutter/Dart example demonstrating `sarvam_flutter_audio`:
/// 1. Real-time microphone audio capture & bounded backpressure.
/// 2. Pure Dart 48 kHz to 16 kHz linear16 resampling.
/// 3. Audio volume metering (RMS, Peak, dBFS).
/// 4. Chunked gapless audio playback.
/// 5. Sub-20ms Conversational Barge-In coordination.
Future<void> main() async {
  // Ensure Flutter engine bindings are initialized
  WidgetsFlutterBinding.ensureInitialized();

  print('===========================================================');
  print(' Sarvam AI Flutter Audio & Conversational Barge-In Example');
  print('===========================================================');

  // 1. Setup Audio Record & Playback Drivers
  // In a production Flutter app, plug in platform drivers like record / audioplayers.
  // In tests and CLI examples, Memory drivers provide zero-hardware determinism.
  final recordDriver = MemoryAudioRecordDriver(
    sampleRate: 48000,
    channelCount: 1,
  );
  final playDriver = MemoryAudioPlayDriver();

  // 2. Setup Chunked Audio Player
  final player = SarvamChunkedAudioPlayer(driver: playDriver);

  // 3. Setup Simulated Realtime STT WebSocket Session
  final simulatedWs = SimulatedWebSocketSession();
  final sttSession = SttRealtimeSession(simulatedWs);

  // 4. Setup Barge-In Coordinator
  // Listens for server-side Voice Activity Detection (VadSpeechStart)
  // and halts player immediately when user interrupts.
  var bargeInCount = 0;
  final coordinator = BargeInCoordinator(
    session: sttSession,
    player: player,
    onBargeIn: (event) {
      bargeInCount++;
      print('⚡ [Barge-In Detected] VadSpeechStart event received!');
      print('   -> Halting playback driver and flushing buffers immediately.');
    },
  )..start();

  // 5. Setup Microphone Streamer
  AudioLevel? latestLevel;
  final micStreamer = SarvamMicStreamer(
    driver: recordDriver,
    session: sttSession,
    maxQueueSize: 10,
    onAudioLevel: (level) {
      latestLevel = level;
    },
    onDroppedFrame: (droppedCount) {
      print('⚠️ Buffer saturated: dropped $droppedCount stale audio frame(s)');
    },
  );

  print('\n[Step 1] Starting microphone capture streamer...');
  await micStreamer.start();
  print('MicStreamer active: ${micStreamer.isCapturing}');

  print('\n[Step 2] Simulating incoming 48 kHz microphone frames...');
  // Feed a 440 Hz audio chunk (10ms = 480 samples = 960 bytes at 48kHz)
  final rawAudioChunk = generateSinePcm48k(
    frequency: 440.0,
    durationSeconds: 0.01,
  );
  recordDriver.feedChunk(rawAudioChunk);

  if (latestLevel != null) {
    print('Audio Level: RMS=${latestLevel!.rms.toStringAsFixed(3)}, '
        'Peak=${latestLevel!.peak.toStringAsFixed(3)}, '
        'dBFS=${latestLevel!.dbFs.toStringAsFixed(1)} dBFS');
  }

  print('\n[Step 3] Simulating assistant speech playback...');
  // Assistant is speaking a synthesized sentence
  final ttsChunk = Uint8List(640); // 20ms of 16kHz audio
  await player.playChunk(ttsChunk);
  print('Player isPlaying: ${player.isPlaying}');
  print('Played chunks before interruption: ${playDriver.playedChunks.length}');

  print('\n[Step 4] Simulating user barge-in (User interrupts assistant)...');
  // Server detects speech start and pushes VadSpeechStart event
  simulatedWs.emitServerEvent(
    '{"event": "speech_start", "timestamp": 1234567}',
  );

  // Small delay for microtask event propagation
  await Future<void>.delayed(const Duration(milliseconds: 10));

  print('Barge-in triggered count: $bargeInCount');
  print('Player isPlaying after barge-in: ${player.isPlaying}');
  print('Play driver flushed: ${playDriver.isFlushed}');

  print('\n[Step 5] Cleaning up audio resources...');
  coordinator.stop();
  await micStreamer.close();
  await player.close();
  await sttSession.close();
  await simulatedWs.close();

  print('All audio pipelines successfully stopped.');
}
