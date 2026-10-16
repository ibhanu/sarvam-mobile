package ai.sarvam.models

import ai.sarvam.generated.LanguageCode
import kotlinx.serialization.SerialName
import kotlinx.serialization.Serializable

@Serializable
public data class TranslateRequest(
    public val input: String,
    @SerialName("source_language_code")
    public val sourceLanguageCode: LanguageCode = LanguageCode.AUTO,
    @SerialName("target_language_code")
    public val targetLanguageCode: LanguageCode,
    @SerialName("speaker_gender")
    public val speakerGender: String? = null,
    public val mode: String? = null,
    public val model: String? = null,
    @SerialName("enable_preprocessing")
    public val enablePreprocessing: Boolean? = null
)

@Serializable
public data class TranslateResponse(
    @SerialName("translated_text")
    public val translatedText: String
)

@Serializable
public data class TransliterateRequest(
    public val input: String,
    @SerialName("source_language_code")
    public val sourceLanguageCode: LanguageCode,
    @SerialName("target_language_code")
    public val targetLanguageCode: LanguageCode,
    @SerialName("spoken_form")
    public val spokenForm: Boolean? = null,
    public val model: String? = null
)

@Serializable
public data class TransliterateResponse(
    @SerialName("transliterated_text")
    public val transliteratedText: String
)

@Serializable
public data class TextLidRequest(
    public val input: String
)

@Serializable
public data class TextLidResponse(
    @SerialName("detected_language")
    public val detectedLanguage: String,
    public val confidence: Double
)
