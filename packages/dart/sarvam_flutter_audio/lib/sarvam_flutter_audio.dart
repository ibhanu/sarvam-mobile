/// Companion audio capture, 16 kHz resampling, and audio playback for Sarvam AI Flutter apps.
library sarvam_flutter_audio;

export 'package:sarvam/sarvam.dart';

export 'src/audio_drivers.dart';
export 'src/barge_in_coordinator.dart';
export 'src/pcm_resampler.dart';
export 'src/sarvam_chunked_audio_player.dart';
export 'src/sarvam_mic_streamer.dart';

/// Current version of the Sarvam Flutter Audio companion package.
const String sarvamFlutterAudioSdkVersion = '0.1.0';
