package ai.sarvam.core.http

import ai.sarvam.core.error.SarvamException
import ai.sarvam.core.error.TimeoutPhase
import ai.sarvam.core.util.Clock
import ai.sarvam.core.util.SystemClock
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.flow
import kotlinx.coroutines.flow.flowOn
import kotlinx.coroutines.suspendCancellableCoroutine
import kotlinx.coroutines.withContext
import okhttp3.Call
import okhttp3.Callback
import okhttp3.Headers
import okhttp3.MediaType.Companion.toMediaTypeOrNull
import okhttp3.MultipartBody
import okhttp3.OkHttpClient
import okhttp3.Request
import okhttp3.RequestBody
import okhttp3.RequestBody.Companion.toRequestBody
import okhttp3.Response
import java.io.IOException
import java.io.InterruptedIOException
import java.net.SocketTimeoutException
import java.util.concurrent.TimeUnit
import kotlin.coroutines.resume
import kotlin.coroutines.resumeWithException

public class OkHttpTransport(
    private val client: OkHttpClient = OkHttpClient.Builder()
        .connectTimeout(10, TimeUnit.SECONDS)
        .readTimeout(30, TimeUnit.SECONDS)
        .writeTimeout(30, TimeUnit.SECONDS)
        .callTimeout(60, TimeUnit.SECONDS)
        .build(),
    private val clock: Clock = SystemClock
) : HttpTransport {

    override suspend fun execute(request: HttpRequest): HttpResponse = withContext(Dispatchers.IO) {
        val okRequest = buildOkHttpRequest(request)
        val activeClient = if (request.timeoutMillis != null) {
            client.newBuilder()
                .callTimeout(request.timeoutMillis, TimeUnit.MILLISECONDS)
                .readTimeout(request.timeoutMillis, TimeUnit.MILLISECONDS)
                .build()
        } else {
            client
        }

        val call = activeClient.newCall(okRequest)
        val response = try {
            suspendCancellableCoroutine<Response> { continuation ->
                continuation.invokeOnCancellation {
                    call.cancel()
                }
                call.enqueue(object : Callback {
                    override fun onResponse(call: Call, response: Response) {
                        continuation.resume(response)
                    }

                    override fun onFailure(call: Call, e: IOException) {
                        if (continuation.isCancelled) return
                        continuation.resumeWithException(e)
                    }
                })
            }
        } catch (e: CancellationException) {
            throw e
        } catch (e: InterruptedIOException) {
            throw SarvamException.TimeoutException(
                phase = TimeoutPhase.TOTAL,
                message = e.message ?: "Request timed out",
                cause = e
            )
        } catch (e: IOException) {
            throw SarvamException.ConnectionException(
                message = e.message ?: "Network connection error",
                cause = e
            )
        }

        val statusCode = response.code
        val headers = response.headers.toMultimap()

        if (statusCode !in 200..299) {
            val errorBody = response.body?.string() ?: ""
            response.close()
            throw SarvamException.fromHttpResponse(statusCode, headers, errorBody, clock)
        }

        OkHttpResponse(response)
    }

    private fun buildOkHttpRequest(request: HttpRequest): Request {
        val builder = Request.Builder().url(request.url)

        for ((k, values) in request.headers) {
            for (v in values) {
                builder.addHeader(k, v)
            }
        }

        val okBody = when (val body = request.body) {
            is HttpBody.Empty -> {
                if (request.method.equals("POST", ignoreCase = true) ||
                    request.method.equals("PUT", ignoreCase = true) ||
                    request.method.equals("PATCH", ignoreCase = true)
                ) {
                    ByteArray(0).toRequestBody(null, 0, 0)
                } else {
                    null
                }
            }
            is HttpBody.Json -> {
                val mediaType = "application/json; charset=utf-8".toMediaTypeOrNull()
                body.content.toRequestBody(mediaType)
            }
            is HttpBody.Binary -> {
                val mediaType = body.contentType.toMediaTypeOrNull()
                body.bytes.toRequestBody(mediaType)
            }
            is HttpBody.Multipart -> {
                val multipartBuilder = MultipartBody.Builder().setType(MultipartBody.FORM)
                for (part in body.parts) {
                    when (part) {
                        is MultipartPart.FormParam -> {
                            multipartBuilder.addFormDataPart(part.name, part.value)
                        }
                        is MultipartPart.FilePart -> {
                            val mediaType = part.file.mimeType.toMediaTypeOrNull()
                            val bytes = part.file.readBytes()
                            val fileBody = bytes.toRequestBody(mediaType)
                            multipartBuilder.addFormDataPart(part.name, part.file.filename, fileBody)
                        }
                    }
                }
                multipartBuilder.build()
            }
        }

        builder.method(request.method, okBody)
        return builder.build()
    }

    private class OkHttpResponse(private val response: Response) : HttpResponse {
        override val statusCode: Int = response.code
        override val headers: Map<String, List<String>> = response.headers.toMultimap()

        override suspend fun bodyAsString(): String = withContext(Dispatchers.IO) {
            response.body?.string() ?: ""
        }

        override suspend fun bodyAsBytes(): ByteArray = withContext(Dispatchers.IO) {
            response.body?.bytes() ?: ByteArray(0)
        }

        override fun bodyByteStream(): Flow<ByteArray> = flow {
            val source = response.body?.source() ?: return@flow
            val buffer = ByteArray(8192)
            try {
                while (!source.exhausted()) {
                    val read = source.read(buffer)
                    if (read == -1) break
                    emit(buffer.copyOf(read))
                }
            } finally {
                response.close()
            }
        }.flowOn(Dispatchers.IO)

        override fun close() {
            response.close()
        }
    }
}
