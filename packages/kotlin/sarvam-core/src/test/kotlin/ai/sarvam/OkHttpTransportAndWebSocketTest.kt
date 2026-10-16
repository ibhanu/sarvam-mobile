package ai.sarvam

import ai.sarvam.core.error.SarvamException
import ai.sarvam.core.error.TimeoutPhase
import ai.sarvam.core.http.HttpBody
import ai.sarvam.core.http.HttpRequest
import ai.sarvam.core.http.MultipartPart
import ai.sarvam.core.http.OkHttpTransport
import ai.sarvam.core.io.FileInput
import ai.sarvam.core.ws.OkHttpWebSocketFactory
import ai.sarvam.core.ws.WebSocketFrame
import kotlinx.coroutines.flow.first
import kotlinx.coroutines.flow.toList
import kotlinx.coroutines.runBlocking
import kotlinx.coroutines.test.runTest
import okhttp3.OkHttpClient
import okhttp3.Response
import okhttp3.WebSocket
import okhttp3.WebSocketListener
import okhttp3.mockwebserver.MockResponse
import okhttp3.mockwebserver.MockWebServer
import okhttp3.mockwebserver.SocketPolicy
import org.junit.After
import org.junit.Assert.assertArrayEquals
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertTrue
import org.junit.Assert.fail
import org.junit.Before
import org.junit.Test
import java.util.concurrent.TimeUnit

class OkHttpTransportAndWebSocketTest {

    private lateinit var server: MockWebServer
    private lateinit var baseUrl: String
    private lateinit var transport: OkHttpTransport
    private lateinit var wsFactory: OkHttpWebSocketFactory

    @Before
    fun setUp() {
        server = MockWebServer()
        server.start()
        baseUrl = server.url("/").toString().trimEnd('/')
        transport = OkHttpTransport()
        wsFactory = OkHttpWebSocketFactory()
    }

    @After
    fun tearDown() {
        server.shutdown()
    }

    // --- OkHttpTransport Tests ---

    @Test
    fun `GET request with headers and query parameters`() = runTest {
        server.enqueue(
            MockResponse()
                .setResponseCode(200)
                .setHeader("Content-Type", "application/json")
                .setHeader("X-Custom-Header", "custom-val")
                .setBody("""{"status":"ok"}""")
        )

        val request = HttpRequest(
            method = "GET",
            url = "$baseUrl/test?param=val",
            headers = mapOf("X-Req-Header" to listOf("req-val"))
        )

        val response = transport.execute(request)
        assertEquals(200, response.statusCode)
        assertTrue(response.headers.containsKey("x-custom-header"))
        assertEquals("""{"status":"ok"}""", response.bodyAsString())

        val recorded = server.takeRequest()
        assertEquals("/test?param=val", recorded.path)
        assertEquals("GET", recorded.method)
        assertEquals("req-val", recorded.getHeader("X-Req-Header"))
    }

    @Test
    fun `POST request with JSON body`() = runTest {
        server.enqueue(MockResponse().setResponseCode(201).setBody("created"))

        val request = HttpRequest(
            method = "POST",
            url = "$baseUrl/create",
            body = HttpBody.Json("""{"name":"test"}""")
        )

        val response = transport.execute(request)
        assertEquals(201, response.statusCode)
        assertEquals("created", response.bodyAsString())

        val recorded = server.takeRequest()
        assertEquals("POST", recorded.method)
        assertEquals("application/json; charset=utf-8", recorded.getHeader("Content-Type"))
        assertEquals("""{"name":"test"}""", recorded.body.readUtf8())
    }

    @Test
    fun `POST and PUT request with Empty body`() = runTest {
        server.enqueue(MockResponse().setResponseCode(200).setBody("ok-post"))
        server.enqueue(MockResponse().setResponseCode(200).setBody("ok-put"))

        val postReq = HttpRequest(method = "POST", url = "$baseUrl/empty-post", body = HttpBody.Empty)
        val postRes = transport.execute(postReq)
        assertEquals("ok-post", postRes.bodyAsString())

        val putReq = HttpRequest(method = "PUT", url = "$baseUrl/empty-put", body = HttpBody.Empty)
        val putRes = transport.execute(putReq)
        assertEquals("ok-put", putRes.bodyAsString())

        assertEquals("POST", server.takeRequest().method)
        assertEquals("PUT", server.takeRequest().method)
    }

    @Test
    fun `POST request with Binary body and bodyAsBytes`() = runTest {
        val bytes = byteArrayOf(10, 20, 30, 40)
        server.enqueue(
            MockResponse()
                .setResponseCode(200)
                .setHeader("Content-Type", "application/octet-stream")
                .setBody(okio.Buffer().write(bytes))
        )

        val request = HttpRequest(
            method = "POST",
            url = "$baseUrl/binary",
            body = HttpBody.Binary(bytes, "application/octet-stream")
        )

        val response = transport.execute(request)
        assertEquals(200, response.statusCode)
        assertArrayEquals(bytes, response.bodyAsBytes())

        val recorded = server.takeRequest()
        assertArrayEquals(bytes, recorded.body.readByteArray())
    }

    @Test
    fun `POST request with Multipart body`() = runTest {
        server.enqueue(MockResponse().setResponseCode(200).setBody("uploaded"))

        val fileInput = FileInput.fromBytes("file content".toByteArray(), "sample.txt", "text/plain")
        val request = HttpRequest(
            method = "POST",
            url = "$baseUrl/upload",
            body = HttpBody.Multipart(
                listOf(
                    MultipartPart.FormParam("description", "A text file"),
                    MultipartPart.FilePart("file", fileInput)
                )
            )
        )

        val response = transport.execute(request)
        assertEquals("uploaded", response.bodyAsString())

        val recorded = server.takeRequest()
        assertTrue(recorded.getHeader("Content-Type")?.startsWith("multipart/form-data") == true)
        val bodyStr = recorded.body.readUtf8()
        assertTrue(bodyStr.contains("name=\"description\""))
        assertTrue(bodyStr.contains("A text file"))
        assertTrue(bodyStr.contains("filename=\"sample.txt\""))
        assertTrue(bodyStr.contains("file content"))
    }

    @Test
    fun `Streaming response bodyByteStream`() = runTest {
        val payload = "chunk1chunk2chunk3".toByteArray()
        server.enqueue(
            MockResponse()
                .setResponseCode(200)
                .setBody(okio.Buffer().write(payload))
        )

        val request = HttpRequest(method = "GET", url = "$baseUrl/stream")
        val response = transport.execute(request)

        val chunks = response.bodyByteStream().toList()
        val combined = chunks.reduce { acc, b -> acc + b }
        assertArrayEquals(payload, combined)
        response.close()
    }

    @Test
    fun `HTTP error response converts to SarvamException`() = runTest {
        server.enqueue(
            MockResponse()
                .setResponseCode(400)
                .setHeader("Content-Type", "application/json")
                .setBody("""{"error":{"code":"bad_request","message":"Missing field"}}""")
        )

        try {
            transport.execute(HttpRequest(method = "GET", url = "$baseUrl/error"))
            fail("Expected BadRequestException")
        } catch (e: SarvamException.BadRequestException) {
            assertEquals(400, e.statusCode)
            assertEquals("bad_request", e.code)
            assertTrue(e.message?.contains("Missing field") == true)
        }
    }

    @Test
    fun `Custom request timeout triggers TimeoutException`() = runTest {
        server.enqueue(
            MockResponse()
                .setHeadersDelay(1000, TimeUnit.MILLISECONDS)
                .setResponseCode(200)
                .setBody("too-late")
        )

        val request = HttpRequest(
            method = "GET",
            url = "$baseUrl/timeout",
            timeoutMillis = 50L
        )

        try {
            transport.execute(request)
            fail("Expected TimeoutException")
        } catch (e: SarvamException.TimeoutException) {
            assertEquals(TimeoutPhase.TOTAL, e.phase)
        }
    }

    @Test
    fun `Connection failure triggers ConnectionException`() = runTest {
        server.enqueue(MockResponse().setSocketPolicy(SocketPolicy.DISCONNECT_AT_START))

        try {
            transport.execute(HttpRequest(method = "GET", url = "$baseUrl/disconnect"))
            fail("Expected ConnectionException")
        } catch (e: SarvamException.ConnectionException) {
            assertNotNull(e.message)
        }
    }

    // --- OkHttpWebSocketFactory Tests ---

    @Test
    fun `WebSocket connection, send, receive text and binary, close`() = runTest {
        val wsUrl = baseUrl.replace("http://", "ws://").replace("https://", "wss://") + "/ws"

        server.enqueue(
            MockResponse().withWebSocketUpgrade(object : WebSocketListener() {
                override fun onMessage(webSocket: WebSocket, text: String) {
                    if (text == "ping") {
                        webSocket.send("pong")
                    }
                }

                override fun onMessage(webSocket: WebSocket, bytes: okio.ByteString) {
                    webSocket.send(bytes) // echo
                }

                override fun onClosing(webSocket: WebSocket, code: Int, reason: String) {
                    webSocket.close(code, reason)
                }
            })
        )

        val session = wsFactory.connect(
            url = wsUrl,
            headers = mapOf("Authorization" to "Bearer test-token"),
            subprotocols = listOf("chat.v1")
        )

        // Send text and receive text
        session.send("ping")
        val frame1 = session.incoming.first()
        assertTrue(frame1 is WebSocketFrame.Text)
        assertEquals("pong", (frame1 as WebSocketFrame.Text).text)

        // Send binary and receive binary
        session.send(byteArrayOf(1, 2, 3))
        val frame2 = session.incoming.first()
        assertTrue(frame2 is WebSocketFrame.Binary)
        assertArrayEquals(byteArrayOf(1, 2, 3), (frame2 as WebSocketFrame.Binary).bytes)

        session.close(1000, "Normal closure")
        Thread.sleep(50)
    }

    @Test
    fun `WebSocket handshake failure completes exceptionally`() = runTest {
        val wsUrl = baseUrl.replace("http://", "ws://").replace("https://", "wss://") + "/bad-ws"
        server.enqueue(MockResponse().setResponseCode(403).setBody("Forbidden"))

        try {
            wsFactory.connect(url = wsUrl)
            fail("Expected RealtimeException on handshake failure")
        } catch (e: SarvamException.RealtimeException) {
            assertEquals("handshake_failure", e.code)
            assertEquals(403, e.closeCode)
        }
    }
}
