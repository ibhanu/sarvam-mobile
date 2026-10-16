package ai.sarvam.core.http

import ai.sarvam.core.io.FileInput
import ai.sarvam.generated.OperationKind
import ai.sarvam.generated.OperationSpec

public sealed interface HttpBody {
    public object Empty : HttpBody

    public data class Json(val content: String) : HttpBody

    public data class Binary(val bytes: ByteArray, val contentType: String) : HttpBody {
        override fun equals(other: Any?): Boolean {
            if (this === other) return true
            if (javaClass != other?.javaClass) return false
            other as Binary
            return bytes.contentEquals(other.bytes) && contentType == other.contentType
        }

        override fun hashCode(): Int {
            var result = bytes.contentHashCode()
            result = 31 * result + contentType.hashCode()
            return result
        }
    }

    public data class Multipart(val parts: List<MultipartPart>) : HttpBody
}

public sealed interface MultipartPart {
    public data class FormParam(val name: String, val value: String) : MultipartPart
    public data class FilePart(val name: String, val file: FileInput) : MultipartPart
}

public data class HttpRequest(
    val method: String,
    val url: String,
    val headers: Map<String, List<String>> = emptyMap(),
    val body: HttpBody = HttpBody.Empty,
    val operationKind: OperationKind = OperationKind.STATELESS_POST,
    val operationSpec: OperationSpec? = null,
    val timeoutMillis: Long? = null,
    val isStreaming: Boolean = false
) {
    public fun header(name: String): String? =
        headers.entries.firstOrNull { it.key.equals(name, ignoreCase = true) }?.value?.firstOrNull()

    public fun withHeader(name: String, value: String): HttpRequest {
        val mutable = headers.toMutableMap()
        mutable[name] = listOf(value)
        return copy(headers = mutable)
    }

    public fun withHeaders(newHeaders: Map<String, String>): HttpRequest {
        val mutable = headers.toMutableMap()
        for ((k, v) in newHeaders) {
            mutable[k] = listOf(v)
        }
        return copy(headers = mutable)
    }

    public val isReplayable: Boolean
        get() = when (body) {
            is HttpBody.Empty -> true
            is HttpBody.Json -> true
            is HttpBody.Binary -> true
            is HttpBody.Multipart -> body.parts.all { part ->
                when (part) {
                    is MultipartPart.FormParam -> true
                    is MultipartPart.FilePart -> part.file.isReplayable
                }
            }
        }
}
