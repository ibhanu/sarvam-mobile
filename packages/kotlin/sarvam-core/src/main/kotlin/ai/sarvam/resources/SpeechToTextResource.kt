package ai.sarvam.resources

import ai.sarvam.core.RequestOptions
import ai.sarvam.core.SarvamClientConfig
import ai.sarvam.core.auth.SarvamCredentials
import ai.sarvam.core.error.SarvamException
import ai.sarvam.core.http.HttpBody
import ai.sarvam.core.http.HttpRequest
import ai.sarvam.core.http.MultipartPart
import ai.sarvam.core.io.FileInput
import ai.sarvam.generated.LanguageCode
import ai.sarvam.generated.OperationKind
import ai.sarvam.generated.SttModel
import ai.sarvam.models.SpeechToTextResponse
import ai.sarvam.models.SttRealtimeConfig
import ai.sarvam.session.SttRealtimeSession
import java.net.URLEncoder
import java.nio.charset.StandardCharsets

public class SpeechToTextResource(private val config: SarvamClientConfig) {

    public suspend fun transcribe(
        file: FileInput,
        model: SttModel? = null,
        languageCode: LanguageCode? = null,
        prompt: String? = null,
        withDiarization: Boolean? = null,
        withTimestamps: Boolean? = null,
        options: RequestOptions? = null
    ): SpeechToTextResponse {
        val parts = mutableListOf<MultipartPart>(
            MultipartPart.FilePart("file", file)
        )
        model?.let { parts.add(MultipartPart.FormParam("model", it.value)) }
        languageCode?.let { parts.add(MultipartPart.FormParam("language_code", it.value)) }
        prompt?.let { parts.add(MultipartPart.FormParam("prompt", it)) }
        withDiarization?.let { parts.add(MultipartPart.FormParam("with_diarization", it.toString())) }
        withTimestamps?.let { parts.add(MultipartPart.FormParam("with_timestamps", it.toString())) }

        var httpRequest = HttpRequest(
            method = "POST",
            url = "${config.environment.apiBaseUrl}/speech-to-text",
            body = HttpBody.Multipart(parts),
            operationKind = OperationKind.MULTIPART_COMPUTE,
            timeoutMillis = options?.timeoutMillis
        )
        if (options != null) {
            httpRequest = httpRequest.withHeaders(options.headers)
        }

        val response = config.execute(httpRequest)
        val bodyString = response.bodyAsString()
        return config.json.decodeFromString(SpeechToTextResponse.serializer(), bodyString)
    }

    public suspend fun translate(
        file: FileInput,
        model: SttModel? = null,
        prompt: String? = null,
        options: RequestOptions? = null
    ): SpeechToTextResponse {
        val parts = mutableListOf<MultipartPart>(
            MultipartPart.FilePart("file", file)
        )
        model?.let { parts.add(MultipartPart.FormParam("model", it.value)) }
        prompt?.let { parts.add(MultipartPart.FormParam("prompt", it)) }

        var httpRequest = HttpRequest(
            method = "POST",
            url = "${config.environment.apiBaseUrl}/speech-to-text-translate",
            body = HttpBody.Multipart(parts),
            operationKind = OperationKind.MULTIPART_COMPUTE,
            timeoutMillis = options?.timeoutMillis
        )
        if (options != null) {
            httpRequest = httpRequest.withHeaders(options.headers)
        }

        val response = config.execute(httpRequest)
        val bodyString = response.bodyAsString()
        return config.json.decodeFromString(SpeechToTextResponse.serializer(), bodyString)
    }

    public suspend fun connect(
        realtimeConfig: SttRealtimeConfig = SttRealtimeConfig(),
        options: RequestOptions? = null
    ): SttRealtimeSession {
        // Client-side validation for sample rate
        if (realtimeConfig.sampleRate != 16000 && realtimeConfig.sampleRate != 8000) {
            throw SarvamException.BadRequestException(
                statusCode = 400,
                code = "invalid_sample_rate",
                requestId = null,
                message = "sampleRate must be 16000 or 8000"
            )
        }

        val queryParams = mutableListOf<Pair<String, String>>()
        queryParams.add("language_code" to realtimeConfig.languageCode.value)
        queryParams.add("model" to realtimeConfig.model.value)
        queryParams.add("sample_rate" to realtimeConfig.sampleRate.toString())
        realtimeConfig.streamType?.let { queryParams.add("stream_type" to it) }
        realtimeConfig.mode?.let { queryParams.add("mode" to it.value) }
        realtimeConfig.encoding?.let { queryParams.add("encoding" to it) }
        realtimeConfig.returnTimestamps?.let { queryParams.add("return_timestamps" to it.toString()) }
        realtimeConfig.endpointing?.let { queryParams.add("endpointing" to it.toString()) }
        realtimeConfig.threshold?.let { queryParams.add("threshold" to it.toString()) }
        realtimeConfig.prefixPaddingMs?.let { queryParams.add("prefix_padding_ms" to it.toString()) }
        realtimeConfig.silenceDurationMs?.let { queryParams.add("silence_duration_ms" to it.toString()) }
        realtimeConfig.minSpeechDurationMs?.let { queryParams.add("min_speech_duration_ms" to it.toString()) }
        realtimeConfig.prompt?.let { queryParams.add("prompt" to it) }
        realtimeConfig.keyterms?.let { queryParams.add("keyterms" to it.joinToString(",")) }

        val queryString = queryParams.joinToString("&") { (k, v) ->
            "$k=${URLEncoder.encode(v, StandardCharsets.UTF_8)}"
        }
        val fullUrl = "${config.environment.wsBaseUrl}/speech-to-text-realtime/ws?$queryString"

        val credentials = config.authProvider.getCredentials()
        val headers = mutableMapOf<String, String>()
        val subprotocols = mutableListOf<String>()

        if (realtimeConfig.useSubprotocolAuth) {
            when (credentials) {
                is SarvamCredentials.SubscriptionKey -> subprotocols.add("api-subscription-key.${credentials.key}")
                is SarvamCredentials.BearerToken -> subprotocols.add("bearer.${credentials.token}")
                is SarvamCredentials.CustomHeaders -> headers.putAll(credentials.headers)
            }
        } else {
            when (credentials) {
                is SarvamCredentials.SubscriptionKey -> headers["Api-Subscription-Key"] = credentials.key
                is SarvamCredentials.BearerToken -> headers["Authorization"] = "Bearer ${credentials.token}"
                is SarvamCredentials.CustomHeaders -> headers.putAll(credentials.headers)
            }
        }

        if (options != null) {
            headers.putAll(options.headers)
        }

        val session = config.webSocketFactory.connect(fullUrl, headers, subprotocols)
        return SttRealtimeSession(session)
    }
}
