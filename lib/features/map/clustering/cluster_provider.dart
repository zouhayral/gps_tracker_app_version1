import 'dart:async';
import 'dart:isolate';

import 'package:flutter/foundation.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:latlong2/latlong.dart';
import 'package:my_app_gps/features/map/clustering/cluster_badge_cache.dart';
import 'package:my_app_gps/features/map/clustering/cluster_engine.dart';
import 'package:my_app_gps/features/map/clustering/cluster_isolate.dart';
import 'package:my_app_gps/features/map/clustering/cluster_models.dart';
import 'package:my_app_gps/features/map/data/position_model.dart';

/// Provider for cluster configuration
final clusterConfigProvider = Provider<ClusterConfig>((ref) {
  return const ClusterConfig(
    minClusterSize: 2,
    useIsolate: true,
    isolateThreshold: 800,
  );
});

/// Provider for current zoom level (watches map state)
final currentZoomProvider = StateProvider<double>((ref) => 10.0);

/// Provider for current viewport bounds
final currentViewportProvider = StateProvider<LatLngBounds?>((ref) => null);

/// Main cluster provider - computes clusters from markers
///
/// **Inputs:**
/// - Marker list (from vehicle positions)
/// - Current zoom level
/// - Viewport bounds
///
/// **Outputs:**
/// - ClusterState with computed clusters
/// - Loading state during computation
/// - Error state on failures
///
/// **Performance:**
/// - Debounced recalculation (250ms delay)
/// - Background isolate for > 800 markers
/// - Sync computation for < 800 markers
final clusterProvider =
    StateNotifierProvider<ClusterNotifier, ClusterState>((ref) {
  return ClusterNotifier(
    config: ref.watch(clusterConfigProvider),
    ref: ref,
  );
});

/// Telemetry model for clustering performance
class ClusterTelemetry {
  final int computeTimeMs;
  final double cacheHitRate;
  final int markerCount;
  final int clusterCount;
  final bool usedIsolate;

  const ClusterTelemetry({
    required this.computeTimeMs,
    required this.cacheHitRate,
    required this.markerCount,
    required this.clusterCount,
    required this.usedIsolate,
  });
}

final clusterTelemetryProvider =
    StateProvider<ClusterTelemetry?>((ref) => null);

class ClusterNotifier extends StateNotifier<ClusterState> {
  final ClusterConfig config;
  final Ref ref;

  Timer? _debounceTimer;
  Isolate? _computeIsolate;
  ReceivePort? _receivePort;

  ClusterNotifier({
    required this.config,
    required this.ref,
  }) : super(const ClusterState.initial());

  /// Compute clusters for given markers
  ///
  /// Automatically chooses sync or isolate path based on marker count
  Future<void> computeClusters({
    required List<Position> positions,
    required double zoom,
    required LatLngBounds viewport,
  }) async {
    // Cancel pending computations
    _debounceTimer?.cancel();

    // Debounce rapid zoom/pan changes
    _debounceTimer = Timer(const Duration(milliseconds: 250), () async {
      await _performComputation(positions, zoom, viewport);
    });
  }

  Future<void> _performComputation(
    List<Position> positions,
    double zoom,
    LatLngBounds viewport,
  ) async {
    try {
      state = state.copyWith(isLoading: true);

      // Convert positions to clusterable markers
      final markers = positions.map((p) {
        return ClusterableMarker(
          id: '${p.deviceId}',
          position: LatLng(p.latitude, p.longitude),
          metadata: {
            'deviceId': p.deviceId,
            'speed': p.speed,
            'course': p.course,
            'deviceTime': p.deviceTime,
            'attributes': p.attributes,
          },
        );
      }).toList();

      // Choose computation path based on marker count
      final useIsolate = config.useIsolate &&
          markers.length >= config.isolateThreshold;

      final ClusterComputeResponse response;

      if (useIsolate) {
        response = await _computeInIsolate(markers, zoom, viewport);
      } else {
        response = await _computeSync(markers, zoom, viewport);
      }

      // Update state with results
      state = ClusterState(
        results: response.results,
        isLoading: false,
        lastComputed: DateTime.now(),
        markerCount: response.markerCount,
        clusterCount: response.clusterCount,
        usedIsolate: useIsolate,
      );

      if (kDebugMode) {
        debugPrint(
          '[CLUSTER_PROVIDER] ✅ Computed ${response.results.length} results '
          '(${response.clusterCount} clusters) in ${response.durationMs}ms '
          '(${useIsolate ? "isolate" : "sync"})',
        );
      }

      // Publish telemetry
      ref.read(clusterTelemetryProvider.notifier).state = ClusterTelemetry(
        computeTimeMs: response.durationMs,
        cacheHitRate: ClusterBadgeCache.hitRate(),
        markerCount: response.markerCount,
        clusterCount: response.clusterCount,
        usedIsolate: useIsolate,
      );
    } catch (e, stack) {
      if (kDebugMode) {
        debugPrint('[CLUSTER_PROVIDER] ❌ Computation failed: $e');
        debugPrint(stack.toString());
      }

      state = state.copyWith(
        isLoading: false,
        error: e.toString(),
      );
    }
  }

  /// Compute clusters synchronously (for small marker counts)
  Future<ClusterComputeResponse> _computeSync(
    List<ClusterableMarker> markers,
    double zoom,
    LatLngBounds viewport,
  ) async {
    final sw = Stopwatch()..start();

    final engine = ClusterEngine(config: config);
    final results = engine.compute(
      markers: markers,
      zoom: zoom,
      viewport: viewport,
    );

    sw.stop();

    final clusterCount = results.where((r) => r.isCluster).length;

    return ClusterComputeResponse(
      results: results,
      markerCount: markers.length,
      clusterCount: clusterCount,
      durationMs: sw.elapsedMilliseconds,
    );
  }

  /// Compute clusters in background isolate (for large marker counts)
  ///
  /// NOTE: This is a simplified implementation. Full isolate support requires:
  /// 1. Spawning isolate with Isolate.spawn()
  /// 2. Setting up bidirectional SendPort/ReceivePort communication
  /// 3. Serializing message data (ClusterableMarker must be serializable)
  /// 4. Managing isolate lifecycle (reuse vs. spawn-per-request)
  ///
  /// For now, falls back to sync computation with a simulated delay
  Future<ClusterComputeResponse> _computeInIsolate(
    List<ClusterableMarker> markers,
    double zoom,
    LatLngBounds viewport,
  ) async {
    final sw = Stopwatch()..start();
    if (kDebugMode) {
      debugPrint('[CLUSTER_PROVIDER] 🔄 Using isolate for ${markers.length} markers');
    }

    final results = await ClusterIsolate.computeClusters(
      markers: markers,
      zoom: zoom,
      viewport: viewport,
      config: config,
      timeout: const Duration(milliseconds: 250),
    );

    sw.stop();
    final clusterCount = results.where((r) => r.isCluster).length;

    if (kDebugMode) {
      debugPrint('[CLUSTER_ISOLATE] ⏲️ took ${sw.elapsedMilliseconds} ms');
    }

    return ClusterComputeResponse(
      results: results,
      markerCount: markers.length,
      clusterCount: clusterCount,
      durationMs: sw.elapsedMilliseconds,
    );
  }

  /// Clean up resources
  @override
  void dispose() {
    _debounceTimer?.cancel();
    _receivePort?.close();
    _computeIsolate?.kill(priority: Isolate.immediate);
    super.dispose();
  }
}
