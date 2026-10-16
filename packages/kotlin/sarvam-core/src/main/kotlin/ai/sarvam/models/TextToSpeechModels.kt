package ai.sarvam.models

import ai.sarvam.generated.AudioCodec
import ai.sarvam.generated.LanguageCode
import ai.sarvam.generated.Speaker
import ai.sarvam.generated.TtsModel
import kotlinx.serialization.SerialName
import kotlinx.serialization.Serializable
import java.util.Base64

@Serializable
public data class TextToSpeechRequest(
    public val text: String,
    @SerialName("target_language_code")
    public val targetLanguageCode: LanguageCode,
    public val speaker: Speaker? = null,
    public val pitch: Double? = null,
    public val pace: Double? = null,
    public val loudness: Double? = null,
    @SerialName("speech_sample_rate")
    public val speechSampleRate: Int? = null,
    @SerialName("enable_preprocessing")
    public val enablePreprocessing: Boolean? = null,
    public val model: TtsModel? = null,
    @SerialName("output_audio_codec")
    public val outputAudioCodec: AudioCodec? = null
)

@Serializable
public data class TextToSpeechResponse(
    public val audios: List<TtsAudio> = emptyList()
) {
    public val audioBytes: ByteArray by lazy {
        val base64 = audios.firstOrNull()?.audio
        if (base64.isNullOrEmpty()) ByteArray(0) else Base64.getDecoder().decode(base64)
    }

    public val firstAudioBase64: String?
        get() = audios.firstOrNull()?.audio

    public val firstAudioByteLength: Int
        get() = audioBytes.size

    public val audioCount: Int
        get() = audios.size
}

@Serializable
public data class TtsAudio(
    public val audio: String
)

public data class TtsStreamingConfig(
    val languageCode: LanguageCode = LanguageCode.HI_IN,
    val speaker: Speaker? = null,
    val model: TtsModel = TtsModel.BULBUL_V4_FLASH,
    val speechSampleRate: Int = 22050,
    val outputAudioCodec: AudioCodec = AudioCodec.MP3,
    val pitch: Double? = null,
    val pace: Double? = null,
    val loudness: Double? = null,
    val enablePreprocessing: Boolean? = null,
    val voiceId: String? = null
)

public sealed interface TtsStreamEvent {
    public data class AudioChunk(
        public val audioBytes: ByteArray,
        public val contentType: String? = null,
        public val requestId: String? = null
    ) : TtsStreamEvent {
        override fun equals(other: Any?): Boolean {
            if (this === other) return true
            if (javaClass != other?.javaClass) return false
            other as AudioChunk
            return audioBytes.contentEquals(other.audioBytes) &&
                    contentType == other.contentType &&
                    requestId == other.requestId
        }

        override fun hashCode(): Int {
            var result = audioBytes.contentHashCode()
            result = 31 * result + (contentType?.hashCode() ?: 0)
            result = 31 * result + (requestId?.hashCode() ?: 0)
            return result
        }
    }

    public data class Completed(public val requestId: String? = null) : TtsStreamEvent
    public data class Error(public val message: String, public val code: String? = null) : TtsStreamEvent
    public data class Unknown(public val rawJson: String) : TtsStreamEvent
}
