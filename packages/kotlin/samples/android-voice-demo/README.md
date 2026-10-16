# Android Indic Voice Demo (Jetpack Compose)

A production-grade Android sample application demonstrating a full-duplex conversational voice pipeline powered by Sarvam AI:
1. **Live Indic Captions**: Real-time microphone streaming via `SarvamMicStreamer` to Sarvam's WebSocket STT (`saaras:v3-realtime`).
2. **Translate-and-Speak**: Automatic Indic translation (`client.text.translate`) followed by low-latency natural TTS playback (`bulbul:v4-flash`).
3. **Sub-20ms Barge-In Interruption**: Instant cancellation of assistant voice playback via `BargeInCoordinator` whenever user speech is detected.

---

## 🛠️ Prerequisites & Setup

### 1. Android Manifest Permissions

Ensure your app's `AndroidManifest.xml` requests microphone and internet access:

```xml
<manifest xmlns:android="http://schemas.android.com/apk/res/android">

    <uses-permission android:name="android.permission.INTERNET" />
    <uses-permission android:name="android.permission.RECORD_AUDIO" />
    <uses-permission android:name="android.permission.MODIFY_AUDIO_SETTINGS" />

    <application
        android:allowBackup="true"
        android:label="Sarvam Voice Demo"
        android:theme="@style/Theme.Material3.DayNight.NoActionBar">
        
        <activity
            android:name=".MainActivity"
            android:exported="true">
            <intent-filter>
                <action android:name="android.intent.action.MAIN" />
                <category android:name="android.intent.category.LAUNCHER" />
            </intent-filter>
        </activity>
    </application>
</manifest>
```

### 2. Gradle Dependencies

In your app module's `build.gradle.kts`:

```kotlin
plugins {
    id("com.android.application")
    id("org.jetbrains.kotlin.android")
    id("org.jetbrains.kotlin.plugin.compose")
}

android {
    namespace = "ai.sarvam.samples.voicedemo"
    compileSdk = 35

    defaultConfig {
        applicationId = "ai.sarvam.samples.voicedemo"
        minSdk = 21
        targetSdk = 35
        versionCode = 1
        versionName = "1.0"
    }

    buildFeatures {
        compose = true
    }
}

dependencies {
    // Sarvam Mobile SDK
    implementation("ai.sarvam:sarvam-core:0.1.0")
    implementation("ai.sarvam:sarvam-android-audio:0.1.0")

    // Jetpack Compose BOM & Material 3
    val composeBom = platform("androidx.compose:compose-bom:2024.10.00")
    implementation(composeBom)
    implementation("androidx.compose.material3:material3")
    implementation("androidx.compose.ui:ui")
    implementation("androidx.compose.ui:ui-tooling-preview")
    implementation("androidx.compose.material:material-icons-extended")
    implementation("androidx.activity:activity-compose:1.9.3")

    // Coroutines
    implementation("org.jetbrains.kotlinx:kotlinx-coroutines-android:1.9.0")
}
```

---

## 🚀 Key Architectural Patterns

### 1. Hardware Microphone Streamer (`SarvamMicStreamer`)
Captures 16-bit PCM audio directly from `android.media.AudioRecord`. If the device records at 44.1 kHz or 48 kHz, the internal `PcmResampler` performs linear interpolation down to 16 kHz mono on the fly.
It features a bounded channel buffer with `BufferOverflow.DROP_OLDEST` to prevent UI thread blocking or memory leaks during high-latency network drops.

```kotlin
val micStreamer = SarvamMicStreamer(
    driver = AndroidAudioRecordCaptureDriver(sampleRate = 16000, channelCount = 1),
    onAudioLevel = { level ->
        // Normalized audio volume (0.0f - 1.0f) for live equalizer UI
        audioLevel = level.normalized
    }
)
```

### 2. Real-time STT WebSocket (`SttRealtimeSession`)
Establishes a bi-directional WebSocket connection with server-side Voice Activity Detection (VAD).
Emits real-time `TranscriptPartial` events as words are spoken, followed by `TranscriptFinal` when a sentence pause is detected.

```kotlin
val session = client.speechToText.connect(
    SttRealtimeConfig(
        languageCode = LanguageCode.HI_IN,
        model = SttModel.SAARAS_V3_REALTIME,
        sampleRate = 16000
    )
)
```

### 3. Ultra-Low Latency Barge-In (`BargeInCoordinator`)
Conversational voice bots feel unnatural if they talk over the user. The `BargeInCoordinator` observes the STT session's VAD events:

```
[Server VAD: VadSpeechStart] ──> [BargeInCoordinator] ──> [SarvamAudioPlayer.stopAndFlush()]
                                                                │
                                                                ▼
                                                   AudioTrack halted & buffers flushed
                                                   (< 20ms latency)
```

```kotlin
val coordinator = BargeInCoordinator(
    onBargeIn = {
        // Update UI state to reflect playback cancellation
        isPlaying = false
    }
)
coordinator.attach(session, audioPlayer, coroutineScope)
```

### 4. Audio Playback (`SarvamAudioPlayer`)
Uses `android.media.AudioTrack` in streaming mode (`MODE_STREAM`), writing audio chunks directly to hardware buffers. `stopAndFlush()` executes `pause()` and `flush()` synchronously, guaranteeing sub-20ms mute latency.

---

## 🔒 Production Security Note

For prototyping, `ApiKeyAuth("...")` can be placed in `MainActivity.kt`.

For production deployment to Google Play, switch to `TokenAuth`:

```kotlin
val client = SarvamClient.builder()
    .authProvider(
        TokenAuth(
            tokenProvider = {
                val response = authService.getSarvamSessionToken()
                AuthToken(
                    token = response.token,
                    expiresAtEpochMs = response.expiresAtEpochMs
                )
            }
        )
    )
    .build()
```
