package ai.sarvam.rust

import java.io.File
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonElement
import kotlinx.serialization.json.JsonNull
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.booleanOrNull
import kotlinx.serialization.json.buildJsonArray
import kotlinx.serialization.json.buildJsonObject
import kotlinx.serialization.json.doubleOrNull
import kotlinx.serialization.json.intOrNull
import kotlinx.serialization.json.jsonObject
import kotlinx.serialization.json.jsonPrimitive
import kotlinx.serialization.json.longOrNull
import kotlinx.serialization.json.put

/**
 * JNI bridge to the shared `libsarvam_rust_core` binary for Android and JVM platforms.
 *
 * Uses zero third-party native wrapper dependencies by binding directly to the JNI
 * entrypoints compiled into `libsarvam_rust_core`.
 */
public object SarvamRustBridge {
    @Volatile
    private var isLoaded: Boolean = false

    private val json: Json = Json { ignoreUnknownKeys = true }

    /**
     * Loads the native `libsarvam_rust_core` shared library.
     *
     * @param explicitPath Optional absolute path to `.so` / `.dylib` / `.dll` for JVM tests or custom packaging.
     */
    @Synchronized
    public fun ensureLoaded(explicitPath: String? = null) {
        if (isLoaded) return
        if (!explicitPath.isNullOrBlank()) {
            System.load(File(explicitPath).absolutePath)
        } else {
            System.loadLibrary("sarvam_rust_core")
        }
        isLoaded = true
    }

    @JvmStatic
    public external fun nativeInvokeJson(commandJson: String): String

    @JvmStatic
    public external fun nativeResamplePcm16(
        inputBytes: ByteArray,
        inputSampleRate: Int,
        channelCount: Int
    ): ByteArray

    /**
     * Invokes any command on the Rust core engine via JSON payload.
     */
    public fun invoke(command: JsonObject): JsonObject {
        val rawResponse = nativeInvokeJson(command.toString())
        val parsed = json.parseToJsonElement(rawResponse).jsonObject
        val status = parsed["status"]?.jsonPrimitive?.content
        if (status == "err") {
            val message = parsed["error"]?.jsonPrimitive?.content ?: "Unknown Rust core error"
            throw IllegalArgumentException(message)
        }
        return parsed["data"]?.jsonObject ?: JsonObject(emptyMap())
    }

    public fun version(): Map<String, String> {
        val data = invoke(buildJsonObject { put("op", "version") })
        return data.mapValues { it.value.jsonPrimitive.content }
    }

    public fun resolveEnvironment(proxyBaseUrl: String? = null): Map<String, String> {
        val data = invoke(
            buildJsonObject {
                put("op", "resolveEnvironment")
                if (proxyBaseUrl != null) {
                    put("proxyBaseUrl", proxyBaseUrl)
                } else {
                    put("proxyBaseUrl", JsonNull)
                }
            }
        )
        return data.mapValues { it.value.jsonPrimitive.content }
    }

    public fun classifyHttpError(
        statusCode: Int,
        headers: Map<String, String> = emptyMap(),
        rawBody: String = "",
        nowEpochMs: Long = 0L
    ): JsonObject {
        return invoke(
            buildJsonObject {
                put("op", "classifyHttpError")
                put("statusCode", statusCode)
                put(
                    "headers",
                    buildJsonObject {
                        headers.forEach { (k, v) -> put(k, v) }
                    }
                )
                put("rawBody", rawBody)
                put("nowEpochMs", nowEpochMs)
            }
        )
    }

    public fun evaluateRetry(
        operationKind: String,
        attempt: Int,
        maxRetries: Int = 2,
        statusCode: Int? = null,
        headers: Map<String, String> = emptyMap(),
        rawBody: String = "",
        isNetworkOrTimeoutError: Boolean = false,
        isTimeoutError: Boolean = false,
        isReplayableBody: Boolean = true,
        hasIdempotencyKey: Boolean = false,
        isTokenAuth: Boolean = false,
        hasRefreshedToken: Boolean = false,
        randomFactor: Double = 0.5,
        nowEpochMs: Long = 0L
    ): JsonObject {
        return invoke(
            buildJsonObject {
                put("op", "evaluateRetry")
                put(
                    "input",
                    buildJsonObject {
                        put("operationKind", operationKind)
                        put("attempt", attempt)
                        put("maxRetries", maxRetries)
                        if (statusCode != null) put("statusCode", statusCode) else put("statusCode", JsonNull)
                        put(
                            "headers",
                            buildJsonObject {
                                headers.forEach { (k, v) -> put(k, v) }
                            }
                        )
                        put("rawBody", rawBody)
                        put("isNetworkOrTimeoutError", isNetworkOrTimeoutError)
                        put("isTimeoutError", isTimeoutError)
                        put("isReplayableBody", isReplayableBody)
                        put("hasIdempotencyKey", hasIdempotencyKey)
                        put("isTokenAuth", isTokenAuth)
                        put("hasRefreshedToken", hasRefreshedToken)
                        put("randomFactor", randomFactor)
                        put("nowEpochMs", nowEpochMs)
                    }
                )
            }
        )
    }

    public fun parseChatSse(rawSse: String): JsonObject {
        return invoke(
            buildJsonObject {
                put("op", "parseChatSse")
                put("rawSse", rawSse)
            }
        )
    }

    public fun parseResponsesSse(rawSse: String): JsonObject {
        return invoke(
            buildJsonObject {
                put("op", "parseResponsesSse")
                put("rawSse", rawSse)
            }
        )
    }

    /**
     * Resamples little-endian PCM16 audio directly over native JNI byte arrays to 16kHz mono linear-16 LE.
     */
    public fun resamplePcm16(
        inputBytes: ByteArray,
        inputSampleRate: Int,
        channelCount: Int = 1
    ): ByteArray {
        if (inputBytes.isEmpty()) return ByteArray(0)
        return nativeResamplePcm16(inputBytes, inputSampleRate, channelCount)
    }

    public fun calculateAudioLevels(pcm16Bytes: ByteArray): Map<String, Double> {
        val data = invoke(
            buildJsonObject {
                put("op", "calculateAudioLevels")
                put(
                    "pcm16Bytes",
                    buildJsonArray {
                        for (b in pcm16Bytes) {
                            add(JsonPrimitive(b.toInt() and 0xFF))
                        }
                    }
                )
            }
        )
        return mapOf(
            "rms" to (data["rms"]?.jsonPrimitive?.doubleOrNull ?: 0.0),
            "peak" to (data["peak"]?.jsonPrimitive?.doubleOrNull ?: 0.0),
            "dbFs" to (data["dbFs"]?.jsonPrimitive?.doubleOrNull ?: -100.0)
        )
    }
}
