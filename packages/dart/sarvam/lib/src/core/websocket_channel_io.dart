import 'package:web_socket_channel/io.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

import 'exceptions.dart';
import 'websocket_factory.dart';

/// Default [WebSocketFactory] implementation for native platforms (Android, iOS, Desktop, Server).
class DefaultWebSocketFactory implements WebSocketFactory {
  const DefaultWebSocketFactory();

  @override
  Future<WebSocketSession> connect(
    Uri uri, {
    Map<String, String>? headers,
    Iterable<String>? protocols,
  }) async {
    try {
      final channel = IOWebSocketChannel.connect(
        uri,
        headers: headers,
        protocols: protocols,
      );
      await channel.ready;
      return ChannelWebSocketSession(channel);
    } on WebSocketChannelException catch (e) {
      throw RealtimeException(
        message: 'WebSocket connection failed: $e',
        cause: e,
      );
    } catch (e) {
      throw RealtimeException( // coverage:ignore-line
        message: 'WebSocket error: $e', // coverage:ignore-line
        cause: e,
      );
    }
  }
}

/// [WebSocketSession] wrapping a [WebSocketChannel].
class ChannelWebSocketSession implements WebSocketSession {
  final WebSocketChannel channel;

  ChannelWebSocketSession(this.channel);

  @override
  Stream<dynamic> get incoming => channel.stream;

  @override
  void send(dynamic data) {
    channel.sink.add(data);
  }

  @override
  Future<void> close([int? code, String? reason]) async {
    await channel.sink.close(code, reason);
  }
}
