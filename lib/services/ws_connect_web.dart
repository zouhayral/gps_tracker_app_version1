import 'package:web_socket_channel/web_socket_channel.dart';

WebSocketChannel connectWebSocket(Uri uri, Map<String, dynamic> headers) {
  // Browsers ignore headers; rely on cookie policy.
  return WebSocketChannel.connect(uri);
}
