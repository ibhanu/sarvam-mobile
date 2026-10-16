import 'dart:convert';

/// Request parameters for [ResponsesResource.createStream].
class ResponseStreamRequest {
  final String model;
  final String input;
  final Map<String, dynamic>? extra;

  const ResponseStreamRequest({
    required this.model,
    required this.input,
    this.extra,
  });

  Map<String, dynamic> toJson() => <String, dynamic>{
        'model': model,
        'input': input,
        if (extra != null) ...extra!,
      };
}

/// Structured SSE event emitted by `/v2/responses`.
class ResponseEvent {
  final String event;
  final String data;
  final Map<String, dynamic> json;

  const ResponseEvent({
    required this.event,
    required this.data,
    required this.json,
  });

  String? get type => json['type'] as String?;
  String? get id => json['id'] as String?;

  factory ResponseEvent.fromSse({required String event, required String data}) {
    Map<String, dynamic> parsed = const <String, dynamic>{};
    try {
      final decoded = jsonDecode(data);
      if (decoded is Map<String, dynamic>) {
        parsed = decoded;
      }
    } catch (_) {}

    return ResponseEvent(
      event: event,
      data: data,
      json: parsed,
    );
  }

  @override
  String toString() => 'ResponseEvent(event: $event, type: $type, id: $id)';
}
