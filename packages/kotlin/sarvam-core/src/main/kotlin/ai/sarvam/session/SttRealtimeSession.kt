package ai.sarvam.session

import ai.sarvam.core.ws.WebSocketFrame
import ai.sarvam.core.ws.WebSocketSession
import ai.sarvam.generated.LanguageCode
import ai.sarvam.models.SttRealtimeEvent
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.mapNotNull
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.doubleOrNull
import kotlinx.serialization.json.intOrNull
import kotlinx.serialization.json.jsonObject
import kotlinx.serialization.json.jsonPrimitive
import kotlinx.serialization.json.longOrNull
import java.util.Base64

public class SttRealtimeSession(
    private val webSocketSession: WebSocketSession
) : AutoCloseable {

    public suspend fun sendAudio(pcmBytes: ByteArray) {
        val b64 = Base64.getEncoder().encodeToString(pcmBytes)
        webSocketSession.send("""{"event":"audio_input","audio":"$b64"}""")
    }

    public suspend fun updateConfig(
        mode: String? = null,
        keyterms: List<String>? = null,
        threshold: Double? = null,
        silenceDurationMs: Int? = null
    ) {
        val fields = mutableListOf<String>()
        mode?.let { fields.add(""""mode":"$it"""") }
        keyterms?.let { terms ->
            val termsJson = terms.joinToString(",", prefix = "[", postfix = "]") { "\"$it\"" }
            fields.add(""""keyterms":$termsJson""")
        }
        threshold?.let { fields.add(""""threshold":$it""") }
        silenceDurationMs?.let { fields.add(""""silence_duration_ms":$it""") }

        val payload = """{"event":"config_update",${fields.joinToString(",")}}"""
        webSocketSession.send(payload)
    }

    public suspend fun flush() {
        webSocketSession.send("""{"event":"flush"}""")
    }

    public suspend fun ping() {
        webSocketSession.send("""{"event":"ping"}""")
    }

    public suspend fun end() {
        webSocketSession.send("""{"event":"end"}""")
    }

    public fun close(code: Int = 1000, reason: String? = null) {
        webSocketSession.close(code, reason)
    }

    override fun close() {
        close(1000, "Closed by client")
    }

    public val events: Flow<SttRealtimeEvent> = webSocketSession.incoming.mapNotNull { frame ->
        when (frame) {
            is WebSocketFrame.Text -> parseFrame(frame.text)
            is WebSocketFrame.Closed -> {
                if (frame.code != 1000) {
                    SttRealtimeEvent.Error(code = "ws_closed_${frame.code}", message = frame.reason)
                } else {
                    null
                }
            }
            is WebSocketFrame.Failure -> {
                SttRealtimeEvent.Error(code = "ws_failure", message = frame.throwable.message ?: "Connection failure")
            }
            else -> null
        }
    }

    private fun parseFrame(jsonString: String): SttRealtimeEvent {
        return try {
            val root = Json.parseToJsonElement(jsonString).jsonObject
            val eventType = root["event"]?.jsonPrimitive?.content ?: return SttRealtimeEvent.Unknown(jsonString)

            when (eventType) {
                "session_begin" -> {
                    val sessionId = root["session_id"]?.jsonPrimitive?.content ?: ""
                    SttRealtimeEvent.SessionBegin(sessionId)
                }
                "vad_speech_start", "speech_start" -> {
                    val timestampMs = root["timestamp_ms"]?.jsonPrimitive?.longOrNull
                    SttRealtimeEvent.VadSpeechStart(timestampMs)
                }
                "vad_speech_end", "speech_end" -> {
                    val timestampMs = root["timestamp_ms"]?.jsonPrimitive?.longOrNull
                    SttRealtimeEvent.VadSpeechEnd(timestampMs)
                }
                "transcript_partial" -> {
                    val utteranceIdx = root["utterance_idx"]?.jsonPrimitive?.intOrNull
                    val text = root["text"]?.jsonPrimitive?.content ?: ""
                    val lang = root["language"]?.jsonPrimitive?.content?.let { LanguageCode(it) }
                    SttRealtimeEvent.TranscriptPartial(utteranceIdx, text, lang)
                }
                "transcript_final", "transcript" -> {
                    val utteranceIdx = root["utterance_idx"]?.jsonPrimitive?.intOrNull
                    val text = root["text"]?.jsonPrimitive?.content ?: ""
                    val lang = root["language"]?.jsonPrimitive?.content?.let { LanguageCode(it) }
                    val confidence = root["language_confidence"]?.jsonPrimitive?.doubleOrNull
                    val startS = root["start_s"]?.jsonPrimitive?.doubleOrNull
                    val endS = root["end_s"]?.jsonPrimitive?.doubleOrNull
                    SttRealtimeEvent.TranscriptFinal(utteranceIdx, text, lang, confidence, startS, endS)
                }
                "session_end" -> {
                    val duration = root["duration_seconds"]?.jsonPrimitive?.doubleOrNull
                    SttRealtimeEvent.SessionEnd(duration)
                }
                "error" -> {
                    val code = root["code"]?.jsonPrimitive?.content
                    val message = root["message"]?.jsonPrimitive?.content ?: "Realtime error"
                    SttRealtimeEvent.Error(code, message)
                }
                else -> SttRealtimeEvent.Unknown(jsonString)
            }
        } catch (_: Exception) {
            SttRealtimeEvent.Unknown(jsonString)
        }
    }
}
