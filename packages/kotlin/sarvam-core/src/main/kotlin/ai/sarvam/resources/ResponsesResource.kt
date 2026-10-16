package ai.sarvam.resources

import ai.sarvam.core.RequestOptions
import ai.sarvam.core.SarvamClientConfig
import ai.sarvam.core.http.HttpBody
import ai.sarvam.core.http.HttpRequest
import ai.sarvam.core.sse.SseReader
import ai.sarvam.generated.OperationKind
import ai.sarvam.models.ContentPart
import ai.sarvam.models.ResponseItem
import ai.sarvam.models.ResponseStreamEvent
import ai.sarvam.models.ResponsesRequest
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.flow
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.jsonObject
import kotlinx.serialization.json.jsonPrimitive

public class ResponsesResource(private val config: SarvamClientConfig) {

    public fun createStream(
        request: ResponsesRequest,
        options: RequestOptions? = null
    ): Flow<ResponseStreamEvent> = flow {
        val jsonPayload = config.json.encodeToString(ResponsesRequest.serializer(), request)
        var httpRequest = HttpRequest(
            method = "POST",
            url = "${config.environment.apiBaseUrl}/v2/responses",
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
            SseReader.parse(response.bodyByteStream()).collect { sseEvent ->
                val rawData = sseEvent.data.trim()
                if (rawData.isEmpty()) return@collect

                val eventType = sseEvent.event ?: extractTypeFromJson(rawData)
                val streamEvent = parseEvent(eventType, rawData)
                emit(streamEvent)

                // Terminate cleanly on completion events without waiting for [DONE]
                if (eventType == "response.completed" ||
                    eventType == "response.failed" ||
                    eventType == "response.incomplete"
                ) {
                    return@collect
                }
            }
        } finally {
            response.close()
        }
    }

    private fun extractTypeFromJson(jsonString: String): String? {
        return try {
            val root = Json.parseToJsonElement(jsonString).jsonObject
            root["type"]?.jsonPrimitive?.content
        } catch (_: Exception) {
            null
        }
    }

    private fun parseEvent(eventType: String?, jsonString: String): ResponseStreamEvent {
        return try {
            val root = Json.parseToJsonElement(jsonString).jsonObject
            val id = root["id"]?.jsonPrimitive?.content ?: ""
            val type = root["type"]?.jsonPrimitive?.content ?: (eventType ?: "")

            when (eventType ?: type) {
                "response.created" -> ResponseStreamEvent.ResponseCreated(id, type)
                "response.output_item.added" -> {
                    val item = root["item"]?.let { config.json.decodeFromString(ResponseItem.serializer(), it.toString()) }
                    ResponseStreamEvent.ResponseOutputItemAdded(id, type, item)
                }
                "response.content_part.added" -> {
                    val itemId = root["item_id"]?.jsonPrimitive?.content
                    val part = root["part"]?.let { config.json.decodeFromString(ContentPart.serializer(), it.toString()) }
                    ResponseStreamEvent.ResponseContentPartAdded(id, type, itemId, part)
                }
                "response.completed" -> {
                    val respObj = root["response"]?.jsonObject
                    val status = respObj?.get("status")?.jsonPrimitive?.content
                    ResponseStreamEvent.ResponseCompleted(id, type, status)
                }
                "response.failed" -> {
                    val error = root["error"]?.jsonPrimitive?.content
                    ResponseStreamEvent.ResponseFailed(id, type, error)
                }
                "response.incomplete" -> {
                    val reason = root["reason"]?.jsonPrimitive?.content
                    ResponseStreamEvent.ResponseIncomplete(id, type, reason)
                }
                else -> ResponseStreamEvent.Unknown(eventType, jsonString)
            }
        } catch (_: Exception) {
            ResponseStreamEvent.Unknown(eventType, jsonString)
        }
    }
}
