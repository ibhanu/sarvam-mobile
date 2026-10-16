package ai.sarvam.core.auth

import ai.sarvam.core.util.Clock
import ai.sarvam.core.util.SystemClock
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock

public sealed interface SarvamCredentials {
    public data class SubscriptionKey(val key: String) : SarvamCredentials
    public data class BearerToken(val token: String, val expiresAtEpochMs: Long? = null) : SarvamCredentials
    public data class CustomHeaders(val headers: Map<String, String>) : SarvamCredentials
}

public data class AuthToken(
    val token: String,
    val expiresAtEpochMs: Long? = null
)

public interface AuthProvider {
    public suspend fun getCredentials(): SarvamCredentials
    public fun invalidate() {}
}

public class ApiKeyAuth(private val apiKey: String) : AuthProvider {
    override suspend fun getCredentials(): SarvamCredentials =
        SarvamCredentials.SubscriptionKey(apiKey)
}

public class TokenAuth(
    private val tokenProvider: suspend () -> AuthToken,
    private val clock: Clock = SystemClock
) : AuthProvider {
    private val mutex = Mutex()
    private var cachedToken: AuthToken? = null

    override suspend fun getCredentials(): SarvamCredentials {
        mutex.withLock {
            val current = cachedToken
            val now = clock.currentTimeMillis()
            // Proactively refresh 60 seconds (60,000ms) prior to expiresAt
            val isExpired = current == null || (current.expiresAtEpochMs != null && now >= (current.expiresAtEpochMs - 60_000L))
            if (isExpired) {
                cachedToken = tokenProvider()
            }
            val active = cachedToken ?: tokenProvider().also { cachedToken = it }
            return SarvamCredentials.BearerToken(active.token, active.expiresAtEpochMs)
        }
    }

    override fun invalidate() {
        cachedToken = null
    }
}

public class ProxyAuth(
    public val proxyBaseUrl: String,
    private val headersProvider: suspend () -> Map<String, String> = { emptyMap() }
) : AuthProvider {
    override suspend fun getCredentials(): SarvamCredentials =
        SarvamCredentials.CustomHeaders(headersProvider())
}
