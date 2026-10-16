package ai.sarvam.core.middleware

import ai.sarvam.core.http.HttpRequest
import ai.sarvam.core.http.HttpResponse

public enum class LogLevel {
    NONE,
    BASIC,
    HEADERS,
    BODY
}

public interface LoggerAdapter {
    public fun log(level: String, message: String)
}

public class ConsoleLogger : LoggerAdapter {
    override fun log(level: String, message: String) {
        println("[$level] $message")
    }
}

public class LoggingMiddleware(
    private val logLevel: LogLevel = LogLevel.NONE,
    private val logger: LoggerAdapter = ConsoleLogger()
) : Middleware {

    override suspend fun intercept(
        request: HttpRequest,
        next: suspend (HttpRequest) -> HttpResponse
    ): HttpResponse {
        if (logLevel == LogLevel.NONE) {
            return next(request)
        }

        val startTime = System.currentTimeMillis()
        logger.log("INFO", "--> ${request.method} ${request.url}")

        if (logLevel == LogLevel.HEADERS || logLevel == LogLevel.BODY) {
            for ((name, values) in request.headers) {
                val display = if (isSensitiveHeader(name)) "[REDACTED]" else values.joinToString(", ")
                logger.log("DEBUG", "  $name: $display")
            }
        }

        return try {
            val response = next(request)
            val duration = System.currentTimeMillis() - startTime
            logger.log("INFO", "<-- ${response.statusCode} ${request.url} (${duration}ms)")
            if (logLevel == LogLevel.HEADERS || logLevel == LogLevel.BODY) {
                for ((name, values) in response.headers) {
                    val display = if (isSensitiveHeader(name)) "[REDACTED]" else values.joinToString(", ")
                    logger.log("DEBUG", "  $name: $display")
                }
            }
            response
        } catch (e: Exception) {
            val duration = System.currentTimeMillis() - startTime
            logger.log("WARN", "<-- FAILED ${request.url} (${duration}ms): ${e.message}")
            throw e
        }
    }

    private fun isSensitiveHeader(name: String): Boolean {
        return name.equals("api-subscription-key", ignoreCase = true) ||
                name.equals("authorization", ignoreCase = true) ||
                name.equals("x-api-key", ignoreCase = true)
    }
}
