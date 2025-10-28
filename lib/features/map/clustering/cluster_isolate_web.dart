import 'package:flutter/foundation.dart';
import 'package:flutter_map/flutter_map.dart';

import 'package:my_app_gps/features/map/clustering/cluster_engine.dart';
import 'package:my_app_gps/features/map/clustering/cluster_models.dart';

/// Web fallback: compute synchronously without spawning isolates.
class ClusterIsolate {
  ClusterIsolate._();

  static Future<List<ClusterResult>> computeClusters({
    required List<ClusterableMarker> markers,
    required double zoom,
    required LatLngBounds viewport,
    required ClusterConfig config,
    Duration timeout = const Duration(milliseconds: 250),
  }) async {
    if (kDebugMode) {
      debugPrint('[CLUSTER_ISOLATE][WEB] Using synchronous compute');
    }
    final engine = ClusterEngine(config: config);
    final results = engine.compute(markers: markers, zoom: zoom, viewport: viewport);
    return results;
  }
}
