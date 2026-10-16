package ai.sarvam.models

import kotlinx.serialization.SerialName
import kotlinx.serialization.Serializable

@Serializable
public data class ResponsesRequest(
    public val model: String,
    public val input: String,
    public val stream: Boolean = true
)

public sealed interface ResponseStreamEvent {
    public data class ResponseCreated(
        public val id: String,
        public val type: String
    ) : ResponseStreamEvent

    public data class ResponseOutputItemAdded(
        public val id: String,
        public val type: String,
        public val item: ResponseItem? = null
    ) : ResponseStreamEvent

    public data class ResponseContentPartAdded(
        public val id: String,
        public val type: String,
        public val itemId: String? = null,
        public val part: ContentPart? = null
    ) : ResponseStreamEvent

    public data class ResponseCompleted(
        public val id: String,
        public val type: String,
        public val status: String? = null
    ) : ResponseStreamEvent

    public data class ResponseFailed(
        public val id: String,
        public val type: String,
        public val error: String? = null
    ) : ResponseStreamEvent

    public data class ResponseIncomplete(
        public val id: String,
        public val type: String,
        public val reason: String? = null
    ) : ResponseStreamEvent

    public data class Unknown(
        public val eventType: String?,
        public val rawJson: String
    ) : ResponseStreamEvent
}

@Serializable
public data class ResponseItem(
    public val id: String? = null,
    public val type: String? = null,
    public val role: String? = null
)

@Serializable
public data class ContentPart(
    public val type: String? = null,
    public val text: String? = null
)
