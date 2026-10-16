# Sarvam iOS Voice Assistant Sample App

This directory provides a production-grade SwiftUI reference implementation of an end-to-end **Live Indic Captions + Translate-and-Speak** voice assistant using the Sarvam Swift SDK (`Sarvam` and `SarvamAudio`).

---

## Architecture & Data Flow

```
+-----------------------------------------------------------------------------------------+
|                                    iOS Application                                      |
|                                                                                         |
|  [Hardware Microphone]                                                                  |
|            | (48 kHz Float32)                                                           |
|            v                                                                            |
|  [CoreAudioCaptureDriver]                                                               |
|            |                                                                            |
|            v                                                                            |
|  [SarvamMicStreamer]  ---> (Real-time Level Metering: RMS & dBFS)                       |
|            | (Resamples to 16 kHz Mono PCM16)                                           |
|            v                                                                            |
|  [SttRealtimeSession (WebSocket)]                                                       |
|            |                                                                            |
|            +---> .transcriptPartial  ---> Updates Live Captions in SwiftUI              |
|            +---> .transcriptFinal    ---> Triggers Translation Pipeline                 |
|            |                                    |                                       |
|            |                                    v                                       |
|            |                         [client.text.translate]                            |
|            |                                    | (Translated Indic Text)               |
|            |                                    v                                       |
|            |                         [client.textToSpeech.stream]                       |
|            |                                    | (AsyncThrowingStream<Data>)           |
|            |                                    v                                       |
|            |                         [SarvamAudioPlayer] ---> [Hardware Speaker]        |
|            |                                    ^                                       |
|            |                                    | (Instant sub-20ms flush)              |
|            +---> .vadSpeechStart -------------->+ [BargeInCoordinator]                  |
+-----------------------------------------------------------------------------------------+
```

---

## Key Features Demonstrated

1. **Live Indic Captions**: Streams microphone audio over WebSockets to `saaras:v3-realtime` and displays streaming partials and final sentences in real time.
2. **Translate-and-Speak**: Translates finalized speech into 11 Indic languages (Hindi, Tamil, Telugu, Bengali, Marathi, Gujarati, Kannada, Malayalam, Punjabi, Odia, English) and speaks the response with low-latency HTTP chunked TTS.
3. **Automated Sub-20ms Barge-In**: Employs `BargeInCoordinator` to listen for voice activity detection (`.vadSpeechStart`) on the STT stream, immediately interrupting and clearing hardware playback buffers.
4. **Hardware Audio Drivers**: Demonstrates how to bridge iOS AVFoundation (`AVAudioEngine`, `AVAudioInputNode`, and `AVAudioPlayerNode`) to the SDK's abstract `AudioCaptureDriver` and `AudioPlaybackDriver` protocols.
5. **Real-time Audio Visualizer**: Captures normalized RMS and dBFS metrics via `SarvamMicStreamer.onAudioLevel` to render a responsive SwiftUI audio level meter.

---

## Integration Guide

### 1. Add SDK Dependencies

Ensure your Xcode project links both `Sarvam` and `SarvamAudio` via Swift Package Manager:

```swift
dependencies: [
    .package(url: "https://github.com/sarvamai/sarvam-mobile.git", from: "0.1.0")
]
```

### 2. Configure Permissions (`Info.plist`)

Microphone access requires declaring `NSMicrophoneUsageDescription` in your app target's `Info.plist`:

```xml
<key>NSMicrophoneUsageDescription</key>
<string>Voice Assistant requires microphone access to transcribe and translate your speech in real time.</string>
```

### 3. Add `VoiceAssistantView.swift` to Your Project

Drop `VoiceAssistantView.swift` into your app target and display it in your view hierarchy:

```swift
import SwiftUI

@main
struct VoiceAssistantApp: App {
    var body: some Scene {
        WindowGroup {
            VoiceAssistantView()
        }
    }
}
```

### 4. Configure Backend Authentication

In `VoiceAssistantViewModel.configureClient()`, replace the demo token fetch with your server's endpoint:

```swift
let auth = TokenAuth {
    let (data, _) = try await URLSession.shared.data(from: URL(string: "https://api.yourbackend.com/sarvam/token")!)
    let token = String(data: data, encoding: .utf8)!.trimmingCharacters(in: .whitespacesAndNewlines)
    return AuthToken(token: token, expiresAtEpochMs: Int64(Date().timeIntervalSince1970 * 1000) + 3600_000)
}
self.client = SarvamClient(authProvider: auth)
```
