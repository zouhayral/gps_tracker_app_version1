import 'dart:async';
import 'dart:isolate';

import 'package:flutter/foundation.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

import 'package:my_app_gps/features/map/clustering/cluster_engine.dart';
import 'package:my_app_gps/features/map/clustering/cluster_models.dart';

/// A dedicated isolate entry and API for performing cluster computations
/// off the UI thread.
class ClusterIsolate {
  ClusterIsolate._();

  /// Spawns an isolate to compute clusters. Falls back to sync path if
  /// isolate fails to respond for [timeout].
  static Future<List<ClusterResult>> computeClusters({
    required List<ClusterableMarker> markers,
    required double zoom,
    required LatLngBounds viewport,
    required ClusterConfig config,
    Duration timeout = const Duration(milliseconds: 250),
  }) async {
    final rp = ReceivePort();
    Isolate? isolate;

    try {
      // Build a simple serializable payload
      final payload = _ComputePayload(
        sendPort: rp.sendPort,
        markers: markers,
        zoom: zoom,
        viewport: viewport,
        config: config,
      ).toMap();

      isolate = await Isolate.spawn(
        _isolateEntry,
        payload,
        debugName: 'cluster_isolate',
      );

      final resultFuture = rp.first.timeout(timeout);
      final raw = await resultFuture as Map<String, dynamic>;
      final results = _Parse.fromMap(raw);
      return results;
    } on TimeoutException {
      if (kDebugMode) {
        debugPrint('[CLUSTER_ISOLATE] ⏱️ Timeout > falling back to sync');
      }
      // Fallback to synchronous compute
      final engine = ClusterEngine(config: config);
      return engine.compute(markers: markers, zoom: zoom, viewport: viewport);
    } finally {
      rp.close();
      isolate?.kill(priority: Isolate.immediate);
    }
  }

  /// Isolate entry point. Receives a serializable payload map, reconstructs
  /// the required objects and performs computation, then replies with a
  /// serializable result map.
  static void _isolateEntry(Map<String, dynamic> data) {
    final send = data['sendPort'] as SendPort;
    try {
      final payload = _ComputePayload.fromMap(data);
      final engine = ClusterEngine(config: payload.config);
      final results = engine.compute(
        markers: payload.markers,
        zoom: payload.zoom,
        viewport: payload.viewport,
      );

      // Serialize results
      final resMap = {
        'results': results.map(_Serialize.result).toList(),
      };
      send.send(resMap);
    } catch (e, st) {
      if (kDebugMode) {
        debugPrint('[CLUSTER_ISOLATE] ❌ Error: $e');
        debugPrint(st.toString());
      }
      send.send({'results': <Map<String, dynamic>>[]});
    }
  }
}

// --- Serialization helpers -------------------------------------------------

class _Serialize {
  static Map<String, dynamic> marker(ClusterableMarker m) => {
        'id': m.id,
        'lat': m.position.latitude,
        'lng': m.position.longitude,
        'metadata': m.metadata,
      };

  static Map<String, dynamic> result(ClusterResult r) => {
        'clusterId': r.clusterId,
        'isCluster': r.isCluster,
        'lat': r.position.latitude,
        'lng': r.position.longitude,
        'members': r.members.map(marker).toList(),
      };

  static Map<String, dynamic> bounds(LatLngBounds b) => {
        'swLat': b.southWest.latitude,
        'swLng': b.southWest.longitude,
        'neLat': b.northEast.latitude,
        'neLng': b.northEast.longitude,
      };

  static Map<String, dynamic> config(ClusterConfig c) => {
        'minZoom': c.minZoom,
        'maxZoom': c.maxZoom,
        'minClusterSize': c.minClusterSize,
        'useIsolate': c.useIsolate,
        'isolateThreshold': c.isolateThreshold,
        'pixelDistanceByZoom': c.pixelDistanceByZoom,
      };
}

class _Parse {
  static ClusterableMarker marker(Map<String, dynamic> m) => ClusterableMarker(
        id: m['id'] as String,
        position: LatLng((m['lat'] as num).toDouble(), (m['lng'] as num).toDouble()),
        metadata: Map<String, dynamic>.from(m['metadata'] as Map),
      );

  static ClusterResult result(Map<String, dynamic> r) => ClusterResult(
        clusterId: r['clusterId'] as String,
        isCluster: r['isCluster'] as bool,
        position: LatLng((r['lat'] as num).toDouble(), (r['lng'] as num).toDouble()),
        members: (r['members'] as List).map((e) => marker(Map<String, dynamic>.from(e as Map))).toList(),
      );

  static List<ClusterResult> fromMap(Map<String, dynamic> raw) {
    final list = (raw['results'] as List?) ?? const [];
    return list.map((e) => result(Map<String, dynamic>.from(e as Map))).toList();
  }

  static LatLngBounds bounds(Map<String, dynamic> m) => LatLngBounds(
        LatLng((m['swLat'] as num).toDouble(), (m['swLng'] as num).toDouble()),
        LatLng((m['neLat'] as num).toDouble(), (m['neLng'] as num).toDouble()),
      );

  static ClusterConfig config(Map<String, dynamic> m) => ClusterConfig(
        minZoom: (m['minZoom'] as num).toDouble(),
        maxZoom: (m['maxZoom'] as num).toDouble(),
        minClusterSize: m['minClusterSize'] as int,
        useIsolate: m['useIsolate'] as bool,
        isolateThreshold: m['isolateThreshold'] as int,
        pixelDistanceByZoom: Map<int, double>.from(
          (m['pixelDistanceByZoom'] as Map).map(
            (k, v) => MapEntry(int.parse(k.toString()), (v as num).toDouble()),
          ),
        ),
      );
}

class _ComputePayload {
  final SendPort sendPort;
  final List<ClusterableMarker> markers;
  final double zoom;
  final LatLngBounds viewport;
  final ClusterConfig config;

  const _ComputePayload({
    required this.sendPort,
    required this.markers,
    required this.zoom,
    required this.viewport,
    required this.config,
  });

  Map<String, dynamic> toMap() => {
        'sendPort': sendPort,
        'markers': markers.map(_Serialize.marker).toList(),
        'zoom': zoom,
        'viewport': _Serialize.bounds(viewport),
        'config': _Serialize.config(config),
      };

    factory _ComputePayload.fromMap(Map<String, dynamic> m) => _ComputePayload(
          sendPort: m['sendPort'] as SendPort,
          markers: (m['markers'] as List).map((e) => _Parse.marker(Map<String, dynamic>.from(e as Map))).toList(),
          zoom: (m['zoom'] as num).toDouble(),
          viewport: _Parse.bounds(Map<String, dynamic>.from(m['viewport'] as Map)),
          config: _Parse.config(Map<String, dynamic>.from(m['config'] as Map)),
        );
}
