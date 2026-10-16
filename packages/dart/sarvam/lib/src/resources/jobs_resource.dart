import 'dart:typed_data';

import 'package:sarvam/src/generated/sarvam_spec_generated.dart';
import '../core/file_input.dart';
import '../core/middleware/middleware.dart';
import '../core/request_options.dart';
import '../core/transport.dart';

/// Resource for job lifecycle management and Azure SAS blob uploads.
class JobsResource {
  final HttpHandler _pipeline;

  JobsResource(this._pipeline);

  /// Uploads binary data to an Azure SAS signed URL, ensuring the mandatory
  /// `x-ms-blob-type: BlockBlob` header is injected.
  Future<void> uploadToSignedUrl(
    String uploadUrl,
    SarvamFileInput fileInput, {
    RequestOptions? options,
  }) async {
    final uri = Uri.parse(uploadUrl);
    final headers = <String, String>{
      'x-ms-blob-type': 'BlockBlob',
      'content-type': fileInput.contentType ?? 'application/octet-stream',
    };
    if (options?.headers != null) {
      headers.addAll(options!.headers!);
    }

    final Uint8List? bodyBytes;
    if (fileInput.bytes != null) {
      bodyBytes = fileInput.bytes;
    } else if (fileInput.streamFactory != null) {
      // Drain stream into byte array for PUT body.
      final chunks = <int>[];
      await for (final chunk in fileInput.streamFactory!()) {
        chunks.addAll(chunk);
      }
      bodyBytes = Uint8List.fromList(chunks);
    } else {
      bodyBytes = Uint8List(0); // coverage:ignore-line
    }

    final httpRequest = HttpRequest(
      url: uri,
      method: 'PUT',
      headers: headers,
      bodyBytes: bodyBytes,
      operationKind: OperationKind.idempotent,
      timeout: options?.timeout,
    );

    await _pipeline(httpRequest);
  }
}
