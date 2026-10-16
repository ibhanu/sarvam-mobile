# Sarvam Indic Live — React Native / Expo Sample App

An interactive, production-ready React Native / Expo application demonstrating real-time multilingual Indic AI features using `@sarvam/react-native`:

1. **Live Indic Captions (Realtime STT)**: Streams audio to Sarvam's `saaras:v3-realtime` WebSocket model, displaying real-time partial hypotheses, final utterances, Voice Activity Detection (VAD) badges, and an RMS audio level visualizer.
2. **Translate-and-Speak (Text + Streaming TTS)**: Translates text across 11+ Indic languages and synthesizes high-quality speech using `bulbul:v4-flash` via conversational WebSocket streaming.
3. **Conversational Turn-Taking (Barge-In)**: Integrates `BargeInCoordinator` so that whenever the user starts speaking while synthesized speech is playing, the audio player halts and flushes immediately.

---

## Running with Expo

### 1. Install Dependencies

```bash
# In the example directory:
cd packages/react-native/example

# Install dependencies:
npm install
```

### 2. Start the Expo Dev Server

```bash
npx expo start
```

Press `i` to launch in the iOS Simulator, `a` for Android Emulator, or scan the QR code with the Expo Go app on your physical mobile device.

---

## Running with React Native CLI

If you are using a pure React Native bare workflow:

```bash
# For iOS:
npx pod-install
npx react-native run-ios

# For Android:
npx react-native run-android
```

---

## Architecture Walkthrough

### 1. Realtime Speech-to-Text WebSocket
The app establishes a low-latency bidirectional WebSocket connection with Sarvam's streaming speech endpoint:
```typescript
const session = await client.speechToText.connect({
  model: SttModel.SAARAS_V3_REALTIME,
  language_code: targetLanguage, // e.g., 'hi-IN'
  sample_rate: 16000,
  endpointing: true,             // Enables server-side VAD
  threshold: 0.5,
});

for await (const event of session.events) {
  if (event.type === 'transcript_partial') {
    setPartialTranscript(event.text);
  } else if (event.type === 'transcript_final') {
    setFinalTranscripts((prev) => [...prev, event.text]);
  } else if (event.type === 'vad_speech_start') {
    setIsSpeakingVad(true);
  }
}
```

### 2. Conversational Interruption (`BargeInCoordinator`)
Natural conversations require immediate audio cutoff when a speaker interrupts:
```typescript
const coordinator = new BargeInCoordinator({
  session,             // SttRealtimeSession
  player,              // SarvamAudioPlayer
  onBargeIn: () => {
    console.log('User spoke! Ongoing TTS playback stopped instantly.');
  },
});

coordinator.start();
```

### 3. Audio Driver Customization
The sample includes `ExampleAudioDriver` which simulates audio streaming so that the UI, WebSocket, state management, and visualizers run out of the box in the simulator.

To connect real hardware microphone recording and speaker playback in production:
```typescript
import { AudioContext } from 'react-native-audio-api'; // or expo-audio
import { ReactNativeAudioDriver } from '@sarvam/react-native';

class ProductionAudioDriver implements ReactNativeAudioDriver {
  private audioContext = new AudioContext();

  startRecording(onAudioData: (chunk: Float32Array) => void) {
    // Pipe native microphone PCM buffer to onAudioData
  }

  stopRecording() {
    // Release native microphone
  }

  playChunk(pcmBytes: Uint8Array) {
    // Stream PCM audio chunk to native audio output
  }

  stopPlayback() {
    // Abort active audio playback
  }
}
```

---

## License

MIT © [Sarvam AI](https://sarvam.ai)
