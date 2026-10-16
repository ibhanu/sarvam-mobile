// ignore_for_file: avoid_print
import 'dart:io';

import 'package:sarvam/sarvam.dart';

/// Clean, runnable example demonstrating Sarvam AI Dart SDK.
///
/// To run:
/// ```bash
/// SARVAM_API_KEY="your-api-key" dart run example/main.dart
/// ```
Future<void> main() async {
  // Read API key from environment, or use a placeholder for dry-run
  final apiKey =
      Platform.environment['SARVAM_API_KEY'] ?? 'mock-sarvam-api-key-example';

  print('==================================================');
  print(' Sarvam AI Dart Client Example');
  print('==================================================');

  // 1. Initialize client
  // For mobile production, prefer SarvamClient.withTokenProvider() or withProxy()!
  final client = SarvamClient.withApiKey(apiKey);

  try {
    print('\n[1/3] Translating English text to Hindi...');
    final translateRequest = const TranslateRequest(
      input: 'Welcome to Sarvam AI! Indic language AI built for everyone.',
      targetLanguageCode: LanguageCode.hiIn,
    );

    // In a live environment with an active API key, this calls the live API.
    // In local sandbox / mock mode, we catch potential exceptions gracefully.
    try {
      final translateResponse = await client.text.translate(translateRequest);
      print('Translated text: ${translateResponse.translatedText}');
    } on SarvamException catch (e) {
      print('Note: Live call skipped/failed: ${e.message} (HTTP ${e.statusCode})');
    }

    print('\n[2/3] Synthesizing speech with Bulbul V4 Flash...');
    final ttsRequest = const TextToSpeechRequest(
      text: 'नमस्ते! सर्वम एआई में आपका स्वागत है।',
      targetLanguageCode: LanguageCode.hiIn,
      speaker: Speaker.anushka,
      model: TtsModel.bulbulV4Flash,
      outputAudioCodec: AudioCodec.mp3,
    );

    try {
      final ttsResponse = await client.textToSpeech.convert(ttsRequest);
      print('Synthesized audio items: ${ttsResponse.audioCount}');
      print('First audio payload size: ${ttsResponse.firstAudioByteLength} bytes');
    } on SarvamException catch (e) {
      print('Note: Live call skipped/failed: ${e.message} (HTTP ${e.statusCode})');
    }

    print('\n[3/3] Creating a Chat Completion with Sarvam-M...');
    final chatRequest = const ChatCompletionRequest(
      model: 'sarvam-m',
      messages: <ChatMessage>[
        ChatMessage(
          role: 'system',
          content: 'You are a helpful multilingual assistant.',
        ),
        ChatMessage(
          role: 'user',
          content: 'Name three popular rivers in India.',
        ),
      ],
      temperature: 0.3,
    );

    try {
      final chatResponse = await client.chat.completions(chatRequest);
      if (chatResponse.choices.isNotEmpty) {
        final message = chatResponse.choices.first.message?.content;
        print('Chat response:\n$message');
      }
    } on SarvamException catch (e) {
      print('Note: Live call skipped/failed: ${e.message} (HTTP ${e.statusCode})');
    }

    print('\nExample execution completed successfully.');
  } on SarvamException catch (e) {
    print('Sarvam error [code=${e.code}, status=${e.statusCode}]: ${e.message}');
  } finally {
    // Always clean up resources and close connection pools
    client.close();
  }
}
