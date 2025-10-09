import 'package:web_socket_channel/web_socket_channel.dart';

WebSocketChannel connectWebSocket(Uri uri, Map<String, dynamic> headers) {
  // Default: no headers (used as fallback)
  return WebSocketChannel.connect(uri);
}
