package ai.sarvam.audio

public interface AudioCaptureDriver : AutoCloseable {
    public val sampleRate: Int
    public val channelCount: Int
    public fun start()
    public fun read(buffer: ByteArray, offset: Int, length: Int): Int
    public fun stop()
}

public interface AudioPlaybackDriver : AutoCloseable {
    public val isPlaying: Boolean
    public fun start()
    public fun write(buffer: ByteArray, offset: Int, length: Int): Int
    public fun flush()
    public fun stop()
}

/**
 * In-memory AudioCaptureDriver for testing or mock streaming.
 */
public class ByteArrayAudioCaptureDriver(
    private val data: ByteArray,
    override val sampleRate: Int = 48000,
    override val channelCount: Int = 1
) : AudioCaptureDriver {
    private var position = 0
    private var isStarted = false

    override fun start() {
        isStarted = true
    }

    override fun read(buffer: ByteArray, offset: Int, length: Int): Int {
        if (!isStarted || position >= data.size) return 0
        val available = minOf(length, data.size - position)
        System.arraycopy(data, position, buffer, offset, available)
        position += available
        return available
    }

    override fun stop() {
        isStarted = false
    }

    override fun close() {
        stop()
    }
}

/**
 * In-memory AudioPlaybackDriver for unit tests.
 */
public class MemoryAudioPlaybackDriver : AudioPlaybackDriver {
    private val _writtenBytes = mutableListOf<ByteArray>()
    public val writtenBytes: List<ByteArray> get() = _writtenBytes.toList()
    public var isFlushed: Boolean = false
        private set
    private var _isPlaying = false
    override val isPlaying: Boolean get() = _isPlaying

    override fun start() {
        _isPlaying = true
        isFlushed = false
    }

    override fun write(buffer: ByteArray, offset: Int, length: Int): Int {
        val chunk = buffer.copyOfRange(offset, offset + length)
        _writtenBytes.add(chunk)
        return length
    }

    override fun flush() {
        isFlushed = true
        _writtenBytes.clear()
    }

    override fun stop() {
        _isPlaying = false
    }

    override fun close() {
        stop()
    }
}

/**
 * Reflection-based Android AudioRecord driver.
 * Safely resolves android.media.AudioRecord at runtime on Android devices,
 * while safely throwing an informative exception if invoked on pure JVM.
 */
public class AndroidAudioRecordCaptureDriver(
    override val sampleRate: Int = 16000,
    override val channelCount: Int = 1,
    private val audioSource: Int = 1 // MediaRecorder.AudioSource.MIC
) : AudioCaptureDriver {

    private var audioRecordInstance: Any? = null

    public companion object {
        public fun isAvailable(): Boolean = try {
            Class.forName("android.media.AudioRecord")
            true
        } catch (_: ClassNotFoundException) {
            false
        }
    }

    override fun start() {
        if (!isAvailable()) {
            throw UnsupportedOperationException("android.media.AudioRecord is not available on this JVM runtime")
        }
        val audioRecordClass = Class.forName("android.media.AudioRecord")
        val channelConfig = if (channelCount == 1) 16 else 12 // CHANNEL_IN_MONO : CHANNEL_IN_STEREO
        val audioFormat = 2 // ENCODING_PCM_16BIT

        val getMinBufferSizeMethod = audioRecordClass.getMethod(
            "getMinBufferSize",
            Int::class.javaPrimitiveType,
            Int::class.javaPrimitiveType,
            Int::class.javaPrimitiveType
        )
        val minBufferSize = getMinBufferSizeMethod.invoke(null, sampleRate, channelConfig, audioFormat) as Int
        val bufferSize = maxOf(minBufferSize, 4096)

        val constructor = audioRecordClass.getConstructor(
            Int::class.javaPrimitiveType,
            Int::class.javaPrimitiveType,
            Int::class.javaPrimitiveType,
            Int::class.javaPrimitiveType,
            Int::class.javaPrimitiveType
        )
        val record = constructor.newInstance(audioSource, sampleRate, channelConfig, audioFormat, bufferSize)
        val startRecordingMethod = audioRecordClass.getMethod("startRecording")
        startRecordingMethod.invoke(record)
        audioRecordInstance = record
    }

    override fun read(buffer: ByteArray, offset: Int, length: Int): Int {
        val record = audioRecordInstance ?: return 0
        val audioRecordClass = record.javaClass
        val readMethod = audioRecordClass.getMethod(
            "read",
            ByteArray::class.java,
            Int::class.javaPrimitiveType,
            Int::class.javaPrimitiveType
        )
        return readMethod.invoke(record, buffer, offset, length) as Int
    }

    override fun stop() {
        audioRecordInstance?.let { record ->
            try {
                val stopMethod = record.javaClass.getMethod("stop")
                stopMethod.invoke(record)
            } catch (_: Exception) {}
        }
    }

    override fun close() {
        audioRecordInstance?.let { record ->
            try {
                stop()
                val releaseMethod = record.javaClass.getMethod("release")
                releaseMethod.invoke(record)
            } catch (_: Exception) {}
            audioRecordInstance = null
        }
    }
}

/**
 * Reflection-based Android AudioTrack driver.
 * Safely resolves android.media.AudioTrack at runtime on Android devices,
 * while safely throwing an informative exception if invoked on pure JVM.
 */
public class AndroidAudioTrackPlaybackDriver(
    private val sampleRate: Int = 16000,
    private val channelCount: Int = 1
) : AudioPlaybackDriver {

    private var audioTrackInstance: Any? = null
    private var _isPlaying = false
    override val isPlaying: Boolean get() = _isPlaying

    public companion object {
        public fun isAvailable(): Boolean = try {
            Class.forName("android.media.AudioTrack")
            true
        } catch (_: ClassNotFoundException) {
            false
        }
    }

    override fun start() {
        if (!isAvailable()) {
            throw UnsupportedOperationException("android.media.AudioTrack is not available on this JVM runtime")
        }
        val audioTrackClass = Class.forName("android.media.AudioTrack")
        val streamType = 3 // STREAM_MUSIC
        val channelConfig = if (channelCount == 1) 4 else 12 // CHANNEL_OUT_MONO : CHANNEL_OUT_STEREO
        val audioFormat = 2 // ENCODING_PCM_16BIT
        val mode = 1 // MODE_STREAM

        val getMinBufferSizeMethod = audioTrackClass.getMethod(
            "getMinBufferSize",
            Int::class.javaPrimitiveType,
            Int::class.javaPrimitiveType,
            Int::class.javaPrimitiveType
        )
        val minBufferSize = getMinBufferSizeMethod.invoke(null, sampleRate, channelConfig, audioFormat) as Int
        val bufferSize = maxOf(minBufferSize, 4096)

        val constructor = audioTrackClass.getConstructor(
            Int::class.javaPrimitiveType,
            Int::class.javaPrimitiveType,
            Int::class.javaPrimitiveType,
            Int::class.javaPrimitiveType,
            Int::class.javaPrimitiveType,
            Int::class.javaPrimitiveType
        )
        val track = constructor.newInstance(streamType, sampleRate, channelConfig, audioFormat, bufferSize, mode)
        val playMethod = audioTrackClass.getMethod("play")
        playMethod.invoke(track)
        audioTrackInstance = track
        _isPlaying = true
    }

    override fun write(buffer: ByteArray, offset: Int, length: Int): Int {
        val track = audioTrackInstance ?: return 0
        val audioTrackClass = track.javaClass
        val writeMethod = audioTrackClass.getMethod(
            "write",
            ByteArray::class.java,
            Int::class.javaPrimitiveType,
            Int::class.javaPrimitiveType
        )
        return writeMethod.invoke(track, buffer, offset, length) as Int
    }

    override fun flush() {
        audioTrackInstance?.let { track ->
            try {
                val pauseMethod = track.javaClass.getMethod("pause")
                pauseMethod.invoke(track)
                val flushMethod = track.javaClass.getMethod("flush")
                flushMethod.invoke(track)
            } catch (_: Exception) {}
        }
    }

    override fun stop() {
        audioTrackInstance?.let { track ->
            try {
                val stopMethod = track.javaClass.getMethod("stop")
                stopMethod.invoke(track)
            } catch (_: Exception) {}
        }
        _isPlaying = false
    }

    override fun close() {
        audioTrackInstance?.let { track ->
            try {
                stop()
                val releaseMethod = track.javaClass.getMethod("release")
                releaseMethod.invoke(track)
            } catch (_: Exception) {}
            audioTrackInstance = null
        }
    }
}
