package ai.sarvam.core

import ai.sarvam.generated.SarvamSpecMetadata

public data class SarvamEnvironment(
    val apiBaseUrl: String,
    val dubbingBaseUrl: String,
    val wsBaseUrl: String
) {
    public companion object {
        public val PRODUCTION: SarvamEnvironment = SarvamEnvironment(
            apiBaseUrl = SarvamSpecMetadata.DEFAULT_API_BASE_URL,
            dubbingBaseUrl = SarvamSpecMetadata.DEFAULT_DUBBING_BASE_URL,
            wsBaseUrl = SarvamSpecMetadata.DEFAULT_WS_BASE_URL
        )

        public fun proxy(baseUrl: String): SarvamEnvironment {
            val cleanBase = baseUrl.trimEnd('/')
            val wsBase = when {
                cleanBase.startsWith("https://") -> cleanBase.replaceFirst("https://", "wss://")
                cleanBase.startsWith("http://") -> cleanBase.replaceFirst("http://", "ws://")
                cleanBase.startsWith("wss://") || cleanBase.startsWith("ws://") -> cleanBase
                else -> "wss://$cleanBase"
            }
            return SarvamEnvironment(
                apiBaseUrl = cleanBase,
                dubbingBaseUrl = "$cleanBase/dubbing",
                wsBaseUrl = wsBase
            )
        }
    }
}
