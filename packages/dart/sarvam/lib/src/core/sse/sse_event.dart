/// Represents a single Server-Sent Event (SSE) frame.
class SseEvent {
  /// Optional event identifier.
  final String? id;

  /// Optional event name (e.g. `'response.completed'`).
  final String? event;

  /// Raw event payload data.
  final String data;

  /// Optional reconnect retry interval in milliseconds.
  final int? retry;

  const SseEvent({
    this.id,
    this.event,
    required this.data,
    this.retry,
  });

  @override
  String toString() =>
      'SseEvent(id: $id, event: $event, retry: $retry, data: $data)';
}
