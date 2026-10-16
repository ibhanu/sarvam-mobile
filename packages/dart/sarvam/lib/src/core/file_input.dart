import 'dart:typed_data';

/// Represents a file attachment for multipart uploads or binary payloads.
///
/// Pure Dart abstraction with zero `dart:io` dependency for seamless Flutter Web support.
class SarvamFileInput {
  /// Multipart form field name (e.g. `'file'`).
  final String field;

  /// Filename reported in the Content-Disposition header.
  final String filename;

  /// Content type MIME string (e.g. `'audio/wav'`).
  final String? contentType;

  /// In-memory byte array payload if created via [SarvamFileInput.fromBytes].
  final Uint8List? bytes;

  /// Factory creating an async byte stream if created via [SarvamFileInput.fromStream].
  final Stream<List<int>> Function()? streamFactory;

  /// Length in bytes.
  final int length;

  /// Whether this file input can be re-read for HTTP retry attempts.
  final bool isReplayable;

  /// Creates a [SarvamFileInput] from in-memory bytes.
  /// Always marked as replayable.
  SarvamFileInput.fromBytes(
    this.field,
    Uint8List data, {
    this.filename = 'file',
    this.contentType,
  })  : bytes = data,
        streamFactory = null,
        length = data.length,
        isReplayable = true;

  /// Creates a [SarvamFileInput] from a stream factory.
  /// If [isReplayable] is true, [streamFactory] must return a fresh, unconsumed stream on every call.
  SarvamFileInput.fromStream(
    this.field,
    this.streamFactory,
    this.length, {
    this.filename = 'file',
    this.contentType,
    this.isReplayable = false,
  }) : bytes = null;

  /// Convenience accessor to read bytes (or null if streaming).
  Uint8List? get byteData => bytes;
}
