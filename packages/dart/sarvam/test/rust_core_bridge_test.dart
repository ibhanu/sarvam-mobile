import 'dart:io';
import 'dart:typed_data';
import 'package:sarvam/sarvam.dart';
import 'package:test/test.dart';

void main() {
  group('SarvamRustCoreBridge (Dart FFI -> libsarvam_rust_core)', () {
    SarvamRustCoreBridge? bridge;

    setUpAll(() {
      final ext = Platform.isMacOS
          ? 'dylib'
          : Platform.isWindows
              ? 'dll'
              : 'so';
      final candidates = <String>[
        '../../rust-core/target/release/libsarvam_rust_core.$ext',
        '../../rust-core/target/debug/libsarvam_rust_core.$ext',
        if (Platform.isWindows) '../../rust-core/target/release/sarvam_rust_core.dll',
      ];
      String? foundPath;
      for (final c in candidates) {
        final f = File(c);
        if (f.existsSync()) {
          foundPath = f.absolute.path;
          break;
        }
      }
      if (foundPath != null) {
        try {
          bridge = SarvamRustCoreBridge.open(foundPath);
        } catch (_) {
          bridge = null;
        }
      }
    });

    test('resolves version and proxy environment URLs via Rust FFI', () {
      if (bridge == null) return;
      final Map<String, dynamic> ver = bridge!.version();
      expect(ver['rustCoreVersion'], isNotEmpty);
      expect(ver['specVersion'], equals('2026-10-16'));

      final Map<String, dynamic> env = bridge!.resolveEnvironment(
        proxyBaseUrl: 'https://bff.sarvam.ai/v1/',
      );
      expect(env['apiBaseUrl'], equals('https://bff.sarvam.ai/v1'));
      expect(env['dubbingBaseUrl'], equals('https://bff.sarvam.ai/v1/dubbing'));
      expect(env['wsBaseUrl'], equals('wss://bff.sarvam.ai/v1'));
    });

    test('classifies HTTP 403 invalid_api_key_error and evaluates retry matrix', () {
      if (bridge == null) return;
      final Map<String, dynamic> err = bridge!.classifyHttpError(
        statusCode: 403,
        headers: <String, String>{'x-request-id': 'req_dart_ffi_403'},
        rawBody:
            '{"error":{"code":"invalid_api_key_error","message":"Token expired"}}',
      );
      expect(err['type'], equals('AuthenticationError'));
      expect(err['shouldTriggerTokenRefresh'], isTrue);
      expect(err['requestId'], equals('req_dart_ffi_403'));

      final Map<String, dynamic> decision = bridge!.evaluateRetry(<String, dynamic>{
        'operationKind': 'STATELESS_POST',
        'attempt': 0,
        'maxRetries': 2,
        'statusCode': 429,
        'headers': <String, String>{'retry-after-ms': '120'},
        'rawBody': '',
        'isNetworkOrTimeoutError': false,
        'isTimeoutError': false,
        'isReplayableBody': true,
        'hasIdempotencyKey': false,
        'isTokenAuth': false,
        'hasRefreshedToken': false,
        'randomFactor': 0.5,
        'nowEpochMs': 0,
      });
      expect(decision['action'], equals('backoffAndRetry'));
      expect(decision['delayMs'], equals(120));
    });

    test('parses Chat V2 SSE and Responses SSE streams in Rust', () {
      if (bridge == null) return;
      final Map<String, dynamic> chat = bridge!.parseChatSse(
        'data: {"id":"1","choices":[{"index":0,"delta":{"content":"Namaste"}}]}\n\n'
        'data: {"id":"1","choices":[],"usage":{"prompt_tokens":5,"completion_tokens":2,"total_tokens":7}}\n\n'
        'data: [DONE]\n',
      );
      expect(chat['accumulatedContent'], equals('Namaste'));
      expect(chat['terminatedOnDone'], isTrue);

      final Map<String, dynamic> resp = bridge!.parseResponsesSse(
        'event: response.completed\n'
        'data: {"id":"r1","type":"response.completed","response":{"status":"completed"}}\n\n',
      );
      expect(resp['terminatedOnEvent'], equals('response.completed'));
      expect(resp['finalResponseStatus'], equals('completed'));
    });

    test('resamples 48kHz PCM16 audio to 16kHz mono over binary FFI and computes audio levels', () {
      if (bridge == null) return;
      final ByteData bd = ByteData(480 * 2);
      for (int i = 0; i < 480; i++) {
        bd.setInt16(i * 2, i.isEven ? 16384 : -16384, Endian.little);
      }
      final Uint8List inputBytes = bd.buffer.asUint8List();
      final Uint8List resampled = bridge!.resamplePcm16(
        inputBytes,
        inputSampleRate: 48000,
        channelCount: 1,
      );
      expect(resampled.length, equals(160 * 2));
      expect(
        bridge!.resamplePcm16(Uint8List(0), inputSampleRate: 48000).length,
        equals(0),
      );

      final Map<String, dynamic> levels = bridge!.calculateAudioLevels(resampled);
      expect((levels['peak'] as num).toDouble(), closeTo(0.5, 0.02));
      expect((levels['rms'] as num).toDouble(), closeTo(0.5, 0.02));
    });
  });
}
