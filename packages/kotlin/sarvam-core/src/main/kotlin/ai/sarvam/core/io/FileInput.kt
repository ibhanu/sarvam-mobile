package ai.sarvam.core.io

import java.io.ByteArrayInputStream
import java.io.File
import java.io.FileInputStream
import java.io.InputStream

public class FileInput private constructor(
    public val filename: String,
    public val mimeType: String,
    public val isReplayable: Boolean,
    private val streamSupplier: () -> InputStream,
    private val cachedBytes: ByteArray? = null
) {
    public fun openStream(): InputStream = streamSupplier()

    public fun readBytes(): ByteArray = cachedBytes ?: streamSupplier().use { it.readBytes() }

    public companion object {
        public fun fromBytes(
            bytes: ByteArray,
            filename: String,
            mimeType: String = "application/octet-stream"
        ): FileInput = FileInput(
            filename = filename,
            mimeType = mimeType,
            isReplayable = true,
            streamSupplier = { ByteArrayInputStream(bytes) },
            cachedBytes = bytes
        )

        public fun fromFile(
            file: File,
            mimeType: String? = null
        ): FileInput {
            val detectedMime = mimeType ?: when (file.extension.lowercase()) {
                "wav" -> "audio/wav"
                "mp3" -> "audio/mpeg"
                "opus" -> "audio/opus"
                "flac" -> "audio/flac"
                "aac" -> "audio/aac"
                "pdf" -> "application/pdf"
                else -> "application/octet-stream"
            }
            return FileInput(
                filename = file.name,
                mimeType = detectedMime,
                isReplayable = true,
                streamSupplier = { FileInputStream(file) }
            )
        }

        public fun fromStream(
            inputStreamProvider: () -> InputStream,
            filename: String,
            mimeType: String = "application/octet-stream",
            isReplayable: Boolean = false
        ): FileInput = FileInput(
            filename = filename,
            mimeType = mimeType,
            isReplayable = isReplayable,
            streamSupplier = inputStreamProvider
        )
    }
}
