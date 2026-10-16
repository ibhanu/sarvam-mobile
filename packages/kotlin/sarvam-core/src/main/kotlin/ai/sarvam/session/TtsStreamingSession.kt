package ai.sarvam.session

import ai.sarvam.core.ws.WebSocketFrame
import ai.sarvam.core.ws.WebSocketSession
import ai.sarvam.models.TtsStreamEvent
import ai.sarvam.models.TtsStreamingConfig
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.mapNotNull
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.jsonObject
import kotlinx.serialization.json.jsonPrimitive
import java.util.Base64

public class TtsStreamingSession(
    private val webSocketSession: WebSocketSession,
    private val initialConfig: TtsStreamingConfig
) : AutoCloseable {

    public suspend fun initialize() {
        val fields = mutableListOf<String>()
        fields.add(""""language_code":"${initialConfig.languageCode.value}"""")
        initialConfig.speaker?.let { fields.add(""""speaker":"${it.value}"""") }
        fields.add(""""model":"${initialConfig.model.value}"""")
        fields.add(""""speech_sample_rate":${initialConfig.speechSampleRate}""")
        fields.add(""""output_audio_codec":"${initialConfig.outputAudioCodec.value}"""")
        initialConfig.pitch?.let { fields.add(""""pitch":$it""") }
        initialConfig.pace?.let { fields.add(""""pace":$it""") }
        initialConfig.loudness?.let { fields.add(""""loudness":$it""") }
        initialConfig.enablePreprocessing?.let { fields.add(""""enable_preprocessing":$it""") }
        initialConfig.voiceId?.let { fields.add(""""voice_id":"$it"""") }

        val configFrame = """{"type":"config","data":{${fields.joinToString(",")}}}"""
        webSocketSession.send(configFrame)
    }

    public suspend fun sendText(text: String) {
        val escaped = text.replace("\\", "\\\\").replace("\"", "\\\"").replace("\n", "\\n")
        webSocketSession.send("""{"type":"text","data":{"text":"$escaped"}}""")
    }

    public suspend fun flush() {
        webSocketSession.send("""{"type":"flush"}""")
    }

    public suspend fun ping() {
        webSocketSession.send("""{"type":"ping"}""")
    }

    public fun close(code: Int = 1000, reason: String? = null) {
        webSocketSession.close(code, reason)
    }

    override fun close() {
        close(1000, "Closed by client")
    }

    public val events: Flow<TtsStreamEvent> = webSocketSession.incoming.mapNotNull { frame ->
        when (frame) {
            is WebSocketFrame.Text -> parseFrame(frame.text)
            is WebSocketFrame.Closed -> {
                if (frame.code != 1000) {
                    TtsStreamEvent.Error(message = frame.reason, code = "ws_closed_${frame.code}")
                } else {
                    null
                }
            }
            is WebSocketFrame.Failure -> {
                TtsStreamEvent.Error(message = frame.throwable.message ?: "Connection failure", code = "ws_failure")
            }
            else -> null
        }
    }

    private fun parseFrame(jsonString: String): TtsStreamEvent {
        return try {
            val root = Json.parseToJsonElement(jsonString).jsonObject
            val type = root["type"]?.jsonPrimitive?.content ?: return TtsStreamEvent.Unknown(jsonString)
            val data = root["data"]?.jsonObject

            when (type) {
                "audio" -> {
                    val audioBase64 = data?.get("audio")?.jsonPrimitive?.content ?: ""
                    val audioBytes = if (audioBase64.isNotEmpty()) Base64.getDecoder().decode(audioBase64) else ByteArray(0)
                    val contentType = data?.get("content_type")?.jsonPrimitive?.content
                    val requestId = root["request_id"]?.jsonPrimitive?.content ?: data?.get("request_id")?.jsonPrimitive?.content
                    TtsStreamEvent.AudioChunk(audioBytes, contentType, requestId)
                }
                "event" -> {
                    val eventName = data?.get("event")?.jsonPrimitive?.content
                    val eventType = data?.get("event_type")?.jsonPrimitive?.content
                    val requestId = root["request_id"]?.jsonPrimitive?.content ?: data?.get("request_id")?.jsonPrimitive?.content
                    if (eventName == "final" || eventType == "completion") {
                        TtsStreamEvent.Completed(requestId)
                    } else {
                        TtsStreamEvent.Unknown(jsonString)
                    }
                }
                "error" -> {
                    val message = data?.get("message")?.jsonPrimitive?.content ?: root["message"]?.jsonPrimitive?.content ?: "TTS error"
                    val code = data?.get("code")?.jsonPrimitive?.content ?: root["code"]?.jsonPrimitive?.content
                    TtsStreamEvent.Error(message, code)
                }
                else -> TtsStreamEvent.Unknown(jsonString)
            }
        } catch (_: Exception) {
            TtsStreamEvent.Unknown(jsonString)
        }
    }
}
