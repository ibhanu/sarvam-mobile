import Foundation
import Testing
@testable import Sarvam
@testable import SarvamAudio

@Suite("SarvamAudio Companion Tests")
struct AudioCompanionTests {

    // MARK: - 1. PcmResampler Tests

    @Test("Resample 48kHz mono PCM16 to 16kHz produces exact sample count")
    func testResample48kTo16kMono() {
        // 480 samples = 10ms at 48kHz (960 bytes)
        let numInputSamples = 480
        var inputBytes = Data(count: numInputSamples * 2)
        inputBytes.withUnsafeMutableBytes { buf in
            for i in 0..<numInputSamples {
                let sample = Int16(clamping: Int((sin(2.0 * .pi * 440.0 * Double(i) / 48000.0) * 16000.0).rounded()))
                buf.storeBytes(of: sample.littleEndian, toByteOffset: i * 2, as: Int16.self)
            }
        }

        let resampled = PcmResampler.resamplePcm16(inputBytes: inputBytes, inputSampleRate: 48000, channelCount: 1)
        let outputSamples = resampled.count / 2

        // 480 / 3 = exactly 160 samples (320 bytes)
        #expect(outputSamples == 160)
        #expect(resampled.count == 320)
    }

    @Test("Resample 48kHz 100ms mono PCM16 produces exactly 1600 samples")
    func testResample48k100msMono() {
        // 4800 samples = 100ms at 48kHz (9600 bytes)
        let numInputSamples = 4800
        var inputBytes = Data(count: numInputSamples * 2)
        inputBytes.withUnsafeMutableBytes { buf in
            for i in 0..<numInputSamples {
                let sample = Int16(i % 1000)
                buf.storeBytes(of: sample.littleEndian, toByteOffset: i * 2, as: Int16.self)
            }
        }

        let resampled = PcmResampler.resamplePcm16(inputBytes: inputBytes, inputSampleRate: 48000, channelCount: 1)
        let outputSamples = resampled.count / 2

        #expect(outputSamples == 1600)
        #expect(resampled.count == 3200)
    }

    @Test("Resample 44.1kHz mono PCM16 to 16kHz produces exact sample count")
    func testResample44k1To16kMono() {
        // 4410 samples = 100ms at 44.1kHz (8820 bytes)
        let numInputSamples = 4410
        let inputBytes = Data(count: numInputSamples * 2)

        let resampled = PcmResampler.resamplePcm16(inputBytes: inputBytes, inputSampleRate: 44100, channelCount: 1)
        let outputSamples = resampled.count / 2

        // 4410 * 16000 / 44100 = 1600 samples (3200 bytes)
        #expect(outputSamples == 1600)
        #expect(resampled.count == 3200)
    }

    @Test("Resample 48kHz stereo to 16kHz mono averages left and right channels")
    func testResample48kStereoTo16kMono() {
        // 3 stereo frames: (L=1000, R=3000)
        // Average should be 2000
        var inputBytes = Data(count: 3 * 4)
        inputBytes.withUnsafeMutableBytes { buf in
            for i in 0..<3 {
                let left: Int16 = 1000
                let right: Int16 = 3000
                let offset = i * 4
                buf.storeBytes(of: left.littleEndian, toByteOffset: offset, as: Int16.self)
                buf.storeBytes(of: right.littleEndian, toByteOffset: offset + 2, as: Int16.self)
            }
        }

        let resampled = PcmResampler.resamplePcm16(inputBytes: inputBytes, inputSampleRate: 48000, channelCount: 2)
        #expect(resampled.count == 2) // 1 sample = 2 bytes

        let outSample = resampled.withUnsafeBytes { $0.load(as: Int16.self).littleEndian }
        #expect(outSample == 2000)
    }

    @Test("Resample 16kHz mono PCM16 returns identical samples")
    func testResample16kMonoIdentical() {
        let input = Data([0x12, 0x34, 0x56, 0x78])
        let resampled = PcmResampler.resamplePcm16(inputBytes: input, inputSampleRate: 16000, channelCount: 1)
        #expect(resampled == input)
    }

    @Test("Resample Float32 audio to 16kHz PCM16")
    func testResampleFloat32() {
        let floatSamples: [Float] = [0.0, 0.5, 1.0, -0.5, -1.0]
        let resampled = PcmResampler.resampleFloat32(inputFloats: floatSamples, inputSampleRate: 16000, channelCount: 1)
        #expect(resampled.count == 10) // 5 samples * 2 bytes

        let s0 = resampled.withUnsafeBytes { $0.load(fromByteOffset: 0, as: Int16.self).littleEndian }
        let s2 = resampled.withUnsafeBytes { $0.load(fromByteOffset: 4, as: Int16.self).littleEndian }
        let s4 = resampled.withUnsafeBytes { $0.load(fromByteOffset: 8, as: Int16.self).littleEndian }

        #expect(s0 == 0)
        #expect(s2 >= 32760) // Near full scale positive
        #expect(s4 <= -32760) // Near full scale negative
    }

    @Test("CalculateLevels calculates peak, RMS, and dBFS accurately")
    func testCalculateLevels() {
        // Silence
        let silence = Data(count: 320)
        let silenceLevel = PcmResampler.calculateLevels(pcm16Bytes: silence)
        #expect(silenceLevel.peak == 0.0)
        #expect(silenceLevel.rms == 0.0)
        #expect(silenceLevel.dbFs == -100.0)

        // Full scale DC (all 32767)
        var fullScale = Data(count: 320)
        fullScale.withUnsafeMutableBytes { buf in
            for i in 0..<160 {
                let sample: Int16 = 32767
                buf.storeBytes(of: sample.littleEndian, toByteOffset: i * 2, as: Int16.self)
            }
        }
        let fullLevel = PcmResampler.calculateLevels(pcm16Bytes: fullScale)
        #expect(fullLevel.peak > 0.99)
        #expect(fullLevel.rms > 0.99)
        #expect(fullLevel.dbFs > -0.1 && fullLevel.dbFs <= 0.0)
    }

    // MARK: - 2. SarvamMicStreamer Tests

    @Test("SarvamMicStreamer captures, resamples 48kHz to 16kHz, and emits levels and audio")
    func testMicStreamerCaptureAndStream() async throws {
        // Create 2 chunks of 4800 samples = 100ms each at 48kHz (19200 bytes)
        var raw48k = Data(count: 9600 * 2)
        raw48k.withUnsafeMutableBytes { buf in
            for i in 0..<9600 {
                let sample: Int16 = 0x2050
                buf.storeBytes(of: sample.littleEndian, toByteOffset: i * 2, as: Int16.self)
            }
        }

        let captureDriver = BufferAudioCaptureDriver(data: raw48k, sampleRate: 48000, channelCount: 1)
        let levelEmitted = LockIsolated(false)

        let streamer = SarvamMicStreamer(
            driver: captureDriver,
            onAudioLevel: { level in
                if level.peak > 0.0 {
                    levelEmitted.withValue { $0 = true }
                }
            }
        )

        let mockSocket = MockWebSocketSession()
        let sttSession = SttRealtimeSession(socketSession: mockSocket)

        try await streamer.start(session: sttSession)

        // Read first chunk from streamer.audioStream
        var iterator = streamer.audioStream.makeAsyncIterator()
        let firstChunk = await iterator.next()

        #expect(firstChunk != nil)
        // 4800 samples -> resampled to 1600 samples (3200 bytes)
        #expect(firstChunk?.count == 3200)
        #expect(levelEmitted.value == true)

        // Wait brief moment for streamingTask to deliver message to sttSession
        try? await Task.sleep(nanoseconds: 50_000_000)

        // Verify STT session received audio_input message
        let sent = mockSocket.sentMessages
        let containsAudioInput = sent.contains { msg in
            if case .text(let t) = msg {
                return t.contains("\"event\":\"audio_input\"")
            }
            return false
        }
        #expect(containsAudioInput == true)

        await streamer.stop()
    }

    // MARK: - 3. SarvamAudioPlayer Tests

    @Test("SarvamAudioPlayer plays audio and supports sub-20ms stopAndFlush")
    func testAudioPlayerSub20msStopAndFlush() async throws {
        let playbackDriver = MemoryAudioPlaybackDriver()
        let player = SarvamAudioPlayer(driver: playbackDriver)

        // Direct play
        let chunk1 = Data([1, 2, 3, 4])
        try await player.play(chunk: chunk1)
        let isPlayingAfterPlay = await player.isPlaying
        #expect(isPlayingAfterPlay == true)
        #expect(playbackDriver.writtenData.count == 1)
        #expect(playbackDriver.writtenData.first == chunk1)

        // Stream play
        let stream = AsyncStream<Data> { continuation in
            continuation.yield(Data([5, 6]))
            continuation.yield(Data([7, 8]))
            continuation.finish()
        }
        _ = try await player.playStream(stream)

        // Instant stopAndFlush (Barge-in benchmark)
        let startNanos = DispatchTime.now().uptimeNanoseconds
        await player.stopAndFlush()
        let durationMs = Double(DispatchTime.now().uptimeNanoseconds - startNanos) / 1_000_000.0

        let isPlayingAfterStop = await player.isPlaying
        #expect(isPlayingAfterStop == false)
        #expect(playbackDriver.isFlushed == true)
        #expect(durationMs < 20.0) // Sub-20ms barge-in latency guarantee!
    }

    // MARK: - 4. BargeInCoordinator Tests

    @Test("BargeInCoordinator automatically invokes stopAndFlush on vadSpeechStart")
    func testBargeInCoordinatorStopsPlayer() async throws {
        let mockSocket = MockWebSocketSession()
        let sttSession = SttRealtimeSession(socketSession: mockSocket)
        let playbackDriver = MemoryAudioPlaybackDriver()
        let player = SarvamAudioPlayer(driver: playbackDriver)

        let bargeInTriggered = LockIsolated(false)
        let coordinator = BargeInCoordinator(
            onBargeIn: {
                bargeInTriggered.withValue { $0 = true }
            }
        )

        // Start infinite audio playback stream
        var continuation: AsyncStream<Data>.Continuation!
        let infiniteStream = AsyncStream<Data> { cont in
            continuation = cont
        }
        continuation.yield(Data([1, 2, 3, 4]))
        _ = try await player.playStream(infiniteStream)

        let isPlayingBefore = await player.isPlaying
        #expect(isPlayingBefore == true)

        // Attach coordinator
        await coordinator.attach(session: sttSession, player: player)

        // Emit other event: transcript_partial
        mockSocket.emitServerMessage("{\"event\":\"transcript_partial\",\"text\":\"Hel\"}")
        try? await Task.sleep(nanoseconds: 10_000_000)
        let isPlayingMid = await player.isPlaying
        #expect(isPlayingMid == true)
        #expect(bargeInTriggered.value == false)

        // Emit vad_speech_start event!
        mockSocket.emitServerMessage("{\"event\":\"vad_speech_start\",\"timestamp_ms\":1234}")
        try? await Task.sleep(nanoseconds: 30_000_000)

        // Verify player is automatically halted and flushed!
        let isPlayingAfter = await player.isPlaying
        #expect(isPlayingAfter == false)
        #expect(playbackDriver.isFlushed == true)
        #expect(bargeInTriggered.value == true)

        await coordinator.detach()
        continuation.finish()
    }

    // MARK: - 5. PcmResampler Edge Cases & Full Overloads
    @Test("PcmResampler edge cases and all overloads")
    func testPcmResamplerEdgeCases() {
        // targetSampleRate check
        #expect(PcmResampler.targetSampleRate == 16000)

        // Empty Data / zero frames
        #expect(PcmResampler.resamplePcm16(inputBytes: Data(), inputSampleRate: 16000).isEmpty)
        #expect(PcmResampler.resamplePcm16(inputBytes: Data([0x01]), inputSampleRate: 16000).isEmpty) // numFrames == 0
        #expect(PcmResampler.resampleFloat32(inputBytes: Data(), inputSampleRate: 16000).isEmpty)
        #expect(PcmResampler.resampleFloat32(inputBytes: Data([0x01, 0x02]), inputSampleRate: 16000).isEmpty)
        #expect(PcmResampler.resampleFloat32(inputFloats: [], inputSampleRate: 16000).isEmpty)

        // resamplePcm16 stereo at 16kHz
        var stereo16k = Data(count: 8)
        stereo16k.withUnsafeMutableBytes { buf in
            buf.storeBytes(of: Int16(1000).littleEndian, toByteOffset: 0, as: Int16.self)
            buf.storeBytes(of: Int16(3000).littleEndian, toByteOffset: 2, as: Int16.self)
            buf.storeBytes(of: Int16(2000).littleEndian, toByteOffset: 4, as: Int16.self)
            buf.storeBytes(of: Int16(4000).littleEndian, toByteOffset: 6, as: Int16.self)
        }
        let outStereo16 = PcmResampler.resamplePcm16(inputBytes: stereo16k, inputSampleRate: 16000, channelCount: 2)
        #expect(outStereo16.count == 4) // 2 mono samples * 2 bytes = 4 bytes
        let s0 = outStereo16.withUnsafeBytes { $0.load(fromByteOffset: 0, as: Int16.self).littleEndian }
        let s1 = outStereo16.withUnsafeBytes { $0.load(fromByteOffset: 2, as: Int16.self).littleEndian }
        #expect(s0 == 2000)
        #expect(s1 == 3000)

        // resampleFloat32 array overloads: stereo at 16kHz
        let stereoFloats: [Float] = [0.2, 0.6, -0.4, 0.4]
        let outStereoFloats16 = PcmResampler.resampleFloat32(inputFloats: stereoFloats, inputSampleRate: 16000, channelCount: 2)
        #expect(outStereoFloats16.count == 4)

        // resampleFloat32 array overloads: stereo at 48kHz
        let outStereoFloats48 = PcmResampler.resampleFloat32(inputFloats: stereoFloats, inputSampleRate: 48000, channelCount: 2)
        #expect(!outStereoFloats48.isEmpty)

        // resampleFloat32 array overloads: mono at 48kHz
        let monoFloats: [Float] = [0.1, 0.2, 0.3, 0.4, 0.5, 0.6]
        let outMonoFloats48 = PcmResampler.resampleFloat32(inputFloats: monoFloats, inputSampleRate: 48000, channelCount: 1)
        #expect(!outMonoFloats48.isEmpty)

        // resampleFloat32 Data overloads: mono at 16kHz
        var floatBytes16 = Data(count: 8)
        floatBytes16.withUnsafeMutableBytes { buf in
            buf.storeBytes(of: Float(0.5).bitPattern.littleEndian, toByteOffset: 0, as: UInt32.self)
            buf.storeBytes(of: Float(-0.5).bitPattern.littleEndian, toByteOffset: 4, as: UInt32.self)
        }
        let outFloatBytes16 = PcmResampler.resampleFloat32(inputBytes: floatBytes16, inputSampleRate: 16000, channelCount: 1)
        #expect(outFloatBytes16.count == 4)

        // resampleFloat32 Data overloads: stereo at 16kHz
        var floatStereo16 = Data(count: 8)
        floatStereo16.withUnsafeMutableBytes { buf in
            buf.storeBytes(of: Float(0.2).bitPattern.littleEndian, toByteOffset: 0, as: UInt32.self)
            buf.storeBytes(of: Float(0.8).bitPattern.littleEndian, toByteOffset: 4, as: UInt32.self)
        }
        let outFloatStereo16 = PcmResampler.resampleFloat32(inputBytes: floatStereo16, inputSampleRate: 16000, channelCount: 2)
        #expect(outFloatStereo16.count == 2)

        // resampleFloat32 Data overloads: stereo at 48kHz (3 frames = 24 bytes -> 1 frame at 16kHz)
        var floatStereo48 = Data(count: 24)
        floatStereo48.withUnsafeMutableBytes { buf in
            for i in 0..<6 {
                buf.storeBytes(of: Float(0.5).bitPattern.littleEndian, toByteOffset: i * 4, as: UInt32.self)
            }
        }
        let outFloatStereo48 = PcmResampler.resampleFloat32(inputBytes: floatStereo48, inputSampleRate: 48000, channelCount: 2)
        #expect(!outFloatStereo48.isEmpty)

        // resampleFloat32 Data overloads: mono at 48kHz
        let outFloatMono48 = PcmResampler.resampleFloat32(inputBytes: floatBytes16, inputSampleRate: 48000, channelCount: 1)
        #expect(!outFloatMono48.isEmpty)

        // calculateLevels on empty Data
        let emptyLevels = PcmResampler.calculateLevels(pcm16Bytes: Data())
        #expect(emptyLevels.rms == 0.0)
        #expect(emptyLevels.peak == 0.0)
        #expect(emptyLevels.dbFs == -100.0)

        // calculateRms & calculatePeak
        let sampleData = Data([0x00, 0x00, 0x00, 0x40])
        #expect(PcmResampler.calculateRms(pcm16Bytes: sampleData) > 0.0)
        #expect(PcmResampler.calculatePeak(pcm16Bytes: sampleData) > 0.0)
    }

    // MARK: - 6. SarvamAudioPlayer Throwing Stream and TtsStreamingSession
    @Test("SarvamAudioPlayer playStream throwing and playSession")
    func testAudioPlayerThrowingStreamAndSession() async throws {
        let playbackDriver = MemoryAudioPlaybackDriver()
        let player = SarvamAudioPlayer(driver: playbackDriver)

        // play discrete chunk when driver is already playing
        try await player.play(chunk: Data([1, 2]))
        try await player.play(chunk: Data([3, 4]))
        #expect(playbackDriver.writtenData.count == 2)

        // playStream throwing with empty chunk and real chunks
        let throwingStream = AsyncThrowingStream<Data, Error> { continuation in
            continuation.yield(Data()) // empty chunk
            continuation.yield(Data([5, 6]))
            continuation.yield(Data([7, 8]))
            continuation.finish()
        }
        let playTask = try await player.playStream(throwingStream)
        _ = await playTask.result
        #expect(playbackDriver.writtenData.contains(Data([5, 6])))

        // playStream throwing with error
        let errorStream = AsyncThrowingStream<Data, Error> { continuation in
            continuation.finish(throwing: NSError(domain: "test", code: 1, userInfo: nil))
        }
        let errorTask = try await player.playStream(errorStream)
        _ = await errorTask.result

        // playSession with TtsStreamingSession
        let wsFactory = MockWebSocketFactory()
        let wsSession = MockWebSocketSession()
        wsFactory.queueSession(wsSession)
        let ttsSession = try await TtsStreamingSession.connect(
            config: TtsStreamingConfig(),
            environment: .production,
            authProvider: ApiKeyAuth(apiKey: "k"),
            webSocketFactory: wsFactory
        )

        let sessionPlayTask = try await player.playSession(ttsSession)

        wsSession.emitServerMessage("{\"type\":\"audio\",\"data\":{\"audio\":\"AQIDBA==\"}}")
        wsSession.emitServerMessage("{\"type\":\"event\",\"data\":{\"event\":\"final\"}}")
        try? await Task.sleep(nanoseconds: 50_000_000)

        #expect(playbackDriver.writtenData.contains(Data([1, 2, 3, 4])))
        await player.stopAndFlush()
        sessionPlayTask.cancel()
    }

    // MARK: - 7. SarvamMicStreamer Extra Streams and Repeated Starts
    @Test("SarvamMicStreamer makeAudioStream, start when already capturing, and stop")
    func testMicStreamerAdvanced() async throws {
        var raw48k = Data(count: 9600 * 2)
        raw48k.withUnsafeMutableBytes { buf in
            for i in 0..<9600 {
                let sample: Int16 = 0x1020
                buf.storeBytes(of: sample.littleEndian, toByteOffset: i * 2, as: Int16.self)
            }
        }
        let captureDriver = BufferAudioCaptureDriver(data: raw48k, sampleRate: 48000, channelCount: 1)
        let streamer = SarvamMicStreamer(driver: captureDriver, channelCapacity: 5)
        let capacity = await streamer.channelCapacity
        #expect(capacity == 5)

        // makeAudioStream
        let extraStream = await streamer.makeAudioStream()

        // start capture
        let task1 = try await streamer.start()
        let task2 = try await streamer.start() // already capturing branch
        #expect(task1 == task2)

        var extraIterator = extraStream.makeAsyncIterator()
        let extraChunk = await extraIterator.next()
        #expect(extraChunk != nil)
        #expect(extraChunk?.count == 3200)

        await streamer.stop()
        await streamer.stop() // stop when already stopped branch
    }
}

/// Simple thread-safe isolated box for assertions in tests.
final class LockIsolated<T>: @unchecked Sendable {
    private var _val: T
    private let lock = NSLock()

    init(_ val: T) {
        self._val = val
    }

    var value: T {
        lock.withLock { _val }
    }

    func withValue(_ block: (inout T) -> Void) {
        lock.withLock { block(&_val) }
    }
}
