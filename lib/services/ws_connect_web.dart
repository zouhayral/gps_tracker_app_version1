import 'package:web_socket_channel/web_socket_channel.dart';

WebSocketChannel connectWebSocket(Uri uri, Map<String, dynamic> headers) {
  // Browsers ignore headers and do not support pingInterval at constructor level.
  // Heartbeat is managed at app level; channel just connects.
  return WebSocketChannel.connect(uri);
}
