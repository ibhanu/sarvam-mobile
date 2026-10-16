/// Immutable configuration for Sarvam API and WebSocket endpoint base URLs.
class SarvamEnvironment {
  /// Base URL for standard REST and streaming endpoints.
  final String apiBaseUrl;

  /// Base URL for dubbing job endpoints.
  final String dubbingBaseUrl;

  /// Base URL for WebSocket realtime endpoints.
  final String wsBaseUrl;

  /// Creates a [SarvamEnvironment] with explicit base URLs.
  const SarvamEnvironment({
    required this.apiBaseUrl,
    required this.dubbingBaseUrl,
    required this.wsBaseUrl,
  });

  /// Default production environment pointing to `https://api.sarvam.ai`.
  static const SarvamEnvironment production = SarvamEnvironment(
    apiBaseUrl: 'https://api.sarvam.ai',
    dubbingBaseUrl: 'https://api.sarvam.ai/dubbing',
    wsBaseUrl: 'wss://api.sarvam.ai',
  );

  /// Factory creating an environment routed through a Backend-For-Frontend (BFF) proxy.
  ///
  /// For example, `SarvamEnvironment.proxy('https://api.myapp.com/sarvam')`:
  /// - `apiBaseUrl`: `https://api.myapp.com/sarvam`
  /// - `dubbingBaseUrl`: `https://api.myapp.com/sarvam/dubbing`
  /// - `wsBaseUrl`: `wss://api.myapp.com/sarvam`
  factory SarvamEnvironment.proxy(String baseUrl) {
    var cleaned = baseUrl.trim();
    while (cleaned.endsWith('/')) {
      cleaned = cleaned.substring(0, cleaned.length - 1);
    }

    final String wsUrl;
    if (cleaned.startsWith('https://')) {
      wsUrl = cleaned.replaceFirst('https://', 'wss://');
    } else if (cleaned.startsWith('http://')) {
      wsUrl = cleaned.replaceFirst('http://', 'ws://');
    } else {
      wsUrl = 'wss://$cleaned';
    }

    return SarvamEnvironment(
      apiBaseUrl: cleaned,
      dubbingBaseUrl: '$cleaned/dubbing',
      wsBaseUrl: wsUrl,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is SarvamEnvironment &&
          runtimeType == other.runtimeType &&
          apiBaseUrl == other.apiBaseUrl &&
          dubbingBaseUrl == other.dubbingBaseUrl &&
          wsBaseUrl == other.wsBaseUrl;

  @override
  int get hashCode =>
      apiBaseUrl.hashCode ^ dubbingBaseUrl.hashCode ^ wsBaseUrl.hashCode;

  @override
  String toString() =>
      'SarvamEnvironment(api: $apiBaseUrl, dubbing: $dubbingBaseUrl, ws: $wsBaseUrl)';
}
