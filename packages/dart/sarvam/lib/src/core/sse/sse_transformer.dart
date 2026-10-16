import 'dart:async';
import 'dart:convert';

import 'sse_event.dart';

/// Parses an incoming binary chunk stream into typed [SseEvent]s.
///
/// Handles chunk buffering across arbitrary TCP boundaries, `\n\n` and `\r\n\r\n` delimiters.
/// When [isResponsesApi] is false (Chat V1/V2), terminates upon receiving `data: [DONE]`.
/// When [isResponsesApi] is true (/v2/responses), terminates cleanly upon receiving
/// `response.completed`, `response.failed`, or `response.incomplete`.
Stream<SseEvent> parseSseStream(
  Stream<List<int>> byteStream, {
  bool isResponsesApi = false,
}) async* {
  var buffer = '';

  await for (final chunk
      in byteStream.cast<List<int>>().transform(utf8.decoder)) {
    buffer += chunk;

    while (true) {
      final indexN = buffer.indexOf('\n\n');
      final indexRN = buffer.indexOf('\r\n\r\n');

      int delimiterIndex = -1;
      int delimiterLength = 0;

      if (indexN != -1 && (indexRN == -1 || indexN < indexRN)) {
        delimiterIndex = indexN;
        delimiterLength = 2;
      } else if (indexRN != -1) {
        delimiterIndex = indexRN;
        delimiterLength = 4;
      }

      if (delimiterIndex == -1) break;

      final block = buffer.substring(0, delimiterIndex);
      buffer = buffer.substring(delimiterIndex + delimiterLength);

      final event = _parseEventBlock(block);
      if (event != null) {
        if (!isResponsesApi && event.data.trim() == '[DONE]') {
          return;
        }

        yield event;

        if (isResponsesApi && _isResponsesApiTerminalEvent(event)) {
          return;
        }
      }
    }
  }

  // Handle any remaining trailing event in buffer.
  if (buffer.trim().isNotEmpty) {
    final event = _parseEventBlock(buffer);
    if (event != null) {
      if (!isResponsesApi && event.data.trim() == '[DONE]') {
        return;
      }
      yield event;
    }
  }
}

bool _isResponsesApiTerminalEvent(SseEvent event) {
  if (event.event == 'response.completed' ||
      event.event == 'response.failed' ||
      event.event == 'response.incomplete') {
    return true;
  }

  try {
    final decoded = jsonDecode(event.data);
    if (decoded is Map<String, dynamic>) {
      final type = decoded['type']?.toString();
      if (type == 'response.completed' ||
          type == 'response.failed' ||
          type == 'response.incomplete') {
        return true;
      }
    }
  } catch (_) {}

  return false;
}

SseEvent? _parseEventBlock(String block) {
  final lines = block.split(RegExp(r'\r?\n'));
  String? id;
  String? eventName;
  final dataLines = <String>[];
  int? retry;

  for (final line in lines) {
    if (line.isEmpty || line.startsWith(':')) continue;

    if (line.startsWith('event:')) {
      eventName = line.substring(6).trimLeft();
    } else if (line.startsWith('data:')) {
      dataLines.add(line.substring(5).trimLeft());
    } else if (line.startsWith('id:')) {
      id = line.substring(3).trimLeft();
    } else if (line.startsWith('retry:')) {
      retry = int.tryParse(line.substring(6).trim());
    }
  }

  if (dataLines.isEmpty && eventName == null && id == null) {
    return null;
  }

  return SseEvent(
    id: id,
    event: eventName,
    data: dataLines.join('\n'),
    retry: retry,
  );
}

/// [StreamTransformer] implementing [parseSseStream].
class SseTransformer extends StreamTransformerBase<List<int>, SseEvent> {
  final bool isResponsesApi;

  const SseTransformer({this.isResponsesApi = false});

  @override
  Stream<SseEvent> bind(Stream<List<int>> stream) =>
      parseSseStream(stream, isResponsesApi: isResponsesApi);
}
