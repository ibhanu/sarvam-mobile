# Swift / iOS SDK Quickstart

Production-grade code snippets for the Sarvam AI Swift SDK (`Sarvam` & `SarvamAudio`).

---

## 1. Swift Package Manager Setup

In your `Package.swift`:

```swift
dependencies: [
    .package(url: "https://github.com/ibhanu/sarvam-mobile.git", from: "0.2.0")
],
targets: [
    .target(
        name: "YourApp",
        dependencies: [
            .product(name: "Sarvam", package: "sarvam-mobile"),
            .product(name: "SarvamAudio", package: "sarvam-mobile") // Hardware mic capture & playback
        ]
    )
]
```

---

## 2. Mobile Authentication

Never bundle static API keys in mobile binaries. Use **TokenAuth** (ephemeral tokens) or **ProxyAuth** (BFF proxy).

### Ephemeral Token Authentication (`TokenAuth`)

```swift
import Sarvam

let auth = TokenAuth {
    // Request short-lived token from your secure backend
    let (data, _) = try await URLSession.shared.data(from: URL(string: "https://api.yourbackend.com/sarvam/token")!)
    let token = String(data: data, encoding: .utf8)!.trimmingCharacters(in: .whitespacesAndNewlines)
    return AuthToken(
        token: token,
        expiresAtEpochMs: Int64(Date().timeIntervalSince1970 * 1000) + 3600_000 // 1 hour TTL
    )
}

let client = SarvamClient(authProvider: auth)
```

### Backend-For-Frontend Proxy (`ProxyAuth`)

```swift
import Sarvam

let proxyAuth = ProxyAuth(proxyBaseUrl: "https://api.yourbackend.com/sarvam") {
    ["Authorization": "Bearer \(userSessionToken)"]
}

let client = SarvamClient(
    authProvider: proxyAuth,
    environment: .proxy(baseUrl: "https://api.yourbackend.com/sarvam")
)
```

---

## 3. Text Translation

Translate text across 11 Indic languages and English:

```swift
import Sarvam

let request = TranslateRequest(
    input: "Hello, where is the nearest hospital?",
    sourceLanguageCode: .enIn,
    targetLanguageCode: .hiIn
)

let response = try await client.text.translate(request)
print("Hindi translation: \(response.translatedText)")
```

---

## 4. Streaming Text-to-Speech (TTS)

Stream raw binary audio chunks over HTTP chunked transfer for minimal audio latency:

```swift
import Sarvam

let request = TextToSpeechRequest(
    text: "सर्वम एआई के साथ अपनी आवाज को सशक्त बनाएं।",
    targetLanguageCode: .hiIn,
    speaker: .anushka,
    model: .bulbulV3
)

for try await chunk in client.textToSpeech.stream(request) {
    print("Received audio chunk: \(chunk.count) bytes")
    // Write chunk directly to audio output stream
}
```

---

## 5. Realtime Speech-to-Text (STT) WebSocket

Stream microphone audio to Saaras real-time STT over WebSockets:

```swift
import Sarvam

let config = SttRealtimeConfig(
    languageCode: .hiIn,
    model: .saarasV3Realtime,
    sampleRate: 16000
)

let session = try await client.speechToText.connect(config: config)

// Background event listener task
Task {
    for try await event in session.events {
        switch event {
        case .transcriptPartial(_, let text, _):
            print("Partial: \(text)")
        case .transcriptFinal(_, let text, let lang, _, _, _):
            print("Final: \(text) [\(lang?.rawValue ?? "auto")]")
        case .vadSpeechStart:
            print("User began speaking")
        case .vadSpeechEnd:
            print("User paused speaking")
        default:
            break
        }
    }
}

// Stream 16kHz mono linear PCM chunks
try await session.sendAudio(pcmData)

// Close stream when finished
try await session.end()
```

---

## 6. Automated Sub-20ms Barge-In

Automatically halt and flush audio player hardware buffers when the user starts speaking:

```swift
import Sarvam
import SarvamAudio

let player = SarvamAudioPlayer(driver: playbackDriver)
let coordinator = BargeInCoordinator {
    print("Barge-in: player stopped and flushed in <20ms")
}

// Attach coordinator to active STT session and player
coordinator.attach(session: sttSession, player: player)

// Stream TTS audio to player
try await player.playStream(client.textToSpeech.stream(ttsRequest))
```

---

## 7. Chat V2 with Stateful `ChatSession`

Maintain multi-turn conversation affinity using `x-session-affinity`:

```swift
import Sarvam

let session = client.chat.createSession()

let request = ChatCompletionRequest(
    model: .sarvam105b,
    messages: [
        ChatMessage(role: "user", content: "Tell me a joke in Hindi.")
    ]
)

for try await chunk in session.completionsV2Stream(request) {
    if let delta = chunk.firstDeltaContent {
        print(delta, terminator: "")
    }
}
print()
```

---

## 8. Document AI (`digitiseAndWait`)

Upload documents (PDF, image) and poll to completion in a single call:

```swift
import Sarvam

let file = FileInput(fileURL: localPdfUrl, mimeType: "application/pdf")

// Uploads and polls until completed, failed, or timed out
let status = try await client.docAi.digitiseAndWait(file: file)
print("Job \(status.jobId) finished with status: \(status.status)")

// Retrieve presigned download URL
let download = try await client.docAi.getDownloadUrl(jobId: status.jobId)
print("Download result from: \(download.downloadUrl)")
```
