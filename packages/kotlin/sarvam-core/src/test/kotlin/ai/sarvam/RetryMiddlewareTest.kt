package ai.sarvam

import ai.sarvam.core.error.SarvamException
import ai.sarvam.core.http.HttpRequest
import ai.sarvam.core.http.HttpResponse
import ai.sarvam.core.middleware.RetryMiddleware
import ai.sarvam.core.util.Clock
import ai.sarvam.core.util.RandomSource
import ai.sarvam.generated.OperationKind
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.emptyFlow
import kotlinx.coroutines.test.runTest
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Assert.fail
import org.junit.Test
import java.util.concurrent.atomic.AtomicInteger

class RetryMiddlewareTest {

    private class ConstantRandom : RandomSource {
        override fun nextLong(until: Long): Long = 100L
    }

    private class FixedClock : Clock {
        override fun currentTimeMillis(): Long = 1_000_000L
    }

    private class SimpleResponse(override val statusCode: Int = 200) : HttpResponse {
        override val headers: Map<String, List<String>> = emptyMap()
        override suspend fun bodyAsString(): String = "{}"
        override suspend fun bodyAsBytes(): ByteArray = ByteArray(0)
        override fun bodyByteStream(): Flow<ByteArray> = emptyFlow()
    }

    @Test
    fun `IDEMPOTENT GET operation retries on HTTP 500 and succeeds on attempt 2`() = runTest {
        val attempts = AtomicInteger(0)
        val delays = mutableListOf<Long>()

        val middleware = RetryMiddleware(
            maxRetries = 2,
            baseBackoffMs = 500L,
            randomSource = ConstantRandom(),
            sleeper = { delays.add(it) }
        )

        val request = HttpRequest(
            method = "GET",
            url = "https://api.sarvam.ai/v2/models",
            operationKind = OperationKind.IDEMPOTENT
        )

        val response = middleware.intercept(request) { req ->
            val count = attempts.incrementAndGet()
            if (count == 1) {
                throw SarvamException.ServerException(500, "internal_server_error", "req_500", "Glitch")
            }
            SimpleResponse(200)
        }

        assertEquals(200, response.statusCode)
        assertEquals(2, attempts.get())
        assertEquals(1, delays.size)
        assertEquals(100L, delays[0])
    }

    @Test
    fun `JOB_CREATE operation throws ServerException immediately on 500 with 0 retries`() = runTest {
        val attempts = AtomicInteger(0)
        val delays = mutableListOf<Long>()

        val middleware = RetryMiddleware(
            maxRetries = 2,
            baseBackoffMs = 500L,
            randomSource = ConstantRandom(),
            sleeper = { delays.add(it) }
        )

        val request = HttpRequest(
            method = "POST",
            url = "https://api.sarvam.ai/doc-ai/v1/job/digitise",
            operationKind = OperationKind.JOB_CREATE
        )

        try {
            middleware.intercept(request) {
                attempts.incrementAndGet()
                throw SarvamException.ServerException(500, "internal_server_error", "req_job_500", "Internal Server Error")
            }
            fail("Expected ServerException")
        } catch (e: SarvamException.ServerException) {
            assertEquals(500, e.statusCode)
            assertEquals("req_job_500", e.requestId)
            assertEquals(1, attempts.get()) // 0 retries performed!
            assertEquals(0, delays.size)
        }
    }

    @Test
    fun `JOB_CREATE operation retries on 429 rate limit`() = runTest {
        val attempts = AtomicInteger(0)
        val delays = mutableListOf<Long>()

        val middleware = RetryMiddleware(
            maxRetries = 2,
            sleeper = { delays.add(it) }
        )

        val request = HttpRequest(
            method = "POST",
            url = "https://api.sarvam.ai/doc-ai/v1/job/digitise",
            operationKind = OperationKind.JOB_CREATE
        )

        val response = middleware.intercept(request) {
            val count = attempts.incrementAndGet()
            if (count == 1) {
                throw SarvamException.RateLimitException(retryAfterMs = 42L, statusCode = 429, code = "rate_limit_exceeded_error", requestId = "req_rl", message = "Busy")
            }
            SimpleResponse(201)
        }

        assertEquals(201, response.statusCode)
        assertEquals(2, attempts.get())
        assertEquals(listOf(42L), delays)
    }

    @Test
    fun `AuthenticationException is never retried with backoff`() {
        val middleware = RetryMiddleware()
        val request = HttpRequest(
            method = "POST",
            url = "https://api.sarvam.ai/translate",
            operationKind = OperationKind.STATELESS_POST
        )
        val authEx = SarvamException.AuthenticationException(401, "invalid_api_key_error", "req_1", "Invalid key")
        assertFalse(middleware.isRetryable(request, authEx))
    }
}
