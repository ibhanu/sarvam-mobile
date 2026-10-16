package ai.sarvam.core

public data class RequestOptions(
    val headers: Map<String, String> = emptyMap(),
    val timeoutMillis: Long? = null,
    val idempotencyKey: String? = null,
    val additionalQueryParams: Map<String, String> = emptyMap()
)
