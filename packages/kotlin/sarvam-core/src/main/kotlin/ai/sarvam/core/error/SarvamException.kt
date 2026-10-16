package ai.sarvam.core.error

import ai.sarvam.core.util.Clock
import ai.sarvam.core.util.SystemClock
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.jsonObject
import kotlinx.serialization.json.jsonPrimitive

public enum class TimeoutPhase {
    CONNECT,
    READ,
    TOTAL
}

public sealed class SarvamException(
    message: String? = null,
    cause: Throwable? = null
) : RuntimeException(message, cause) {

    public class AuthenticationException(
        public val statusCode: Int,
        public val code: String?,
        public val requestId: String?,
        message: String
    ) : SarvamException("Authentication failed ($statusCode${code?.let { ": $it" } ?: ""}): $message")

    public class PermissionDeniedException(
        public val statusCode: Int,
        public val code: String?,
        public val requestId: String?,
        message: String
    ) : SarvamException("Permission denied ($statusCode${code?.let { ": $it" } ?: ""}): $message")

    public class BadRequestException(
        public val statusCode: Int,
        public val code: String?,
        public val requestId: String?,
        public val rawBody: String? = null,
        message: String
    ) : SarvamException("Bad request ($statusCode${code?.let { ": $it" } ?: ""}): $message")

    public class NotFoundException(
        public val statusCode: Int,
        public val code: String?,
        public val requestId: String?,
        message: String
    ) : SarvamException("Not found ($statusCode${code?.let { ": $it" } ?: ""}): $message")

    public class PayloadTooLargeException(
        public val statusCode: Int,
        public val code: String?,
        public val requestId: String?,
        message: String
    ) : SarvamException("Payload too large ($statusCode${code?.let { ": $it" } ?: ""}): $message")

    public class UnprocessableEntityException(
        public val statusCode: Int,
        public val code: String?,
        public val requestId: String?,
        public val rawBody: String? = null,
        message: String
    ) : SarvamException("Unprocessable entity ($statusCode${code?.let { ": $it" } ?: ""}): $message")

    public class RateLimitException(
        public val retryAfterMs: Long?,
        public val statusCode: Int,
        public val code: String?,
        public val requestId: String?,
        message: String
    ) : SarvamException("Rate limit exceeded ($statusCode${code?.let { ": $it" } ?: ""}${retryAfterMs?.let { ", retry-after: ${it}ms" } ?: ""}): $message")

    public class ServerException(
        public val statusCode: Int,
        public val code: String?,
        public val requestId: String?,
        message: String
    ) : SarvamException("Server error ($statusCode${code?.let { ": $it" } ?: ""}): $message")

    public class ConnectionException(
        message: String,
        cause: Throwable? = null
    ) : SarvamException(message, cause)

    public class TimeoutException(
        public val phase: TimeoutPhase,
        message: String,
        cause: Throwable? = null
    ) : SarvamException(message, cause)

    public class StreamException(
        public val requestId: String?,
        message: String,
        cause: Throwable? = null
    ) : SarvamException(message, cause)

    public class RealtimeException(
        public val closeCode: Int?,
        public val code: String?,
        message: String
    ) : SarvamException("Realtime error (code=$code, closeCode=$closeCode): $message")

    public class DecodingException(
        public val rawBody: String?,
        message: String,
        cause: Throwable? = null
    ) : SarvamException(message, cause)

    public companion object {
        public fun fromHttpResponse(
            statusCode: Int,
            headers: Map<String, List<String>>,
            bodyString: String,
            clock: Clock = SystemClock
        ): SarvamException {
            var parsedCode: String? = null
            var parsedMessage: String? = null
            var parsedRequestId: String? = headers.entries
                .firstOrNull { it.key.equals("x-request-id", ignoreCase = true) }
                ?.value?.firstOrNull()

            if (bodyString.isNotBlank()) {
                try {
                    val root = Json.parseToJsonElement(bodyString).jsonObject
                    if (root.containsKey("error")) {
                        val errorObj = root["error"]?.jsonObject
                        if (errorObj != null) {
                            parsedCode = errorObj["code"]?.jsonPrimitive?.content
                            parsedMessage = errorObj["message"]?.jsonPrimitive?.content
                            if (parsedRequestId == null) {
                                parsedRequestId = errorObj["request_id"]?.jsonPrimitive?.content
                            }
                        }
                    } else if (root.containsKey("detail")) {
                        parsedMessage = root["detail"]?.jsonPrimitive?.content
                    }
                } catch (_: Exception) {
                    // Not JSON, bodyString is raw message
                }
            }

            val finalMessage = parsedMessage ?: bodyString.ifBlank { "HTTP $statusCode error" }

            // Rate limit header parsing
            val retryAfterMs = parseRetryAfterMs(headers, clock)

            return when {
                statusCode == 401 || (statusCode == 403 && parsedCode == "invalid_api_key_error") -> {
                    AuthenticationException(
                        statusCode = statusCode,
                        code = parsedCode,
                        requestId = parsedRequestId,
                        message = finalMessage
                    )
                }
                statusCode == 403 -> {
                    PermissionDeniedException(
                        statusCode = statusCode,
                        code = parsedCode,
                        requestId = parsedRequestId,
                        message = finalMessage
                    )
                }
                statusCode == 400 -> {
                    BadRequestException(
                        statusCode = statusCode,
                        code = parsedCode,
                        requestId = parsedRequestId,
                        rawBody = bodyString,
                        message = finalMessage
                    )
                }
                statusCode == 404 -> {
                    NotFoundException(
                        statusCode = statusCode,
                        code = parsedCode,
                        requestId = parsedRequestId,
                        message = finalMessage
                    )
                }
                statusCode == 413 -> {
                    PayloadTooLargeException(
                        statusCode = statusCode,
                        code = parsedCode,
                        requestId = parsedRequestId,
                        message = finalMessage
                    )
                }
                statusCode == 422 -> {
                    UnprocessableEntityException(
                        statusCode = statusCode,
                        code = parsedCode,
                        requestId = parsedRequestId,
                        rawBody = bodyString,
                        message = finalMessage
                    )
                }
                statusCode == 429 || (statusCode == 503 && parsedCode == "rate_limit_exceeded_error") -> {
                    RateLimitException(
                        retryAfterMs = retryAfterMs,
                        statusCode = statusCode,
                        code = parsedCode,
                        requestId = parsedRequestId,
                        message = finalMessage
                    )
                }
                statusCode in listOf(500, 502, 503, 504, 408, 409) -> {
                    ServerException(
                        statusCode = statusCode,
                        code = parsedCode,
                        requestId = parsedRequestId,
                        message = finalMessage
                    )
                }
                statusCode >= 500 -> {
                    ServerException(
                        statusCode = statusCode,
                        code = parsedCode,
                        requestId = parsedRequestId,
                        message = finalMessage
                    )
                }
                else -> {
                    BadRequestException(
                        statusCode = statusCode,
                        code = parsedCode,
                        requestId = parsedRequestId,
                        rawBody = bodyString,
                        message = finalMessage
                    )
                }
            }
        }

        private fun parseRetryAfterMs(headers: Map<String, List<String>>, clock: Clock): Long? {
            // 1. retry-after-ms (case insensitive)
            val msHeader = headers.entries.firstOrNull { it.key.equals("retry-after-ms", ignoreCase = true) }?.value?.firstOrNull()
            if (!msHeader.isNullOrBlank()) {
                msHeader.toLongOrNull()?.let { return it }
            }

            // 2. Retry-After (seconds or HTTP date)
            val retryAfter = headers.entries.firstOrNull { it.key.equals("retry-after", ignoreCase = true) }?.value?.firstOrNull()
            if (!retryAfter.isNullOrBlank()) {
                retryAfter.toLongOrNull()?.let { return it * 1000L }
                // Try parse HTTP Date if needed
                try {
                    val date = java.time.format.DateTimeFormatter.RFC_1123_DATE_TIME.parse(retryAfter)
                    val instant = java.time.Instant.from(date)
                    val diff = instant.toEpochMilli() - clock.currentTimeMillis()
                    if (diff > 0) return diff
                } catch (_: Exception) {}
            }

            // 3. X-RateLimit-Reset (epoch seconds)
            val resetHeader = headers.entries.firstOrNull { it.key.equals("x-ratelimit-reset", ignoreCase = true) }?.value?.firstOrNull()
            if (!resetHeader.isNullOrBlank()) {
                resetHeader.toLongOrNull()?.let { resetEpochSec ->
                    val diffMs = (resetEpochSec * 1000L) - clock.currentTimeMillis()
                    if (diffMs > 0) return diffMs
                }
            }

            return null
        }
    }
}
