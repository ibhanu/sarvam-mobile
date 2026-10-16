package ai.sarvam.models

import ai.sarvam.generated.LanguageCode
import ai.sarvam.generated.SttMode
import ai.sarvam.generated.SttModel
import kotlinx.serialization.SerialName
import kotlinx.serialization.Serializable

@Serializable
public data class SpeechToTextResponse(
    public val transcript: String? = null,
    @SerialName("language_code")
    public val languageCode: LanguageCode? = null,
    public val timestamps: List<SpeechTimestamp>? = null,
    @SerialName("diarized_transcript")
    public val diarizedTranscript: DiarizedTranscript? = null
)

@Serializable
public data class SpeechTimestamp(
    public val word: String? = null,
    @SerialName("start_s")
    public val startS: Double? = null,
    @SerialName("end_s")
    public val endS: Double? = null
)

@Serializable
public data class DiarizedTranscript(
    public val entries: List<DiarizedEntry> = emptyList()
)

@Serializable
public data class DiarizedEntry(
    public val transcript: String,
    @SerialName("start_time_seconds")
    public val startTimeSeconds: Double? = null,
    @SerialName("end_time_seconds")
    public val endTimeSeconds: Double? = null,
    @SerialName("speaker_id")
    public val speakerId: String? = null
)

public data class SttRealtimeConfig(
    val languageCode: LanguageCode = LanguageCode.HI_IN,
    val model: SttModel = SttModel.SAARAS_V3_REALTIME,
    val sampleRate: Int = 16000,
    val streamType: String? = null,
    val mode: SttMode? = null,
    val encoding: String? = null,
    val returnTimestamps: Boolean? = null,
    val endpointing: Boolean? = null,
    val threshold: Double? = null,
    val prefixPaddingMs: Int? = null,
    val silenceDurationMs: Int? = null,
    val minSpeechDurationMs: Int? = null,
    val prompt: String? = null,
    val keyterms: List<String>? = null,
    val useSubprotocolAuth: Boolean = false
)

public sealed interface SttRealtimeEvent {
    public data class SessionBegin(public val sessionId: String) : SttRealtimeEvent
    public data class VadSpeechStart(public val timestampMs: Long? = null) : SttRealtimeEvent
    public data class VadSpeechEnd(public val timestampMs: Long? = null) : SttRealtimeEvent
    public data class TranscriptPartial(
        public val utteranceIdx: Int? = null,
        public val text: String,
        public val language: LanguageCode? = null
    ) : SttRealtimeEvent
    public data class TranscriptFinal(
        public val utteranceIdx: Int? = null,
        public val text: String,
        public val language: LanguageCode? = null,
        public val languageConfidence: Double? = null,
        public val startS: Double? = null,
        public val endS: Double? = null
    ) : SttRealtimeEvent
    public data class SessionEnd(public val durationSeconds: Double? = null) : SttRealtimeEvent
    public data class Error(public val code: String? = null, public val message: String) : SttRealtimeEvent
    public data class Unknown(public val rawJson: String) : SttRealtimeEvent
}
