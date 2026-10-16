package ai.sarvam.resources

import ai.sarvam.core.RequestOptions
import ai.sarvam.core.SarvamClientConfig
import ai.sarvam.core.auth.SarvamCredentials
import ai.sarvam.core.http.HttpBody
import ai.sarvam.core.http.HttpRequest
import ai.sarvam.core.http.MultipartPart
import ai.sarvam.core.io.FileInput
import ai.sarvam.generated.OperationKind
import ai.sarvam.models.TtsStreamingConfig
import ai.sarvam.models.VoiceCloneRequest
import ai.sarvam.models.VoiceCloneResponse
import ai.sarvam.models.VoiceLibraryCreateResponse
import ai.sarvam.models.VoiceLibraryDetailResponse
import ai.sarvam.models.VoiceLibraryListResponse
import ai.sarvam.session.TtsStreamingSession
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.flow
import java.net.URLEncoder
import java.nio.charset.StandardCharsets

public class VoiceCloningResource(private val config: SarvamClientConfig) {

    public suspend fun listVoices(
        search: String? = null,
        gender: String? = null,
        accent: String? = null,
        limit: Int? = null,
        offset: Int? = null,
        options: RequestOptions? = null
    ): VoiceLibraryListResponse {
        val queryParams = mutableListOf<Pair<String, String>>()
        search?.let { queryParams.add("search" to it) }
        gender?.let { queryParams.add("gender" to it) }
        accent?.let { queryParams.add("accent" to it) }
        limit?.let { queryParams.add("limit" to it.toString()) }
        offset?.let { queryParams.add("offset" to it.toString()) }

        val queryString = if (queryParams.isNotEmpty()) {
            "?" + queryParams.joinToString("&") { (k, v) ->
                "$k=${URLEncoder.encode(v, StandardCharsets.UTF_8)}"
            }
        } else ""

        var httpRequest = HttpRequest(
            method = "GET",
            url = "${config.environment.apiBaseUrl}/voices$queryString",
            operationKind = OperationKind.IDEMPOTENT,
            timeoutMillis = options?.timeoutMillis
        )
        if (options != null) {
            httpRequest = httpRequest.withHeaders(options.headers)
        }

        val response = config.execute(httpRequest)
        return config.json.decodeFromString(VoiceLibraryListResponse.serializer(), response.bodyAsString())
    }

    public suspend fun createVoice(
        file: FileInput,
        name: String? = null,
        language: String? = null,
        style: String? = null,
        gender: String? = null,
        options: RequestOptions? = null
    ): VoiceLibraryCreateResponse {
        val parts = mutableListOf<MultipartPart>(
            MultipartPart.FilePart("file", file)
        )
        name?.let { parts.add(MultipartPart.FormParam("name", it)) }
        language?.let { parts.add(MultipartPart.FormParam("language", it)) }
        style?.let { parts.add(MultipartPart.FormParam("style", it)) }
        gender?.let { parts.add(MultipartPart.FormParam("gender", it)) }

        var httpRequest = HttpRequest(
            method = "POST",
            url = "${config.environment.apiBaseUrl}/voices/create",
            body = HttpBody.Multipart(parts),
            operationKind = OperationKind.JOB_CREATE,
            timeoutMillis = options?.timeoutMillis
        )
        if (options != null) {
            httpRequest = httpRequest.withHeaders(options.headers)
        }

        val response = config.execute(httpRequest)
        return config.json.decodeFromString(VoiceLibraryCreateResponse.serializer(), response.bodyAsString())
    }

    public suspend fun getVoice(
        voiceId: String,
        options: RequestOptions? = null
    ): VoiceLibraryDetailResponse {
        val encodedId = URLEncoder.encode(voiceId, StandardCharsets.UTF_8)
        var httpRequest = HttpRequest(
            method = "GET",
            url = "${config.environment.apiBaseUrl}/voices/$encodedId",
            operationKind = OperationKind.IDEMPOTENT,
            timeoutMillis = options?.timeoutMillis
        )
        if (options != null) {
            httpRequest = httpRequest.withHeaders(options.headers)
        }

        val response = config.execute(httpRequest)
        return config.json.decodeFromString(VoiceLibraryDetailResponse.serializer(), response.bodyAsString())
    }

    public suspend fun deleteVoice(
        voiceId: String,
        options: RequestOptions? = null
    ) {
        val encodedId = URLEncoder.encode(voiceId, StandardCharsets.UTF_8)
        var httpRequest = HttpRequest(
            method = "DELETE",
            url = "${config.environment.apiBaseUrl}/voices/delete/$encodedId",
            operationKind = OperationKind.IDEMPOTENT,
            timeoutMillis = options?.timeoutMillis
        )
        if (options != null) {
            httpRequest = httpRequest.withHeaders(options.headers)
        }

        config.execute(httpRequest)
    }

    public suspend fun convert(
        request: VoiceCloneRequest,
        options: RequestOptions? = null
    ): VoiceCloneResponse {
        val parts = buildCloneParts(request)
        var httpRequest = HttpRequest(
            method = "POST",
            url = "${config.environment.apiBaseUrl}/voices/clone",
            body = HttpBody.Multipart(parts),
            operationKind = OperationKind.MULTIPART_COMPUTE,
            timeoutMillis = options?.timeoutMillis
        )
        if (options != null) {
            httpRequest = httpRequest.withHeaders(options.headers)
        }

        val response = config.execute(httpRequest)
        return config.json.decodeFromString(VoiceCloneResponse.serializer(), response.bodyAsString())
    }

    public fun stream(
        request: VoiceCloneRequest,
        options: RequestOptions? = null
    ): Flow<ByteArray> = flow {
        val parts = buildCloneParts(request)
        var httpRequest = HttpRequest(
            method = "POST",
            url = "${config.environment.apiBaseUrl}/voices/clone/stream",
            body = HttpBody.Multipart(parts),
            operationKind = OperationKind.MULTIPART_COMPUTE,
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
        voiceId: String,
        streamingConfig: TtsStreamingConfig = TtsStreamingConfig(),
        options: RequestOptions? = null
    ): TtsStreamingSession {
        val encodedVoiceId = URLEncoder.encode(voiceId, StandardCharsets.UTF_8)
        val fullUrl = "${config.environment.wsBaseUrl}/voices/clone/ws?voice_id=$encodedVoiceId&send_completion_event=true"
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

        val resolvedConfig = streamingConfig.copy(voiceId = voiceId)
        val wsSession = config.webSocketFactory.connect(fullUrl, headers)
        val session = TtsStreamingSession(wsSession, resolvedConfig)
        session.initialize()
        return session
    }

    private fun buildCloneParts(request: VoiceCloneRequest): List<MultipartPart> {
        val parts = mutableListOf<MultipartPart>()
        parts.add(MultipartPart.FormParam("text", request.text))
        request.voiceId?.let { parts.add(MultipartPart.FormParam("voice_id", it)) }
        request.refAudio?.let { parts.add(MultipartPart.FilePart("ref_audio", it)) }
        request.refText?.let { parts.add(MultipartPart.FormParam("ref_text", it)) }
        request.languageCode?.let { parts.add(MultipartPart.FormParam("language_code", it.value)) }
        request.pace?.let { parts.add(MultipartPart.FormParam("pace", it.toString())) }
        request.outputAudioCodec?.let { parts.add(MultipartPart.FormParam("output_audio_codec", it.value)) }
        request.speechSampleRate?.let { parts.add(MultipartPart.FormParam("speech_sample_rate", it.toString())) }
        request.enableQc?.let { parts.add(MultipartPart.FormParam("enable_qc", it.toString())) }
        request.enableCachedResponses?.let { parts.add(MultipartPart.FormParam("enable_cached_responses", it.toString())) }
        request.enableVad?.let { parts.add(MultipartPart.FormParam("enable_vad", it.toString())) }
        request.enableTextNormalization?.let { parts.add(MultipartPart.FormParam("enable_text_normalization", it.toString())) }
        request.minAudioDuration?.let { parts.add(MultipartPart.FormParam("min_audio_duration", it.toString())) }
        request.maxAudioDuration?.let { parts.add(MultipartPart.FormParam("max_audio_duration", it.toString())) }
        request.refAudioDuration?.let { parts.add(MultipartPart.FormParam("ref_audio_duration", it.toString())) }
        return parts
    }
}
