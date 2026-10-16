package ai.sarvam.core.ws

import kotlinx.coroutines.flow.Flow

public sealed interface WebSocketFrame {
    public data class Text(val text: String) : WebSocketFrame
    public data class Binary(val bytes: ByteArray) : WebSocketFrame {
        override fun equals(other: Any?): Boolean {
            if (this === other) return true
            if (javaClass != other?.javaClass) return false
            other as Binary
            return bytes.contentEquals(other.bytes)
        }

        override fun hashCode(): Int = bytes.contentHashCode()
    }
    public data class Closing(val code: Int, val reason: String) : WebSocketFrame
    public data class Closed(val code: Int, val reason: String) : WebSocketFrame
    public data class Failure(val throwable: Throwable) : WebSocketFrame
}

public interface WebSocketSession : AutoCloseable {
    public suspend fun send(text: String)
    public suspend fun send(bytes: ByteArray)
    public fun close(code: Int = 1000, reason: String? = null)
    public val incoming: Flow<WebSocketFrame>

    override fun close() {
        close(1000, "Normal closure")
    }
}
