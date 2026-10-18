# Sarvam AI Kotlin & Android SDK Quickstart

Comprehensive, production-ready Kotlin code snippets for integrating Sarvam AI into Android and JVM applications.

---

## 1. Gradle Installation

Add the official artifacts to your module's `build.gradle.kts`:

```kotlin
dependencies {
    // Core API client (pure Kotlin JVM, coroutines, OkHttp, kotlinx.serialization)
    implementation("io.github.ibhanu:sarvam-core:0.1.0")

    // Android audio companion (optional: microphone capture, 16kHz resampler, AudioTrack playback, Barge-in)
    implementation("io.github.ibhanu:sarvam-android-audio:0.1.0")
}
```

---

## 2. Authentication Patterns

### 2.1 Production Mobile Security: `TokenAuth`
Fetches short-lived ephemeral bearer tokens from your secure backend. Proactively refreshes 60 seconds before expiration with mutex deduplication and automatic single-retry recovery on HTTP 401/403.

```kotlin
import ai.sarvam.SarvamClient
import ai.sarvam.core.auth.AuthToken
import ai.sarvam.core.auth.TokenAuth

val authProvider = TokenAuth(
    tokenProvider = {
        // Fetch short-lived token from your secure backend API
        val authResult = myBackendApi.getSarvamSessionToken()
        AuthToken(
            token = authResult.token,
            expiresAtEpochMs = authResult.expiresAtEpochMs
        )
    }
)

val client = SarvamClient(authProvider)
```

### 2.2 Backend-For-Frontend (BFF): `ProxyAuth`
Routes requests through a self-hosted gateway, forwarding app session cookies or JWT tokens:

```kotlin
import ai.sarvam.SarvamClient
import ai.sarvam.core.auth.ProxyAuth

val client = SarvamClient.builder()
    .authProvider(
        ProxyAuth(
            proxyBaseUrl = "https://api.mycompany.com/sarvam-proxy",
            headersProvider = {
                mapOf("X-User-Session" to userSessionManager.currentSessionId)
            }
        )
    )
    .apiBaseUrl("https://api.mycompany.com/sarvam-proxy")
    .wsBaseUrl("wss://api.mycompany.com/sarvam-proxy-ws")
    .build()
```

### 2.3 Prototyping & Development: `ApiKeyAuth`
```kotlin
import ai.sarvam.SarvamClient

val client = SarvamClient(apiKey = "YOUR_API_KEY")
```

---

## 3. Indic Text AI: Translation, Transliteration & LID

### 3.1 Text Translation
Translate between English and 22+ Indic languages:

```kotlin
import ai.sarvam.generated.LanguageCode

val result = client.text.translate(
    input = "How can I help you today?",
    targetLanguageCode = LanguageCode.HI_IN, // Hindi
    sourceLanguageCode = LanguageCode.EN_IN
)

println("Translated: ${result.translatedText}")
```

### 3.2 Transliteration
Convert text across scripts phonetically:

```kotlin
import ai.sarvam.generated.LanguageCode

val transliteration = client.text.transliterate(
    input = "shukriya",
    sourceLanguageCode = LanguageCode.EN_IN,
    targetLanguageCode = LanguageCode.HI_IN
)

println("Devanagari: ${transliteration.transliteratedText}")
// Output: "शुक्रिया"
```

### 3.3 Language Identification (LID)
Detect language of Indic text with confidence metrics:

```kotlin
val lid = client.text.identifyLanguage("નમસ્તે, તમે કેમ છો?")
println("Detected: ${lid.languageCode?.value}, Confidence: ${lid.confidence}")
// Output: "gu-IN", Confidence: 0.99
```

---

## 4. Text-to-Speech (TTS)

### 4.1 Batch Audio Generation
```kotlin
import ai.sarvam.models.TextToSpeechRequest
import ai.sarvam.generated.LanguageCode
import ai.sarvam.generated.Speaker
import ai.sarvam.generated.AudioCodec
import ai.sarvam.generated.TtsModel

val response = client.textToSpeech.convert(
    TextToSpeechRequest(
        text = "नमस्ते, सर्वम एआई में आपका स्वागत है।",
        targetLanguageCode = LanguageCode.HI_IN,
        speaker = Speaker.ANUSHKA,
        model = TtsModel.BULBUL_V4_FLASH,
        speechSampleRate = 22050,
        outputAudioCodec = AudioCodec.WAV
    )
)

val wavBytes: ByteArray = response.audioBytes
```

### 4.2 HTTP Chunked Byte Streaming
Stream audio chunks over HTTP as they are synthesized:

```kotlin
import kotlinx.coroutines.flow.Flow

val stream: Flow<ByteArray> = client.textToSpeech.stream(
    TextToSpeechRequest(
        text = "यह एक लंबा वाक्य है जो रीयल-टाइम में स्ट्रीम किया जा रहा है।",
        targetLanguageCode = LanguageCode.HI_IN,
        speaker = Speaker.VIDYA
    )
)

stream.collect { chunk ->
    audioTrack.write(chunk, 0, chunk.size)
}
```

### 4.3 WebSocket Full-Duplex TTS Streaming
Send text incrementally and receive audio chunks with sub-second time-to-first-byte (TTFB):

```kotlin
import ai.sarvam.models.TtsStreamingConfig
import ai.sarvam.models.TtsStreamEvent
import ai.sarvam.generated.LanguageCode
import ai.sarvam.generated.Speaker

val session = client.textToSpeech.connect(
    TtsStreamingConfig(
        languageCode = LanguageCode.HI_IN,
        speaker = Speaker.ANUSHKA
    )
)

// Collect incoming synthesized audio chunks
launch {
    session.events.collect { event ->
        when (event) {
            is TtsStreamEvent.AudioChunk -> {
                audioTrack.write(event.audioBytes, 0, event.audioBytes.size)
            }
            is TtsStreamEvent.Completed -> {
                println("Synthesis completed")
            }
            is TtsStreamEvent.Error -> {
                println("TTS error: ${event.message}")
            }
            else -> Unit
        }
    }
}

// Push text chunks
session.sendText("पहला वाक्य यहाँ भेजा जा रहा है। ")
session.sendText("दूसरा वाक्य इसके बाद आ रहा है।")
session.flush()
```

---

## 5. Realtime Speech-to-Text WebSocket (STT)

Stream microphone audio over WebSockets with server-side VAD, partial word streaming, and dynamic configuration updates:

```kotlin
import ai.sarvam.models.SttRealtimeConfig
import ai.sarvam.models.SttRealtimeEvent
import ai.sarvam.generated.LanguageCode
import ai.sarvam.generated.SttModel

val sttSession = client.speechToText.connect(
    SttRealtimeConfig(
        languageCode = LanguageCode.HI_IN,
        model = SttModel.SAARAS_V3_REALTIME,
        sampleRate = 16000 // Must be 16000 or 8000
    )
)

// Listen for VAD and transcription events
launch {
    sttSession.events.collect { event ->
        when (event) {
            is SttRealtimeEvent.TranscriptPartial -> {
                println("Partial: ${event.text}")
            }
            is SttRealtimeEvent.TranscriptFinal -> {
                println("Final: ${event.text} (Confidence: ${event.languageConfidence})")
            }
            is SttRealtimeEvent.VadSpeechStart -> {
                println("User started speaking")
            }
            is SttRealtimeEvent.VadSpeechEnd -> {
                println("User paused speaking")
            }
            is SttRealtimeEvent.Error -> {
                println("Realtime STT error: ${event.message}")
            }
            else -> Unit
        }
    }
}

// Send 16-bit linear PCM audio chunk (16 kHz, mono)
val pcmBytes: ByteArray = getMicAudioChunk()
sttSession.sendAudio(pcmBytes)

// Update config dynamically in-flight
sttSession.updateConfig(
    keyterms = listOf("UPI", "Aadhaar", "Sarvam")
)
```

---

## 6. Android Hardware Audio & Sub-20ms Barge-In

Combine microphone capture, resamplers, AudioTrack playback, and interrupt handling:

```kotlin
import ai.sarvam.audio.AndroidAudioRecordCaptureDriver
import ai.sarvam.audio.AndroidAudioTrackPlaybackDriver
import ai.sarvam.audio.BargeInCoordinator
import ai.sarvam.audio.SarvamAudioPlayer
import ai.sarvam.audio.SarvamMicStreamer

// 1. Initialize microphone streamer with 16kHz resampler and visualizer listener
val micStreamer = SarvamMicStreamer(
    driver = AndroidAudioRecordCaptureDriver(sampleRate = 16000, channelCount = 1),
    onAudioLevel = { level ->
        updateVolumeMeter(level.normalized) // 0.0f .. 1.0f
    }
)

// 2. Initialize low-latency AudioTrack player
val audioPlayer = SarvamAudioPlayer(
    driver = AndroidAudioTrackPlaybackDriver(sampleRate = 16000, channelCount = 1)
)

// 3. Setup BargeInCoordinator
// Instantly flushes playback buffers when user speaks (sub-20ms latency)
val coordinator = BargeInCoordinator(
    onBargeIn = {
        println("User interrupted playback! Stopping assistant voice.")
    }
)
coordinator.attach(sttSession, audioPlayer, coroutineScope)

// 4. Start streaming audio from mic to STT WebSocket
micStreamer.start(scope = coroutineScope, session = sttSession)
```

---

## 7. Conversational AI: Indic Chat V2 with Session Affinity

Chat completions supporting SSE token streaming and session affinity routing (`x-session-affinity` header) to maintain state on multi-turn conversations:

```kotlin
import ai.sarvam.generated.ChatModel
import ai.sarvam.models.ChatCompletionRequest
import ai.sarvam.models.ChatMessage

// 1. Create session (generates UUID and attaches x-session-affinity header)
val chatSession = client.chat.createSession()

val request = ChatCompletionRequest(
    model = ChatModel.SARVAM_105B.value,
    messages = listOf(
        ChatMessage(role = "system", content = "You are an expert Indic financial advisor."),
        ChatMessage(role = "user", content = "म्यूचुअल फंड में निवेश कैसे शुरू करें?")
    ),
    temperature = 0.7
)

// 2. Stream tokens via Server-Sent Events (SSE)
chatSession.completionsV2Stream(request).collect { chunk ->
    chunk.firstDeltaContent?.let { token ->
        print(token)
    }
}

// 3. Multi-turn continuation (preserves conversation affinity)
val followUp = ChatCompletionRequest(
    model = ChatModel.SARVAM_105B.value,
    messages = listOf(
        ChatMessage(role = "user", content = "SIP क्या होता है?")
    )
)
val response = chatSession.completionsV2(followUp)
println("\nResponse: ${response.choices.firstOrNull()?.message?.content}")
```

---

## 8. Document AI: Digitisation & Structured Data Extraction

Process PDFs and images asynchronously with built-in polling (`digitiseAndWait` and `extractAndWait`):

```kotlin
import ai.sarvam.core.io.FileInput
import java.io.File

val documentFile = File("/path/to/invoice.pdf")
val fileInput = FileInput.fromFile(documentFile, mimeType = "application/pdf")

// 1. Digitise Document & Wait for Completion
val digitiseJob = client.docAi.digitiseAndWait(
    file = fileInput,
    language = "hi-IN",
    pollIntervalMs = 3000L,
    timeoutMs = 180_000L
)

if (digitiseJob.isSuccessful) {
    val rawText = client.docAi.getResults(digitiseJob.jobId)
    println("Digitised content: $rawText")
}

// 2. Extract Structured Data via Schema & Wait
val invoiceSchema = mapOf(
    "invoice_number" to "string",
    "total_amount" to "number",
    "vendor_name" to "string",
    "line_items" to listOf(
        mapOf(
            "item_name" to "string",
            "quantity" to "number",
            "price" to "number"
        )
    )
)

val extractJob = client.docAi.extractAndWait(
    file = fileInput,
    schema = invoiceSchema,
    pollIntervalMs = 3000L
)

if (extractJob.isSuccessful) {
    val extractedJson = client.docAi.getResults(extractJob.jobId)
    println("Extracted JSON: $extractedJson")
}
```

---

## 9. Error Handling

Handle typed `SarvamException` instances:

```kotlin
import ai.sarvam.core.error.SarvamException

try {
    val result = client.text.translate("Hello", LanguageCode.HI_IN)
} catch (e: SarvamException.AuthenticationException) {
    // HTTP 401 or HTTP 403 invalid key
    println("Authentication failed: ${e.message} (Request ID: ${e.requestId})")
} catch (e: SarvamException.RateLimitException) {
    // HTTP 429
    println("Rate limited. Recommended backoff: ${e.retryAfterMs} ms")
} catch (e: SarvamException.BadRequestException) {
    // HTTP 400 validation error
    println("Bad request: ${e.message}, Code: ${e.code}, Payload: ${e.rawBody}")
} catch (e: SarvamException.ServerException) {
    // HTTP 5xx
    println("Server error: ${e.statusCode} ${e.message}")
} catch (e: SarvamException.ConnectionException) {
    // DNS, TLS, or offline connection failure
    println("Connection failed: ${e.message}")
}
```
