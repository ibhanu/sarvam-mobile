package ai.sarvam.resources

import ai.sarvam.core.RequestOptions
import ai.sarvam.core.SarvamClientConfig
import ai.sarvam.core.http.HttpBody
import ai.sarvam.core.http.HttpRequest
import ai.sarvam.core.io.FileInput
import ai.sarvam.generated.OperationKind

public class JobsResource(private val config: SarvamClientConfig) {

    public suspend fun uploadToSignedUrl(
        uploadUrl: String,
        fileInput: FileInput,
        options: RequestOptions? = null
    ) {
        val bytes = fileInput.readBytes()
        var httpRequest = HttpRequest(
            method = "PUT",
            url = uploadUrl,
            body = HttpBody.Binary(bytes, fileInput.mimeType),
            operationKind = OperationKind.IDEMPOTENT,
            timeoutMillis = options?.timeoutMillis
        )
            .withHeader("x-ms-blob-type", "BlockBlob")
            .withHeader("Content-Type", fileInput.mimeType)

        if (options != null) {
            httpRequest = httpRequest.withHeaders(options.headers)
        }

        config.execute(httpRequest)
    }
}
