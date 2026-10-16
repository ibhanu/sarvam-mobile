package ai.sarvam.models

import kotlinx.serialization.SerialName
import kotlinx.serialization.Serializable

@Serializable
public data class PronunciationDictionaryCreateResponse(
    @SerialName("dictionary_id")
    public val dictionaryId: String
)

@Serializable
public data class PronunciationDictionaryListResponse(
    @SerialName("dictionary_count")
    public val dictionaryCount: Int = 0,
    public val dictionaries: List<String> = emptyList()
)

@Serializable
public data class PronunciationDictionaryUpdateResponse(
    @SerialName("dictionary_id")
    public val dictionaryId: String,
    @SerialName("updated_pronunciations")
    public val updatedPronunciations: Map<String, Map<String, String>> = emptyMap()
)

@Serializable
public data class PronunciationDictionaryDeleteResponse(
    public val success: Boolean,
    public val message: String
)

@Serializable
public data class PronunciationDictionaryData(
    public val pronunciations: Map<String, Map<String, String>> = emptyMap()
)
