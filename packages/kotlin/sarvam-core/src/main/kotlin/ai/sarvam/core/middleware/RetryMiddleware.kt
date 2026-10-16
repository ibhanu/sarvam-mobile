package ai.sarvam.core.middleware

import ai.sarvam.core.error.SarvamException
import ai.sarvam.core.http.HttpRequest
import ai.sarvam.core.http.HttpResponse
import ai.sarvam.core.util.Clock
import ai.sarvam.core.util.DefaultRandomSource
import ai.sarvam.core.util.RandomSource
import ai.sarvam.core.util.SystemClock
import ai.sarvam.generated.OperationKind
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.delay

public class RetryMiddleware(
    private val maxRetries: Int = 2,
    private val baseBackoffMs: Long = 500L,
    private val maxBackoffMs: Long = 8000L,
    private val clock: Clock = SystemClock,
    private val randomSource: RandomSource = DefaultRandomSource,
    private val sleeper: suspend (Long) -> Unit = { delay(it) }
) : Middleware {

    override suspend fun intercept(
        request: HttpRequest,
        next: suspend (HttpRequest) -> HttpResponse
    ): HttpResponse {
        var attempt = 0
        while (true) {
            try {
                return next(request)
            } catch (e: CancellationException) {
                throw e
            } catch (e: SarvamException) {
                if (attempt < maxRetries && isRetryable(request, e)) {
                    val delayMs = computeDelayMs(attempt, e)
                    attempt++
                    sleeper(delayMs)
                } else {
                    throw e
                }
            }
        }
    }

    public fun isRetryable(request: HttpRequest, e: SarvamException): Boolean {
        return when (e) {
            is SarvamException.AuthenticationException -> false
            is SarvamException.PermissionDeniedException -> false
            is SarvamException.BadRequestException -> false
            is SarvamException.NotFoundException -> false
            is SarvamException.PayloadTooLargeException -> false
            is SarvamException.UnprocessableEntityException -> false
            is SarvamException.StreamException -> false
            is SarvamException.RealtimeException -> false
            is SarvamException.DecodingException -> false
            is SarvamException.RateLimitException -> {
                when (request.operationKind) {
                    OperationKind.MULTIPART_COMPUTE -> request.isReplayable
                    else -> true
                }
            }
            is SarvamException.ServerException -> {
                when (request.operationKind) {
                    OperationKind.IDEMPOTENT -> true
                    OperationKind.STATELESS_POST -> true
                    OperationKind.MULTIPART_COMPUTE -> e.statusCode == 503 && request.isReplayable
                    OperationKind.JOB_CREATE -> request.header("Idempotency-Key") != null
                }
            }
            is SarvamException.ConnectionException -> {
                when (request.operationKind) {
                    OperationKind.IDEMPOTENT -> true
                    OperationKind.STATELESS_POST -> true
                    OperationKind.MULTIPART_COMPUTE -> request.isReplayable
                    OperationKind.JOB_CREATE -> request.header("Idempotency-Key") != null
                }
            }
            is SarvamException.TimeoutException -> {
                when (request.operationKind) {
                    OperationKind.IDEMPOTENT -> true
                    OperationKind.STATELESS_POST -> true
                    OperationKind.MULTIPART_COMPUTE -> request.isReplayable
                    OperationKind.JOB_CREATE -> request.header("Idempotency-Key") != null
                }
            }
        }
    }

    private fun computeDelayMs(attempt: Int, e: SarvamException): Long {
        if (e is SarvamException.RateLimitException && e.retryAfterMs != null) {
            return e.retryAfterMs
        }
        val factor = (1L shl attempt).coerceAtMost(64L)
        val ceiling = minOf(maxBackoffMs, baseBackoffMs * factor)
        return randomSource.nextLong(ceiling + 1L)
    }
}
