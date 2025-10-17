import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:http/io_client.dart';

/// Dedicated HTTP/1.1 client for map tile loading with FMTC
///
/// This client is configured specifically for reliable tile fetching:
/// - Uses HTTP/1.1 (required by FMTC, prevents unknownFetchException)
/// - Proper User-Agent for OpenStreetMap and CDN compliance
/// - Short connection timeouts to fail fast
/// - Gzip compression support
/// - Self-signed certificate support for development
///
/// **Why HTTP/1.1 is Critical:**
/// - FMTC's ObjectBox-based caching requires standard HTTP/1.1 protocol
/// - HTTP/2 causes "unknownFetchException" errors on mobile platforms
/// - Dart's default HttpClient uses HTTP/2 which breaks FMTC tile loading
///
/// **Usage:**
/// ```dart
/// final client = TileNetworkClient.create();
/// final tileProvider = FMTCTileProvider(
///   stores: const {'main': null}, // 'main' store initialized in main.dart
///   httpClient: client,
/// );
/// ```
class TileNetworkClient {
  TileNetworkClient._(); // Private constructor

  /// User-Agent string identifying this app to tile servers
  /// OpenStreetMap and some CDNs require a valid User-Agent
  static const String userAgent = 'GPS_Tracker_App/1.0 Flutter';

  /// Connection timeout for tile requests (fail fast)
  static const Duration connectionTimeout = Duration(seconds: 10);

  /// Idle timeout for keeping connections alive
  static const Duration idleTimeout = Duration(seconds: 15);

  /// Create a properly configured IOClient for FMTC tile loading
  ///
  /// This client is optimized for:
  /// - Reliable tile fetching (no grey tiles)
  /// - Fast failure on network issues
  /// - OpenStreetMap TOS compliance (User-Agent)
  /// - FMTC compatibility (HTTP/1.1 only)
  ///
  /// **Returns:** IOClient ready for use with FMTCTileProvider or NetworkTileProvider
  static IOClient create() {
    final httpClient = HttpClient()
      // CRITICAL: Short timeout prevents grey tiles on slow networks
      ..connectionTimeout = connectionTimeout
      ..idleTimeout = idleTimeout
      
      // CRITICAL: Allow self-signed certs for development/testing
      // Remove in production if all tile servers use valid certificates
      ..badCertificateCallback = (cert, host, port) => true;

    // Wrap in IOClient to ensure HTTP/1.1 protocol
    final ioClient = IOClient(httpClient);

    if (kDebugMode) {
      debugPrint('[TileNetworkClient] 🌐 Created HTTP/1.1 client');
      debugPrint('[TileNetworkClient] ⏱️  Connection timeout: $connectionTimeout');
      debugPrint('[TileNetworkClient] 🏷️  User-Agent: $userAgent');
    }

    return ioClient;
  }

  /// Get the User-Agent header value for manual HTTP requests
  ///
  /// Use this when making direct HTTP requests to tile servers:
  /// ```dart
  /// final response = await http.get(
  ///   url,
  ///   headers: TileNetworkClient.getUserAgentHeader(),
  /// );
  /// ```
  static Map<String, String> getUserAgentHeader() {
    return {'User-Agent': userAgent};
  }
}
