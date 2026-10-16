package ai.sarvam.resources

import ai.sarvam.core.RequestOptions
import ai.sarvam.core.SarvamClientConfig
import ai.sarvam.core.http.HttpBody
import ai.sarvam.core.http.HttpRequest
import ai.sarvam.generated.OperationKind
import ai.sarvam.models.BulkJobInitResponse
import ai.sarvam.models.FilesDownloadResponse
import ai.sarvam.models.FilesRequest
import ai.sarvam.models.FilesUploadResponse
import ai.sarvam.models.JobStatusResponse
import ai.sarvam.models.SpeechToTextJobInitRequest
import java.net.URLEncoder
import java.nio.charset.StandardCharsets

public class SpeechToTextJobResource(
    private val config: SarvamClientConfig,
    private val poller: JobPoller = JobPoller(config.clock)
) {

    public suspend fun initialise(
        request: SpeechToTextJobInitRequest,
        options: RequestOptions? = null
    ): BulkJobInitResponse {
        val payload = config.json.encodeToString(SpeechToTextJobInitRequest.serializer(), request)
        var httpRequest = HttpRequest(
            method = "POST",
            url = "${config.environment.apiBaseUrl}/speech-to-text/job/v1",
            body = HttpBody.Json(payload),
            operationKind = OperationKind.JOB_CREATE,
            timeoutMillis = options?.timeoutMillis
        )
        if (options != null) {
            httpRequest = httpRequest.withHeaders(options.headers)
        }

        val response = config.execute(httpRequest)
        return config.json.decodeFromString(BulkJobInitResponse.serializer(), response.bodyAsString())
    }

    public suspend fun getUploadLinks(
        jobId: String,
        files: List<String>,
        options: RequestOptions? = null
    ): FilesUploadResponse {
        val payload = config.json.encodeToString(FilesRequest.serializer(), FilesRequest(jobId = jobId, files = files))
        var httpRequest = HttpRequest(
            method = "POST",
            url = "${config.environment.apiBaseUrl}/speech-to-text/job/v1/upload-files",
            body = HttpBody.Json(payload),
            operationKind = OperationKind.STATELESS_POST,
            timeoutMillis = options?.timeoutMillis
        )
        if (options != null) {
            httpRequest = httpRequest.withHeaders(options.headers)
        }

        val response = config.execute(httpRequest)
        return config.json.decodeFromString(FilesUploadResponse.serializer(), response.bodyAsString())
    }

    public suspend fun start(
        jobId: String,
        ptuId: String? = null,
        options: RequestOptions? = null
    ): JobStatusResponse {
        val encodedId = URLEncoder.encode(jobId, StandardCharsets.UTF_8)
        val queryString = if (ptuId != null) "?ptu_id=${URLEncoder.encode(ptuId, StandardCharsets.UTF_8)}" else ""
        var httpRequest = HttpRequest(
            method = "POST",
            url = "${config.environment.apiBaseUrl}/speech-to-text/job/v1/$encodedId/start$queryString",
            operationKind = OperationKind.STATELESS_POST,
            timeoutMillis = options?.timeoutMillis
        )
        if (options != null) {
            httpRequest = httpRequest.withHeaders(options.headers)
        }

        val response = config.execute(httpRequest)
        return config.json.decodeFromString(JobStatusResponse.serializer(), response.bodyAsString())
    }

    public suspend fun getStatus(
        jobId: String,
        options: RequestOptions? = null
    ): JobStatusResponse {
        val encodedId = URLEncoder.encode(jobId, StandardCharsets.UTF_8)
        var httpRequest = HttpRequest(
            method = "GET",
            url = "${config.environment.apiBaseUrl}/speech-to-text/job/v1/$encodedId/status",
            operationKind = OperationKind.IDEMPOTENT,
            timeoutMillis = options?.timeoutMillis
        )
        if (options != null) {
            httpRequest = httpRequest.withHeaders(options.headers)
        }

        val response = config.execute(httpRequest)
        return config.json.decodeFromString(JobStatusResponse.serializer(), response.bodyAsString())
    }

    public suspend fun getDownloadLinks(
        jobId: String,
        files: List<String>,
        options: RequestOptions? = null
    ): FilesDownloadResponse {
        val payload = config.json.encodeToString(FilesRequest.serializer(), FilesRequest(jobId = jobId, files = files))
        var httpRequest = HttpRequest(
            method = "POST",
            url = "${config.environment.apiBaseUrl}/speech-to-text/job/v1/download-files",
            body = HttpBody.Json(payload),
            operationKind = OperationKind.STATELESS_POST,
            timeoutMillis = options?.timeoutMillis
        )
        if (options != null) {
            httpRequest = httpRequest.withHeaders(options.headers)
        }

        val response = config.execute(httpRequest)
        return config.json.decodeFromString(FilesDownloadResponse.serializer(), response.bodyAsString())
    }

    public suspend fun waitUntilComplete(
        jobId: String,
        pollIntervalMs: Long = 5000L,
        timeoutMs: Long = 600_000L,
        options: RequestOptions? = null
    ): JobStatusResponse {
        return poller.waitUntilComplete(
            jobId = jobId,
            pollIntervalMs = pollIntervalMs,
            timeoutMs = timeoutMs,
            fetchStatus = { getStatus(it, options) },
            isTerminal = {
                val state = it.jobState ?: ""
                state.equals("Completed", ignoreCase = true) || state.equals("Failed", ignoreCase = true)
            },
            isFailed = {
                val state = it.jobState ?: ""
                state.equals("Failed", ignoreCase = true)
            }
        )
    }
}
