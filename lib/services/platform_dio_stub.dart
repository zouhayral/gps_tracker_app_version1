import 'package:dio/dio.dart';

// Stub used for non-IO platforms by default (overridden by conditional imports)
Dio createPlatformDio(BaseOptions options, {required bool allowInsecure}) {
  return Dio(options);
}

String adjustBaseForEmulator(String rawBase) => rawBase;

Future<Map<String, dynamic>> socketProbe(
  String host,
  int port, {
  Duration timeout = const Duration(seconds: 5),
}) async {
  // Not supported on non-IO platforms; return a neutral result
  return {'socketSupported': false};
}
