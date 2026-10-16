package ai.sarvam.resources

import ai.sarvam.core.RequestOptions
import ai.sarvam.core.SarvamClientConfig
import ai.sarvam.core.http.HttpBody
import ai.sarvam.core.http.HttpRequest
import ai.sarvam.core.sse.SseReader
import ai.sarvam.generated.OperationKind
import ai.sarvam.models.ChatCompletionChunk
import ai.sarvam.models.ChatCompletionRequest
import ai.sarvam.models.ChatCompletionResponse
import ai.sarvam.models.ModelInfo
import ai.sarvam.models.ModelListResponse
import ai.sarvam.session.ChatSession
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.flow
import java.util.UUID

public class ChatResource(private val config: SarvamClientConfig) {

    public suspend fun completions(
        request: ChatCompletionRequest,
        options: RequestOptions? = null
    ): ChatCompletionResponse {
        val jsonPayload = config.json.encodeToString(ChatCompletionRequest.serializer(), request)
        var httpRequest = HttpRequest(
            method = "POST",
            url = "${config.environment.apiBaseUrl}/v1/chat/completions",
            body = HttpBody.Json(jsonPayload),
            operationKind = OperationKind.STATELESS_POST,
            timeoutMillis = options?.timeoutMillis
        )
        if (options != null) {
            httpRequest = httpRequest.withHeaders(options.headers)
        }

        val response = config.execute(httpRequest)
        val bodyString = response.bodyAsString()
        return config.json.decodeFromString(ChatCompletionResponse.serializer(), bodyString)
    }

    public fun completionsStream(
        request: ChatCompletionRequest,
        options: RequestOptions? = null
    ): Flow<ChatCompletionChunk> = streamCompletionsInternal(
        path = "/v1/chat/completions",
        request = request,
        options = options
    )

    public suspend fun completionsV2(
        request: ChatCompletionRequest,
        options: RequestOptions? = null
    ): ChatCompletionResponse {
        val jsonPayload = config.json.encodeToString(ChatCompletionRequest.serializer(), request)
        var httpRequest = HttpRequest(
            method = "POST",
            url = "${config.environment.apiBaseUrl}/v2/chat/completions",
            body = HttpBody.Json(jsonPayload),
            operationKind = OperationKind.STATELESS_POST,
            timeoutMillis = options?.timeoutMillis
        )
        if (options != null) {
            httpRequest = httpRequest.withHeaders(options.headers)
        }

        val response = config.execute(httpRequest)
        val bodyString = response.bodyAsString()
        return config.json.decodeFromString(ChatCompletionResponse.serializer(), bodyString)
    }

    public fun completionsV2Stream(
        request: ChatCompletionRequest,
        options: RequestOptions? = null
    ): Flow<ChatCompletionChunk> = streamCompletionsInternal(
        path = "/v2/chat/completions",
        request = request,
        options = options
    )

    private fun streamCompletionsInternal(
        path: String,
        request: ChatCompletionRequest,
        options: RequestOptions?
    ): Flow<ChatCompletionChunk> = flow {
        val streamingRequest = request.copy(stream = true)
        val jsonPayload = config.json.encodeToString(ChatCompletionRequest.serializer(), streamingRequest)
        var httpRequest = HttpRequest(
            method = "POST",
            url = "${config.environment.apiBaseUrl}$path",
            body = HttpBody.Json(jsonPayload),
            operationKind = OperationKind.STATELESS_POST,
            timeoutMillis = options?.timeoutMillis,
            isStreaming = true
        )
        if (options != null) {
            httpRequest = httpRequest.withHeaders(options.headers)
        }

        val response = config.execute(httpRequest)
        try {
            SseReader.parse(response.bodyByteStream()).collect { event ->
                val trimmedData = event.data.trim()
                if (trimmedData == "[DONE]") {
                    return@collect
                }
                if (trimmedData.isNotEmpty()) {
                    val chunk = config.json.decodeFromString(ChatCompletionChunk.serializer(), trimmedData)
                    emit(chunk)
                }
            }
        } finally {
            response.close()
        }
    }

    public suspend fun listModels(options: RequestOptions? = null): ModelListResponse {
        var httpRequest = HttpRequest(
            method = "GET",
            url = "${config.environment.apiBaseUrl}/v2/models",
            operationKind = OperationKind.IDEMPOTENT,
            timeoutMillis = options?.timeoutMillis
        )
        if (options != null) {
            httpRequest = httpRequest.withHeaders(options.headers)
        }

        val response = config.execute(httpRequest)
        val bodyString = response.bodyAsString()
        return config.json.decodeFromString(ModelListResponse.serializer(), bodyString)
    }

    public suspend fun getModel(modelId: String, options: RequestOptions? = null): ModelInfo {
        var httpRequest = HttpRequest(
            method = "GET",
            url = "${config.environment.apiBaseUrl}/v2/models/$modelId",
            operationKind = OperationKind.IDEMPOTENT,
            timeoutMillis = options?.timeoutMillis
        )
        if (options != null) {
            httpRequest = httpRequest.withHeaders(options.headers)
        }

        val response = config.execute(httpRequest)
        val bodyString = response.bodyAsString()
        return config.json.decodeFromString(ModelInfo.serializer(), bodyString)
    }

    public fun createSession(sessionId: String = UUID.randomUUID().toString()): ChatSession {
        return ChatSession(this, sessionId)
    }
}
