package ai.sarvam.session

import ai.sarvam.core.RequestOptions
import ai.sarvam.models.ChatCompletionChunk
import ai.sarvam.models.ChatCompletionRequest
import ai.sarvam.models.ChatCompletionResponse
import ai.sarvam.resources.ChatResource
import kotlinx.coroutines.flow.Flow
import java.util.UUID

public class ChatSession(
    private val chatResource: ChatResource,
    public val sessionId: String = UUID.randomUUID().toString()
) {
    public suspend fun completions(
        request: ChatCompletionRequest,
        options: RequestOptions? = null
    ): ChatCompletionResponse {
        val mergedOptions = withSessionAffinity(options)
        return chatResource.completions(request, mergedOptions)
    }

    public fun completionsStream(
        request: ChatCompletionRequest,
        options: RequestOptions? = null
    ): Flow<ChatCompletionChunk> {
        val mergedOptions = withSessionAffinity(options)
        return chatResource.completionsStream(request, mergedOptions)
    }

    public suspend fun completionsV2(
        request: ChatCompletionRequest,
        options: RequestOptions? = null
    ): ChatCompletionResponse {
        val mergedOptions = withSessionAffinity(options)
        return chatResource.completionsV2(request, mergedOptions)
    }

    public fun completionsV2Stream(
        request: ChatCompletionRequest,
        options: RequestOptions? = null
    ): Flow<ChatCompletionChunk> {
        val mergedOptions = withSessionAffinity(options)
        return chatResource.completionsV2Stream(request, mergedOptions)
    }

    private fun withSessionAffinity(options: RequestOptions?): RequestOptions {
        val currentHeaders = options?.headers?.toMutableMap() ?: mutableMapOf()
        currentHeaders["x-session-affinity"] = sessionId
        return (options ?: RequestOptions()).copy(headers = currentHeaders)
    }
}
