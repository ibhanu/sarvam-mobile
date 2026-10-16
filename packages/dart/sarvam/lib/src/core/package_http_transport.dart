import 'dart:async';
import 'dart:typed_data';

import 'package:http/http.dart' as http;
import 'package:http_parser/http_parser.dart';

import 'exceptions.dart';
import 'transport.dart';

/// Implementation of [HttpTransport] backed by `package:http`.
///
/// Pure Dart implementation compatible across Flutter Android, iOS, Desktop, and Web.
class PackageHttpTransport implements HttpTransport {
  final http.Client _client;
  final bool _ownsClient;

  PackageHttpTransport({http.Client? client})
      : _client = client ?? http.Client(),
        _ownsClient = client == null;

  @override
  Future<HttpResponse> send(HttpRequest request) async {
    try {
      final http.BaseRequest httpRequest;

      if (request.files != null && request.files!.isNotEmpty) {
        final multipart = http.MultipartRequest(request.method, request.url);
        multipart.headers.addAll(request.headers);

        if (request.fields != null) {
          multipart.fields.addAll(request.fields!);
        }

        for (final file in request.files!) {
          final mediaType = file.contentType != null
              ? MediaType.parse(file.contentType!)
              : null;

          if (file.bytes != null) {
            multipart.files.add(
              http.MultipartFile.fromBytes(
                file.field,
                file.bytes!,
                filename: file.filename,
                contentType: mediaType,
              ),
            );
          } else if (file.streamFactory != null) {
            multipart.files.add(
              http.MultipartFile(
                file.field,
                file.streamFactory!(),
                file.length,
                filename: file.filename,
                contentType: mediaType,
              ),
            );
          }
        }
        httpRequest = multipart;
      } else {
        final normalRequest = http.Request(request.method, request.url);
        normalRequest.headers.addAll(request.headers);

        if (request.bodyBytes != null) {
          normalRequest.bodyBytes = request.bodyBytes!;
        }
        httpRequest = normalRequest;
      }

      Future<http.StreamedResponse> sendFuture = _client.send(httpRequest);
      if (request.timeout != null) {
        sendFuture = sendFuture.timeout(
          request.timeout!,
          onTimeout: () => throw TimeoutException(
            message:
                'Request timed out after ${request.timeout!.inMilliseconds}ms',
            phase: TimeoutPhase.total,
          ),
        );
      }

      final streamedResponse = await sendFuture;

      if (request.isStreaming) {
        return HttpResponse(
          statusCode: streamedResponse.statusCode,
          headers: streamedResponse.headers,
          bodyBytes: Uint8List(0),
          stream: streamedResponse.stream.map(Uint8List.fromList),
        );
      } else {
        final bytes = await streamedResponse.stream.toBytes();
        return HttpResponse(
          statusCode: streamedResponse.statusCode,
          headers: streamedResponse.headers,
          bodyBytes: bytes,
          stream: Stream<Uint8List>.value(bytes),
        );
      }
    } on TimeoutException {
      rethrow;
    } on Exception catch (e) {
      throw ConnectionException(
        message: 'Network connection failed: $e',
        cause: e,
      );
    }
  }

  @override
  void close() {
    if (_ownsClient) {
      _client.close();
    }
  }
}
