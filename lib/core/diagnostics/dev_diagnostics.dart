import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:my_app_gps/core/diagnostics/rebuild_tracker.dart';

/// Lightweight runtime diagnostics for debug builds.
///
/// Exposes ValueNotifiers for a small overlay:
/// - WebSocket reconnects
/// - Backfill requests and applied events
/// - Marker builds/sec (from RebuildTracker "MarkerLayer")
/// - FPS (average over last ~1s window)
class DevDiagnostics {
  DevDiagnostics._internal() {
    if (kDebugMode) {
      _start();
    }
  }

  static final DevDiagnostics instance = DevDiagnostics._internal();

  /// Central toggle: diagnostics are only enabled in debug mode
  static bool get isEnabled => kDebugMode;

  /// Lightweight unified log method (no-op in release)
  static void log(String message) {
    if (kDebugMode) debugPrint('[DevDiagnostics] $message');
  }

  /// Optional overlay hook (kept as a no-op by default)
  static void attachOverlay(BuildContext context) {
    if (!kDebugMode) return;
    // Overlay is provided via DevDiagnosticsOverlay widget in debug builds.
  }

  /// Generic duration recorder for ad-hoc timings (no-op in release)
  static void record(String name, Duration duration) {
    if (kDebugMode) {
      debugPrint('[DevDiagnostics] $name took ${duration.inMilliseconds}ms');
    }
  }

  // Public notifiers consumed by overlay
  final ValueNotifier<int> wsReconnects = ValueNotifier<int>(0);
  final ValueNotifier<int> backfillRequests = ValueNotifier<int>(0);
  final ValueNotifier<int> backfillAppliedEvents = ValueNotifier<int>(0);
  final ValueNotifier<double> markerBuildsPerSec = ValueNotifier<double>(0);
  final ValueNotifier<double> fps = ValueNotifier<double>(0);
  final ValueNotifier<int> dedupSkipped = ValueNotifier<int>(0);
  final ValueNotifier<double> pingLatencyMs = ValueNotifier<double>(0);
  final ValueNotifier<int> clusterComputeMs = ValueNotifier<int>(0);
  final ValueNotifier<int> filterComputeMs = ValueNotifier<int>(0);

  // Internals for rate computation
  Timer? _markerRateTimer;
  int _lastMarkerCount = 0;

  // Internals for FPS calculation
  final List<FrameTiming> _frameTimings = <FrameTiming>[];
  Timer? _fpsTimer;
  bool _started = false;

  void _start() {
    if (_started) return;
    _started = true;

    // Marker builds/sec — compute every second from RebuildTracker counter
    _lastMarkerCount = RebuildTracker.instance.getCount('MarkerLayer');
    _markerRateTimer?.cancel();
    _markerRateTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      final current = RebuildTracker.instance.getCount('MarkerLayer');
      final delta = current - _lastMarkerCount;
      _lastMarkerCount = current;
      markerBuildsPerSec.value = delta.clamp(0, 100000).toDouble();
    });

    // FPS — collect frame timings and compute rolling fps every second
    SchedulerBinding.instance.addTimingsCallback(_onTimings);
    _fpsTimer?.cancel();
    _fpsTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (_frameTimings.isEmpty) {
        fps.value = 0;
        return;
      }
      // Compute FPS from frame durations in the last second window
      final now = DateTime.now().microsecondsSinceEpoch;
      final recent = _frameTimings.where((t) {
        final endUs = t.timestampInMicroseconds(ui.FramePhase.rasterFinish);
        return (now - endUs) <= 1000000; // last 1s
      }).toList(growable: false);
      if (recent.isEmpty) {
        fps.value = 0;
      } else {
        final totalFrames = recent.length;
        // Approximate fps as frames per second in that window
        fps.value = totalFrames.clamp(0, 120).toDouble();
      }
      // Trim old timings to keep memory bounded
      if (_frameTimings.length > 300) {
        _frameTimings.removeRange(0, _frameTimings.length - 200);
      }
    });
  }

  void dispose() {
    _markerRateTimer?.cancel();
    _fpsTimer?.cancel();
    SchedulerBinding.instance.removeTimingsCallback(_onTimings);
  }

  void _onTimings(List<FrameTiming> timings) {
    _frameTimings.addAll(timings);
  }

  // Hooks to be called from code paths
  void onWsConnected() {
    if (!kDebugMode) return;
    wsReconnects.value += 1;
  }

  void onBackfillRequested(int deviceCount) {
    if (!kDebugMode) return;
    backfillRequests.value += 1; // count requests, deviceCount available if needed later
  }

  void onBackfillApplied(int eventsCount) {
    if (!kDebugMode) return;
    backfillAppliedEvents.value += eventsCount;
  }

  // Extended metrics
  void incrementDedupSkipped() {
    if (!kDebugMode) return;
    dedupSkipped.value += 1;
  }

  void recordPingLatency(double ms) {
    if (!kDebugMode) return;
    pingLatencyMs.value = ms;
  }

  void recordClusterCompute(int ms) {
    if (!kDebugMode) return;
    clusterComputeMs.value = ms;
  }

  void recordFilterCompute(int ms) {
    if (!kDebugMode) return;
    filterComputeMs.value = ms;
  }
  
  // ============================================================================
  // TRIP PERFORMANCE METRICS (Phase 2 Optimization)
  // ============================================================================
  
  final ValueNotifier<int> tripCacheHits = ValueNotifier<int>(0);
  final ValueNotifier<int> tripCacheMisses = ValueNotifier<int>(0);
  final ValueNotifier<int> tripApiCalls = ValueNotifier<int>(0);
  final ValueNotifier<int> tripDbQueries = ValueNotifier<int>(0);
  final ValueNotifier<int> tripLoadTimeMs = ValueNotifier<int>(0);
  
  Stopwatch? _tripLoadTimer;
  
  /// Start measuring trip load time
  void startTripLoad() {
    if (!kDebugMode) return;
    _tripLoadTimer = Stopwatch()..start();
  }
  
  /// Stop measuring and record trip load time
  void endTripLoad() {
    if (!kDebugMode) return;
    if (_tripLoadTimer != null) {
      _tripLoadTimer!.stop();
      tripLoadTimeMs.value = _tripLoadTimer!.elapsedMilliseconds;
      debugPrint('[TripMetrics] ⏱️ Load time: ${_tripLoadTimer!.elapsedMilliseconds}ms');
      _tripLoadTimer!.reset();
    }
  }
  
  /// Record cache hit
  void recordTripCacheHit() {
    if (!kDebugMode) return;
    tripCacheHits.value += 1;
  }
  
  /// Record cache miss
  void recordTripCacheMiss() {
    if (!kDebugMode) return;
    tripCacheMisses.value += 1;
  }
  
  /// Record API call
  void recordTripApiCall() {
    if (!kDebugMode) return;
    tripApiCalls.value += 1;
  }
  
  /// Record database query
  void recordTripDbQuery() {
    if (!kDebugMode) return;
    tripDbQueries.value += 1;
  }
  
  /// Get trip cache hit rate as percentage
  double get tripCacheHitRate {
    final total = tripCacheHits.value + tripCacheMisses.value;
    if (total == 0) return 0.0;
    return (tripCacheHits.value / total) * 100;
  }
  
  /// Get trip metrics summary
  Map<String, dynamic> get tripMetricsSummary => {
    'cache_hit_rate': '${tripCacheHitRate.toStringAsFixed(1)}%',
    'cache_hits': tripCacheHits.value,
    'cache_misses': tripCacheMisses.value,
    'api_calls': tripApiCalls.value,
    'db_queries': tripDbQueries.value,
    'last_load_time_ms': tripLoadTimeMs.value,
  };
  
  /// Reset trip metrics
  void resetTripMetrics() {
    if (!kDebugMode) return;
    tripCacheHits.value = 0;
    tripCacheMisses.value = 0;
    tripApiCalls.value = 0;
    tripDbQueries.value = 0;
    tripLoadTimeMs.value = 0;
    debugPrint('[TripMetrics] 🔄 Metrics reset');
  }
}
