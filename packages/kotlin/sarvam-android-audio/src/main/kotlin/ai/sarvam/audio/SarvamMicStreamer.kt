package ai.sarvam.audio

import ai.sarvam.session.SttRealtimeSession
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.channels.BufferOverflow
import kotlinx.coroutines.channels.Channel
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.receiveAsFlow
import kotlinx.coroutines.isActive
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import java.util.concurrent.atomic.AtomicBoolean

public class SarvamMicStreamer(
    private val driver: AudioCaptureDriver,
    private val resampler: PcmResampler = PcmResampler,
    public val channelCapacity: Int = 10,
    public var onAudioLevel: ((AudioLevel) -> Unit)? = null
) : AutoCloseable {

    private val channel = Channel<ByteArray>(
        capacity = channelCapacity,
        onBufferOverflow = BufferOverflow.DROP_OLDEST
    )

    public val audioFlow: Flow<ByteArray> = channel.receiveAsFlow()

    @Volatile
    private var captureJob: Job? = null
    @Volatile
    private var streamingJob: Job? = null
    private val isRunning = AtomicBoolean(false)

    public fun isCapturing(): Boolean = isRunning.get()

    @Synchronized
    public fun start(
        scope: CoroutineScope,
        session: SttRealtimeSession? = null
    ): Job {
        if (!isRunning.compareAndSet(false, true)) {
            return captureJob ?: Job().apply { complete() }
        }

        driver.start()

        val job = scope.launch(Dispatchers.IO) {
            val bytesPerFrame = 2 * driver.channelCount
            val chunkFrames = maxOf(driver.sampleRate / 10, 160) // 100ms chunk
            val readBuffer = ByteArray(chunkFrames * bytesPerFrame)

            try {
                while (isActive && isRunning.get()) {
                    val bytesRead = driver.read(readBuffer, 0, readBuffer.size)
                    if (bytesRead > 0) {
                        val chunkBytes = if (bytesRead == readBuffer.size) {
                            readBuffer.copyOf()
                        } else {
                            readBuffer.copyOfRange(0, bytesRead)
                        }

                        val resampled = resampler.resamplePcm16(
                            inputBytes = chunkBytes,
                            inputSampleRate = driver.sampleRate,
                            channelCount = driver.channelCount
                        )

                        if (resampled.isNotEmpty()) {
                            onAudioLevel?.let { callback ->
                                val level = resampler.calculateLevels(resampled)
                                callback(level)
                            }
                            channel.trySend(resampled)
                        }
                    } else if (bytesRead < 0) {
                        break
                    }
                }
            } catch (_: CancellationException) {
                // Expected on stop
            } finally {
                driver.stop()
                isRunning.set(false)
            }
        }
        captureJob = job

        if (session != null) {
            streamingJob = scope.launch {
                try {
                    audioFlow.collect { pcmBytes ->
                        session.sendAudio(pcmBytes)
                    }
                } catch (_: CancellationException) {
                    // Stopped streaming
                }
            }
        }

        return job
    }

    public fun stop() {
        if (isRunning.compareAndSet(true, false)) {
            captureJob?.cancel()
            captureJob = null
            streamingJob?.cancel()
            streamingJob = null
            try {
                driver.stop()
            } catch (_: Exception) {}
        }
    }

    override fun close() {
        stop()
        channel.close()
        driver.close()
    }
}
