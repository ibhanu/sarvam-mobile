package ai.sarvam.audio

import ai.sarvam.models.SttRealtimeEvent
import ai.sarvam.session.SttRealtimeSession
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Job
import kotlinx.coroutines.launch

public class BargeInCoordinator(
    public var onBargeIn: (() -> Unit)? = null
) {
    public fun attach(
        session: SttRealtimeSession,
        player: SarvamAudioPlayer,
        scope: CoroutineScope
    ): Job {
        return scope.launch {
            try {
                session.events.collect { event ->
                    if (event is SttRealtimeEvent.VadSpeechStart) {
                        player.stopAndFlush()
                        onBargeIn?.invoke()
                    }
                }
            } catch (_: CancellationException) {
                // Cancelled
            }
        }
    }
}
