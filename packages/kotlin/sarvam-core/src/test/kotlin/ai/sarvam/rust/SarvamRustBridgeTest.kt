package ai.sarvam.rust

import java.io.File
import java.nio.ByteBuffer
import java.nio.ByteOrder
import kotlinx.serialization.json.boolean
import kotlinx.serialization.json.int
import kotlinx.serialization.json.jsonPrimitive
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.BeforeClass
import org.junit.Test

class SarvamRustBridgeTest {
    companion object {
        @JvmStatic
        @BeforeClass
        fun setUpClass() {
            val dylibFile = File("../../rust-core/target/release/libsarvam_rust_core.dylib")
            val soFile = File("../../rust-core/target/release/libsarvam_rust_core.so")
            val target = when {
                dylibFile.exists() -> dylibFile.absolutePath
                soFile.exists() -> soFile.absolutePath
                else -> error("Compiled libsarvam_rust_core binary not found in ../../rust-core/target/release")
            }
            SarvamRustBridge.ensureLoaded(target)
        }
    }

    @Test
    fun `resolves version and proxy environment URLs via JNI`() {
        val version = SarvamRustBridge.version()
        assertEquals("0.2.0", version["rustCoreVersion"])
        assertEquals("2026-10-16", version["specVersion"])

        val env = SarvamRustBridge.resolveEnvironment("https://bff.sarvam.ai/kotlin/")
        assertEquals("https://bff.sarvam.ai/kotlin", env["apiBaseUrl"])
        assertEquals("https://bff.sarvam.ai/kotlin/dubbing", env["dubbingBaseUrl"])
        assertEquals("wss://bff.sarvam.ai/kotlin", env["wsBaseUrl"])
    }

    @Test
    fun `classifies HTTP 403 invalid_api_key_error and evaluates retry matrix via JNI`() {
        val classified = SarvamRustBridge.classifyHttpError(
            statusCode = 403,
            headers = mapOf("x-request-id" to "req_jni_403"),
            rawBody = """{"error":{"code":"invalid_api_key_error","message":"Key expired"}}"""
        )
        assertEquals("AuthenticationError", classified["type"]?.jsonPrimitive?.content)
        assertTrue(classified["shouldTriggerTokenRefresh"]?.jsonPrimitive?.boolean == true)
        assertEquals("req_jni_403", classified["requestId"]?.jsonPrimitive?.content)

        val retryDecision = SarvamRustBridge.evaluateRetry(
            operationKind = "STATELESS_POST",
            attempt = 0,
            maxRetries = 2,
            statusCode = 429,
            headers = mapOf("retry-after-ms" to "90")
        )
        assertEquals("backoffAndRetry", retryDecision["action"]?.jsonPrimitive?.content)
        assertEquals(90, retryDecision["delayMs"]?.jsonPrimitive?.int)
    }

    @Test
    fun `parses Chat V2 SSE and Responses SSE streams via JNI`() {
        val chatSse = SarvamRustBridge.parseChatSse(
            "data: {\"id\":\"1\",\"choices\":[{\"index\":0,\"delta\":{\"content\":\"Vanakkam\"}}]}\n\n" +
                "data: {\"id\":\"1\",\"choices\":[],\"usage\":{\"prompt_tokens\":3,\"completion_tokens\":1,\"total_tokens\":4}}\n\n" +
                "data: [DONE]\n"
        )
        assertEquals("Vanakkam", chatSse["accumulatedContent"]?.jsonPrimitive?.content)
        assertTrue(chatSse["terminatedOnDone"]?.jsonPrimitive?.boolean == true)

        val respSse = SarvamRustBridge.parseResponsesSse(
            "event: response.completed\n" +
                "data: {\"id\":\"r1\",\"type\":\"response.completed\",\"response\":{\"status\":\"completed\"}}\n\n"
        )
        assertEquals("response.completed", respSse["terminatedOnEvent"]?.jsonPrimitive?.content)
        assertEquals("completed", respSse["finalResponseStatus"]?.jsonPrimitive?.content)
    }

    @Test
    fun `resamples 48kHz PCM16 audio directly over JNI ByteArray and computes levels`() {
        val buf = ByteBuffer.allocate(480 * 2).order(ByteOrder.LITTLE_ENDIAN)
        for (i in 0 until 480) {
            buf.putShort(if (i % 2 == 0) 16384.toShort() else (-16384).toShort())
        }
        val resampled = SarvamRustBridge.resamplePcm16(buf.array(), 48000, 1)
        assertEquals(160 * 2, resampled.size)
        assertEquals(0, SarvamRustBridge.resamplePcm16(ByteArray(0), 48000, 1).size)

        val levels = SarvamRustBridge.calculateAudioLevels(resampled)
        assertTrue((levels["peak"] ?: 0.0) in 0.49..0.51)
        assertTrue((levels["rms"] ?: 0.0) in 0.49..0.51)
    }
}
