package ai.sarvam

import ai.sarvam.core.auth.ApiKeyAuth
import ai.sarvam.core.auth.AuthToken
import ai.sarvam.core.auth.ProxyAuth
import ai.sarvam.core.auth.SarvamCredentials
import ai.sarvam.core.auth.TokenAuth
import ai.sarvam.core.util.Clock
import kotlinx.coroutines.async
import kotlinx.coroutines.awaitAll
import kotlinx.coroutines.test.runTest
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test
import java.util.concurrent.atomic.AtomicInteger

class AuthProviderTest {

    private class TestClock(var time: Long = 1_000_000L) : Clock {
        override fun currentTimeMillis(): Long = time
    }

    @Test
    fun `ApiKeyAuth produces subscription key credentials`() = runTest {
        val auth = ApiKeyAuth("my-secret-key")
        val creds = auth.getCredentials()
        assertTrue(creds is SarvamCredentials.SubscriptionKey)
        assertEquals("my-secret-key", (creds as SarvamCredentials.SubscriptionKey).key)
    }

    @Test
    fun `TokenAuth caches token and proactively refreshes 60s before expiry`() = runTest {
        val clock = TestClock(1_000_000L)
        val fetchCount = AtomicInteger(0)

        val auth = TokenAuth(
            tokenProvider = {
                val count = fetchCount.incrementAndGet()
                // expires in 120s from current clock
                AuthToken(token = "token-$count", expiresAtEpochMs = clock.time + 120_000L)
            },
            clock = clock
        )

        // First call: fetches token-1 (expires at 1_120_000)
        val cred1 = auth.getCredentials() as SarvamCredentials.BearerToken
        assertEquals("token-1", cred1.token)
        assertEquals(1, fetchCount.get())

        // Second call 30s later (clock = 1_030_000, 90s until expiry): should use cache
        clock.time = 1_030_000L
        val cred2 = auth.getCredentials() as SarvamCredentials.BearerToken
        assertEquals("token-1", cred2.token)
        assertEquals(1, fetchCount.get())

        // Third call at 65s later (clock = 1_065_000, 55s until expiry <= 60s threshold): should proactively refresh
        clock.time = 1_065_000L
        val cred3 = auth.getCredentials() as SarvamCredentials.BearerToken
        assertEquals("token-2", cred3.token)
        assertEquals(2, fetchCount.get())

        // Explicit invalidation forces fresh fetch
        auth.invalidate()
        val cred4 = auth.getCredentials() as SarvamCredentials.BearerToken
        assertEquals("token-3", cred4.token)
        assertEquals(3, fetchCount.get())
    }

    @Test
    fun `TokenAuth deduplicates concurrent refreshes with mutex`() = runTest {
        val clock = TestClock(1_000_000L)
        val fetchCount = AtomicInteger(0)

        val auth = TokenAuth(
            tokenProvider = {
                kotlinx.coroutines.delay(50)
                val count = fetchCount.incrementAndGet()
                AuthToken(token = "token-$count", expiresAtEpochMs = clock.time + 300_000L)
            },
            clock = clock
        )

        val deferreds = (1..10).map {
            async {
                auth.getCredentials() as SarvamCredentials.BearerToken
            }
        }

        val results = deferreds.awaitAll()
        assertEquals(10, results.size)
        // All concurrent callers received token-1
        results.forEach { assertEquals("token-1", it.token) }
        // Provider was only called once!
        assertEquals(1, fetchCount.get())
    }

    @Test
    fun `ProxyAuth produces custom headers`() = runTest {
        val auth = ProxyAuth("https://my-bff.com") {
            mapOf("X-App-Session" to "session_123")
        }
        val creds = auth.getCredentials()
        assertTrue(creds is SarvamCredentials.CustomHeaders)
        assertEquals("session_123", (creds as SarvamCredentials.CustomHeaders).headers["X-App-Session"])
    }
}
