package ai.sarvam.resources

import ai.sarvam.core.RequestOptions
import ai.sarvam.core.SarvamClientConfig
import ai.sarvam.core.http.HttpBody
import ai.sarvam.core.http.HttpRequest
import ai.sarvam.generated.OperationKind
import ai.sarvam.models.CreateDocumentJobRequest
import ai.sarvam.models.CreateDocumentJobResponse
import ai.sarvam.models.DocumentJobExportStatusResponse
import ai.sarvam.models.DocumentJobLiveStatusResponse
import ai.sarvam.models.DocumentJobStartResponse
import java.net.URLEncoder
import java.nio.charset.StandardCharsets

public class DocumentTranslationResource(
    private val config: SarvamClientConfig,
    private val poller: JobPoller = JobPoller(config.clock)
) {

    public suspend fun create(
        request: CreateDocumentJobRequest,
        options: RequestOptions? = null
    ): CreateDocumentJobResponse {
        val payload = config.json.encodeToString(CreateDocumentJobRequest.serializer(), request)
        var httpRequest = HttpRequest(
            method = "POST",
            url = "${config.environment.apiBaseUrl}/translate/document/jobs",
            body = HttpBody.Json(payload),
            operationKind = OperationKind.JOB_CREATE,
            timeoutMillis = options?.timeoutMillis
        )
        if (options != null) {
            httpRequest = httpRequest.withHeaders(options.headers)
        }

        val response = config.execute(httpRequest)
        return config.json.decodeFromString(CreateDocumentJobResponse.serializer(), response.bodyAsString())
    }

    public suspend fun start(
        jobId: String,
        options: RequestOptions? = null
    ): DocumentJobStartResponse {
        val encodedId = URLEncoder.encode(jobId, StandardCharsets.UTF_8)
        var httpRequest = HttpRequest(
            method = "POST",
            url = "${config.environment.apiBaseUrl}/translate/document/jobs/$encodedId/start",
            operationKind = OperationKind.STATELESS_POST,
            timeoutMillis = options?.timeoutMillis
        )
        if (options != null) {
            httpRequest = httpRequest.withHeaders(options.headers)
        }

        val response = config.execute(httpRequest)
        return config.json.decodeFromString(DocumentJobStartResponse.serializer(), response.bodyAsString())
    }

    public suspend fun getLiveStatus(
        jobId: String,
        options: RequestOptions? = null
    ): DocumentJobLiveStatusResponse {
        val encodedId = URLEncoder.encode(jobId, StandardCharsets.UTF_8)
        var httpRequest = HttpRequest(
            method = "GET",
            url = "${config.environment.apiBaseUrl}/translate/document/jobs/$encodedId/live-status",
            operationKind = OperationKind.IDEMPOTENT,
            timeoutMillis = options?.timeoutMillis
        )
        if (options != null) {
            httpRequest = httpRequest.withHeaders(options.headers)
        }

        val response = config.execute(httpRequest)
        return config.json.decodeFromString(DocumentJobLiveStatusResponse.serializer(), response.bodyAsString())
    }

    public suspend fun triggerExport(
        jobId: String,
        lang: String,
        format: String? = null,
        options: RequestOptions? = null
    ): DocumentJobExportStatusResponse {
        val encodedId = URLEncoder.encode(jobId, StandardCharsets.UTF_8)
        val queryParams = mutableListOf<Pair<String, String>>()
        queryParams.add("lang" to lang)
        format?.let { queryParams.add("format" to it) }

        val queryString = "?" + queryParams.joinToString("&") { (k, v) ->
            "$k=${URLEncoder.encode(v, StandardCharsets.UTF_8)}"
        }

        var httpRequest = HttpRequest(
            method = "POST",
            url = "${config.environment.apiBaseUrl}/translate/document/jobs/$encodedId/export$queryString",
            operationKind = OperationKind.STATELESS_POST,
            timeoutMillis = options?.timeoutMillis
        )
        if (options != null) {
            httpRequest = httpRequest.withHeaders(options.headers)
        }

        val response = config.execute(httpRequest)
        return config.json.decodeFromString(DocumentJobExportStatusResponse.serializer(), response.bodyAsString())
    }

    public suspend fun getExportStatus(
        jobId: String,
        lang: String? = null,
        exportId: String? = null,
        options: RequestOptions? = null
    ): DocumentJobExportStatusResponse {
        val encodedId = URLEncoder.encode(jobId, StandardCharsets.UTF_8)
        val queryParams = mutableListOf<Pair<String, String>>()
        lang?.let { queryParams.add("lang" to it) }
        exportId?.let { queryParams.add("export_id" to it) }

        val queryString = if (queryParams.isNotEmpty()) {
            "?" + queryParams.joinToString("&") { (k, v) ->
                "$k=${URLEncoder.encode(v, StandardCharsets.UTF_8)}"
            }
        } else ""

        var httpRequest = HttpRequest(
            method = "GET",
            url = "${config.environment.apiBaseUrl}/translate/document/jobs/$encodedId/export/status$queryString",
            operationKind = OperationKind.IDEMPOTENT,
            timeoutMillis = options?.timeoutMillis
        )
        if (options != null) {
            httpRequest = httpRequest.withHeaders(options.headers)
        }

        val response = config.execute(httpRequest)
        return config.json.decodeFromString(DocumentJobExportStatusResponse.serializer(), response.bodyAsString())
    }

    public suspend fun waitUntilComplete(
        jobId: String,
        pollIntervalMs: Long = 5000L,
        timeoutMs: Long = 600_000L,
        options: RequestOptions? = null
    ): DocumentJobLiveStatusResponse {
        return poller.waitUntilComplete(
            jobId = jobId,
            pollIntervalMs = pollIntervalMs,
            timeoutMs = timeoutMs,
            fetchStatus = { getLiveStatus(it, options) },
            isTerminal = {
                val state = it.jobState ?: ""
                state.equals("Completed", ignoreCase = true) ||
                        state.equals("PartiallyCompleted", ignoreCase = true) ||
                        state.equals("Failed", ignoreCase = true)
            },
            isFailed = {
                val state = it.jobState ?: ""
                state.equals("Failed", ignoreCase = true)
            }
        )
    }
}
