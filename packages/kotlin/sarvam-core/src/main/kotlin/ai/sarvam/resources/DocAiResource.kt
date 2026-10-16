package ai.sarvam.resources

import ai.sarvam.core.RequestOptions
import ai.sarvam.core.SarvamClientConfig
import ai.sarvam.core.http.HttpBody
import ai.sarvam.core.http.HttpRequest
import ai.sarvam.core.http.MultipartPart
import ai.sarvam.core.io.FileInput
import ai.sarvam.generated.OperationKind
import ai.sarvam.models.DocAIDownloadURLResponse
import ai.sarvam.models.DocAIJobStatusResponse
import ai.sarvam.models.DocAIPresignUploadRequest
import ai.sarvam.models.DocAIPresignUploadResponse
import ai.sarvam.models.DocAIStartJobResponse
import kotlinx.serialization.json.JsonArray
import kotlinx.serialization.json.JsonElement
import kotlinx.serialization.json.JsonNull
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import java.net.URLEncoder
import java.nio.charset.StandardCharsets

public class DocAiResource(
    private val config: SarvamClientConfig,
    private val poller: JobPoller = JobPoller(config.clock)
) {

    public suspend fun digitise(
        files: List<FileInput>,
        uploadIds: List<String>? = null,
        language: String? = null,
        contentType: String? = null,
        model: String? = null,
        options: RequestOptions? = null
    ): DocAIStartJobResponse {
        val parts = mutableListOf<MultipartPart>()
        for (file in files) {
            parts.add(MultipartPart.FilePart("file", file))
        }
        uploadIds?.forEach { parts.add(MultipartPart.FormParam("upload_ids", it)) }
        language?.let { parts.add(MultipartPart.FormParam("language", it)) }
        contentType?.let { parts.add(MultipartPart.FormParam("content_type", it)) }
        model?.let { parts.add(MultipartPart.FormParam("model", it)) }

        var httpRequest = HttpRequest(
            method = "POST",
            url = "${config.environment.apiBaseUrl}/doc-ai/v1/job/digitise",
            body = HttpBody.Multipart(parts),
            operationKind = OperationKind.JOB_CREATE,
            timeoutMillis = options?.timeoutMillis
        )
        if (options != null) {
            httpRequest = httpRequest.withHeaders(options.headers)
        }

        val response = config.execute(httpRequest)
        return config.json.decodeFromString(DocAIStartJobResponse.serializer(), response.bodyAsString())
    }

    public suspend fun digitise(
        file: FileInput,
        uploadIds: List<String>? = null,
        language: String? = null,
        contentType: String? = null,
        model: String? = null,
        options: RequestOptions? = null
    ): DocAIStartJobResponse = digitise(
        files = listOf(file),
        uploadIds = uploadIds,
        language = language,
        contentType = contentType,
        model = model,
        options = options
    )

    public suspend fun extract(
        files: List<FileInput>,
        schema: Any,
        uploadIds: List<String>? = null,
        configId: String? = null,
        outputFormat: String? = null,
        classification: String? = null,
        model: String? = null,
        options: RequestOptions? = null
    ): DocAIStartJobResponse {
        val parts = mutableListOf<MultipartPart>()
        for (file in files) {
            parts.add(MultipartPart.FilePart("file", file))
        }
        uploadIds?.forEach { parts.add(MultipartPart.FormParam("upload_ids", it)) }

        val serializedSchema = serializeSchema(schema)
        parts.add(MultipartPart.FormParam("schema", serializedSchema))

        configId?.let { parts.add(MultipartPart.FormParam("config_id", it)) }
        outputFormat?.let { parts.add(MultipartPart.FormParam("output_format", it)) }
        classification?.let { parts.add(MultipartPart.FormParam("classification", it)) }
        model?.let { parts.add(MultipartPart.FormParam("model", it)) }

        var httpRequest = HttpRequest(
            method = "POST",
            url = "${config.environment.apiBaseUrl}/doc-ai/v1/job/extract",
            body = HttpBody.Multipart(parts),
            operationKind = OperationKind.JOB_CREATE,
            timeoutMillis = options?.timeoutMillis
        )
        if (options != null) {
            httpRequest = httpRequest.withHeaders(options.headers)
        }

        val response = config.execute(httpRequest)
        return config.json.decodeFromString(DocAIStartJobResponse.serializer(), response.bodyAsString())
    }

    public suspend fun extract(
        file: FileInput,
        schema: Any,
        uploadIds: List<String>? = null,
        configId: String? = null,
        outputFormat: String? = null,
        classification: String? = null,
        model: String? = null,
        options: RequestOptions? = null
    ): DocAIStartJobResponse = extract(
        files = listOf(file),
        schema = schema,
        uploadIds = uploadIds,
        configId = configId,
        outputFormat = outputFormat,
        classification = classification,
        model = model,
        options = options
    )

    public suspend fun createUploadUrl(
        contentType: String? = null,
        options: RequestOptions? = null
    ): DocAIPresignUploadResponse {
        val payload = config.json.encodeToString(
            DocAIPresignUploadRequest.serializer(),
            DocAIPresignUploadRequest(contentType = contentType)
        )
        var httpRequest = HttpRequest(
            method = "POST",
            url = "${config.environment.apiBaseUrl}/doc-ai/v1/job/upload",
            body = HttpBody.Json(payload),
            operationKind = OperationKind.STATELESS_POST,
            timeoutMillis = options?.timeoutMillis
        )
        if (options != null) {
            httpRequest = httpRequest.withHeaders(options.headers)
        }

        val response = config.execute(httpRequest)
        return config.json.decodeFromString(DocAIPresignUploadResponse.serializer(), response.bodyAsString())
    }

    public suspend fun getStatus(
        jobId: String,
        options: RequestOptions? = null
    ): DocAIJobStatusResponse {
        val encodedId = URLEncoder.encode(jobId, StandardCharsets.UTF_8)
        var httpRequest = HttpRequest(
            method = "GET",
            url = "${config.environment.apiBaseUrl}/doc-ai/v1/job/$encodedId/status",
            operationKind = OperationKind.IDEMPOTENT,
            timeoutMillis = options?.timeoutMillis
        )
        if (options != null) {
            httpRequest = httpRequest.withHeaders(options.headers)
        }

        val response = config.execute(httpRequest)
        return config.json.decodeFromString(DocAIJobStatusResponse.serializer(), response.bodyAsString())
    }

    public suspend fun getResults(
        jobId: String,
        format: String? = null,
        options: RequestOptions? = null
    ): String {
        val encodedId = URLEncoder.encode(jobId, StandardCharsets.UTF_8)
        val queryString = if (format != null) "?format=${URLEncoder.encode(format, StandardCharsets.UTF_8)}" else ""
        var httpRequest = HttpRequest(
            method = "GET",
            url = "${config.environment.apiBaseUrl}/doc-ai/v1/job/$encodedId/results$queryString",
            operationKind = OperationKind.IDEMPOTENT,
            timeoutMillis = options?.timeoutMillis
        )
        if (options != null) {
            httpRequest = httpRequest.withHeaders(options.headers)
        }

        val response = config.execute(httpRequest)
        return response.bodyAsString()
    }

    public suspend fun getDownloadUrl(
        jobId: String,
        options: RequestOptions? = null
    ): DocAIDownloadURLResponse {
        val encodedId = URLEncoder.encode(jobId, StandardCharsets.UTF_8)
        var httpRequest = HttpRequest(
            method = "GET",
            url = "${config.environment.apiBaseUrl}/doc-ai/v1/job/$encodedId/download-url",
            operationKind = OperationKind.IDEMPOTENT,
            timeoutMillis = options?.timeoutMillis
        )
        if (options != null) {
            httpRequest = httpRequest.withHeaders(options.headers)
        }

        val response = config.execute(httpRequest)
        return config.json.decodeFromString(DocAIDownloadURLResponse.serializer(), response.bodyAsString())
    }

    public suspend fun digitiseAndWait(
        jobId: String,
        pollIntervalMs: Long = 5000L,
        timeoutMs: Long = 600_000L,
        options: RequestOptions? = null
    ): DocAIJobStatusResponse {
        return poller.waitUntilComplete(
            jobId = jobId,
            pollIntervalMs = pollIntervalMs,
            timeoutMs = timeoutMs,
            fetchStatus = { getStatus(it, options) },
            isTerminal = { it.isTerminal }
        )
    }

    public suspend fun digitiseAndWait(
        files: List<FileInput>,
        uploadIds: List<String>? = null,
        language: String? = null,
        contentType: String? = null,
        model: String? = null,
        pollIntervalMs: Long = 5000L,
        timeoutMs: Long = 600_000L,
        options: RequestOptions? = null
    ): DocAIJobStatusResponse {
        val startResponse = digitise(
            files = files,
            uploadIds = uploadIds,
            language = language,
            contentType = contentType,
            model = model,
            options = options
        )
        return digitiseAndWait(
            jobId = startResponse.jobId,
            pollIntervalMs = pollIntervalMs,
            timeoutMs = timeoutMs,
            options = options
        )
    }

    public suspend fun digitiseAndWait(
        file: FileInput,
        uploadIds: List<String>? = null,
        language: String? = null,
        contentType: String? = null,
        model: String? = null,
        pollIntervalMs: Long = 5000L,
        timeoutMs: Long = 600_000L,
        options: RequestOptions? = null
    ): DocAIJobStatusResponse = digitiseAndWait(
        files = listOf(file),
        uploadIds = uploadIds,
        language = language,
        contentType = contentType,
        model = model,
        pollIntervalMs = pollIntervalMs,
        timeoutMs = timeoutMs,
        options = options
    )

    public suspend fun extractAndWait(
        jobId: String,
        pollIntervalMs: Long = 5000L,
        timeoutMs: Long = 600_000L,
        options: RequestOptions? = null
    ): DocAIJobStatusResponse {
        return poller.waitUntilComplete(
            jobId = jobId,
            pollIntervalMs = pollIntervalMs,
            timeoutMs = timeoutMs,
            fetchStatus = { getStatus(it, options) },
            isTerminal = { it.isTerminal }
        )
    }

    public suspend fun extractAndWait(
        files: List<FileInput>,
        schema: Any,
        uploadIds: List<String>? = null,
        configId: String? = null,
        outputFormat: String? = null,
        classification: String? = null,
        model: String? = null,
        pollIntervalMs: Long = 5000L,
        timeoutMs: Long = 600_000L,
        options: RequestOptions? = null
    ): DocAIJobStatusResponse {
        val startResponse = extract(
            files = files,
            schema = schema,
            uploadIds = uploadIds,
            configId = configId,
            outputFormat = outputFormat,
            classification = classification,
            model = model,
            options = options
        )
        return extractAndWait(
            jobId = startResponse.jobId,
            pollIntervalMs = pollIntervalMs,
            timeoutMs = timeoutMs,
            options = options
        )
    }

    public suspend fun extractAndWait(
        file: FileInput,
        schema: Any,
        uploadIds: List<String>? = null,
        configId: String? = null,
        outputFormat: String? = null,
        classification: String? = null,
        model: String? = null,
        pollIntervalMs: Long = 5000L,
        timeoutMs: Long = 600_000L,
        options: RequestOptions? = null
    ): DocAIJobStatusResponse = extractAndWait(
        files = listOf(file),
        schema = schema,
        uploadIds = uploadIds,
        configId = configId,
        outputFormat = outputFormat,
        classification = classification,
        model = model,
        pollIntervalMs = pollIntervalMs,
        timeoutMs = timeoutMs,
        options = options
    )

    private fun serializeSchema(schema: Any): String {
        return when (schema) {
            is String -> schema
            is JsonElement -> schema.toString()
            is Map<*, *> -> convertMapToJsonElement(schema).toString()
            else -> schema.toString()
        }
    }

    private fun convertMapToJsonElement(map: Map<*, *>): JsonElement {
        val content = mutableMapOf<String, JsonElement>()
        for ((key, value) in map) {
            val keyStr = key?.toString() ?: continue
            content[keyStr] = convertValueToJsonElement(value)
        }
        return JsonObject(content)
    }

    private fun convertValueToJsonElement(value: Any?): JsonElement {
        return when (value) {
            null -> JsonNull
            is JsonElement -> value
            is Boolean -> JsonPrimitive(value)
            is Number -> JsonPrimitive(value)
            is String -> JsonPrimitive(value)
            is Map<*, *> -> convertMapToJsonElement(value)
            is Iterable<*> -> JsonArray(value.map { convertValueToJsonElement(it) })
            is Array<*> -> JsonArray(value.map { convertValueToJsonElement(it) })
            else -> JsonPrimitive(value.toString())
        }
    }
}
