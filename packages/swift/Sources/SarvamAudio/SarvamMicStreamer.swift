import Foundation
import Sarvam

/// Manages microphone capture, resampling to 16kHz mono PCM, and real-time streaming to Sarvam STT.
public actor SarvamMicStreamer {
    private let driver: AudioCaptureDriver
    public let channelCapacity: Int
    public var onAudioLevel: (@Sendable (AudioLevel) -> Void)?

    private var _isCapturing: Bool = false
    public var isCapturing: Bool { _isCapturing }

    private var captureTask: Task<Void, Never>?
    private var streamingTask: Task<Void, Never>?

    private let primaryContinuation: AsyncStream<Data>.Continuation
    public nonisolated let audioStream: AsyncStream<Data>

    private var extraContinuations: [UUID: AsyncStream<Data>.Continuation] = [:]

    public init(
        driver: AudioCaptureDriver,
        channelCapacity: Int = 10,
        onAudioLevel: (@Sendable (AudioLevel) -> Void)? = nil
    ) {
        self.driver = driver
        self.channelCapacity = channelCapacity
        self.onAudioLevel = onAudioLevel

        var cont: AsyncStream<Data>.Continuation!
        self.audioStream = AsyncStream<Data>(bufferingPolicy: .bufferingNewest(channelCapacity)) { c in
            cont = c
        }
        self.primaryContinuation = cont
    }

    /// Creates an additional independent `AsyncStream<Data>` of 16kHz mono audio chunks.
    public func makeAudioStream() -> AsyncStream<Data> {
        let id = UUID()
        return AsyncStream<Data>(bufferingPolicy: .bufferingNewest(channelCapacity)) { cont in
            self.extraContinuations[id] = cont
            cont.onTermination = { @Sendable [weak self] _ in
                Task { [weak self] in
                    await self?.removeContinuation(id: id)
                }
            }
        }
    }

    private func removeContinuation(id: UUID) {
        extraContinuations.removeValue(forKey: id)
    }

    /// Starts audio capture from the driver and optionally streams resampled audio directly to an active STT session.
    @discardableResult
    public func start(session: SttRealtimeSession? = nil) throws -> Task<Void, Never> {
        if _isCapturing, let task = captureTask {
            return task
        }

        try driver.start()
        _isCapturing = true

        let driver = self.driver
        let onAudioLevel = self.onAudioLevel
        let primaryContinuation = self.primaryContinuation

        let task = Task { [weak self] in
            let bytesPerFrame = 2 * driver.channelCount
            let chunkFrames = max(driver.sampleRate / 10, 160) // 100ms chunk
            let readLength = chunkFrames * bytesPerFrame

            while !Task.isCancelled {
                guard let self = self, await self.isCapturing else { break }

                guard let rawChunk = try? driver.read(length: readLength) else {
                    break
                }

                if rawChunk.isEmpty {
                    try? await Task.sleep(nanoseconds: 10_000_000)
                    continue
                }

                let resampled = PcmResampler.resamplePcm16(
                    inputBytes: rawChunk,
                    inputSampleRate: driver.sampleRate,
                    channelCount: driver.channelCount
                )

                guard !resampled.isEmpty else { continue }

                let level = PcmResampler.calculateLevels(pcm16Bytes: resampled)
                onAudioLevel?(level)

                primaryContinuation.yield(resampled)
                await self.broadcastToExtra(data: resampled)

                if let session = session {
                    try? await session.sendAudio(resampled)
                }
            }

            driver.stop()
            await self?.markStopped()
        }

        self.captureTask = task
        return task
    }

    private func broadcastToExtra(data: Data) {
        for cont in extraContinuations.values {
            cont.yield(data)
        }
    }

    private func markStopped() {
        _isCapturing = false
    }

    /// Halts audio capture and finishes streaming tasks.
    public func stop() {
        guard _isCapturing else { return }
        _isCapturing = false
        captureTask?.cancel()
        captureTask = nil
        streamingTask?.cancel()
        streamingTask = nil
        driver.stop()
    }

    deinit {
        primaryContinuation.finish()
        for cont in extraContinuations.values {
            cont.finish()
        }
        driver.stop()
    }
}
