package ai.sarvam.resources

import ai.sarvam.core.RequestOptions
import ai.sarvam.core.SarvamClientConfig
import ai.sarvam.core.auth.SarvamCredentials
import ai.sarvam.core.http.HttpBody
import ai.sarvam.core.http.HttpRequest
import ai.sarvam.generated.OperationKind
import ai.sarvam.models.TextToSpeechRequest
import ai.sarvam.models.TextToSpeechResponse
import ai.sarvam.models.TtsStreamingConfig
import ai.sarvam.session.TtsStreamingSession
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.flow

public class TextToSpeechResource(private val config: SarvamClientConfig) {

    public suspend fun convert(
        request: TextToSpeechRequest,
        options: RequestOptions? = null
    ): TextToSpeechResponse {
        val jsonPayload = config.json.encodeToString(TextToSpeechRequest.serializer(), request)
        var httpRequest = HttpRequest(
            method = "POST",
            url = "${config.environment.apiBaseUrl}/text-to-speech",
            body = HttpBody.Json(jsonPayload),
            operationKind = OperationKind.STATELESS_POST,
            timeoutMillis = options?.timeoutMillis
        )
        if (options != null) {
            httpRequest = httpRequest.withHeaders(options.headers)
        }

        val response = config.execute(httpRequest)
        val bodyString = response.bodyAsString()
        return config.json.decodeFromString(TextToSpeechResponse.serializer(), bodyString)
    }

    public fun stream(
        request: TextToSpeechRequest,
        options: RequestOptions? = null
    ): Flow<ByteArray> = flow {
        val jsonPayload = config.json.encodeToString(TextToSpeechRequest.serializer(), request)
        var httpRequest = HttpRequest(
            method = "POST",
            url = "${config.environment.apiBaseUrl}/text-to-speech/stream",
            body = HttpBody.Json(jsonPayload),
            operationKind = OperationKind.STATELESS_POST,
            timeoutMillis = options?.timeoutMillis,
            isStreaming = true
        )
        if (options != null) {
            httpRequest = httpRequest.withHeaders(options.headers)
        }

        val response = config.execute(httpRequest)
        response.bodyByteStream().collect { chunk ->
            emit(chunk)
        }
    }

    public suspend fun connect(
        streamingConfig: TtsStreamingConfig = TtsStreamingConfig(),
        options: RequestOptions? = null
    ): TtsStreamingSession {
        val fullUrl = "${config.environment.wsBaseUrl}/text-to-speech/ws?model=${streamingConfig.model.value}&send_completion_event=true"
        val credentials = config.authProvider.getCredentials()
        val headers = mutableMapOf<String, String>()

        when (credentials) {
            is SarvamCredentials.SubscriptionKey -> headers["Api-Subscription-Key"] = credentials.key
            is SarvamCredentials.BearerToken -> headers["Authorization"] = "Bearer ${credentials.token}"
            is SarvamCredentials.CustomHeaders -> headers.putAll(credentials.headers)
        }

        if (options != null) {
            headers.putAll(options.headers)
        }

        val wsSession = config.webSocketFactory.connect(fullUrl, headers)
        val session = TtsStreamingSession(wsSession, streamingConfig)
        session.initialize()
        return session
    }
}
