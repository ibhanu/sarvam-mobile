import Foundation
import Sarvam

/// Coordinates automated barge-in by monitoring STT Realtime VAD events
/// and immediately stopping & flushing the audio player on `.vadSpeechStart`.
public actor BargeInCoordinator {
    public var onBargeIn: (@Sendable () -> Void)?
    private var monitorTask: Task<Void, Never>?

    public init(onBargeIn: (@Sendable () -> Void)? = nil) {
        self.onBargeIn = onBargeIn
    }

    /// Attaches to an active STT Realtime session and intercepts VAD speech events to halt the player.
    @discardableResult
    public func attach(
        session: SttRealtimeSession,
        player: SarvamAudioPlayer
    ) -> Task<Void, Never> {
        detach()

        let onBargeIn = self.onBargeIn
        let task = Task {
            do {
                for try await event in session.events {
                    guard !Task.isCancelled else { break }
                    if case .vadSpeechStart = event {
                        await player.stopAndFlush()
                        onBargeIn?()
                    }
                }
            } catch {}
        }

        self.monitorTask = task
        return task
    }

    /// Detaches from the STT session and ceases VAD event monitoring.
    public func detach() {
        monitorTask?.cancel()
        monitorTask = nil
    }

    deinit {
        monitorTask?.cancel()
    }
}
