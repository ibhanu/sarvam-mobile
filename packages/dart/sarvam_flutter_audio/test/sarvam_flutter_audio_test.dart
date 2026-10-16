import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:sarvam_flutter_audio/sarvam_flutter_audio.dart';

class MockWebSocketSession implements WebSocketSession {
  final StreamController<dynamic> _incomingController =
      StreamController<dynamic>.broadcast();
  final List<dynamic> sentFrames = <dynamic>[];
  bool isClosed = false;
  int? closeCode;
  String? closeReason;

  @override
  Stream<dynamic> get incoming => _incomingController.stream;

  @override
  void send(dynamic data) {
    sentFrames.add(data);
  }

  void pushIncoming(dynamic frame) {
    _incomingController.add(frame);
  }

  @override
  Future<void> close([int? code, String? reason]) async {
    isClosed = true;
    closeCode = code;
    closeReason = reason;
    await _incomingController.close();
  }
}

Uint8List createPcm16Sine({
  required int sampleRate,
  required double frequency,
  required double durationSeconds,
  double amplitude = 1.0,
}) {
  final sampleCount = (sampleRate * durationSeconds).round();
  final bytes = Uint8List(sampleCount * 2);
  final byteData = ByteData.sublistView(bytes);

  for (var i = 0; i < sampleCount; i++) {
    final t = i / sampleRate;
    final val = sin(2 * pi * frequency * t) * amplitude;
    final sample = (val * 32767.0).round().clamp(-32768, 32767);
    byteData.setInt16(i * 2, sample, Endian.little);
  }
  return bytes;
}

Uint8List createPcm16Stereo({
  required int sampleRate,
  required int frameCount,
  required int leftVal,
  required int rightVal,
}) {
  final bytes = Uint8List(frameCount * 4);
  final byteData = ByteData.sublistView(bytes);
  for (var i = 0; i < frameCount; i++) {
    byteData.setInt16(i * 4, leftVal, Endian.little);
    byteData.setInt16(i * 4 + 2, rightVal, Endian.little);
  }
  return bytes;
}

void main() {
  group('PcmResampler Unit Tests', () {
    test('resamplePcm16 handles empty inputs', () {
      final res = PcmResampler.resamplePcm16(Uint8List(0));
      expect(res, isEmpty);

      final singleByte = Uint8List(1);
      final resSingle = PcmResampler.resamplePcm16(singleByte);
      expect(resSingle, isEmpty);
    });

    test('resamplePcm16 downsamples 48kHz mono to 16kHz mono (3:1 ratio)', () {
      // 480 samples at 48kHz = 10ms of audio = 960 bytes
      final inputBytes = createPcm16Sine(
        sampleRate: 48000,
        frequency: 440.0,
        durationSeconds: 0.01,
      );
      expect(inputBytes.length, 960);

      final resampled = PcmResampler.resamplePcm16(
        inputBytes,
        inputSampleRate: 48000,
        channelCount: 1,
      );

      // 480 samples / 3 = 160 output samples = 320 bytes
      expect(resampled.length, 320);

      final levels = PcmResampler.calculateLevels(resampled);
      expect(levels.rms, greaterThan(0.5));
      expect(levels.peak, greaterThan(0.8));
    });

    test('resamplePcm16 downsamples 44.1kHz mono to 16kHz mono', () {
      // 441 samples at 44.1kHz = 10ms = 882 bytes
      final inputBytes = createPcm16Sine(
        sampleRate: 44100,
        frequency: 440.0,
        durationSeconds: 0.01,
      );
      expect(inputBytes.length, 882);

      final resampled = PcmResampler.resamplePcm16(
        inputBytes,
        inputSampleRate: 44100,
        channelCount: 1,
      );

      // 441 * 16000 / 44100 = 160 output samples = 320 bytes
      expect(resampled.length, 320);
    });

    test('resamplePcm16 mixes 48kHz stereo down to 16kHz mono', () {
      // 480 stereo frames = 480 * 4 = 1920 bytes
      // Left = +10000, Right = -10000 -> Mixed average = 0
      final stereoBytes = createPcm16Stereo(
        sampleRate: 48000,
        frameCount: 480,
        leftVal: 10000,
        rightVal: -10000,
      );
      expect(stereoBytes.length, 1920);

      final resampled = PcmResampler.resamplePcm16(
        stereoBytes,
        inputSampleRate: 48000,
        channelCount: 2,
      );

      // Output: 160 samples mono = 320 bytes
      expect(resampled.length, 320);
      final byteData = ByteData.sublistView(resampled);
      for (var i = 0; i < 160; i++) {
        expect(byteData.getInt16(i * 2, Endian.little), 0);
      }
    });

    test('resamplePcm16 with 16kHz mono bypasses interpolation', () {
      final inputBytes = createPcm16Sine(
        sampleRate: 16000,
        frequency: 440.0,
        durationSeconds: 0.01,
      );
      final resampled = PcmResampler.resamplePcm16(
        inputBytes,
        inputSampleRate: 16000,
        channelCount: 1,
      );
      expect(resampled.length, inputBytes.length);
      expect(resampled, equals(inputBytes));
    });

    test('resamplePcm16 throws on invalid channel counts', () {
      final bytes = Uint8List(100);
      expect(
        () => PcmResampler.resamplePcm16(bytes, channelCount: 0),
        throwsArgumentError,
      );
      expect(
        () => PcmResampler.resamplePcm16(bytes, channelCount: 3),
        throwsArgumentError,
      );
    });

    test('resampleFloat32 converts and downsamples normalized floats', () {
      final floats = Float32List(480);
      for (var i = 0; i < 480; i++) {
        floats[i] = sin(2 * pi * 440.0 * (i / 48000.0));
      }

      final resampled = PcmResampler.resampleFloat32(
        floats,
        inputSampleRate: 48000,
        channelCount: 1,
      );
      expect(resampled.length, 320); // 160 samples * 2 bytes
    });

    test('resampleFloat32Bytes converts raw Float32 byte buffer', () {
      final floats = Float32List(480);
      for (var i = 0; i < 480; i++) {
        floats[i] = 0.5;
      }
      final rawBytes = Uint8List.view(floats.buffer);

      final resampled = PcmResampler.resampleFloat32Bytes(
        rawBytes,
        inputSampleRate: 48000,
        channelCount: 1,
      );
      expect(resampled.length, 320);
      final byteData = ByteData.sublistView(resampled);
      // 0.5 * 32767 = 16384 (approx)
      expect(byteData.getInt16(0, Endian.little), closeTo(16384, 5));
    });

    test('PcmResampler instance resample convenience method', () {
      const resampler = PcmResampler(sourceSampleRate: 48000, channels: 1);
      final inputBytes = createPcm16Sine(
        sampleRate: 48000,
        frequency: 440.0,
        durationSeconds: 0.01,
      );
      final res = resampler.resample(inputBytes);
      expect(res.length, 320);
    });

    test('calculateLevels reports accurate RMS, Peak, and dBFS', () {
      // 1. Silence
      final silence = Uint8List(320);
      final silenceLevel = PcmResampler.calculateLevels(silence);
      expect(silenceLevel.rms, 0.0);
      expect(silenceLevel.peak, 0.0);
      expect(silenceLevel.dbFs, -100.0);

      // 2. Full-scale square wave
      final fullScale = Uint8List(320);
      final fsData = ByteData.sublistView(fullScale);
      for (var i = 0; i < 160; i++) {
        fsData.setInt16(i * 2, i.isEven ? 32767 : -32768, Endian.little);
      }
      final fullLevel = PcmResampler.calculateLevels(fullScale);
      expect(fullLevel.peak, closeTo(1.0, 0.001));
      expect(fullLevel.rms, closeTo(1.0, 0.001));
      expect(fullLevel.dbFs, closeTo(0.0, 0.01));

      // 3. Static helpers
      expect(PcmResampler.calculateRms(fullScale), closeTo(1.0, 0.001));
      expect(PcmResampler.calculatePeak(fullScale), closeTo(1.0, 0.001));

      // 4. AudioLevel toString and equality
      expect(silenceLevel, equals(const AudioLevel(rms: 0, peak: 0, dbFs: -100)));
      expect(silenceLevel.hashCode, isA<int>());
      expect(silenceLevel.toString(), contains('rms: 0.0'));
    });

    test('resampleFloat32 validates channelCount and handles stereo & targetSampleRate', () {
      expect(
        () => PcmResampler.resampleFloat32(Float32List(4), channelCount: 0),
        throwsArgumentError,
      );
      expect(
        () => PcmResampler.resampleFloat32(Float32List(4), channelCount: 3),
        throwsArgumentError,
      );

      // Stereo Float32
      final stereoFloats = Float32List.fromList([0.5, -0.5, 0.25, -0.25]);
      final stereoResampled = PcmResampler.resampleFloat32(
        stereoFloats,
        inputSampleRate: 48000,
        channelCount: 2,
      );
      expect(stereoResampled, isNotEmpty);

      // targetSampleRate (16000)
      final monoFloats16k = Float32List.fromList([0.1, -0.1, 0.5, -0.5]);
      final res16k = PcmResampler.resampleFloat32(
        monoFloats16k,
        inputSampleRate: 16000,
        channelCount: 1,
      );
      expect(res16k.length, 8); // 4 samples * 2 bytes
    });
  });

  group('Audio Drivers Unit Tests', () {
    test('MemoryAudioRecordDriver records and feeds chunks', () async {
      final initialChunk = Uint8List.fromList([1, 2, 3, 4]);
      final driver = MemoryAudioRecordDriver(
        chunks: [initialChunk],
        sampleRate: 48000,
        channelCount: 1,
      );

      final received = <Uint8List>[];
      await driver.startRecording((chunk) {
        received.add(chunk);
      });
      expect(driver.isRecording, isTrue);
      expect(driver.sampleRate, 48000);
      expect(driver.channelCount, 1);
      expect(received, [initialChunk]);

      final liveChunk = Uint8List.fromList([5, 6, 7, 8]);
      driver.feedChunk(liveChunk);
      expect(received.length, 2);
      expect(received[1], liveChunk);

      await driver.stopRecording();
      expect(driver.isRecording, isFalse);

      driver.feedChunk(Uint8List.fromList([9, 10]));
      expect(received.length, 2);
    });

    test('MemoryAudioPlayDriver plays, flushes, and stops', () async {
      final driver = MemoryAudioPlayDriver();
      expect(driver.isPlaying, isFalse);

      final chunk1 = Uint8List.fromList([10, 20]);
      final chunk2 = Uint8List.fromList([30, 40]);

      await driver.playChunk(chunk1);
      expect(driver.isPlaying, isTrue);
      expect(driver.isFlushed, isFalse);
      expect(driver.playedChunks, [chunk1]);

      await driver.playChunk(chunk2);
      expect(driver.playedChunks, [chunk1, chunk2]);

      await driver.flush();
      expect(driver.isFlushed, isTrue);
      expect(driver.playedChunks, isEmpty);

      await driver.stop();
      expect(driver.isPlaying, isFalse);
    });
  });

  group('SarvamMicStreamer Unit Tests', () {
    test('captures and resamples audio from driver', () async {
      final chunk48k = createPcm16Sine(
        sampleRate: 48000,
        frequency: 440.0,
        durationSeconds: 0.01,
      );
      final driver = MemoryAudioRecordDriver(
        sampleRate: 48000,
        channelCount: 1,
      );

      AudioLevel? lastLevel;
      double? lastRms;
      final streamer = SarvamMicStreamer(
        driver: driver,
        onAudioLevel: (lvl) => lastLevel = lvl,
        onRmsLevel: (rms) => lastRms = rms,
      );

      final emittedFrames = <Uint8List>[];
      final sub = streamer.audioStream.listen(emittedFrames.add);

      await streamer.start();
      expect(streamer.isCapturing, isTrue);
      expect(streamer.isRecording, isTrue);

      driver.feedChunk(chunk48k);
      await pumpEventQueue();

      expect(emittedFrames.length, 1);
      expect(emittedFrames[0].length, 320); // 16kHz resampled!
      expect(lastLevel, isNotNull);
      expect(lastRms, isNotNull);

      await sub.cancel();
      await streamer.close();
      expect(streamer.isCapturing, isFalse);
    });

    test('bounded backpressure queue drops oldest frames when saturated', () async {
      final driver = MemoryAudioRecordDriver(
        sampleRate: 48000,
        channelCount: 1,
      );

      var droppedCount = 0;
      final streamer = SarvamMicStreamer(
        driver: driver,
        maxQueueSize: 3,
        onDroppedFrame: (count) => droppedCount += count,
      );

      // Start without session to accumulate frames in queue
      await streamer.start();

      // Feed 5 chunks: max queue size is 3 -> 2 should be dropped
      for (var i = 0; i < 5; i++) {
        final chunk = Uint8List(480 * 2); // 480 samples
        driver.feedChunk(chunk);
      }

      expect(streamer.queuedFramesCount, 3);
      expect(droppedCount, 2);

      await streamer.stop();
      expect(streamer.queuedFramesCount, 0);
      await streamer.close();
    });

    test('streaming to SttRealtimeSession and pausing behavior', () async {
      final wsSession = MockWebSocketSession();
      final sttSession = SttRealtimeSession(wsSession);

      final driver = MemoryAudioRecordDriver(
        sampleRate: 16000,
        channelCount: 1,
      );

      final streamer = SarvamMicStreamer(
        driver: driver,
        session: sttSession,
      );

      await streamer.start();

      final chunk = Uint8List(160 * 2);
      driver.feedChunk(chunk);

      expect(wsSession.sentFrames.length, 1);
      final sent1 = jsonDecode(wsSession.sentFrames[0] as String)
          as Map<String, dynamic>;
      expect(sent1['event'], 'audio_input');
      expect(sent1['audio'], base64Encode(chunk));

      // Pause streaming
      streamer.setPaused(true);
      expect(streamer.isPaused, isTrue);

      driver.feedChunk(chunk);
      // Should not send to session while paused, but queue it
      expect(wsSession.sentFrames.length, 1);
      expect(streamer.queuedFramesCount, 1);

      // Unpause -> drains queue to session
      streamer.setPaused(false);
      expect(streamer.isPaused, isFalse);
      expect(wsSession.sentFrames.length, 2);
      expect(streamer.queuedFramesCount, 0);

      // pipeTo and start with session
      final wsSession2 = MockWebSocketSession();
      final sttSession2 = SttRealtimeSession(wsSession2);
      streamer.pipeTo(sttSession2);
      await streamer.stop();
      await streamer.start(sttSession2);

      await streamer.close();
    });
  });

  group('SarvamChunkedAudioPlayer Unit Tests', () {
    test('playChunk and playStream sequentially play audio', () async {
      final driver = MemoryAudioPlayDriver();
      final player = SarvamChunkedAudioPlayer(driver: driver);

      final chunk1 = Uint8List.fromList([1, 2, 3]);
      final chunk2 = Uint8List.fromList([4, 5, 6]);

      await player.playChunk(chunk1);
      expect(driver.playedChunks, [chunk1]);
      expect(player.isPlaying, isTrue);

      final stream = Stream<Uint8List>.fromIterable([chunk2]);
      await player.playStream(stream);

      expect(driver.playedChunks, [chunk2]); // playStream stopped and cleared
      expect(player.isPlaying, isFalse);

      await player.close();
    });

    test('attachSession plays TtsAudioChunk and finishes on TtsCompleted', () async {
      final driver = MemoryAudioPlayDriver();
      final player = SarvamChunkedAudioPlayer(driver: driver);

      final wsSession = MockWebSocketSession();
      final ttsSession = TtsStreamingSession(wsSession);

      player.attachSession(ttsSession);
      expect(player.isPlaying, isTrue);

      final chunkBytes = Uint8List.fromList([7, 8, 9]);
      wsSession.pushIncoming(jsonEncode({
        'type': 'audio',
        'data': {
          'audio': base64Encode(chunkBytes),
        },
      }));

      await pumpEventQueue();
      expect(driver.playedChunks, [chunkBytes]);
      expect(player.isPlaying, isTrue);

      wsSession.pushIncoming(jsonEncode({
        'type': 'event',
        'data': {'event': 'completion'},
      }));

      await pumpEventQueue();
      expect(player.isPlaying, isFalse);

      await player.close();
    });

    test('stopAndFlush halts driver and clears buffers', () async {
      final driver = MemoryAudioPlayDriver();
      final player = SarvamChunkedAudioPlayer(driver: driver);

      await player.playChunk(Uint8List.fromList([10, 20]));
      expect(player.isPlaying, isTrue);

      await player.stopAndFlush();
      expect(player.isPlaying, isFalse);
      expect(driver.isPlaying, isFalse);
      expect(driver.isFlushed, isTrue);
    });

    test('playStream handles stream error', () async {
      final driver = MemoryAudioPlayDriver();
      final player = SarvamChunkedAudioPlayer(driver: driver);
      final controller = StreamController<Uint8List>();
      final future = player.playStream(controller.stream);
      controller.addError(Exception('stream failure'));
      await expectLater(future, throwsException);
      expect(player.isPlaying, isFalse);
      await player.close();
    });

    test('attachSession / playSession handles onError and onDone', () async {
      final driver = MemoryAudioPlayDriver();
      final player = SarvamChunkedAudioPlayer(driver: driver);

      final wsSession1 = MockWebSocketSession();
      final ttsSession1 = TtsStreamingSession(wsSession1);
      player.playSession(ttsSession1);
      expect(player.isPlaying, isTrue);

      wsSession1.pushIncoming('invalid json or trigger onError');
      // Adding an error to incoming stream:
      // Note MockWebSocketSession has _incomingController
      // Let's close with error or add error
      wsSession1._incomingController.addError('socket failure');
      await pumpEventQueue();
      expect(player.isPlaying, isFalse);

      final wsSession2 = MockWebSocketSession();
      final ttsSession2 = TtsStreamingSession(wsSession2);
      player.attachSession(ttsSession2);
      expect(player.isPlaying, isTrue);
      await wsSession2.close();
      await pumpEventQueue();
      expect(player.isPlaying, isFalse);

      await player.close();
    });
  });

  group('BargeInCoordinator Unit Tests', () {
    test('halts player immediately when VadSpeechStart is emitted', () async {
      final driver = MemoryAudioPlayDriver();
      final player = SarvamChunkedAudioPlayer(driver: driver);
      await player.playChunk(Uint8List.fromList([100, 200]));
      expect(player.isPlaying, isTrue);

      final wsSession = MockWebSocketSession();
      final sttSession = SttRealtimeSession(wsSession);

      SttRealtimeEvent? receivedEvent;
      final coordinator = BargeInCoordinator(
        session: sttSession,
        player: player,
        onBargeIn: (event) => receivedEvent = event,
      );

      coordinator.start();
      expect(coordinator.isAttached, isTrue);

      // 1. Non-barge-in event should NOT stop player
      wsSession.pushIncoming(jsonEncode({
        'event': 'transcript_partial',
        'text': 'hello',
      }));
      await pumpEventQueue();
      expect(player.isPlaying, isTrue);
      expect(receivedEvent, isNull);

      // 2. VadSpeechStart (SttVadSpeechStart) triggers instant barge-in!
      wsSession.pushIncoming(jsonEncode({
        'event': 'vad_speech_start',
        'timestamp_ms': 1234,
      }));
      await pumpEventQueue();

      expect(player.isPlaying, isFalse);
      expect(driver.isPlaying, isFalse);
      expect(driver.isFlushed, isTrue);
      expect(receivedEvent, isA<VadSpeechStart>());
      expect(receivedEvent, isA<SttVadSpeechStart>());

      coordinator.stop();
      expect(coordinator.isAttached, isFalse);
    });

    test('attach method allows dynamic runtime binding', () async {
      final driver = MemoryAudioPlayDriver();
      final player = SarvamChunkedAudioPlayer(driver: driver);
      await player.playChunk(Uint8List.fromList([50, 60]));

      final wsSession = MockWebSocketSession();
      final sttSession = SttRealtimeSession(wsSession);

      var bargeInFired = false;
      final coordinator = BargeInCoordinator(
        onBargeIn: (_) => bargeInFired = true,
      );

      coordinator.attach(session: sttSession, player: player);
      expect(coordinator.isAttached, isTrue);

      wsSession.pushIncoming(jsonEncode({
        'event': 'speech_start',
        'timestamp_ms': 5678,
      }));
      await pumpEventQueue();

      expect(bargeInFired, isTrue);
      expect(player.isPlaying, isFalse);

      coordinator.stop();
      expect(coordinator.isAttached, isFalse);
    });
  });
}
