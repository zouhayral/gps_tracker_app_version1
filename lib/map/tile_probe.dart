import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:my_app_gps/map/tile_network_client.dart';

class TileProbe {
  static final Uri _osm = Uri.parse(
      'https://a.tile.openstreetmap.fr/hot/5/15/12.png',);
  static final Uri _esri = Uri.parse(
      'https://server.arcgisonline.com/ArcGIS/rest/services/World_Imagery/MapServer/tile/5/15/12',);

  /// Perform simple GET requests to validate tile endpoints.
  /// Logs HTTP status codes; returns when both complete.
  static Future<void> run() async {
    final client = TileNetworkClient.shared();
    await Future.wait([
      _probe('OSM', _osm, client),
      _probe('Esri', _esri, client),
    ]);
  }

  static Future<void> _probe(
      String name, Uri url, http.Client client,) async {
    try {
      final isEsri = name.toLowerCase().contains('esri');
      final resp = await client
          .get(url, headers: TileNetworkClient.getUserAgentHeader(isEsri: isEsri))
          .timeout(const Duration(seconds: 8));
      if (kDebugMode) {
        debugPrint('[PROBE][$name] ${resp.statusCode} ${url.host}');
      }
    } on TimeoutException {
      if (kDebugMode) debugPrint('[PROBE][$name] TIMEOUT ${url.host}');
    } catch (e) {
      if (kDebugMode) {
        debugPrint('[PROBE][$name] ERROR ${e.runtimeType}: $e');
      }
    }
  }
}
