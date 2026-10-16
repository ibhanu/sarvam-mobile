package ai.sarvam.core.ws

import ai.sarvam.core.error.SarvamException
import kotlinx.coroutines.CompletableDeferred
import kotlinx.coroutines.channels.Channel
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.receiveAsFlow
import okhttp3.OkHttpClient
import okhttp3.Request
import okhttp3.Response
import okhttp3.WebSocket
import okhttp3.WebSocketListener
import okio.ByteString

public class OkHttpWebSocketFactory(
    private val client: OkHttpClient = OkHttpClient()
) : WebSocketFactory {

    override suspend fun connect(
        url: String,
        headers: Map<String, String>,
        subprotocols: List<String>
    ): WebSocketSession {
        val requestBuilder = Request.Builder().url(url)

        for ((k, v) in headers) {
            requestBuilder.addHeader(k, v)
        }

        if (subprotocols.isNotEmpty()) {
            requestBuilder.addHeader("Sec-WebSocket-Protocol", subprotocols.joinToString(", "))
        }

        val request = requestBuilder.build()
        val channel = Channel<WebSocketFrame>(Channel.BUFFERED)
        val sessionDeferred = CompletableDeferred<WebSocketSession>()

        val listener = object : WebSocketListener() {
            private var currentWebSocket: WebSocket? = null

            override fun onOpen(webSocket: WebSocket, response: Response) {
                currentWebSocket = webSocket
                val session = OkHttpWebSocketSession(webSocket, channel)
                sessionDeferred.complete(session)
            }

            override fun onMessage(webSocket: WebSocket, text: String) {
                channel.trySend(WebSocketFrame.Text(text))
            }

            override fun onMessage(webSocket: WebSocket, bytes: ByteString) {
                channel.trySend(WebSocketFrame.Binary(bytes.toByteArray()))
            }

            override fun onClosing(webSocket: WebSocket, code: Int, reason: String) {
                channel.trySend(WebSocketFrame.Closing(code, reason))
            }

            override fun onClosed(webSocket: WebSocket, code: Int, reason: String) {
                channel.trySend(WebSocketFrame.Closed(code, reason))
                channel.close()
            }

            override fun onFailure(webSocket: WebSocket, t: Throwable, response: Response?) {
                if (!sessionDeferred.isCompleted) {
                    val message = response?.let { "HTTP ${it.code}: ${t.message}" } ?: (t.message ?: "WebSocket handshake failure")
                    sessionDeferred.completeExceptionally(
                        SarvamException.RealtimeException(
                            closeCode = response?.code,
                            code = "handshake_failure",
                            message = message
                        )
                    )
                } else {
                    channel.trySend(WebSocketFrame.Failure(t))
                }
                channel.close(t)
            }
        }

        client.newWebSocket(request, listener)
        return sessionDeferred.await()
    }

    private class OkHttpWebSocketSession(
        private val webSocket: WebSocket,
        private val channel: Channel<WebSocketFrame>
    ) : WebSocketSession {

        override suspend fun send(text: String) {
            val sent = webSocket.send(text)
            if (!sent) {
                throw SarvamException.RealtimeException(
                    closeCode = null,
                    code = "send_failed",
                    message = "Failed to queue outgoing text frame"
                )
            }
        }

        override suspend fun send(bytes: ByteArray) {
            val sent = webSocket.send(ByteString.of(*bytes))
            if (!sent) {
                throw SarvamException.RealtimeException(
                    closeCode = null,
                    code = "send_failed",
                    message = "Failed to queue outgoing binary frame"
                )
            }
        }

        override fun close(code: Int, reason: String?) {
            webSocket.close(code, reason)
            channel.close()
        }

        override val incoming: Flow<WebSocketFrame> = channel.receiveAsFlow()
    }
}
