import 'dart:convert';
import 'dart:ffi' as ffi;
import 'dart:io' show Platform;
import 'dart:typed_data';

typedef _AllocNative = ffi.Pointer<ffi.Uint8> Function(ffi.Size size);
typedef _AllocDart = ffi.Pointer<ffi.Uint8> Function(int size);

typedef _DeallocNative = ffi.Void Function(ffi.Pointer<ffi.Uint8> ptr, ffi.Size size);
typedef _DeallocDart = void Function(ffi.Pointer<ffi.Uint8> ptr, int size);

typedef _InvokeBytesNative = ffi.Pointer<ffi.Uint8> Function(
  ffi.Pointer<ffi.Uint8> inputPtr,
  ffi.Size inputLen,
  ffi.Pointer<ffi.Uint64> outMetaPair,
);
typedef _InvokeBytesDart = ffi.Pointer<ffi.Uint8> Function(
  ffi.Pointer<ffi.Uint8> inputPtr,
  int inputLen,
  ffi.Pointer<ffi.Uint64> outMetaPair,
);

typedef _ResamplePcm16Native = ffi.Pointer<ffi.Uint8> Function(
  ffi.Pointer<ffi.Uint8> inputPtr,
  ffi.Size inputLen,
  ffi.Uint32 inputSampleRate,
  ffi.Uint16 channelCount,
  ffi.Pointer<ffi.Uint64> outMetaPair,
);
typedef _ResamplePcm16Dart = ffi.Pointer<ffi.Uint8> Function(
  ffi.Pointer<ffi.Uint8> inputPtr,
  int inputLen,
  int inputSampleRate,
  int channelCount,
  ffi.Pointer<ffi.Uint64> outMetaPair,
);

typedef _FreeBytesNative = ffi.Void Function(
  ffi.Pointer<ffi.Uint8> ptr,
  ffi.Size len,
  ffi.Size cap,
);
typedef _FreeBytesDart = void Function(
  ffi.Pointer<ffi.Uint8> ptr,
  int len,
  int cap,
);

/// Dart FFI bridge to the shared `libsarvam_rust_core` native binary.
///
/// Uses zero third-party pub dependencies (`dart:ffi` + `sarvam_rust_alloc` directly).
class SarvamRustCoreBridge {
  /// Creates a bridge bound to an already opened [ffi.DynamicLibrary].
  SarvamRustCoreBridge(this.dylib)
      : _alloc = dylib.lookupFunction<_AllocNative, _AllocDart>('sarvam_rust_alloc'),
        _dealloc = dylib.lookupFunction<_DeallocNative, _DeallocDart>('sarvam_rust_dealloc'),
        _invokeBytes =
            dylib.lookupFunction<_InvokeBytesNative, _InvokeBytesDart>('sarvam_rust_invoke_bytes'),
        _resamplePcm16 = dylib
            .lookupFunction<_ResamplePcm16Native, _ResamplePcm16Dart>('sarvam_rust_resample_pcm16'),
        _freeBytes =
            dylib.lookupFunction<_FreeBytesNative, _FreeBytesDart>('sarvam_rust_free_bytes');

  /// Opens the shared `libsarvam_rust_core` dynamic library from [libraryPath] or platform default.
  factory SarvamRustCoreBridge.open([String? libraryPath]) {
    if (libraryPath != null && libraryPath.isNotEmpty) {
      return SarvamRustCoreBridge(ffi.DynamicLibrary.open(libraryPath));
    }
    if (Platform.isIOS) {
      return SarvamRustCoreBridge(ffi.DynamicLibrary.process());
    }
    if (Platform.isMacOS) {
      return SarvamRustCoreBridge(ffi.DynamicLibrary.open('libsarvam_rust_core.dylib'));
    }
    if (Platform.isWindows) {
      return SarvamRustCoreBridge(ffi.DynamicLibrary.open('sarvam_rust_core.dll'));
    }
    return SarvamRustCoreBridge(ffi.DynamicLibrary.open('libsarvam_rust_core.so'));
  }

  /// Underlying opened [ffi.DynamicLibrary] handle.
  final ffi.DynamicLibrary dylib;
  final _AllocDart _alloc;
  final _DeallocDart _dealloc;
  final _InvokeBytesDart _invokeBytes;
  final _ResamplePcm16Dart _resamplePcm16;
  final _FreeBytesDart _freeBytes;

  /// Invokes a command on the Rust core engine via JSON-serialized payload.
  Map<String, dynamic> invoke(Map<String, dynamic> command) {
    final Uint8List inputBytes = utf8.encode(jsonEncode(command));
    final ffi.Pointer<ffi.Uint8> inPtr = _alloc(inputBytes.length);
    final ffi.Pointer<ffi.Uint64> metaPtr = _alloc(16).cast<ffi.Uint64>();

    ffi.Pointer<ffi.Uint8> outPtr = ffi.nullptr;
    int outLen = 0;
    int outCap = 0;
    String responseJson;

    try {
      if (inputBytes.isNotEmpty) {
        inPtr.asTypedList(inputBytes.length).setAll(0, inputBytes);
      }
      outPtr = _invokeBytes(inPtr, inputBytes.length, metaPtr);
      final Uint64List meta = metaPtr.asTypedList(2);
      outLen = meta[0];
      outCap = meta[1];
      if (outPtr == ffi.nullptr || outLen == 0) {
        throw StateError('Empty response from sarvam_rust_invoke_bytes');
      }
      final Uint8List outBytes = Uint8List.fromList(outPtr.asTypedList(outLen));
      responseJson = utf8.decode(outBytes);
    } finally {
      if (inPtr != ffi.nullptr) {
        _dealloc(inPtr, inputBytes.length);
      }
      if (metaPtr != ffi.nullptr) {
        _dealloc(metaPtr.cast<ffi.Uint8>(), 16);
      }
      if (outPtr != ffi.nullptr && outCap > 0) {
        _freeBytes(outPtr, outLen, outCap);
      }
    }

    final Map<String, dynamic> decoded =
        jsonDecode(responseJson) as Map<String, dynamic>;
    if (decoded['status'] == 'err') {
      throw ArgumentError(decoded['error']?.toString() ?? 'Unknown Rust core error');
    }
    final Object? data = decoded['data'];
    if (data is Map<String, dynamic>) {
      return data;
    }
    return <String, dynamic>{'value': data};
  }

  /// Returns version metadata from the native Rust core.
  Map<String, dynamic> version() => invoke(<String, dynamic>{'op': 'version'});

  /// Resolves production or proxy environment URLs in Rust.
  Map<String, dynamic> resolveEnvironment({String? proxyBaseUrl}) =>
      invoke(<String, dynamic>{
        'op': 'resolveEnvironment',
        'proxyBaseUrl': proxyBaseUrl,
      });

  /// Classifies an HTTP status code, headers, and error payload using the canonical Sarvam error taxonomy.
  Map<String, dynamic> classifyHttpError({
    required int statusCode,
    Map<String, String> headers = const <String, String>{},
    String rawBody = '',
    int nowEpochMs = 0,
  }) =>
      invoke(<String, dynamic>{
        'op': 'classifyHttpError',
        'statusCode': statusCode,
        'headers': headers,
        'rawBody': rawBody,
        'nowEpochMs': nowEpochMs,
      });

  /// Evaluates retry policy for an operation according to the Safe Retry Matrix.
  Map<String, dynamic> evaluateRetry(Map<String, dynamic> input) =>
      invoke(<String, dynamic>{
        'op': 'evaluateRetry',
        'input': input,
      });

  /// Parses a Chat Completions V1/V2 SSE payload.
  Map<String, dynamic> parseChatSse(String rawSse) =>
      invoke(<String, dynamic>{
        'op': 'parseChatSse',
        'rawSse': rawSse,
      });

  /// Parses a Responses API (`/v2/responses`) SSE payload.
  Map<String, dynamic> parseResponsesSse(String rawSse) =>
      invoke(<String, dynamic>{
        'op': 'parseResponsesSse',
        'rawSse': rawSse,
      });

  /// Resamples little-endian PCM16 audio directly over binary FFI to 16kHz mono linear-16 LE.
  Uint8List resamplePcm16(
    Uint8List inputBytes, {
    required int inputSampleRate,
    int channelCount = 1,
  }) {
    if (inputBytes.isEmpty) {
      return Uint8List(0);
    }

    final ffi.Pointer<ffi.Uint8> inPtr = _alloc(inputBytes.length);
    final ffi.Pointer<ffi.Uint64> metaPtr = _alloc(16).cast<ffi.Uint64>();
    ffi.Pointer<ffi.Uint8> outPtr = ffi.nullptr;
    int outLen = 0;
    int outCap = 0;

    try {
      inPtr.asTypedList(inputBytes.length).setAll(0, inputBytes);
      outPtr = _resamplePcm16(
        inPtr,
        inputBytes.length,
        inputSampleRate,
        channelCount,
        metaPtr,
      );
      final Uint64List meta = metaPtr.asTypedList(2);
      outLen = meta[0];
      outCap = meta[1];
      if (outPtr == ffi.nullptr || outLen == 0) {
        return Uint8List(0);
      }
      return Uint8List.fromList(outPtr.asTypedList(outLen));
    } finally {
      _dealloc(inPtr, inputBytes.length);
      _dealloc(metaPtr.cast<ffi.Uint8>(), 16);
      if (outPtr != ffi.nullptr && outCap > 0) {
        _freeBytes(outPtr, outLen, outCap);
      }
    }
  }

  /// Calculates RMS, Peak, and dBFS audio levels for 16-bit PCM bytes.
  Map<String, dynamic> calculateAudioLevels(Uint8List pcm16Bytes) =>
      invoke(<String, dynamic>{
        'op': 'calculateAudioLevels',
        'pcm16Bytes': pcm16Bytes,
      });
}
