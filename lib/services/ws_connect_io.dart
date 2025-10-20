import 'package:web_socket_channel/io.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

WebSocketChannel connectWebSocket(Uri uri, Map<String, dynamic> headers) {
  // Configure ping interval to reduce noisy frequent pong logs
  return IOWebSocketChannel.connect(
    uri.toString(),
    headers: headers,
    pingInterval: const Duration(seconds: 10),
  );
}
