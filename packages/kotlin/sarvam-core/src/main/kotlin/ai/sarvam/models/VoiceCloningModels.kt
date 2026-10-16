package ai.sarvam.models

import ai.sarvam.core.io.FileInput
import ai.sarvam.generated.AudioCodec
import ai.sarvam.generated.LanguageCode
import kotlinx.serialization.SerialName
import kotlinx.serialization.Serializable
import java.util.Base64

public data class VoiceCloneRequest(
    public val text: String,
    public val voiceId: String? = null,
    public val refAudio: FileInput? = null,
    public val refText: String? = null,
    public val languageCode: LanguageCode? = null,
    public val pace: Double? = null,
    public val outputAudioCodec: AudioCodec? = null,
    public val speechSampleRate: Int? = null,
    public val enableQc: Boolean? = null,
    public val enableCachedResponses: Boolean? = null,
    public val enableVad: Boolean? = null,
    public val enableTextNormalization: Boolean? = null,
    public val minAudioDuration: Double? = null,
    public val maxAudioDuration: Double? = null,
    public val refAudioDuration: Double? = null
)

@Serializable
public data class VoiceCloneResponse(
    public val audio: String? = null,
    @SerialName("audio_b64")
    public val audioB64: String? = null,
    @SerialName("request_id")
    public val requestId: String? = null,
    @SerialName("audio_duration")
    public val audioDuration: Double? = null
) {
    public val audioBytes: ByteArray by lazy {
        val b64 = audio ?: audioB64
        if (b64.isNullOrEmpty()) ByteArray(0) else Base64.getDecoder().decode(b64)
    }
}

@Serializable
public data class VoiceLibraryListResponse(
    public val status: String? = null,
    public val data: VoiceLibraryListData? = null
)

@Serializable
public data class VoiceLibraryListData(
    public val voices: List<VoiceLibraryVoice> = emptyList(),
    public val total: Int = 0
)

@Serializable
public data class VoiceLibraryVoice(
    public val id: String,
    public val name: String,
    public val language: String? = null,
    public val gender: String? = null,
    public val accent: String? = null,
    public val descriptor: String? = null,
    public val status: String? = null,
    public val source: String? = null,
    @SerialName("created_at")
    public val createdAt: String? = null
)

@Serializable
public data class VoiceLibraryCreateResponse(
    public val status: String? = null,
    public val data: VoiceLibraryCreateData? = null
)

@Serializable
public data class VoiceLibraryCreateData(
    @SerialName("voice_id")
    public val voiceId: String,
    public val status: String? = null,
    @SerialName("reference_text")
    public val referenceText: String? = null
)

@Serializable
public data class VoiceLibraryDetailResponse(
    public val status: String? = null,
    public val data: VoiceLibraryDetail? = null
)

@Serializable
public data class VoiceLibraryDetail(
    public val id: String,
    public val name: String,
    public val language: String? = null,
    public val gender: String? = null,
    public val accent: String? = null,
    public val descriptor: String? = null,
    public val status: String? = null,
    public val source: String? = null,
    @SerialName("created_at")
    public val createdAt: String? = null,
    @SerialName("reference_text")
    public val referenceText: String? = null,
    @SerialName("preview_audio_url")
    public val previewAudioUrl: String? = null,
    @SerialName("reference_audio_url")
    public val referenceAudioUrl: String? = null
)
