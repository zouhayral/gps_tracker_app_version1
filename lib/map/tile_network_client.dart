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
/// final tileProvider = const FMTCStore('main').getTileProvider(
///   httpClient: client,
/// );
/// ```
class TileNetworkClient {
  TileNetworkClient._(); // Private constructor

  /// User-Agent string identifying this app to tile servers
  /// OpenStreetMap and some CDNs require a valid User-Agent
  static const String userAgent = 'FleetTracker/1.0 (contact@yourdomain.com)';

  /// Connection timeout for tile requests (fail fast)
  static const Duration connectionTimeout = Duration(seconds: 10);

  /// Idle timeout for keeping connections alive
  static const Duration idleTimeout = Duration(seconds: 15);

  static IOClient? _sharedInstance;

  /// Get a shared IOClient instance for reuse across all FMTC providers
  /// This avoids creating multiple clients and ensures consistent behavior.
  static IOClient shared() => _sharedInstance ??= create();

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
      // Limit parallel connections to be friendly to tile servers
      ..maxConnectionsPerHost = 8
      // Ensure gzip responses are transparently decompressed
      ..autoUncompress = true
      // Ensure all requests carry a compliant User-Agent
      ..userAgent = userAgent;

    // Allow self-signed certs only in debug/profile for development/testing
    if (kDebugMode || kProfileMode) {
      httpClient.badCertificateCallback = (cert, host, port) => true;
    }

    // Wrap in IOClient to ensure HTTP/1.1 protocol
    final ioClient = IOClient(httpClient);

    if (kDebugMode) {
      debugPrint('[TileNetworkClient] 🌐 Created HTTP/1.1 client');
      debugPrint('[TileNetworkClient] ⏱️  Connection timeout: $connectionTimeout');
      debugPrint('[TileNetworkClient] 🏷️  User-Agent: $userAgent');
      debugPrint('[TileNetworkClient] 🔗  maxConnectionsPerHost: ${httpClient.maxConnectionsPerHost}');
      debugPrint('[TileNetworkClient] ✅ HTTP/1.1 enforced via IOClient wrapper');
      debugPrint('[TileNetworkClient] 📦 gzip compression: ${httpClient.autoUncompress}');
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
  static Map<String, String> getUserAgentHeader({bool isEsri = false}) {
    final headers = {
      'User-Agent': userAgent,
      // HttpClient already advertises gzip, but include here for completeness
      'Accept-Encoding': 'gzip, deflate',
    };
    
    // Esri ArcGIS services may need explicit Accept header to avoid negotiation issues
    if (isEsri) {
      headers['Accept'] = 'image/png, image/jpeg, */*';
    }
    
    return headers;
  }
}
