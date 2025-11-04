import 'package:firebase_performance/firebase_performance.dart';
import 'package:flutter/foundation.dart';

/// Enhanced Firebase Performance traces for production monitoring
/// 
/// Traces:
/// - load_trips: Trip repository batch loading
/// - map_render: Map rendering with marker updates
/// - tile_switch: Map tile provider switching
/// - marker_update: Marker pool updates
/// - ws_json_parse: WebSocket JSON parsing (existing)
/// - position_batch: Position update batching (existing)
class FirebaseTraces {
  static final _instance = FirebaseTraces._();
  factory FirebaseTraces() => _instance;
  FirebaseTraces._();

  Trace? _loadTripsTrace;
  Trace? _mapRenderTrace;
  Trace? _tileSwitchTrace;
  Trace? _markerUpdateTrace;

  /// Start load_trips trace
  Future<void> startLoadTrips({required int deviceCount}) async {
    try {
      _loadTripsTrace = FirebasePerformance.instance.newTrace('load_trips');
      _loadTripsTrace?.setMetric('device_count', deviceCount);
      await _loadTripsTrace?.start();
      
      if (kDebugMode) {
        debugPrint('[FirebaseTrace] 🚀 Started load_trips trace (devices: $deviceCount)');
      }
    } catch (e) {
      if (kDebugMode) {
        debugPrint('[FirebaseTrace] ⚠️ Failed to start load_trips trace: $e');
      }
    }
  }

  /// Stop load_trips trace
  Future<void> stopLoadTrips({
    required int totalTrips,
    required int cacheHits,
    required int cacheMisses,
    required int durationMs,
  }) async {
    try {
      _loadTripsTrace?.setMetric('total_trips', totalTrips);
      _loadTripsTrace?.setMetric('cache_hits', cacheHits);
      _loadTripsTrace?.setMetric('cache_misses', cacheMisses);
      _loadTripsTrace?.setMetric('duration_ms', durationMs);
      
      final hitRate = (cacheHits + cacheMisses) > 0
          ? (cacheHits / (cacheHits + cacheMisses) * 100).round()
          : 0;
      _loadTripsTrace?.setMetric('cache_hit_rate_percent', hitRate);
      
      await _loadTripsTrace?.stop();
      _loadTripsTrace = null;
      
      if (kDebugMode) {
        debugPrint(
          '[FirebaseTrace] ⏹️ Stopped load_trips trace: '
          '$totalTrips trips, ${durationMs}ms, ${hitRate}% cache hit',
        );
      }
    } catch (e) {
      if (kDebugMode) {
        debugPrint('[FirebaseTrace] ⚠️ Failed to stop load_trips trace: $e');
      }
    }
  }

  /// Start map_render trace
  Future<void> startMapRender() async {
    try {
      _mapRenderTrace = FirebasePerformance.instance.newTrace('map_render');
      await _mapRenderTrace?.start();
      
      if (kDebugMode) {
        debugPrint('[FirebaseTrace] 🗺️ Started map_render trace');
      }
    } catch (e) {
      if (kDebugMode) {
        debugPrint('[FirebaseTrace] ⚠️ Failed to start map_render trace: $e');
      }
    }
  }

  /// Stop map_render trace
  Future<void> stopMapRender({
    required int markerCount,
    required int visibleMarkers,
    required int durationMs,
  }) async {
    try {
      _mapRenderTrace?.setMetric('marker_count', markerCount);
      _mapRenderTrace?.setMetric('visible_markers', visibleMarkers);
      _mapRenderTrace?.setMetric('duration_ms', durationMs);
      
      await _mapRenderTrace?.stop();
      _mapRenderTrace = null;
      
      if (kDebugMode) {
        debugPrint(
          '[FirebaseTrace] ⏹️ Stopped map_render trace: '
          '$markerCount markers ($visibleMarkers visible), ${durationMs}ms',
        );
      }
    } catch (e) {
      if (kDebugMode) {
        debugPrint('[FirebaseTrace] ⚠️ Failed to stop map_render trace: $e');
      }
    }
  }

  /// Start tile_switch trace
  Future<void> startTileSwitch({required String from, required String to}) async {
    try {
      _tileSwitchTrace = FirebasePerformance.instance.newTrace('tile_switch');
      _tileSwitchTrace?.putAttribute('from_provider', from);
      _tileSwitchTrace?.putAttribute('to_provider', to);
      await _tileSwitchTrace?.start();
      
      if (kDebugMode) {
        debugPrint('[FirebaseTrace] 🔄 Started tile_switch trace: $from → $to');
      }
    } catch (e) {
      if (kDebugMode) {
        debugPrint('[FirebaseTrace] ⚠️ Failed to start tile_switch trace: $e');
      }
    }
  }

  /// Stop tile_switch trace
  Future<void> stopTileSwitch({required int durationMs}) async {
    try {
      _tileSwitchTrace?.setMetric('duration_ms', durationMs);
      await _tileSwitchTrace?.stop();
      _tileSwitchTrace = null;
      
      if (kDebugMode) {
        debugPrint('[FirebaseTrace] ⏹️ Stopped tile_switch trace: ${durationMs}ms');
      }
    } catch (e) {
      if (kDebugMode) {
        debugPrint('[FirebaseTrace] ⚠️ Failed to stop tile_switch trace: $e');
      }
    }
  }

  /// Start marker_update trace
  Future<void> startMarkerUpdate({required int updateCount}) async {
    try {
      _markerUpdateTrace = FirebasePerformance.instance.newTrace('marker_update');
      _markerUpdateTrace?.setMetric('update_count', updateCount);
      await _markerUpdateTrace?.start();
      
      if (kDebugMode) {
        debugPrint('[FirebaseTrace] 📍 Started marker_update trace: $updateCount updates');
      }
    } catch (e) {
      if (kDebugMode) {
        debugPrint('[FirebaseTrace] ⚠️ Failed to start marker_update trace: $e');
      }
    }
  }

  /// Stop marker_update trace
  Future<void> stopMarkerUpdate({
    required int poolCacheHits,
    required int poolCacheMisses,
    required int durationMs,
  }) async {
    try {
      _markerUpdateTrace?.setMetric('pool_cache_hits', poolCacheHits);
      _markerUpdateTrace?.setMetric('pool_cache_misses', poolCacheMisses);
      _markerUpdateTrace?.setMetric('duration_ms', durationMs);
      
      final hitRate = (poolCacheHits + poolCacheMisses) > 0
          ? (poolCacheHits / (poolCacheHits + poolCacheMisses) * 100).round()
          : 0;
      _markerUpdateTrace?.setMetric('pool_hit_rate_percent', hitRate);
      
      await _markerUpdateTrace?.stop();
      _markerUpdateTrace = null;
      
      if (kDebugMode) {
        debugPrint(
          '[FirebaseTrace] ⏹️ Stopped marker_update trace: '
          '${durationMs}ms, ${hitRate}% pool hit',
        );
      }
    } catch (e) {
      if (kDebugMode) {
        debugPrint('[FirebaseTrace] ⚠️ Failed to stop marker_update trace: $e');
      }
    }
  }

  /// Record custom metric
  static Future<void> recordMetric(String name, int value) async {
    try {
      final trace = FirebasePerformance.instance.newTrace(name);
      await trace.start();
      trace.setMetric('value', value);
      await trace.stop();
      
      if (kDebugMode) {
        debugPrint('[FirebaseTrace] 📊 Recorded metric $name: $value');
      }
    } catch (e) {
      if (kDebugMode) {
        debugPrint('[FirebaseTrace] ⚠️ Failed to record metric $name: $e');
      }
    }
  }
}
