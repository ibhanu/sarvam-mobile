package ai.sarvam.resources

import ai.sarvam.core.RequestOptions
import ai.sarvam.core.SarvamClientConfig
import ai.sarvam.core.http.HttpBody
import ai.sarvam.core.http.HttpRequest
import ai.sarvam.generated.LanguageCode
import ai.sarvam.generated.OperationKind
import ai.sarvam.models.TextLidRequest
import ai.sarvam.models.TextLidResponse
import ai.sarvam.models.TranslateRequest
import ai.sarvam.models.TranslateResponse
import ai.sarvam.models.TransliterateRequest
import ai.sarvam.models.TransliterateResponse

public class TextResource(private val config: SarvamClientConfig) {

    public suspend fun translate(
        request: TranslateRequest,
        options: RequestOptions? = null
    ): TranslateResponse {
        val jsonPayload = config.json.encodeToString(TranslateRequest.serializer(), request)
        var httpRequest = HttpRequest(
            method = "POST",
            url = "${config.environment.apiBaseUrl}/translate",
            body = HttpBody.Json(jsonPayload),
            operationKind = OperationKind.STATELESS_POST,
            timeoutMillis = options?.timeoutMillis
        )
        if (options != null) {
            httpRequest = httpRequest.withHeaders(options.headers)
        }

        val response = config.execute(httpRequest)
        val bodyString = response.bodyAsString()
        return config.json.decodeFromString(TranslateResponse.serializer(), bodyString)
    }

    public suspend fun translate(
        input: String,
        targetLanguageCode: LanguageCode,
        sourceLanguageCode: LanguageCode = LanguageCode.AUTO,
        options: RequestOptions? = null
    ): TranslateResponse = translate(
        TranslateRequest(
            input = input,
            sourceLanguageCode = sourceLanguageCode,
            targetLanguageCode = targetLanguageCode
        ),
        options
    )

    public suspend fun transliterate(
        request: TransliterateRequest,
        options: RequestOptions? = null
    ): TransliterateResponse {
        val jsonPayload = config.json.encodeToString(TransliterateRequest.serializer(), request)
        var httpRequest = HttpRequest(
            method = "POST",
            url = "${config.environment.apiBaseUrl}/transliterate",
            body = HttpBody.Json(jsonPayload),
            operationKind = OperationKind.STATELESS_POST,
            timeoutMillis = options?.timeoutMillis
        )
        if (options != null) {
            httpRequest = httpRequest.withHeaders(options.headers)
        }

        val response = config.execute(httpRequest)
        val bodyString = response.bodyAsString()
        return config.json.decodeFromString(TransliterateResponse.serializer(), bodyString)
    }

    public suspend fun transliterate(
        input: String,
        sourceLanguageCode: LanguageCode,
        targetLanguageCode: LanguageCode,
        options: RequestOptions? = null
    ): TransliterateResponse = transliterate(
        TransliterateRequest(
            input = input,
            sourceLanguageCode = sourceLanguageCode,
            targetLanguageCode = targetLanguageCode
        ),
        options
    )

    public suspend fun identifyLanguage(
        request: TextLidRequest,
        options: RequestOptions? = null
    ): TextLidResponse {
        val jsonPayload = config.json.encodeToString(TextLidRequest.serializer(), request)
        var httpRequest = HttpRequest(
            method = "POST",
            url = "${config.environment.apiBaseUrl}/text-lid",
            body = HttpBody.Json(jsonPayload),
            operationKind = OperationKind.STATELESS_POST,
            timeoutMillis = options?.timeoutMillis
        )
        if (options != null) {
            httpRequest = httpRequest.withHeaders(options.headers)
        }

        val response = config.execute(httpRequest)
        val bodyString = response.bodyAsString()
        return config.json.decodeFromString(TextLidResponse.serializer(), bodyString)
    }

    public suspend fun identifyLanguage(
        input: String,
        options: RequestOptions? = null
    ): TextLidResponse = identifyLanguage(TextLidRequest(input), options)
}
