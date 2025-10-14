import 'dart:io';
import 'package:dio/dio.dart';
import 'package:dio/io.dart';

Dio createPlatformDio(BaseOptions options, {required bool allowInsecure}) {
  final dio = Dio(options);
  if (allowInsecure) {
    try {
      final adapter = dio.httpClientAdapter as IOHttpClientAdapter;
      adapter.createHttpClient = () {
        final client = HttpClient();
        client.badCertificateCallback = (cert, host, port) => true; // DEV ONLY
        return client;
      };
    } catch (_) {}
  }
  return dio;
}

String adjustBaseForEmulator(String rawBase) {
  try {
    final uri = Uri.parse(rawBase);
    if (Platform.isAndroid &&
        (uri.host == 'localhost' || uri.host == '127.0.0.1')) {
      return rawBase.replaceFirst(uri.host, '10.0.2.2');
    }
  } catch (_) {}
  return rawBase;
}

Future<Map<String, dynamic>> socketProbe(
  String host,
  int port, {
  Duration timeout = const Duration(seconds: 5),
}) async {
  final sw = Stopwatch()..start();
  try {
    final socket = await Socket.connect(host, port, timeout: timeout);
    sw.stop();
    final ms = sw.elapsedMilliseconds;
    socket.destroy();
    return {'socketSupported': true, 'socketConnected': true, 'socketMs': ms};
  } catch (e) {
    sw.stop();
    return {
      'socketSupported': true,
      'socketConnected': false,
      'socketError': e.toString(),
    };
  }
}
