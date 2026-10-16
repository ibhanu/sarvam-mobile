package ai.sarvam.samples.voicedemo

import android.Manifest
import android.content.pm.PackageManager
import android.os.Bundle
import android.widget.Toast
import androidx.activity.ComponentActivity
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.compose.setContent
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.animation.AnimatedVisibility
import androidx.compose.animation.animateColorAsState
import androidx.compose.animation.core.animateFloatAsState
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Mic
import androidx.compose.material.icons.filled.MicOff
import androidx.compose.material.icons.filled.PlayArrow
import androidx.compose.material.icons.filled.Stop
import androidx.compose.material3.Button
import androidx.compose.material3.ButtonDefaults
import androidx.compose.material3.Card
import androidx.compose.material3.CardDefaults
import androidx.compose.material3.DropdownMenuItem
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.ExposedDropdownMenuBox
import androidx.compose.material3.ExposedDropdownMenuDefaults
import androidx.compose.material3.Icon
import androidx.compose.material3.LinearProgressIndicator
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.material3.TopAppBar
import androidx.compose.material3.TopAppBarDefaults
import androidx.compose.runtime.Composable
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableFloatStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.font.FontStyle
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.core.content.ContextCompat
import ai.sarvam.SarvamClient
import ai.sarvam.audio.AndroidAudioRecordCaptureDriver
import ai.sarvam.audio.AndroidAudioTrackPlaybackDriver
import ai.sarvam.audio.BargeInCoordinator
import ai.sarvam.audio.SarvamAudioPlayer
import ai.sarvam.audio.SarvamMicStreamer
import ai.sarvam.core.auth.ApiKeyAuth
import ai.sarvam.core.auth.AuthToken
import ai.sarvam.core.auth.TokenAuth
import ai.sarvam.generated.AudioCodec
import ai.sarvam.generated.LanguageCode
import ai.sarvam.generated.Speaker
import ai.sarvam.generated.SttModel
import ai.sarvam.generated.TtsModel
import ai.sarvam.models.SttRealtimeConfig
import ai.sarvam.models.SttRealtimeEvent
import ai.sarvam.models.TextToSpeechRequest
import ai.sarvam.session.SttRealtimeSession
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext

/**
 * Sarvam Voice Demo: Live Indic Captions + Translate-and-Speak
 *
 * Demonstrates:
 * 1. Mobile auth security with TokenAuth (or ApiKeyAuth for quick prototyping).
 * 2. Hardware mic streaming via SarvamMicStreamer + PcmResampler to 16 kHz.
 * 3. Realtime STT WebSocket with server-side VAD, partial & final transcripts.
 * 4. Sub-20ms audio interruption via BargeInCoordinator.
 * 5. Instant Indic translation and low-latency AudioTrack playback.
 */
class MainActivity : ComponentActivity() {

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)

        // Initialize Sarvam Client
        // In production: use TokenAuth fetching ephemeral tokens from your secure backend
        val client = SarvamClient.builder()
            .authProvider(
                // Replace with your TokenAuth backend provider or demo key:
                ApiKeyAuth(apiKey = BuildConfig_SARVAM_KEY)
            )
            .build()

        setContent {
            MaterialTheme {
                SarvamVoiceScreen(client = client)
            }
        }
    }

    companion object {
        // For development only. In production, use TokenAuth with backend token minting.
        const val BuildConfig_SARVAM_KEY = "YOUR_SARVAM_API_KEY_HERE"
    }
}

data class SupportedLanguage(
    val label: String,
    val code: LanguageCode
)

val INDIC_LANGUAGES = listOf(
    SupportedLanguage("Hindi (हिन्दी)", LanguageCode.HI_IN),
    SupportedLanguage("Tamil (தமிழ்)", LanguageCode.TA_IN),
    SupportedLanguage("Telugu (తెలుగు)", LanguageCode.TE_IN),
    SupportedLanguage("Bengali (বাংলা)", LanguageCode.BN_IN),
    SupportedLanguage("Kannada (ಕನ್ನಡ)", LanguageCode.KN_IN),
    SupportedLanguage("Malayalam (മലയാളം)", LanguageCode.ML_IN),
    SupportedLanguage("Marathi (मराठी)", LanguageCode.MR_IN),
    SupportedLanguage("Gujarati (ગુજરાતી)", LanguageCode.GU_IN),
    SupportedLanguage("Punjabi (ਪੰਜਾਬੀ)", LanguageCode.PA_IN),
    SupportedLanguage("Odia (ଓଡ଼ିଆ)", LanguageCode.OR_IN),
    SupportedLanguage("English (India)", LanguageCode.EN_IN)
)

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun SarvamVoiceScreen(client: SarvamClient) {
    val context = LocalContext.current
    val scope = rememberCoroutineScope()

    // State
    var isListening by remember { mutableStateOf(false) }
    var isPlaying by remember { mutableStateOf(false) }
    var audioLevel by remember { mutableFloatStateOf(0.0f) }
    var sourceLanguage by remember { mutableStateOf(INDIC_LANGUAGES[0]) } // Hindi default
    var targetLanguage by remember { mutableStateOf(INDIC_LANGUAGES[10]) } // English default

    var partialTranscript by remember { mutableStateOf("") }
    var finalTranscript by remember { mutableStateOf("") }
    var translatedText by remember { mutableStateOf("") }
    var statusText by remember { mutableStateOf("Ready to listen") }

    // Audio hardware components
    val micStreamer = remember {
        SarvamMicStreamer(
            driver = AndroidAudioRecordCaptureDriver(sampleRate = 16000, channelCount = 1),
            onAudioLevel = { level ->
                audioLevel = level.normalized
            }
        )
    }

    val audioPlayer = remember {
        SarvamAudioPlayer(
            driver = AndroidAudioTrackPlaybackDriver(sampleRate = 16000, channelCount = 1)
        )
    }

    var sttSession by remember { mutableStateOf<SttRealtimeSession?>(null) }
    var bargeInJob by remember { mutableStateOf<Job?>(null) }
    var sttEventsJob by remember { mutableStateOf<Job?>(null) }

    // Barge-in coordinator to instantly flush audio playback when user speaks
    val bargeInCoordinator = remember {
        BargeInCoordinator(
            onBargeIn = {
                isPlaying = false
                statusText = "Barge-in: playback stopped"
            }
        )
    }

    // Function to stop listening and clean up session
    fun stopListening() {
        isListening = false
        audioLevel = 0.0f
        statusText = "Idle"
        micStreamer.stop()
        bargeInJob?.cancel()
        sttEventsJob?.cancel()
        sttSession?.close()
        sttSession = null
    }

    // Function to translate and speak the finalized transcript
    fun translateAndSpeak(textToTranslate: String) {
        if (textToTranslate.isBlank()) return

        scope.launch(Dispatchers.IO) {
            try {
                withContext(Dispatchers.Main) {
                    statusText = "Translating to ${targetLanguage.label}..."
                }

                val translation = client.text.translate(
                    input = textToTranslate,
                    targetLanguageCode = targetLanguage.code,
                    sourceLanguageCode = sourceLanguage.code
                )

                val translated = translation.translatedText
                withContext(Dispatchers.Main) {
                    translatedText = translated
                    statusText = "Synthesizing speech (${targetLanguage.label})..."
                    isPlaying = true
                }

                val ttsResponse = client.textToSpeech.convert(
                    TextToSpeechRequest(
                        text = translated,
                        targetLanguageCode = targetLanguage.code,
                        speaker = Speaker.ANUSHKA,
                        model = TtsModel.BULBUL_V4_FLASH,
                        speechSampleRate = 16000,
                        outputAudioCodec = AudioCodec.WAV
                    )
                )

                val audioBytes = ttsResponse.audioBytes
                if (audioBytes.isNotEmpty()) {
                    withContext(Dispatchers.Main) {
                        statusText = "Playing audio..."
                    }
                    audioPlayer.play(audioBytes)
                }

                withContext(Dispatchers.Main) {
                    isPlaying = false
                    statusText = "Done playing"
                }
            } catch (e: Exception) {
                withContext(Dispatchers.Main) {
                    isPlaying = false
                    statusText = "Error: ${e.localizedMessage}"
                }
            }
        }
    }

    // Function to start listening via WebSocket STT
    fun startListening() {
        scope.launch {
            try {
                statusText = "Connecting to Sarvam STT WebSocket..."
                partialTranscript = ""

                val session = client.speechToText.connect(
                    SttRealtimeConfig(
                        languageCode = sourceLanguage.code,
                        model = SttModel.SAARAS_V3_REALTIME,
                        sampleRate = 16000
                    )
                )
                sttSession = session
                isListening = true
                statusText = "Listening (${sourceLanguage.label})..."

                // Attach Barge-in coordinator to STT session
                bargeInJob = bargeInCoordinator.attach(session, audioPlayer, scope)

                // Start hardware mic capture
                micStreamer.start(scope = scope, session = session)

                // Process STT events
                sttEventsJob = launch {
                    session.events.collect { event ->
                        when (event) {
                            is SttRealtimeEvent.TranscriptPartial -> {
                                partialTranscript = event.text
                            }
                            is SttRealtimeEvent.TranscriptFinal -> {
                                partialTranscript = ""
                                finalTranscript = event.text
                                statusText = "Captured final speech"
                                // Automatically translate and speak
                                translateAndSpeak(event.text)
                            }
                            is SttRealtimeEvent.VadSpeechStart -> {
                                statusText = "Speech detected..."
                            }
                            is SttRealtimeEvent.VadSpeechEnd -> {
                                statusText = "Speech ended, processing..."
                            }
                            is SttRealtimeEvent.Error -> {
                                statusText = "STT Error: ${event.message}"
                                stopListening()
                            }
                            else -> Unit
                        }
                    }
                }
            } catch (e: Exception) {
                statusText = "Connection error: ${e.localizedMessage}"
                stopListening()
            }
        }
    }

    // Permission launcher for RECORD_AUDIO
    val permissionLauncher = rememberLauncherForActivityResult(
        contract = ActivityResultContracts.RequestPermission()
    ) { isGranted ->
        if (isGranted) {
            startListening()
        } else {
            Toast.makeText(context, "Microphone permission required for voice demo", Toast.LENGTH_SHORT).show()
        }
    }

    // Clean up hardware resources on dispose
    DisposableEffect(Unit) {
        onDispose {
            stopListening()
            audioPlayer.close()
            micStreamer.close()
        }
    }

    Scaffold(
        topBar = {
            TopAppBar(
                title = { Text("Sarvam Indic Voice Demo", fontWeight = FontWeight.Bold) },
                colors = TopAppBarDefaults.topAppBarColors(
                    containerColor = MaterialTheme.colorScheme.primaryContainer,
                    titleContentColor = MaterialTheme.colorScheme.onPrimaryContainer
                )
            )
        }
    ) { paddingValues ->
        Column(
            modifier = Modifier
                .fillMaxSize()
                .padding(paddingValues)
                .padding(16.dp)
                .verticalScroll(rememberScrollState()),
            verticalArrangement = Arrangement.spacedBy(16.dp)
        ) {
            // Status bar
            Card(
                colors = CardDefaults.cardColors(containerColor = MaterialTheme.colorScheme.surfaceVariant),
                modifier = Modifier.fillMaxWidth()
            ) {
                Row(
                    modifier = Modifier.padding(12.dp),
                    verticalAlignment = Alignment.CenterVertically
                ) {
                    Box(
                        modifier = Modifier
                            .size(10.dp)
                            .clip(CircleShape)
                            .background(if (isListening) Color(0xFF4CAF50) else Color(0xFF9E9E9E))
                    )
                    Spacer(modifier = Modifier.width(8.dp))
                    Text(text = statusText, fontSize = 14.sp, color = MaterialTheme.colorScheme.onSurfaceVariant)
                }
            }

            // Language Selector Row
            Row(
                modifier = Modifier.fillMaxWidth(),
                horizontalArrangement = Arrangement.spacedBy(8.dp)
            ) {
                LanguageDropdown(
                    modifier = Modifier.weight(1f),
                    label = "Speak In",
                    selected = sourceLanguage,
                    enabled = !isListening,
                    onSelected = { sourceLanguage = it }
                )
                LanguageDropdown(
                    modifier = Modifier.weight(1f),
                    label = "Translate To",
                    selected = targetLanguage,
                    enabled = !isListening,
                    onSelected = { targetLanguage = it }
                )
            }

            // Mic Streaming Visualizer
            AnimatedVisibility(visible = isListening) {
                Column(modifier = Modifier.fillMaxWidth()) {
                    Text(
                        text = "Microphone Level",
                        fontSize = 12.sp,
                        color = MaterialTheme.colorScheme.outline
                    )
                    Spacer(modifier = Modifier.height(4.dp))
                    val animatedProgress by animateFloatAsState(targetValue = audioLevel, label = "audioLevel")
                    LinearProgressIndicator(
                        progress = { animatedProgress },
                        modifier = Modifier
                            .fillMaxWidth()
                            .height(8.dp)
                            .clip(RoundedCornerShape(4.dp)),
                    )
                }
            }

            // Live Captions Card (STT)
            Card(
                modifier = Modifier.fillMaxWidth(),
                colors = CardDefaults.cardColors(containerColor = MaterialTheme.colorScheme.surface)
            ) {
                Column(modifier = Modifier.padding(16.dp)) {
                    Row(
                        modifier = Modifier.fillMaxWidth(),
                        horizontalArrangement = Arrangement.SpaceBetween,
                        verticalAlignment = Alignment.CenterVertically
                    ) {
                        Text(
                            text = "Live Speech Captions (${sourceLanguage.label.split(" ")[0]})",
                            fontWeight = FontWeight.SemiBold,
                            fontSize = 15.sp,
                            color = MaterialTheme.colorScheme.primary
                        )
                        if (isListening) {
                            Text(text = "LIVE", fontSize = 11.sp, fontWeight = FontWeight.Bold, color = Color.Red)
                        }
                    }

                    Spacer(modifier = Modifier.height(8.dp))

                    if (finalTranscript.isEmpty() && partialTranscript.isEmpty()) {
                        Text(
                            text = "Tap 'Start Speaking' and speak in ${sourceLanguage.label.split(" ")[0]}...",
                            color = MaterialTheme.colorScheme.outline,
                            fontStyle = FontStyle.Italic
                        )
                    } else {
                        if (finalTranscript.isNotEmpty()) {
                            Text(text = finalTranscript, fontSize = 16.sp, fontWeight = FontWeight.Medium)
                        }
                        if (partialTranscript.isNotEmpty()) {
                            Text(
                                text = partialTranscript,
                                fontSize = 16.sp,
                                fontStyle = FontStyle.Italic,
                                color = MaterialTheme.colorScheme.outline
                            )
                        }
                    }
                }
            }

            // Translation & Speech Card
            Card(
                modifier = Modifier.fillMaxWidth(),
                colors = CardDefaults.cardColors(containerColor = MaterialTheme.colorScheme.secondaryContainer.copy(alpha = 0.4f))
            ) {
                Column(modifier = Modifier.padding(16.dp)) {
                    Text(
                        text = "Translated & Spoken (${targetLanguage.label.split(" ")[0]})",
                        fontWeight = FontWeight.SemiBold,
                        fontSize = 15.sp,
                        color = MaterialTheme.colorScheme.secondary
                    )
                    Spacer(modifier = Modifier.height(8.dp))

                    if (translatedText.isEmpty()) {
                        Text(
                            text = "Translation will appear and play automatically...",
                            color = MaterialTheme.colorScheme.outline,
                            fontStyle = FontStyle.Italic
                        )
                    } else {
                        Text(text = translatedText, fontSize = 16.sp, fontWeight = FontWeight.Medium)
                    }

                    Spacer(modifier = Modifier.height(12.dp))

                    Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                        Button(
                            onClick = { translateAndSpeak(finalTranscript) },
                            enabled = finalTranscript.isNotBlank() && !isPlaying,
                            modifier = Modifier.weight(1f)
                        ) {
                            Icon(Icons.Default.PlayArrow, contentDescription = "Replay")
                            Spacer(modifier = Modifier.width(4.dp))
                            Text("Replay Audio")
                        }

                        if (isPlaying) {
                            Button(
                                onClick = {
                                    audioPlayer.stopAndFlush()
                                    isPlaying = false
                                    statusText = "Playback stopped manually"
                                },
                                colors = ButtonDefaults.buttonColors(containerColor = MaterialTheme.colorScheme.error)
                            ) {
                                Icon(Icons.Default.Stop, contentDescription = "Stop")
                                Spacer(modifier = Modifier.width(4.dp))
                                Text("Stop")
                            }
                        }
                    }
                }
            }

            Spacer(modifier = Modifier.weight(1f, fill = false))

            // Main Microphone Toggle Button
            val buttonColor by animateColorAsState(
                targetValue = if (isListening) MaterialTheme.colorScheme.error else MaterialTheme.colorScheme.primary,
                label = "buttonColor"
            )

            Button(
                onClick = {
                    if (isListening) {
                        stopListening()
                    } else {
                        val hasMicPermission = ContextCompat.checkSelfPermission(
                            context,
                            Manifest.permission.RECORD_AUDIO
                        ) == PackageManager.PERMISSION_GRANTED

                        if (hasMicPermission) {
                            startListening()
                        } else {
                            permissionLauncher.launch(Manifest.permission.RECORD_AUDIO)
                        }
                    }
                },
                modifier = Modifier
                    .fillMaxWidth()
                    .height(56.dp),
                shape = RoundedCornerShape(28.dp),
                colors = ButtonDefaults.buttonColors(containerColor = buttonColor)
            ) {
                Icon(
                    imageVector = if (isListening) Icons.Default.MicOff else Icons.Default.Mic,
                    contentDescription = if (isListening) "Stop" else "Start",
                    modifier = Modifier.size(24.dp)
                )
                Spacer(modifier = Modifier.width(8.dp))
                Text(
                    text = if (isListening) "Stop Listening" else "Start Speaking (${sourceLanguage.label.split(" ")[0]})",
                    fontSize = 16.sp,
                    fontWeight = FontWeight.Bold
                )
            }
        }
    }
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun LanguageDropdown(
    modifier: Modifier = Modifier,
    label: String,
    selected: SupportedLanguage,
    enabled: Boolean,
    onSelected: (SupportedLanguage) -> Unit
) {
    var expanded by remember { mutableStateOf(false) }

    ExposedDropdownMenuBox(
        expanded = expanded && enabled,
        onExpandedChange = { if (enabled) expanded = !expanded },
        modifier = modifier
    ) {
        OutlinedTextField(
            value = selected.label.split(" ")[0],
            onValueChange = {},
            readOnly = true,
            label = { Text(label, fontSize = 12.sp) },
            trailingIcon = { ExposedDropdownMenuDefaults.TrailingIcon(expanded = expanded) },
            modifier = Modifier.menuAnchor(),
            enabled = enabled,
            singleLine = true
        )

        ExposedDropdownMenu(
            expanded = expanded && enabled,
            onDismissRequest = { expanded = false }
        ) {
            INDIC_LANGUAGES.forEach { lang ->
                DropdownMenuItem(
                    text = { Text(lang.label) },
                    onClick = {
                        onSelected(lang)
                        expanded = false
                    }
                )
            }
        }
    }
}
