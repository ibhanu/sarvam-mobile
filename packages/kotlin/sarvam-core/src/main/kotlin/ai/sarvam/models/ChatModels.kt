package ai.sarvam.models

import kotlinx.serialization.SerialName
import kotlinx.serialization.Serializable

@Serializable
public data class ChatMessage(
    public val role: String,
    public val content: String
)

@Serializable
public data class ChatCompletionRequest(
    public val model: String,
    public val messages: List<ChatMessage>,
    public val stream: Boolean? = null,
    public val temperature: Double? = null,
    @SerialName("top_p")
    public val topP: Double? = null,
    @SerialName("max_tokens")
    public val maxTokens: Int? = null
)

@Serializable
public data class ChatCompletionResponse(
    public val id: String = "",
    public val choices: List<ChatChoice> = emptyList(),
    public val usage: ChatUsage? = null
)

@Serializable
public data class ChatChoice(
    public val index: Int = 0,
    public val message: ChatMessage? = null,
    @SerialName("finish_reason")
    public val finishReason: String? = null
)

@Serializable
public data class ChatCompletionChunk(
    public val id: String? = null,
    public val choices: List<ChatChunkChoice> = emptyList(),
    public val usage: ChatUsage? = null
) {
    public val firstDeltaContent: String?
        get() = choices.firstOrNull()?.delta?.content
}

@Serializable
public data class ChatChunkChoice(
    public val index: Int = 0,
    public val delta: ChatChunkDelta? = null,
    @SerialName("finish_reason")
    public val finishReason: String? = null
)

@Serializable
public data class ChatChunkDelta(
    public val role: String? = null,
    public val content: String? = null
)

@Serializable
public data class ChatUsage(
    @SerialName("prompt_tokens")
    public val promptTokens: Int = 0,
    @SerialName("completion_tokens")
    public val completionTokens: Int = 0,
    @SerialName("total_tokens")
    public val totalTokens: Int = 0
)

@Serializable
public data class ModelListResponse(
    public val models: List<ModelInfo> = emptyList()
)

@Serializable
public data class ModelInfo(
    public val id: String,
    public val created: Long? = null,
    @SerialName("owned_by")
    public val ownedBy: String? = null
)
