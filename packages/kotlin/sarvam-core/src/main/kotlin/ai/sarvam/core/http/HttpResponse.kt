package ai.sarvam.core.http

import kotlinx.coroutines.flow.Flow

public interface HttpResponse : AutoCloseable {
    public val statusCode: Int
    public val headers: Map<String, List<String>>
    public suspend fun bodyAsString(): String
    public suspend fun bodyAsBytes(): ByteArray
    public fun bodyByteStream(): Flow<ByteArray>
    public fun header(name: String): String? =
        headers.entries.firstOrNull { it.key.equals(name, ignoreCase = true) }?.value?.firstOrNull()

    override fun close() {}
}
