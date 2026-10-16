package ai.sarvam.resources

import ai.sarvam.core.RequestOptions
import ai.sarvam.core.SarvamClientConfig
import ai.sarvam.core.http.HttpBody
import ai.sarvam.core.http.HttpRequest
import ai.sarvam.generated.OperationKind
import ai.sarvam.models.CreateDubbingJobRequest
import ai.sarvam.models.CreateDubbingJobResponse
import ai.sarvam.models.DubbingExportStatusResponse
import ai.sarvam.models.DubbingLiveStatusResponse
import ai.sarvam.models.DubbingStartResponse
import java.net.URLEncoder
import java.nio.charset.StandardCharsets

public class DubbingResource(
    private val config: SarvamClientConfig,
    private val poller: JobPoller = JobPoller(config.clock)
) {

    public suspend fun create(
        request: CreateDubbingJobRequest,
        options: RequestOptions? = null
    ): CreateDubbingJobResponse {
        val payload = config.json.encodeToString(CreateDubbingJobRequest.serializer(), request)
        var httpRequest = HttpRequest(
            method = "POST",
            url = "${config.environment.dubbingBaseUrl}/jobs",
            body = HttpBody.Json(payload),
            operationKind = OperationKind.JOB_CREATE,
            timeoutMillis = options?.timeoutMillis
        )
        if (options != null) {
            httpRequest = httpRequest.withHeaders(options.headers)
        }

        val response = config.execute(httpRequest)
        return config.json.decodeFromString(CreateDubbingJobResponse.serializer(), response.bodyAsString())
    }

    public suspend fun start(
        jobId: String,
        options: RequestOptions? = null
    ): DubbingStartResponse {
        val encodedId = URLEncoder.encode(jobId, StandardCharsets.UTF_8)
        var httpRequest = HttpRequest(
            method = "POST",
            url = "${config.environment.dubbingBaseUrl}/jobs/$encodedId/start",
            operationKind = OperationKind.STATELESS_POST,
            timeoutMillis = options?.timeoutMillis
        )
        if (options != null) {
            httpRequest = httpRequest.withHeaders(options.headers)
        }

        val response = config.execute(httpRequest)
        return config.json.decodeFromString(DubbingStartResponse.serializer(), response.bodyAsString())
    }

    public suspend fun getLiveStatus(
        jobId: String,
        options: RequestOptions? = null
    ): DubbingLiveStatusResponse {
        val encodedId = URLEncoder.encode(jobId, StandardCharsets.UTF_8)
        var httpRequest = HttpRequest(
            method = "GET",
            url = "${config.environment.dubbingBaseUrl}/jobs/$encodedId/live-status",
            operationKind = OperationKind.IDEMPOTENT,
            timeoutMillis = options?.timeoutMillis
        )
        if (options != null) {
            httpRequest = httpRequest.withHeaders(options.headers)
        }

        val response = config.execute(httpRequest)
        return config.json.decodeFromString(DubbingLiveStatusResponse.serializer(), response.bodyAsString())
    }

    public suspend fun getExportStatus(
        jobId: String,
        limit: Int? = null,
        options: RequestOptions? = null
    ): DubbingExportStatusResponse {
        val encodedId = URLEncoder.encode(jobId, StandardCharsets.UTF_8)
        val queryString = if (limit != null) "?limit=$limit" else ""
        var httpRequest = HttpRequest(
            method = "GET",
            url = "${config.environment.dubbingBaseUrl}/jobs/$encodedId/export-status$queryString",
            operationKind = OperationKind.IDEMPOTENT,
            timeoutMillis = options?.timeoutMillis
        )
        if (options != null) {
            httpRequest = httpRequest.withHeaders(options.headers)
        }

        val response = config.execute(httpRequest)
        return config.json.decodeFromString(DubbingExportStatusResponse.serializer(), response.bodyAsString())
    }

    public suspend fun waitUntilComplete(
        jobId: String,
        pollIntervalMs: Long = 5000L,
        timeoutMs: Long = 600_000L,
        options: RequestOptions? = null
    ): DubbingLiveStatusResponse {
        return poller.waitUntilComplete(
            jobId = jobId,
            pollIntervalMs = pollIntervalMs,
            timeoutMs = timeoutMs,
            fetchStatus = { getLiveStatus(it, options) },
            isTerminal = {
                val status = it.data?.status?.lowercase() ?: ""
                status in TERMINAL_STATUSES
            },
            isFailed = {
                val status = it.data?.status?.lowercase() ?: ""
                status in FAILED_STATUSES
            }
        )
    }

    public companion object {
        public val TERMINAL_STATUSES: Set<String> = setOf("completed", "failed", "partial_failure", "deleted")
        public val FAILED_STATUSES: Set<String> = setOf("failed", "partial_failure", "deleted")
    }
}
