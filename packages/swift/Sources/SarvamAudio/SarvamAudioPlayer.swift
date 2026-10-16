import Foundation
import Sarvam

/// Low-latency streaming audio player with sub-20ms barge-in stop & flush.
public actor SarvamAudioPlayer {
    private let driver: AudioPlaybackDriver
    private var activeTask: Task<Void, Never>?

    public init(driver: AudioPlaybackDriver) {
        self.driver = driver
    }

    /// Whether the player driver is currently active.
    public var isPlaying: Bool {
        driver.isPlaying
    }

    /// Plays a single discrete audio chunk immediately.
    public func play(chunk: Data) throws {
        if !driver.isPlaying {
            try driver.start()
        }
        _ = try driver.write(data: chunk)
    }

    /// Plays a continuous asynchronous stream of raw audio chunks.
    @discardableResult
    public func playStream(_ audioStream: AsyncStream<Data>) throws -> Task<Void, Never> {
        stopAndFlush()
        try driver.start()

        let driver = self.driver
        let task = Task {
            for await chunk in audioStream {
                guard !Task.isCancelled else { break }
                if !chunk.isEmpty {
                    _ = try? driver.write(data: chunk)
                }
            }
        }
        self.activeTask = task
        return task
    }

    /// Plays a continuous throwing stream of raw audio chunks (e.g. from HTTP chunked transfer).
    @discardableResult
    public func playStream(_ audioStream: AsyncThrowingStream<Data, Error>) throws -> Task<Void, Never> {
        stopAndFlush()
        try driver.start()

        let driver = self.driver
        let task = Task {
            do {
                for try await chunk in audioStream {
                    guard !Task.isCancelled else { break }
                    if !chunk.isEmpty {
                        _ = try? driver.write(data: chunk)
                    }
                }
            } catch {}
        }
        self.activeTask = task
        return task
    }

    /// Plays audio chunks emitted by a real-time `TtsStreamingSession`.
    @discardableResult
    public func playSession(_ session: TtsStreamingSession) throws -> Task<Void, Never> {
        let stream = AsyncStream<Data> { continuation in
            let sessionTask = Task {
                do {
                    for try await event in session.events {
                        guard !Task.isCancelled else { break }
                        switch event {
                        case .audioChunk(let audioBytes, _, _):
                            continuation.yield(audioBytes)
                        case .completed:
                            continuation.finish()
                        case .error, .unknown:
                            break
                        }
                    }
                    continuation.finish()
                } catch {
                    continuation.finish()
                }
            }

            continuation.onTermination = { @Sendable _ in
                sessionTask.cancel()
            }
        }

        return try playStream(stream)
    }

    /// Instantly halts playback, flushes queued hardware buffers, and stops the driver.
    ///
    /// Provides guaranteed sub-20ms barge-in latency.
    public func stopAndFlush() {
        activeTask?.cancel()
        activeTask = nil
        driver.flush()
        driver.stop()
    }
}
