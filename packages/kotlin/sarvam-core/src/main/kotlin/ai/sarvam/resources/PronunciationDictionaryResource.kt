package ai.sarvam.resources

import ai.sarvam.core.RequestOptions
import ai.sarvam.core.SarvamClientConfig
import ai.sarvam.core.http.HttpBody
import ai.sarvam.core.http.HttpRequest
import ai.sarvam.core.http.MultipartPart
import ai.sarvam.core.io.FileInput
import ai.sarvam.generated.OperationKind
import ai.sarvam.models.PronunciationDictionaryCreateResponse
import ai.sarvam.models.PronunciationDictionaryData
import ai.sarvam.models.PronunciationDictionaryDeleteResponse
import ai.sarvam.models.PronunciationDictionaryListResponse
import ai.sarvam.models.PronunciationDictionaryUpdateResponse
import java.net.URLEncoder
import java.nio.charset.StandardCharsets

public class PronunciationDictionaryResource(private val config: SarvamClientConfig) {

    public suspend fun list(options: RequestOptions? = null): PronunciationDictionaryListResponse {
        var httpRequest = HttpRequest(
            method = "GET",
            url = "${config.environment.apiBaseUrl}/text-to-speech/pronunciation-dictionary",
            operationKind = OperationKind.IDEMPOTENT,
            timeoutMillis = options?.timeoutMillis
        )
        if (options != null) {
            httpRequest = httpRequest.withHeaders(options.headers)
        }

        val response = config.execute(httpRequest)
        return config.json.decodeFromString(PronunciationDictionaryListResponse.serializer(), response.bodyAsString())
    }

    public suspend fun create(
        file: FileInput,
        options: RequestOptions? = null
    ): PronunciationDictionaryCreateResponse {
        val parts = listOf<MultipartPart>(
            MultipartPart.FilePart("file", file)
        )
        var httpRequest = HttpRequest(
            method = "POST",
            url = "${config.environment.apiBaseUrl}/text-to-speech/pronunciation-dictionary",
            body = HttpBody.Multipart(parts),
            operationKind = OperationKind.MULTIPART_COMPUTE,
            timeoutMillis = options?.timeoutMillis
        )
        if (options != null) {
            httpRequest = httpRequest.withHeaders(options.headers)
        }

        val response = config.execute(httpRequest)
        return config.json.decodeFromString(PronunciationDictionaryCreateResponse.serializer(), response.bodyAsString())
    }

    public suspend fun update(
        dictId: String,
        file: FileInput,
        options: RequestOptions? = null
    ): PronunciationDictionaryUpdateResponse {
        val encodedId = URLEncoder.encode(dictId, StandardCharsets.UTF_8)
        val parts = listOf<MultipartPart>(
            MultipartPart.FilePart("file", file)
        )
        var httpRequest = HttpRequest(
            method = "PUT",
            url = "${config.environment.apiBaseUrl}/text-to-speech/pronunciation-dictionary?dict_id=$encodedId",
            body = HttpBody.Multipart(parts),
            operationKind = OperationKind.IDEMPOTENT,
            timeoutMillis = options?.timeoutMillis
        )
        if (options != null) {
            httpRequest = httpRequest.withHeaders(options.headers)
        }

        val response = config.execute(httpRequest)
        return config.json.decodeFromString(PronunciationDictionaryUpdateResponse.serializer(), response.bodyAsString())
    }

    public suspend fun get(
        dictId: String,
        options: RequestOptions? = null
    ): PronunciationDictionaryData {
        val encodedId = URLEncoder.encode(dictId, StandardCharsets.UTF_8)
        var httpRequest = HttpRequest(
            method = "GET",
            url = "${config.environment.apiBaseUrl}/text-to-speech/pronunciation-dictionary/$encodedId",
            operationKind = OperationKind.IDEMPOTENT,
            timeoutMillis = options?.timeoutMillis
        )
        if (options != null) {
            httpRequest = httpRequest.withHeaders(options.headers)
        }

        val response = config.execute(httpRequest)
        return config.json.decodeFromString(PronunciationDictionaryData.serializer(), response.bodyAsString())
    }

    public suspend fun delete(
        dictId: String,
        options: RequestOptions? = null
    ): PronunciationDictionaryDeleteResponse {
        val encodedId = URLEncoder.encode(dictId, StandardCharsets.UTF_8)
        var httpRequest = HttpRequest(
            method = "DELETE",
            url = "${config.environment.apiBaseUrl}/text-to-speech/pronunciation-dictionary?dict_id=$encodedId",
            operationKind = OperationKind.IDEMPOTENT,
            timeoutMillis = options?.timeoutMillis
        )
        if (options != null) {
            httpRequest = httpRequest.withHeaders(options.headers)
        }

        val response = config.execute(httpRequest)
        return config.json.decodeFromString(PronunciationDictionaryDeleteResponse.serializer(), response.bodyAsString())
    }
}
