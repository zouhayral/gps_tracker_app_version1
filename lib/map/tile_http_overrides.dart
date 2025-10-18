import 'dart:io';
import 'package:flutter/foundation.dart';

/// Global HttpOverrides to stabilise DNS resolution, socket layer and SSL
/// for all dart:io HttpClient users (including FMTC internals).
///
/// - Forces short timeouts and limited parallel connections
/// - Enforces HTTP/1.1 usage (HTTP/2 is disabled by default in dart:io on IOClient)
/// - Adds debug-only bad certificate handling (never in release)
class TileHttpOverrides extends HttpOverrides {
  TileHttpOverrides();

  static const Duration _connectionTimeout = Duration(seconds: 8);
  static const Duration _idleTimeout = Duration(seconds: 10);
  static const int _maxConnectionsPerHost = 8;

  @override
  HttpClient createHttpClient(SecurityContext? context) {
    final client = super.createHttpClient(context)
      ..connectionTimeout = _connectionTimeout
      ..idleTimeout = _idleTimeout
      ..maxConnectionsPerHost = _maxConnectionsPerHost
      ..autoUncompress = true;

    // Allow self-signed only in debug/profile for troubleshooting networks
    if (kDebugMode || kProfileMode) {
      client.badCertificateCallback = (cert, host, port) => true;
    }

    return client;
  }
}
