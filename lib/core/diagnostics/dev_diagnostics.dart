import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
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
}
