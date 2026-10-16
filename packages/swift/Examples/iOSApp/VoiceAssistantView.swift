import SwiftUI
import AVFoundation
import Sarvam
import SarvamAudio

// MARK: - Production Hardware Audio Drivers for iOS

#if os(iOS)
/// Hardware microphone capture driver backed by `AVAudioEngine`.
///
/// Installs a tap on the input node, converts audio to 16-bit linear PCM,
/// and feeds an internal thread-safe buffer for consumption by `SarvamMicStreamer`.
public final class CoreAudioCaptureDriver: AudioCaptureDriver, @unchecked Sendable {
    public let sampleRate: Int
    public let channelCount: Int

    private let engine = AVAudioEngine()
    private let lock = NSLock()
    private var buffer = Data()
    private var isRunning = false

    public init(sampleRate: Int = 48000, channelCount: Int = 1) {
        self.sampleRate = sampleRate
        self.channelCount = channelCount
    }

    public func start() throws {
        lock.lock()
        defer { lock.unlock() }
        guard !isRunning else { return }

        let audioSession = AVAudioSession.sharedInstance()
        try audioSession.setCategory(.playAndRecord, mode: .voiceChat, options: [.defaultToSpeaker, .allowBluetooth])
        try audioSession.setActive(true, options: .notifyOthersOnDeactivation)

        let inputNode = engine.inputNode
        let inputFormat = inputNode.inputFormat(forBus: 0)

        inputNode.installTap(onBus: 0, bufferSize: 1024, format: inputFormat) { [weak self] pcmBuffer, _ in
            guard let self = self else { return }
            guard let channelData = pcmBuffer.floatChannelData else { return }

            let frameCount = Int(pcmBuffer.frameLength)
            let channelCount = Int(pcmBuffer.format.channelCount)

            // Convert Float32 samples to 16-bit signed PCM bytes
            var pcm16Data = Data(capacity: frameCount * channelCount * 2)
            for frame in 0..<frameCount {
                for channel in 0..<channelCount {
                    let sample = channelData[channel][frame]
                    let clamped = max(-1.0, min(1.0, sample))
                    var intSample = Int16(clamped * 32767.0)
                    withUnsafeBytes(of: &intSample) { rawBytes in
                        pcm16Data.append(contentsOf: rawBytes)
                    }
                }
            }

            self.lock.lock()
            self.buffer.append(pcm16Data)
            self.lock.unlock()
        }

        try engine.start()
        isRunning = true
    }

    public func read(length: Int) throws -> Data? {
        lock.lock()
        defer { lock.unlock() }
        guard isRunning else { return nil }

        if buffer.isEmpty {
            return Data()
        }

        let bytesToRead = min(length, buffer.count)
        let chunk = buffer.prefix(bytesToRead)
        buffer.removeFirst(bytesToRead)
        return Data(chunk)
    }

    public func stop() {
        lock.lock()
        defer { lock.unlock() }
        guard isRunning else { return }
        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
        buffer.removeAll()
        isRunning = false
    }
}

/// Hardware audio playback driver backed by `AVAudioEngine` and `AVAudioPlayerNode`.
///
/// Provides sub-20ms buffer flushing for instant interruption when barge-in is triggered.
public final class CoreAudioPlaybackDriver: AudioPlaybackDriver, @unchecked Sendable {
    private let engine = AVAudioEngine()
    private let playerNode = AVAudioPlayerNode()
    private let lock = NSLock()
    private var _isPlaying = false
    private let audioFormat: AVAudioFormat

    public init(sampleRate: Double = 22050, channels: AVAudioChannelCount = 1) {
        self.audioFormat = AVAudioFormat(
            commonFormat: .pcmFormatInt16,
            sampleRate: sampleRate,
            channels: channels,
            interleaved: true
        ) ?? AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: channels)!

        engine.attach(playerNode)
        engine.connect(playerNode, to: engine.mainMixerNode, format: audioFormat)
    }

    public var isPlaying: Bool {
        lock.lock()
        defer { lock.unlock() }
        return _isPlaying && playerNode.isPlaying
    }

    public func start() throws {
        lock.lock()
        defer { lock.unlock() }
        guard !_isPlaying else { return }

        let audioSession = AVAudioSession.sharedInstance()
        try audioSession.setCategory(.playAndRecord, mode: .voiceChat, options: [.defaultToSpeaker, .allowBluetooth])
        try audioSession.setActive(true)

        if !engine.isRunning {
            try engine.start()
        }
        playerNode.play()
        _isPlaying = true
    }

    public func write(data: Data) throws -> Int {
        lock.lock()
        defer { lock.unlock() }
        guard _isPlaying, !data.isEmpty else { return 0 }

        let bytesPerFrame = Int(audioFormat.streamDescription.pointee.mBytesPerFrame)
        guard bytesPerFrame > 0 else { return 0 }
        let frameCount = UInt32(data.count / bytesPerFrame)
        guard frameCount > 0 else { return 0 }

        guard let buffer = AVAudioPCMBuffer(pcmFormat: audioFormat, frameCapacity: frameCount) else {
            return 0
        }
        buffer.frameLength = frameCount

        data.withUnsafeBytes { rawPtr in
            guard let baseAddress = rawPtr.baseAddress else { return }
            memcpy(buffer.int16ChannelData?[0], baseAddress, data.count)
        }

        playerNode.scheduleBuffer(buffer, completionHandler: nil)
        return data.count
    }

    public func flush() {
        lock.lock()
        defer { lock.unlock() }
        // Instantly stops queued frames and resets buffer queue (<20ms latency)
        playerNode.stop()
        if _isPlaying {
            playerNode.play()
        }
    }

    public func stop() {
        lock.lock()
        defer { lock.unlock() }
        guard _isPlaying else { return }
        playerNode.stop()
        engine.stop()
        _isPlaying = false
    }
}
#endif

// MARK: - Voice Assistant View Model

@MainActor
public final class VoiceAssistantViewModel: ObservableObject {
    @Published public var isRunning: Bool = false
    @Published public var isUserSpeaking: Bool = false
    @Published public var isBotSpeaking: Bool = false
    @Published public var partialTranscript: String = ""
    @Published public var finalTranscript: String = ""
    @Published public var translatedText: String = ""
    @Published public var audioLevelDbfs: Double = -100.0
    @Published public var audioLevelRms: Double = 0.0
    @Published public var statusMessage: String = "Tap microphone to begin"
    @Published public var bargeInCount: Int = 0

    @Published public var sourceLanguage: LanguageCode = .hiIn
    @Published public var targetLanguage: LanguageCode = .enIn

    private var client: SarvamClient?
    private var micStreamer: SarvamMicStreamer?
    private var audioPlayer: SarvamAudioPlayer?
    private var coordinator: BargeInCoordinator?
    private var activeSttSession: SttRealtimeSession?
    private var eventConsumerTask: Task<Void, Never>?

    public init() {
        configureClient()
    }

    /// Configures the SarvamClient with TokenAuth or local development key.
    private func configureClient() {
        // In production iOS apps, authenticate with short-lived tokens or BFF proxy.
        // For development/demo, replace the token provider with your real server or key.
        let auth = TokenAuth {
            // Simulated token fetch from your backend:
            AuthToken(
                token: "DEMO_EPHEMERAL_TOKEN",
                expiresAtEpochMs: Int64(Date().timeIntervalSince1970 * 1000) + 3600_000
            )
        }
        self.client = SarvamClient(authProvider: auth)
    }

    /// Starts the end-to-end Voice Assistant pipeline:
    /// Mic -> 16kHz Resampling -> STT WebSocket -> Live Translation -> TTS Stream -> Barge-in Player
    public func toggleSession() {
        if isRunning {
            stopSession()
        } else {
            startSession()
        }
    }

    public func startSession() {
        guard !isRunning else { return }

        #if os(iOS)
        AVAudioSession.sharedInstance().requestRecordPermission { [weak self] granted in
            Task { @MainActor [weak self] in
                guard let self = self else { return }
                if granted {
                    await self.launchPipeline()
                } else {
                    self.statusMessage = "Microphone permission denied"
                }
            }
        }
        #else
        Task { await launchPipeline() }
        #endif
    }

    private func launchPipeline() async {
        guard let client = self.client else { return }

        statusMessage = "Connecting to Sarvam..."
        isRunning = true
        partialTranscript = ""
        finalTranscript = ""
        translatedText = ""

        do {
            #if os(iOS)
            let captureDriver = CoreAudioCaptureDriver()
            let playbackDriver = CoreAudioPlaybackDriver()
            #else
            let captureDriver = BufferAudioCaptureDriver(data: Data())
            let playbackDriver = MemoryAudioPlaybackDriver()
            #endif

            // 1. Setup Audio Player with sub-20ms flush support
            let player = SarvamAudioPlayer(driver: playbackDriver)
            self.audioPlayer = player

            // 2. Setup Mic Streamer with level metering
            let streamer = SarvamMicStreamer(driver: captureDriver) { [weak self] level in
                Task { @MainActor [weak self] in
                    self?.audioLevelDbfs = level.dbFs
                    self?.audioLevelRms = level.rms
                }
            }
            self.micStreamer = streamer

            // 3. Connect real-time STT WebSocket
            let sttConfig = SttRealtimeConfig(
                languageCode: sourceLanguage,
                model: .saarasV3Realtime,
                sampleRate: 16000
            )
            let sttSession = try await client.speechToText.connect(config: sttConfig)
            self.activeSttSession = sttSession

            // 4. Setup BargeInCoordinator to auto-silence player on speech start
            let coordinator = BargeInCoordinator { [weak self] in
                Task { @MainActor [weak self] in
                    guard let self = self else { return }
                    self.bargeInCount += 1
                    self.isBotSpeaking = false
                    self.statusMessage = "Barge-in: playback silenced"
                }
            }
            await coordinator.attach(session: sttSession, player: player)
            self.coordinator = coordinator

            // 5. Start streaming microphone audio to STT WebSocket
            try await streamer.start(session: sttSession)

            // 6. Listen to incoming STT events
            eventConsumerTask = Task { [weak self] in
                guard let self = self else { return }
                do {
                    for try await event in sttSession.events {
                        guard !Task.isCancelled else { break }
                        await self.handleSttEvent(event)
                    }
                } catch {
                    await MainActor.run {
                        self.statusMessage = "STT Error: \(error.localizedDescription)"
                    }
                }
            }

            statusMessage = "Listening..."
        } catch {
            statusMessage = "Initialization failed: \(error.localizedDescription)"
            isRunning = false
        }
    }

    private func handleSttEvent(_ event: SttRealtimeEvent) async {
        switch event {
        case .vadSpeechStart:
            isUserSpeaking = true
            statusMessage = "User speaking..."

        case .vadSpeechEnd:
            isUserSpeaking = false
            statusMessage = "Processing speech..."

        case .transcriptPartial(_, let text, _):
            partialTranscript = text

        case .transcriptFinal(_, let text, _, _, _, _):
            partialTranscript = ""
            finalTranscript = text
            statusMessage = "Translating..."

            // Trigger translation and synthesis
            await translateAndSpeak(input: text)

        case .error(let code, let msg):
            statusMessage = "Error [\(code ?? "general")]: \(msg)"

        default:
            break
        }
    }

    /// Translates finalized speech and streams synthesis directly to the audio player.
    private func translateAndSpeak(input: String) async {
        guard let client = self.client, let player = self.audioPlayer, !input.isEmpty else { return }

        do {
            // 1. Text Translation across Indic languages
            let transRequest = TranslateRequest(
                input: input,
                sourceLanguageCode: sourceLanguage,
                targetLanguageCode: targetLanguage
            )
            let translation = try await client.text.translate(transRequest)
            translatedText = translation.translatedText
            statusMessage = "Synthesizing speech..."
            isBotSpeaking = true

            // 2. Stream synthesized audio chunks
            let ttsRequest = TextToSpeechRequest(
                text: translation.translatedText,
                targetLanguageCode: targetLanguage,
                speaker: .anushka,
                model: .bulbulV3
            )
            let audioStream = client.textToSpeech.stream(ttsRequest)

            // 3. Play stream; automatically silenced if user interrupts
            try await player.playStream(audioStream)
            statusMessage = "Listening..."
        } catch {
            statusMessage = "Translation/TTS error: \(error.localizedDescription)"
            isBotSpeaking = false
        }
    }

    public func stopSession() {
        guard isRunning else { return }
        isRunning = false
        isUserSpeaking = false
        isBotSpeaking = false
        audioLevelDbfs = -100.0
        audioLevelRms = 0.0

        eventConsumerTask?.cancel()
        eventConsumerTask = nil

        Task {
            await micStreamer?.stop()
            await audioPlayer?.stopAndFlush()
            await coordinator?.detach()
            try? await activeSttSession?.close()

            micStreamer = nil
            audioPlayer = nil
            coordinator = nil
            activeSttSession = nil
            statusMessage = "Session ended. Tap mic to restart."
        }
    }
}

// MARK: - SwiftUI User Interface

public struct VoiceAssistantView: View {
    @StateObject private var viewModel = VoiceAssistantViewModel()

    private let supportedLanguages: [(name: String, code: LanguageCode)] = [
        ("Hindi", .hiIn),
        ("English", .enIn),
        ("Bengali", .bnIn),
        ("Tamil", .taIn),
        ("Telugu", .teIn),
        ("Marathi", .mrIn),
        ("Gujarati", .guIn),
        ("Kannada", .knIn),
        ("Malayalam", .mlIn),
        ("Punjabi", .paIn),
        ("Odia", .orIn)
    ]

    public init() {}

    public var body: some View {
        NavigationView {
            VStack(spacing: 16) {
                // Header & Language Selectors
                languagePickersHeader

                Divider()

                // Live Audio Level Visualizer
                audioLevelBar

                ScrollView {
                    VStack(spacing: 16) {
                        // Live Indic Captions Card
                        captionsCard

                        // Translated & Spoken Response Card
                        translationCard
                    }
                    .padding(.horizontal)
                }

                Spacer()

                // Status Message & Barge-In Badge
                footerStatusView

                // Main Push-to-Talk / Toggle Control
                microphoneControlButton
                    .padding(.bottom, 20)
            }
            .navigationTitle("Sarvam Voice Assistant")
            .navigationBarTitleDisplayMode(.inline)
        }
    }

    private var languagePickersHeader: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text("Speak (Input)")
                    .font(.caption)
                    .foregroundColor(.secondary)
                Picker("Source", selection: $viewModel.sourceLanguage) {
                    ForEach(supportedLanguages, id: \.code) { item in
                        Text(item.name).tag(item.code)
                    }
                }
                .pickerStyle(.menu)
                .disabled(viewModel.isRunning)
            }

            Spacer()

            Image(systemName: "arrow.right.circle.fill")
                .foregroundColor(.orange)
                .font(.title2)

            Spacer()

            VStack(alignment: .trailing, spacing: 4) {
                Text("Translate (Output)")
                    .font(.caption)
                    .foregroundColor(.secondary)
                Picker("Target", selection: $viewModel.targetLanguage) {
                    ForEach(supportedLanguages, id: \.code) { item in
                        Text(item.name).tag(item.code)
                    }
                }
                .pickerStyle(.menu)
                .disabled(viewModel.isRunning)
            }
        }
        .padding(.horizontal)
        .padding(.top, 8)
    }

    private var audioLevelBar: some View {
        VStack(spacing: 4) {
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 4)
                        .fill(Color.gray.opacity(0.2))
                    RoundedRectangle(cornerRadius: 4)
                        .fill(viewModel.isUserSpeaking ? Color.green : Color.orange)
                        .frame(width: max(0, min(geo.size.width, geo.size.width * CGFloat(viewModel.audioLevelRms * 3))))
                        .animation(.linear(duration: 0.1), value: viewModel.audioLevelRms)
                }
            }
            .frame(height: 6)
            .padding(.horizontal)

            HStack {
                Text("Mic Level: \(Int(viewModel.audioLevelDbfs)) dBFS")
                    .font(.caption2)
                    .foregroundColor(.secondary)
                Spacer()
                if viewModel.bargeInCount > 0 {
                    Text("Barge-ins: \(viewModel.bargeInCount)")
                        .font(.caption2)
                        .fontWeight(.semibold)
                        .foregroundColor(.red)
                }
            }
            .padding(.horizontal)
        }
    }

    private var captionsCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Label("Live Captions (STT)", systemImage: "waveform")
                    .font(.subheadline)
                    .fontWeight(.semibold)
                    .foregroundColor(.primary)
                Spacer()
                if viewModel.isUserSpeaking {
                    Text("Speaking")
                        .font(.caption2)
                        .fontWeight(.bold)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.green.opacity(0.2))
                        .foregroundColor(.green)
                        .cornerRadius(4)
                }
            }

            if !viewModel.finalTranscript.isEmpty || !viewModel.partialTranscript.isEmpty {
                Text(viewModel.finalTranscript + " " + viewModel.partialTranscript)
                    .font(.body)
                    .foregroundColor(.primary)
            } else {
                Text("Transcripts will appear here in real time...")
                    .font(.callout)
                    .foregroundColor(.secondary)
                    .italic()
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(Color(.secondarySystemBackground))
        .cornerRadius(12)
    }

    private var translationCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Label("Translate & Speak (TTS)", systemImage: "speaker.wave.2")
                    .font(.subheadline)
                    .fontWeight(.semibold)
                    .foregroundColor(.primary)
                Spacer()
                if viewModel.isBotSpeaking {
                    Text("Playing")
                        .font(.caption2)
                        .fontWeight(.bold)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.blue.opacity(0.2))
                        .foregroundColor(.blue)
                        .cornerRadius(4)
                }
            }

            if !viewModel.translatedText.isEmpty {
                Text(viewModel.translatedText)
                    .font(.body)
                    .fontWeight(.medium)
                    .foregroundColor(.blue)
            } else {
                Text("Translated spoken audio will appear here...")
                    .font(.callout)
                    .foregroundColor(.secondary)
                    .italic()
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(Color(.secondarySystemBackground))
        .cornerRadius(12)
    }

    private var footerStatusView: some View {
        HStack {
            Circle()
                .fill(viewModel.isRunning ? Color.green : Color.gray)
                .frame(width: 8, height: 8)
            Text(viewModel.statusMessage)
                .font(.footnote)
                .foregroundColor(.secondary)
        }
    }

    private var microphoneControlButton: some View {
        Button(action: {
            viewModel.toggleSession()
        }) {
            ZStack {
                Circle()
                    .fill(viewModel.isRunning ? Color.red : Color.orange)
                    .frame(width: 72, height: 72)
                    .shadow(radius: 4)

                Image(systemName: viewModel.isRunning ? "stop.fill" : "mic.fill")
                    .font(.title)
                    .foregroundColor(.white)
            }
        }
    }
}
