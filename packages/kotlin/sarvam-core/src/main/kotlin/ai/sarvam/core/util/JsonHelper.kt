package ai.sarvam.core.util

import kotlinx.serialization.json.Json

public object JsonHelper {
    public val defaultJson: Json = Json {
        ignoreUnknownKeys = true
        isLenient = true
        encodeDefaults = true
        coerceInputValues = true
        explicitNulls = false
    }
}
