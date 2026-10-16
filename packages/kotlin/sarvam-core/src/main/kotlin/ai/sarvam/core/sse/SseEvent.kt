package ai.sarvam.core.sse

public data class SseEvent(
    val id: String? = null,
    val event: String? = null,
    val data: String = "",
    val retry: Long? = null
)
