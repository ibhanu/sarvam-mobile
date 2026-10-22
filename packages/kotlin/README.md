<p align="center">
  <a href="https://sarvam.ai">
    <img src="https://raw.githubusercontent.com/ibhanu/sarvam-mobile/main/assets/sarvam-ai-website.png" alt="Sarvam AI - India's Sovereign AI Platform" width="100%" style="border-radius: 12px; max-width: 860px; box-shadow: 0 8px 30px rgba(0,0,0,0.12);" />
  </a>
</p>

# Sarvam AI Kotlin & Android SDK

[![Maven Central](https://img.shields.io/maven-central/v/io.github.ibhanu/sarvam-core.svg)](https://central.sonatype.com/artifact/io.github.ibhanu/sarvam-core)
[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](https://opensource.org/licenses/MIT)
[![Rust Core JNI](https://img.shields.io/badge/Rust%20Core-JNI-DEA584.svg?logo=rust)](../rust-core)
[![Kotlin](https://img.shields.io/badge/Kotlin-2.0.21-purple.svg)](https://kotlinlang.org)
[![Android Min SDK](https://img.shields.io/badge/Android%20Min%20SDK-21+-green.svg)](https://developer.android.com)

Unofficial, production-grade Kotlin & Android client SDK for [Sarvam AI](https://sarvam.ai) — India's foundational AI platform. Designed for high performance, sub-20ms voice barge-in, sound nullability, structured concurrency with Kotlin Coroutines & Flow, and zero-leak mobile security.

---

## ⏱️ < 5 Minutes to First Call

### 1. Add Dependencies

Add the core client and optional audio hardware companion to your `build.gradle.kts`:

```kotlin
dependencies {
    // Core API client (pure Kotlin JVM, coroutines, OkHttp, kotlinx.serialization)
    implementation("io.github.ibhanu:sarvam-core:0.1.0")

    // Android hardware audio companion (AudioRecord, AudioTrack, 16kHz resampler, Barge-in)
    implementation("io.github.ibhanu:sarvam-android-audio:0.1.0")
}
```

*(Using Groovy `build.gradle`? Use `implementation 'io.github.ibhanu:sarvam-core:0.1.0'` and `implementation 'io.github.ibhanu:sarvam-android-audio:0.1.0'`)*

### 2. Make Your First Call

```kotlin
import ai.sarvam.SarvamClient
import ai.sarvam.generated.LanguageCode
import kotlinx.coroutines.runBlocking

fun main() = runBlocking {
    val client = SarvamClient("YOUR_API_KEY")

    val response = client.text.translate(
        input = "Good morning! Welcome to Sarvam AI.",
        targetLanguageCode = LanguageCode.HI_IN
    )

    println(response.translatedText)
    // Output: "सुप्रभात! सर्वम एआई में आपका स्वागत है।"
}
```

---

## 🔐 Mobile Security: TokenAuth & ProxyAuth

> [!WARNING]
> **Never compile static API keys into mobile application binaries!**
> Static secrets compiled into APKs or AABs are easily extracted via `strings`, `apktool`, or class decompiler tools.

The Sarvam SDK provides two production-grade authentication patterns for mobile apps:

### 1. `TokenAuth` (Recommended for Direct-to-Sarvam Mobile Connections)
Fetches short-lived ephemeral bearer tokens from your secure backend.
- Automatically caches tokens in memory.
- Proactively refreshes credentials **60 seconds** before expiration.
- Uses **single-flight deduplication** to ensure concurrent requests share one refresh cycle.
- Automatically handles HTTP `401` / `403` by invalidating the cache and retrying with a fresh token.

```kotlin
import ai.sarvam.SarvamClient
import ai.sarvam.core.auth.AuthToken
import ai.sarvam.core.auth.TokenAuth

val authProvider = TokenAuth(
    tokenProvider = {
        // Fetch ephemeral session token from your auth backend
        val resp = myBackendApi.getSarvamSessionToken()
        AuthToken(
            token = resp.token,
            expiresAtEpochMs = resp.expiresAtEpochMs
        )
    }
)

val client = SarvamClient(authProvider)
```

### 2. `ProxyAuth` (Recommended for Backend-For-Frontend / BFF Deployments)
Routes all client traffic through your self-hosted proxy/gateway, attaching your own session headers:

```kotlin
import ai.sarvam.SarvamClient
import ai.sarvam.core.auth.ProxyAuth

val client = SarvamClient.builder()
    .authProvider(
        ProxyAuth(
            proxyBaseUrl = "https://api.yourdomain.com/sarvam-proxy",
            headersProvider = {
                mapOf("Authorization" to "Bearer ${userSession.jwtToken}")
            }
        )
    )
    .apiBaseUrl("https://api.yourdomain.com/sarvam-proxy")
    .wsBaseUrl("wss://api.yourdomain.com/sarvam-proxy-ws")
    .build()
```

### 3. `ApiKeyAuth` (Development & Local Testing Only)
```kotlin
val client = SarvamClient("sarvam-api-key")
```

---

## 🚀 Quickstart Guides

### 1. Indic Text Translation & Transliteration

```kotlin
import ai.sarvam.SarvamClient
import ai.sarvam.generated.LanguageCode

val client = SarvamClient(authProvider)

// 1. Translate
val translation = client.text.translate(
    input = "Where is the nearest railway station?",
    targetLanguageCode = LanguageCode.TA_IN, // Tamil
    sourceLanguageCode = LanguageCode.EN_IN
)
println("Tamil: ${translation.translatedText}")

// 2. Transliterate (convert script across Indic languages)
val transliteration = client.text.transliterate(
    input = "namaste dosto",
    sourceLanguageCode = LanguageCode.EN_IN,
    targetLanguageCode = LanguageCode.HI_IN
)
println("Devanagari: ${transliteration.transliteratedText}")

// 3. Language Identification (LID)
val lid = client.text.identifyLanguage("வணக்கம், நீங்கள் எப்படி இருக்கிறீர்கள்?")
println("Detected: ${lid.languageCode?.value} (Confidence: ${lid.confidence})")
```

---

### 2. Streaming Text-to-Speech (TTS)

Convert text into lifelike natural speech across 11+ Indic languages using Bulbul models.

#### HTTP Byte Streaming
```kotlin
import ai.sarvam.models.TextToSpeechRequest
import ai.sarvam.generated.LanguageCode
import ai.sarvam.generated.Speaker
import ai.sarvam.generated.AudioCodec

val request = TextToSpeechRequest(
    text = "नमस्ते, सर्वम एआई में आपका स्वागत है।",
    targetLanguageCode = LanguageCode.HI_IN,
    speaker = Speaker.ANUSHKA,
    outputAudioCodec = AudioCodec.WAV
)

// Collect incoming PCM/WAV chunks as a Flow<ByteArray>
client.textToSpeech.stream(request).collect { audioChunk ->
    audioTrack.write(audioChunk, 0, audioChunk.size)
}
```

#### Real-time Full-Duplex WebSocket TTS
```kotlin
import ai.sarvam.models.TtsStreamingConfig
import ai.sarvam.models.TtsStreamEvent
import ai.sarvam.generated.LanguageCode
import ai.sarvam.generated.TtsModel

val ttsSession = client.textToSpeech.connect(
    TtsStreamingConfig(
        languageCode = LanguageCode.HI_IN,
        model = TtsModel.BULBUL_V4_FLASH
    )
)

// Listen for audio chunks
launch {
    ttsSession.events.collect { event ->
        when (event) {
            is TtsStreamEvent.AudioChunk -> player.play(event.audioBytes)
            is TtsStreamEvent.Completed -> println("TTS synthesis complete")
            is TtsStreamEvent.Error -> println("TTS error: ${event.message}")
            else -> Unit
        }
    }
}

// Send streaming text segments
ttsSession.sendText("सर्वम एआई के साथ अपनी आवाज़ को सशक्त बनाएं।")
ttsSession.flush()
```

---

### 3. Realtime Speech-to-Text WebSocket (STT)

Stream microphone audio over low-latency WebSockets with server-side Voice Activity Detection (VAD) and live partial transcripts.

```kotlin
import ai.sarvam.models.SttRealtimeConfig
import ai.sarvam.models.SttRealtimeEvent
import ai.sarvam.generated.LanguageCode
import ai.sarvam.generated.SttModel

val sttSession = client.speechToText.connect(
    SttRealtimeConfig(
        languageCode = LanguageCode.HI_IN,
        model = SttModel.SAARAS_V3_REALTIME,
        sampleRate = 16000 // 16 kHz or 8 kHz PCM 16-bit mono
    )
)

// Collect realtime events
launch {
    sttSession.events.collect { event ->
        when (event) {
            is SttRealtimeEvent.TranscriptPartial -> {
                println("Partial: ${event.text}")
            }
            is SttRealtimeEvent.TranscriptFinal -> {
                println("Final: ${event.text} (Lang: ${event.language?.value})")
            }
            is SttRealtimeEvent.VadSpeechStart -> {
                println("User started speaking...")
            }
            is SttRealtimeEvent.VadSpeechEnd -> {
                println("User finished speaking.")
            }
            is SttRealtimeEvent.Error -> {
                println("STT error: ${event.message}")
            }
            else -> Unit
        }
    }
}

// Stream 16kHz PCM audio bytes
val pcm16Chunk: ByteArray = getMicAudioChunk()
sttSession.sendAudio(pcm16Chunk)
```

---

### 4. Android Hardware Audio & Sub-20ms Barge-In

The companion package `io.github.ibhanu:sarvam-android-audio` integrates microphone capture, resamplers, AudioTrack playback, and interrupt handling:

```kotlin
import ai.sarvam.audio.AndroidAudioRecordCaptureDriver
import ai.sarvam.audio.AndroidAudioTrackPlaybackDriver
import ai.sarvam.audio.BargeInCoordinator
import ai.sarvam.audio.SarvamAudioPlayer
import ai.sarvam.audio.SarvamMicStreamer

// 1. Initialize drivers and controllers
val micStreamer = SarvamMicStreamer(
    driver = AndroidAudioRecordCaptureDriver(sampleRate = 16000, channelCount = 1),
    onAudioLevel = { level ->
        // Normalized volume level for visualizer UI (0.0f - 1.0f)
        updateVisualizer(level.normalized)
    }
)

val audioPlayer = SarvamAudioPlayer(
    driver = AndroidAudioTrackPlaybackDriver(sampleRate = 16000, channelCount = 1)
)

// 2. Setup BargeInCoordinator
// Instantly flushes playback buffers when user speaks (sub-20ms latency)
val coordinator = BargeInCoordinator(
    onBargeIn = {
        println("User interrupted playback! Stopping assistant voice.")
    }
)
coordinator.attach(sttSession, audioPlayer, coroutineScope)

// 3. Start streaming microphone directly to STT WebSocket
micStreamer.start(scope = coroutineScope, session = sttSession)
```

---

### 5. Chat V2 with Session Affinity (`ChatSession`)

Multi-turn conversational AI with server-side context routing and SSE token streaming:

```kotlin
import ai.sarvam.generated.ChatModel
import ai.sarvam.models.ChatCompletionRequest
import ai.sarvam.models.ChatMessage

// Create session; automatically injects x-session-affinity header
val chatSession = client.chat.createSession()

val request = ChatCompletionRequest(
    model = ChatModel.SARVAM_105B.value,
    messages = listOf(
        ChatMessage(role = "system", content = "You are a helpful Indic assistant."),
        ChatMessage(role = "user", content = "भारत की राजधानी क्या है?")
    )
)

// Stream tokens in real time
chatSession.completionsV2Stream(request).collect { chunk ->
    chunk.firstDeltaContent?.let { token ->
        print(token)
    }
}
```

---

### 6. Document AI: Digitisation & Extraction

Digitise and extract structured data from multilingual PDFs and scanned documents with built-in polling (`digitiseAndWait`):

```kotlin
import ai.sarvam.core.io.FileInput
import java.io.File

val pdfFile = File("/path/to/invoice.pdf")
val fileInput = FileInput.fromFile(pdfFile, mimeType = "application/pdf")

// Uploads document, starts job, and polls until terminal status (completed/failed)
val jobStatus = client.docAi.digitiseAndWait(
    file = fileInput,
    language = "hi-IN",
    pollIntervalMs = 3000L,
    timeoutMs = 120_000L
)

if (jobStatus.isSuccessful) {
    val resultsJson = client.docAi.getResults(jobStatus.jobId)
    println("Extracted Document Text:\n$resultsJson")
}
```

---

## 🛡️ Error Handling

All SDK exceptions derive from `SarvamException`, carrying status codes, machine-readable error codes, and correlation request IDs:

```kotlin
import ai.sarvam.core.error.SarvamException

try {
    val response = client.text.translate("Hello", LanguageCode.HI_IN)
} catch (e: SarvamException.AuthenticationException) {
    // 401 Unauthorized or 403 invalid key
    println("Auth error: ${e.message} (Request ID: ${e.requestId})")
} catch (e: SarvamException.RateLimitException) {
    // 429 Too Many Requests (automatically retried by default)
    println("Rate limited. Retry after ${e.retryAfterMs}ms")
} catch (e: SarvamException.BadRequestException) {
    // 400 Bad Request
    println("Bad request: ${e.message}, Code: ${e.code}")
} catch (e: SarvamException.ConnectionException) {
    // Offline, DNS, TLS failure
    println("Network failure: ${e.message}")
}
```

---

## ⚙️ Client Configuration & Customization

```kotlin
import ai.sarvam.SarvamClient
import ai.sarvam.core.middleware.LogLevel
import kotlin.time.Duration.Companion.seconds

val client = SarvamClient.builder()
    .authProvider(authProvider)
    .maxRetries(3)                // Exponential backoff with full jitter
    .baseBackoffMs(500L)
    .maxBackoffMs(8000L)
    .logLevel(LogLevel.HEADERS)   // LogLevel.NONE, BASIC, HEADERS, BODY
    .build()
```

---

## 📦 Architecture & Packages

| Package | Artifact | Maven Central | Description |
| :--- | :--- | :--- | :--- |
| **`sarvam-core`** | `io.github.ibhanu:sarvam-core` | [![Maven Central](https://img.shields.io/maven-central/v/io.github.ibhanu/sarvam-core.svg)](https://central.sonatype.com/artifact/io.github.ibhanu/sarvam-core) | Pure Kotlin JVM library containing REST clients, SSE streaming, WebSocket sessions, and Auth/Retry middlewares. |
| **`sarvam-android-audio`** | `io.github.ibhanu:sarvam-android-audio` | [![Maven Central](https://img.shields.io/maven-central/v/io.github.ibhanu/sarvam-android-audio.svg)](https://central.sonatype.com/artifact/io.github.ibhanu/sarvam-android-audio) | Android companion library containing `AudioRecord` capture, `AudioTrack` playback, 16kHz `PcmResampler`, RMS visualizer calculations, and `BargeInCoordinator`. |

### R8 / ProGuard
Rules are automatically packaged in the library AAR/JAR via `consumer-rules.pro`. No additional configuration is required in consumer apps.

---

## 🦀 Unified Rust Core Engine (Direct JNI)

`io.github.ibhanu:sarvam-core` integrates with [`packages/rust-core`](../rust-core) via direct JNI exports (`SarvamRustBridge`):

- **Direct JNI without JNA Overhead**: Zero third-party runtime dependencies. Uses direct native JVM symbol resolution (`Java_ai_sarvam_rust_SarvamRustBridge_*`).
- **SIMD DSP Audio Downsampling**: Transforms high-rate microphone audio (`AudioRecord` at 44.1 kHz or 48 kHz) into 16 kHz mono linear-16 PCM with bit-exact parity across all platforms.
- **Single-Flight Token Synchronization**: Lock-free proactive refresh coordination with atomic state management.
- **Graceful Pure-Kotlin Fallback**: If the native shared library (`libsarvam_rust_core.so`) is absent, `SarvamRustBridge` falls back to pure Kotlin JVM routines seamlessly.

```kotlin
import ai.sarvam.rust.SarvamRustBridge

// 1. Resample raw microphone PCM buffer to 16 kHz mono linear-16 PCM
val pcm16k = SarvamRustBridge.resampleAudio(
    inputPcm = microphoneBytes,
    sourceSampleRate = 48000,
    channels = 1
)

// 2. Compute canonical retry delay (attempt 2, HTTP 429 with 3s Retry-After)
val delayMs = SarvamRustBridge.computeRetryDelay(
    attempt = 2,
    statusCode = 429,
    retryAfterSeconds = 3
)
```

---

## 📱 Sample Application

Check out the full Jetpack Compose sample app:
[`packages/kotlin/samples/android-voice-demo`](./samples/android-voice-demo)
- Live Indic captions with partial/final speech-to-text.
- Instant translate-and-speak.
- Hardware microphone streaming with RMS audio wave.
- Sub-20ms barge-in interruption.

---

## 📄 License

Licensed under the [MIT License](../../LICENSE).
