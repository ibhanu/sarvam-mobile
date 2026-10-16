package ai.sarvam.core.middleware

import ai.sarvam.core.http.HttpRequest
import ai.sarvam.core.http.HttpResponse
import ai.sarvam.generated.SarvamSpecMetadata

public class UserAgentMiddleware : Middleware {

    private val userAgentString: String by lazy {
        val javaVersion = System.getProperty("java.version") ?: "unknown"
        val vmName = System.getProperty("java.vm.name") ?: "jvm"
        val osName = System.getProperty("os.name")?.lowercase() ?: "generic"
        val osVersion = System.getProperty("os.version") ?: "unknown"
        val platformTag = if (osName.contains("android") || vmName.contains("dalvik", ignoreCase = true) || vmName.contains("art", ignoreCase = true)) {
            "android/$osVersion"
        } else {
            "java/$javaVersion; jvm/$javaVersion"
        }
        "sarvam-kotlin/${SarvamSpecMetadata.SDK_VERSION} (spec/${SarvamSpecMetadata.SPEC_VERSION}; $platformTag)"
    }

    override suspend fun intercept(
        request: HttpRequest,
        next: suspend (HttpRequest) -> HttpResponse
    ): HttpResponse {
        var enriched = request
        if (enriched.header("User-Agent") == null) {
            enriched = enriched.withHeader("User-Agent", userAgentString)
        }
        if (enriched.header("X-Sarvam-SDK-Version") == null) {
            enriched = enriched.withHeader("X-Sarvam-SDK-Version", SarvamSpecMetadata.SDK_VERSION)
        }
        return next(enriched)
    }
}
