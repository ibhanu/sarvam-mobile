import React, { useState, useEffect, useRef, useCallback } from 'react';
import {
  SafeAreaView,
  ScrollView,
  View,
  Text,
  TextInput,
  TouchableOpacity,
  StyleSheet,
  ActivityIndicator,
  StatusBar,
  Alert,
} from 'react-native';
import {
  SarvamReactNativeClient,
  SttRealtimeSession,
  SttRealtimeEvent,
  SarvamAudioPlayer,
  SarvamAudioRecorder,
  BargeInCoordinator,
  ReactNativeAudioDriver,
  PcmResampler,
  LanguageCode,
  SttModel,
  Speaker,
  TtsStreamingSession,
} from '@sarvam/react-native';

// Available Indic languages supported by Sarvam AI
const INDIC_LANGUAGES: Array<{ label: string; code: LanguageCode }> = [
  { label: 'Hindi (हिन्दी)', code: 'hi-IN' },
  { label: 'Bengali (বাংলা)', code: 'bn-IN' },
  { label: 'Tamil (தமிழ்)', code: 'ta-IN' },
  { label: 'Telugu (తెలుగు)', code: 'te-IN' },
  { label: 'Kannada (ಕನ್ನಡ)', code: 'kn-IN' },
  { label: 'Marathi (मराठी)', code: 'mr-IN' },
  { label: 'Gujarati (ગુજરાતી)', code: 'gu-IN' },
  { label: 'English (India)', code: 'en-IN' },
];

/**
 * Universal Mock/Bridge Audio Driver.
 * Provides immediate simulated mic chunks and player handling so the example
 * runs out of the box in Expo Go, Simulator, or Web without native audio crashes.
 *
 * In production with real microphone and speaker hardware, replace with:
 * `react-native-audio-api`, `expo-audio`, or custom C++ Turbo/Nitro modules.
 */
class ExampleAudioDriver implements ReactNativeAudioDriver {
  private recordingInterval: any = null;
  private isRec = false;
  private isPlaying = false;
  private pcmChunkHandler: ((chunk: Float32Array) => void) | null = null;

  startRecording(onAudioData: (pcmChunk: Float32Array) => void): void {
    this.isRec = true;
    this.pcmChunkHandler = onAudioData;

    // Simulate 48kHz audio capture (100ms frames = 4800 samples)
    // Produces gentle synthetic sine/ambient activity for demo visualization
    let phase = 0;
    this.recordingInterval = setInterval(() => {
      if (!this.isRec || !this.pcmChunkHandler) return;
      const frame = new Float32Array(4800);
      for (let i = 0; i < frame.length; i++) {
        frame[i] = Math.sin(phase) * 0.15 + (Math.random() - 0.5) * 0.02;
        phase += 0.05;
      }
      this.pcmChunkHandler(frame);
    }, 100);
  }

  stopRecording(): void {
    this.isRec = false;
    if (this.recordingInterval) {
      clearInterval(this.recordingInterval);
      this.recordingInterval = null;
    }
    this.pcmChunkHandler = null;
  }

  playChunk(pcmBytes: Uint8Array): void {
    this.isPlaying = true;
    // In production, send `pcmBytes` to native AudioTrack / AVAudioEngine
  }

  stopPlayback(): void {
    this.isPlaying = false;
  }

  flushPlayback(): void {
    this.isPlaying = false;
  }

  getSampleRate(): number {
    return 48000;
  }

  getChannels(): number {
    return 1;
  }
}

export default function App() {
  // Client instance
  const [apiKey, setApiKey] = useState('YOUR_SARVAM_API_KEY');
  const [targetLanguage, setTargetLanguage] = useState<LanguageCode>('hi-IN');

  // Realtime STT State
  const [isRecording, setIsRecording] = useState(false);
  const [sttStatus, setSttStatus] = useState<'idle' | 'connecting' | 'listening' | 'error'>('idle');
  const [partialTranscript, setPartialTranscript] = useState('');
  const [finalTranscripts, setFinalTranscripts] = useState<string[]>([]);
  const [rmsLevel, setRmsLevel] = useState(0);
  const [isSpeakingVad, setIsSpeakingVad] = useState(false);

  // Translation & TTS State
  const [inputText, setInputText] = useState('Welcome to Sarvam AI. Experience speech and translation across India.');
  const [translatedText, setTranslatedText] = useState('');
  const [isTranslating, setIsTranslating] = useState(false);
  const [isSynthesizing, setIsSynthesizing] = useState(false);
  const [bargeInOccurred, setBargeInOccurred] = useState(false);

  // Audio & SDK Controller Refs
  const clientRef = useRef<SarvamReactNativeClient | null>(null);
  const audioDriverRef = useRef<ExampleAudioDriver>(new ExampleAudioDriver());
  const playerRef = useRef<SarvamAudioPlayer | null>(null);
  const recorderRef = useRef<SarvamAudioRecorder | null>(null);
  const sttSessionRef = useRef<SttRealtimeSession | null>(null);
  const bargeInCoordinatorRef = useRef<BargeInCoordinator | null>(null);
  const ttsSessionRef = useRef<TtsStreamingSession | null>(null);

  // Initialize Audio Player & Recorder
  useEffect(() => {
    const driver = audioDriverRef.current;
    const player = new SarvamAudioPlayer({ driver });
    playerRef.current = player;

    const recorder = new SarvamAudioRecorder({
      driver,
      onRmsLevel: (rms) => setRmsLevel(rms),
      onDroppedFrame: (dropped) => console.warn(`Dropped ${dropped} audio frames under backpressure`),
    });
    recorderRef.current = recorder;

    return () => {
      recorder.stop();
      player.stopAndFlush();
      sttSessionRef.current?.close();
      ttsSessionRef.current?.close();
    };
  }, []);

  // Update Sarvam Client when API Key changes
  const getClient = useCallback(() => {
    if (!clientRef.current || clientRef.current['authProvider'] === undefined) {
      clientRef.current = new SarvamReactNativeClient({
        apiKey: apiKey.trim(),
      });
    }
    return clientRef.current;
  }, [apiKey]);

  // Toggle Realtime STT Captions
  const toggleLiveTranscription = async () => {
    if (isRecording) {
      // Stop Session
      recorderRef.current?.stop();
      sttSessionRef.current?.end();
      bargeInCoordinatorRef.current?.stop();
      setIsRecording(false);
      setSttStatus('idle');
      setIsSpeakingVad(false);
      setRmsLevel(0);
      return;
    }

    try {
      setSttStatus('connecting');
      const client = getClient();

      // 1. Connect to Realtime STT WebSocket
      const session = await client.speechToText.connect({
        model: SttModel.SAARAS_V3_REALTIME,
        language_code: targetLanguage,
        sample_rate: 16000,
        endpointing: true,
        threshold: 0.5,
      });
      sttSessionRef.current = session;

      // 2. Attach Barge-In Coordinator (cuts off TTS if user talks!)
      if (playerRef.current) {
        const coordinator = new BargeInCoordinator({
          session,
          player: playerRef.current,
          onBargeIn: () => {
            setBargeInOccurred(true);
            setIsSynthesizing(false);
            setTimeout(() => setBargeInOccurred(false), 2500);
          },
        });
        coordinator.start();
        bargeInCoordinatorRef.current = coordinator;
      }

      // 3. Pipe audio recorder frames to WebSocket
      recorderRef.current?.pipeTo(session);
      await recorderRef.current?.start();

      setIsRecording(true);
      setSttStatus('listening');

      // 4. Listen for real-time transcription & VAD events
      (async () => {
        try {
          for await (const event of session.events) {
            if (event.type === 'transcript_partial') {
              setPartialTranscript(event.text);
            } else if (event.type === 'transcript_final') {
              setFinalTranscripts((prev) => [...prev, event.text]);
              setPartialTranscript('');
            } else if (event.type === 'vad_speech_start') {
              setIsSpeakingVad(true);
            } else if (event.type === 'vad_speech_end') {
              setIsSpeakingVad(false);
            }
          }
        } catch (err: any) {
          console.error('STT stream error:', err);
        } finally {
          setIsRecording(false);
          setSttStatus('idle');
          setIsSpeakingVad(false);
        }
      })();
    } catch (err: any) {
      setSttStatus('error');
      Alert.alert('Connection Failed', err?.message || 'Could not connect to Sarvam Realtime STT');
    }
  };

  // Translate text to target Indic language
  const handleTranslate = async () => {
    if (!inputText.trim()) return;
    setIsTranslating(true);
    try {
      const client = getClient();
      const res = await client.text.translate({
        input: inputText,
        target_language_code: targetLanguage,
      });
      setTranslatedText(res.translated_text);
    } catch (err: any) {
      Alert.alert('Translation Error', err?.message || 'Failed to translate');
    } finally {
      setIsTranslating(false);
    }
  };

  // Synthesize and stream speech aloud using conversational TTS WebSocket
  const handleSpeak = async () => {
    const textToSpeak = translatedText || inputText;
    if (!textToSpeak.trim()) return;

    setIsSynthesizing(true);
    setBargeInOccurred(false);

    try {
      const client = getClient();
      const player = playerRef.current!;

      // Connect to conversational TTS WebSocket
      const session = await client.textToSpeech.connect({
        language_code: targetLanguage,
        speaker: Speaker.ANUSHKA,
      });
      ttsSessionRef.current = session;

      // Attach player to stream events
      const detach = player.attachSession(session);

      // Send the text and flush
      session.sendText(textToSpeak);
      session.flush();

      // Monitor completion
      (async () => {
        for await (const event of session.events) {
          if (event.type === 'completed') {
            setIsSynthesizing(false);
            detach();
            break;
          }
        }
      })();
    } catch (err: any) {
      setIsSynthesizing(false);
      Alert.alert('TTS Error', err?.message || 'Failed to synthesize speech');
    }
  };

  const stopPlayback = () => {
    playerRef.current?.stopAndFlush();
    ttsSessionRef.current?.close();
    setIsSynthesizing(false);
  };

  return (
    <SafeAreaView style={styles.container}>
      <StatusBar barStyle="light-content" backgroundColor="#0f172a" />
      <ScrollView contentContainerStyle={styles.scrollContent} keyboardShouldPersistTaps="handled">
        {/* Header */}
        <View style={styles.header}>
          <Text style={styles.title}>Sarvam Indic Live</Text>
          <Text style={styles.subtitle}>Realtime STT Captions • Translation • Streaming TTS</Text>
        </View>

        {/* API Key Input */}
        <View style={styles.card}>
          <Text style={styles.sectionLabel}>Sarvam API Key (or TokenAuth in Prod)</Text>
          <TextInput
            style={styles.input}
            value={apiKey}
            onChangeText={setApiKey}
            placeholder="Enter Sarvam API Key"
            placeholderTextColor="#64748b"
            secureTextEntry
          />
        </View>

        {/* Language Selector */}
        <View style={styles.card}>
          <Text style={styles.sectionLabel}>Target Indic Language</Text>
          <ScrollView horizontal showsHorizontalScrollIndicator={false} style={styles.langScroll}>
            {INDIC_LANGUAGES.map((lang) => (
              <TouchableOpacity
                key={lang.code}
                style={[
                  styles.langChip,
                  targetLanguage === lang.code && styles.langChipActive,
                ]}
                onPress={() => setTargetLanguage(lang.code)}
              >
                <Text
                  style={[
                    styles.langText,
                    targetLanguage === lang.code && styles.langTextActive,
                  ]}
                >
                  {lang.label}
                </Text>
              </TouchableOpacity>
            ))}
          </ScrollView>
        </View>

        {/* SECTION 1: Live Indic Captions */}
        <View style={styles.card}>
          <View style={styles.rowBetween}>
            <Text style={styles.cardHeading}>🎙️ Live Indic Captions</Text>
            {isSpeakingVad && (
              <View style={styles.vadBadge}>
                <Text style={styles.vadText}>VAD SPEECH</Text>
              </View>
            )}
          </View>

          {/* Volume Meter */}
          <View style={styles.meterContainer}>
            <View
              style={[
                styles.meterBar,
                { width: `${Math.min(100, Math.round(rmsLevel * 100))}%` },
              ]}
            />
          </View>

          {/* Transcripts Display */}
          <View style={styles.transcriptBox}>
            {finalTranscripts.length === 0 && !partialTranscript ? (
              <Text style={styles.placeholderText}>
                {isRecording ? 'Listening for speech in ' + targetLanguage + '...' : 'Press Start Captions to begin streaming audio.'}
              </Text>
            ) : (
              <>
                {finalTranscripts.map((t, idx) => (
                  <Text key={idx} style={styles.finalText}>
                    • {t}
                  </Text>
                ))}
                {partialTranscript ? (
                  <Text style={styles.partialText}>{partialTranscript}</Text>
                ) : null}
              </>
            )}
          </View>

          {/* Captions Controls */}
          <TouchableOpacity
            style={[
              styles.primaryButton,
              isRecording ? styles.stopButton : styles.startButton,
            ]}
            onPress={toggleLiveTranscription}
          >
            {sttStatus === 'connecting' ? (
              <ActivityIndicator color="#ffffff" />
            ) : (
              <Text style={styles.buttonText}>
                {isRecording ? '⏹ Stop Live Captions' : '▶ Start Live Captions'}
              </Text>
            )}
          </TouchableOpacity>
        </View>

        {/* SECTION 2: Translate & Speak */}
        <View style={styles.card}>
          <Text style={styles.cardHeading}>🗣️ Translate-and-Speak</Text>

          {bargeInOccurred && (
            <View style={styles.bargeInBanner}>
              <Text style={styles.bargeInText}>
                ⚡ Barge-in detected! TTS playback cut off instantly by user speech.
              </Text>
            </View>
          )}

          <TextInput
            style={[styles.input, styles.textArea]}
            value={inputText}
            onChangeText={setInputText}
            placeholder="Enter text to translate and speak..."
            placeholderTextColor="#64748b"
            multiline
          />

          {finalTranscripts.length > 0 && (
            <TouchableOpacity
              style={styles.quickAction}
              onPress={() => setInputText(finalTranscripts[finalTranscripts.length - 1])}
            >
              <Text style={styles.quickActionText}>↳ Use latest transcript text</Text>
            </TouchableOpacity>
          )}

          <View style={styles.buttonRow}>
            <TouchableOpacity
              style={[styles.secondaryButton, isTranslating && styles.disabledButton]}
              onPress={handleTranslate}
              disabled={isTranslating}
            >
              {isTranslating ? (
                <ActivityIndicator color="#94a3b8" />
              ) : (
                <Text style={styles.secondaryButtonText}>🌐 Translate</Text>
              )}
            </TouchableOpacity>

            <TouchableOpacity
              style={[styles.actionButton, isSynthesizing && styles.speakingButton]}
              onPress={isSynthesizing ? stopPlayback : handleSpeak}
            >
              <Text style={styles.buttonText}>
                {isSynthesizing ? '⏹ Stop Speaking' : '🔊 Speak Aloud'}
              </Text>
            </TouchableOpacity>
          </View>

          {/* Translated Result */}
          {translatedText ? (
            <View style={styles.translationResult}>
              <Text style={styles.resultLabel}>Translated ({targetLanguage}):</Text>
              <Text style={styles.resultText}>{translatedText}</Text>
            </View>
          ) : null}
        </View>
      </ScrollView>
    </SafeAreaView>
  );
}

const styles = StyleSheet.create({
  container: {
    flex: 1,
    backgroundColor: '#0f172a',
  },
  scrollContent: {
    padding: 16,
    paddingBottom: 40,
  },
  header: {
    marginBottom: 20,
    alignItems: 'center',
  },
  title: {
    fontSize: 26,
    fontWeight: '700',
    color: '#f8fafc',
    letterSpacing: 0.5,
  },
  subtitle: {
    fontSize: 13,
    color: '#94a3b8',
    marginTop: 4,
    textAlign: 'center',
  },
  card: {
    backgroundColor: '#1e293b',
    borderRadius: 14,
    padding: 16,
    marginBottom: 16,
    borderWidth: 1,
    borderColor: '#334155',
  },
  cardHeading: {
    fontSize: 17,
    fontWeight: '600',
    color: '#f1f5f9',
    marginBottom: 12,
  },
  rowBetween: {
    flexDirection: 'row',
    justifyContent: 'space-between',
    alignItems: 'center',
  },
  sectionLabel: {
    fontSize: 12,
    fontWeight: '600',
    color: '#94a3b8',
    textTransform: 'uppercase',
    marginBottom: 8,
  },
  input: {
    backgroundColor: '#0f172a',
    borderRadius: 8,
    paddingHorizontal: 12,
    paddingVertical: 10,
    color: '#f8fafc',
    fontSize: 14,
    borderWidth: 1,
    borderColor: '#334155',
  },
  textArea: {
    height: 80,
    textAlignVertical: 'top',
  },
  langScroll: {
    flexDirection: 'row',
    marginTop: 4,
  },
  langChip: {
    paddingHorizontal: 12,
    paddingVertical: 6,
    borderRadius: 20,
    backgroundColor: '#334155',
    marginRight: 8,
  },
  langChipActive: {
    backgroundColor: '#38bdf8',
  },
  langText: {
    color: '#cbd5e1',
    fontSize: 13,
    fontWeight: '500',
  },
  langTextActive: {
    color: '#0f172a',
    fontWeight: '700',
  },
  meterContainer: {
    height: 4,
    backgroundColor: '#334155',
    borderRadius: 2,
    marginVertical: 10,
    overflow: 'hidden',
  },
  meterBar: {
    height: '100%',
    backgroundColor: '#10b981',
  },
  vadBadge: {
    backgroundColor: '#ef4444',
    paddingHorizontal: 8,
    paddingVertical: 3,
    borderRadius: 6,
  },
  vadText: {
    color: '#ffffff',
    fontSize: 10,
    fontWeight: '700',
  },
  transcriptBox: {
    backgroundColor: '#0f172a',
    borderRadius: 8,
    padding: 12,
    minHeight: 110,
    marginBottom: 12,
    borderWidth: 1,
    borderColor: '#334155',
  },
  placeholderText: {
    color: '#64748b',
    fontSize: 13,
    fontStyle: 'italic',
  },
  finalText: {
    color: '#f1f5f9',
    fontSize: 14,
    lineHeight: 20,
    marginBottom: 4,
  },
  partialText: {
    color: '#38bdf8',
    fontSize: 14,
    lineHeight: 20,
    fontStyle: 'italic',
  },
  primaryButton: {
    borderRadius: 10,
    paddingVertical: 12,
    alignItems: 'center',
    justifyContent: 'center',
  },
  startButton: {
    backgroundColor: '#0284c7',
  },
  stopButton: {
    backgroundColor: '#dc2626',
  },
  buttonText: {
    color: '#ffffff',
    fontSize: 15,
    fontWeight: '600',
  },
  buttonRow: {
    flexDirection: 'row',
    gap: 10,
    marginTop: 12,
  },
  secondaryButton: {
    flex: 1,
    backgroundColor: '#334155',
    borderRadius: 10,
    paddingVertical: 12,
    alignItems: 'center',
    justifyContent: 'center',
  },
  secondaryButtonText: {
    color: '#f8fafc',
    fontSize: 14,
    fontWeight: '600',
  },
  actionButton: {
    flex: 1,
    backgroundColor: '#16a34a',
    borderRadius: 10,
    paddingVertical: 12,
    alignItems: 'center',
    justifyContent: 'center',
  },
  speakingButton: {
    backgroundColor: '#d97706',
  },
  disabledButton: {
    opacity: 0.6,
  },
  quickAction: {
    marginTop: 6,
    marginBottom: 2,
  },
  quickActionText: {
    color: '#38bdf8',
    fontSize: 12,
  },
  translationResult: {
    marginTop: 14,
    padding: 12,
    backgroundColor: '#0f172a',
    borderRadius: 8,
    borderLeftWidth: 3,
    borderLeftColor: '#38bdf8',
  },
  resultLabel: {
    fontSize: 11,
    color: '#94a3b8',
    fontWeight: '600',
    marginBottom: 4,
  },
  resultText: {
    fontSize: 15,
    color: '#f8fafc',
    lineHeight: 22,
  },
  bargeInBanner: {
    backgroundColor: '#78350f',
    padding: 10,
    borderRadius: 8,
    marginBottom: 10,
  },
  bargeInText: {
    color: '#fef08a',
    fontSize: 12,
    fontWeight: '600',
  },
});
