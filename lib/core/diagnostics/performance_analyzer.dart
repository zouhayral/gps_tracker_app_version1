import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/scheduler.dart';
import 'package:my_app_gps/core/diagnostics/rebuild_tracker.dart';
import 'package:my_app_gps/core/map/marker_performance_monitor.dart';

/// Comprehensive performance analyzer for widget rebuilds and frame timing
/// 
/// Tracks:
/// - Widget rebuild counts and frequency
/// - Frame times over 16ms (60 FPS threshold) and 100ms
/// - Marker layer performance
/// - MapPage rebuild statistics
/// - NotificationList rebuild statistics
class PerformanceAnalyzer {
  PerformanceAnalyzer._();

  static final PerformanceAnalyzer instance = PerformanceAnalyzer._();

  bool _isAnalyzing = false;
  DateTime? _analysisStartTime;
  Timer? _reportTimer;

  // Widget rebuild tracking
  final Map<String, List<DateTime>> _rebuildTimestamps = {};
  final Map<String, int> _rebuildCounts = {};

  // Frame timing tracking
  final List<_FrameData> _frames = [];
  int _jankFrames = 0; // >16ms
  int _severeJankFrames = 0; // >100ms

  // Marker performance
  int _markerLayerRebuilds = 0;
  int _mapPageFullRebuilds = 0;

  /// Start analyzing performance for widget rebuilds
  /// 
  /// Duration: how long to analyze (default 10 seconds)
  void startAnalysis({Duration duration = const Duration(seconds: 10)}) {
    if (_isAnalyzing) {
      debugPrint('[PerfAnalyzer] Already analyzing');
      return;
    }

    _isAnalyzing = true;
    _analysisStartTime = DateTime.now();
    _reset();

    // Start RebuildTracker
    RebuildTracker.instance.start();

    // Start frame timing callback
    SchedulerBinding.instance.addTimingsCallback(_onFrameTiming);

    debugPrint('');
    debugPrint('╔════════════════════════════════════════════════════════╗');
    debugPrint('║    PERFORMANCE ANALYSIS STARTED                        ║');
    debugPrint('╠════════════════════════════════════════════════════════╣');
    debugPrint('║ Duration: ${duration.inSeconds}s                                          ║');
    debugPrint('║ Tracking:                                              ║');
    debugPrint('║   • Widget rebuilds (all components)                   ║');
    debugPrint('║   • Frame timing (jank detection)                      ║');
    debugPrint('║   • MapPage & MarkerLayer rebuilds                     ║');
    debugPrint('║   • NotificationList rebuilds                          ║');
    debugPrint('╚════════════════════════════════════════════════════════╝');
    debugPrint('');

    // Auto-stop after duration
    _reportTimer = Timer(duration, () {
      stopAnalysis();
    });
  }

  /// Stop analysis and print comprehensive report
  void stopAnalysis() {
    if (!_isAnalyzing) {
      debugPrint('[PerfAnalyzer] Not analyzing');
      return;
    }

    _isAnalyzing = false;
    _reportTimer?.cancel();
    _reportTimer = null;

    // Stop RebuildTracker
    RebuildTracker.instance.stop();

    // Generate report
    _generateReport();

    debugPrint('[PerfAnalyzer] Analysis stopped');
  }

  /// Track a widget rebuild
  void trackRebuild(String widgetName) {
    if (!_isAnalyzing) return;

    final now = DateTime.now();
    _rebuildTimestamps.putIfAbsent(widgetName, () => []).add(now);
    _rebuildCounts[widgetName] = (_rebuildCounts[widgetName] ?? 0) + 1;

    // Track specific widgets
    if (widgetName == 'MapPage') {
      _mapPageFullRebuilds++;
    } else if (widgetName == 'MarkerLayer' || widgetName == 'FlutterMapAdapter') {
      _markerLayerRebuilds++;
    }

    // Log excessive rebuilds in real-time
    if (_rebuildCounts[widgetName]! > 20) {
      final elapsed = now.difference(_analysisStartTime!).inSeconds;
      if (elapsed >= 10) {
        final rate = _rebuildCounts[widgetName]! / elapsed;
        if (rate > 2.0) { // More than 2 rebuilds per second
          debugPrint(
            '⚠️ [PerfAnalyzer] $widgetName: ${_rebuildCounts[widgetName]} rebuilds '
            '(${rate.toStringAsFixed(1)}/s) - EXCESSIVE!',
          );
        }
      }
    }
  }

  /// Frame timing callback
  void _onFrameTiming(List<FrameTiming> timings) {
    if (!_isAnalyzing) return;

    for (final timing in timings) {
      final buildMs = timing.buildDuration.inMilliseconds;
      final rasterMs = timing.rasterDuration.inMilliseconds;
      final totalMs = timing.totalSpan.inMilliseconds;

      _frames.add(_FrameData(
        buildMs: buildMs,
        rasterMs: rasterMs,
        totalMs: totalMs,
        timestamp: DateTime.now(),
      ));

      // Track jank
      if (totalMs > 16) {
        _jankFrames++;
        if (totalMs > 100) {
          _severeJankFrames++;
          debugPrint(
            '🔴 [PerfAnalyzer] SEVERE JANK: ${totalMs}ms '
            '(build: ${buildMs}ms, raster: ${rasterMs}ms)',
          );
        }
      }
    }
  }

  /// Generate comprehensive performance report
  void _generateReport() {
    if (_analysisStartTime == null) return;

    final elapsed = DateTime.now().difference(_analysisStartTime!);
    final elapsedSeconds = elapsed.inSeconds;

    debugPrint('');
    debugPrint('╔═══════════════════════════════════════════════════════════════╗');
    debugPrint('║         PERFORMANCE ANALYSIS REPORT                           ║');
    debugPrint('╠═══════════════════════════════════════════════════════════════╣');
    debugPrint('║ Analysis Duration: ${elapsedSeconds}s                                          ║');
    debugPrint('╚═══════════════════════════════════════════════════════════════╝');
    debugPrint('');

    // 1. Widget Rebuild Analysis
    _printWidgetRebuildReport(elapsedSeconds);

    // 2. Frame Timing Analysis
    _printFrameTimingReport();

    // 3. Critical Widgets Report
    _printCriticalWidgetsReport(elapsedSeconds);

    // 4. Marker Performance
    _printMarkerPerformanceReport();

    // 5. Recommendations
    _printRecommendations();
  }

  void _printWidgetRebuildReport(int elapsedSeconds) {
    debugPrint('╔═══════════════════════════════════════════════════════════════╗');
    debugPrint('║ 1. WIDGET REBUILD ANALYSIS                                    ║');
    debugPrint('╠═══════════════════════════════════════════════════════════════╣');

    if (_rebuildCounts.isEmpty) {
      debugPrint('║ No widget rebuilds tracked                                    ║');
      debugPrint('╚═══════════════════════════════════════════════════════════════╝');
      debugPrint('');
      return;
    }

    // Sort by rebuild count
    final sorted = _rebuildCounts.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));

    // Filter widgets with >20 rebuilds in 10s
    final excessive = sorted.where((e) => e.value > 20).toList();

    debugPrint('║ Total Widgets Tracked: ${_rebuildCounts.length}                              ║');
    debugPrint('║ Widgets Rebuilding >20 times: ${excessive.length}                      ║');
    debugPrint('╠═══════════════════════════════════════════════════════════════╣');

    for (final entry in sorted.take(15)) {
      final count = entry.value;
      final rate = elapsedSeconds > 0 ? count / elapsedSeconds : 0.0;
      final status = _getRebuildStatus(count, rate);
      final padding = ' ' * (30 - entry.key.length);
      
      debugPrint(
        '║ $status ${entry.key}$padding${count.toString().padLeft(4)} rebuilds (${rate.toStringAsFixed(1)}/s)',
      );
    }

    if (sorted.length > 15) {
      debugPrint('║ ... and ${sorted.length - 15} more widgets                               ║');
    }

    debugPrint('╚═══════════════════════════════════════════════════════════════╝');
    debugPrint('');
  }

  void _printFrameTimingReport() {
    debugPrint('╔═══════════════════════════════════════════════════════════════╗');
    debugPrint('║ 2. FRAME TIMING ANALYSIS                                      ║');
    debugPrint('╠═══════════════════════════════════════════════════════════════╣');

    if (_frames.isEmpty) {
      debugPrint('║ No frame data collected                                       ║');
      debugPrint('╚═══════════════════════════════════════════════════════════════╝');
      debugPrint('');
      return;
    }

    final totalFrames = _frames.length;
    final avgBuild = _frames.map((f) => f.buildMs).reduce((a, b) => a + b) / totalFrames;
    final avgRaster = _frames.map((f) => f.rasterMs).reduce((a, b) => a + b) / totalFrames;
    final avgTotal = _frames.map((f) => f.totalMs).reduce((a, b) => a + b) / totalFrames;

    final sortedFrames = List<_FrameData>.from(_frames)
      ..sort((a, b) => b.totalMs.compareTo(a.totalMs));

    final p95 = sortedFrames[(0.05 * totalFrames).floor()].totalMs;
    final p99 = sortedFrames[(0.01 * totalFrames).floor()].totalMs;
    final worst = sortedFrames.first;

    final jankPercent = ((_jankFrames / totalFrames) * 100).toStringAsFixed(1);
    final severeJankPercent = ((_severeJankFrames / totalFrames) * 100).toStringAsFixed(1);

    // Frames over 100ms
    final over100ms = _frames.where((f) => f.totalMs > 100).toList();

    debugPrint('║ Total Frames: ${totalFrames.toString().padLeft(4)}                                       ║');
    debugPrint('║ Average Frame Time: ${avgTotal.toStringAsFixed(1)}ms                             ║');
    debugPrint('║   • Build: ${avgBuild.toStringAsFixed(1)}ms                                        ║');
    debugPrint('║   • Raster: ${avgRaster.toStringAsFixed(1)}ms                                       ║');
    debugPrint('╠═══════════════════════════════════════════════════════════════╣');
    debugPrint('║ Jank Analysis (>16ms):                                        ║');
    debugPrint('║   • Jank Frames: $_jankFrames ($jankPercent%)                           ║');
    debugPrint('║   • Severe Jank (>100ms): $_severeJankFrames ($severeJankPercent%)                  ║');
    debugPrint('╠═══════════════════════════════════════════════════════════════╣');
    debugPrint('║ Percentiles:                                                  ║');
    debugPrint('║   • P95: ${p95}ms                                                ║');
    debugPrint('║   • P99: ${p99}ms                                                ║');
    debugPrint('║   • Worst: ${worst.totalMs}ms (build: ${worst.buildMs}ms, raster: ${worst.rasterMs}ms)  ║');
    debugPrint('╠═══════════════════════════════════════════════════════════════╣');

    if (over100ms.isNotEmpty) {
      debugPrint('║ Frames Over 100ms: ${over100ms.length}                                  ║');
      debugPrint('╠═══════════════════════════════════════════════════════════════╣');
      for (final frame in over100ms.take(5)) {
        debugPrint(
          '║   • ${frame.totalMs}ms (build: ${frame.buildMs}ms, raster: ${frame.rasterMs}ms)             ║',
        );
      }
      if (over100ms.length > 5) {
        debugPrint('║   ... and ${over100ms.length - 5} more                                     ║');
      }
    }

    debugPrint('╚═══════════════════════════════════════════════════════════════╝');
    debugPrint('');
  }

  void _printCriticalWidgetsReport(int elapsedSeconds) {
    debugPrint('╔═══════════════════════════════════════════════════════════════╗');
    debugPrint('║ 3. CRITICAL WIDGETS REPORT                                    ║');
    debugPrint('╠═══════════════════════════════════════════════════════════════╣');

    final mapPageCount = _mapPageFullRebuilds;
    final markerLayerCount = _markerLayerRebuilds;
    final notificationListCount = _rebuildCounts['NotificationList'] ?? 0;
    final notificationsPageCount = _rebuildCounts['NotificationsPage'] ?? 0;

    final mapPageRate = elapsedSeconds > 0 ? mapPageCount / elapsedSeconds : 0.0;
    final markerRate = elapsedSeconds > 0 ? markerLayerCount / elapsedSeconds : 0.0;
    final notifListRate = elapsedSeconds > 0 ? notificationListCount / elapsedSeconds : 0.0;

    debugPrint('║ MapPage (Full Rebuilds):                                      ║');
    debugPrint('║   • Count: $mapPageCount                                              ║');
    debugPrint('║   • Rate: ${mapPageRate.toStringAsFixed(2)}/frame                                  ║');
    debugPrint('║   • Status: ${_getCriticalStatus(mapPageCount, 10)}                                 ║');
    debugPrint('╠═══════════════════════════════════════════════════════════════╣');
    debugPrint('║ MarkerLayer/FlutterMapAdapter:                                ║');
    debugPrint('║   • Count: $markerLayerCount                                              ║');
    debugPrint('║   • Rate: ${markerRate.toStringAsFixed(2)}/frame                                  ║');
    debugPrint('║   • Status: ${_getCriticalStatus(markerLayerCount, 20)}                             ║');
    debugPrint('╠═══════════════════════════════════════════════════════════════╣');
    debugPrint('║ NotificationList:                                             ║');
    debugPrint('║   • Count: $notificationListCount                                              ║');
    debugPrint('║   • Rate: ${notifListRate.toStringAsFixed(2)}/frame                                  ║');
    debugPrint('║   • Status: ${_getCriticalStatus(notificationListCount, 10)}                         ║');
    debugPrint('╠═══════════════════════════════════════════════════════════════╣');
    debugPrint('║ NotificationsPage:                                            ║');
    debugPrint('║   • Count: $notificationsPageCount                                              ║');
    debugPrint('╚═══════════════════════════════════════════════════════════════╝');
    debugPrint('');
  }

  void _printMarkerPerformanceReport() {
    final stats = MarkerPerformanceMonitor.instance.getStats();

    debugPrint('╔═══════════════════════════════════════════════════════════════╗');
    debugPrint('║ 4. MARKER PERFORMANCE                                         ║');
    debugPrint('╠═══════════════════════════════════════════════════════════════╣');
    debugPrint('║ Total Updates: ${stats.totalUpdates}                                       ║');
    debugPrint('║ Avg Processing Time: ${stats.averageProcessingMs.toStringAsFixed(1)}ms                    ║');
    debugPrint('║ Reuse Rate: ${(stats.averageReuseRate * 100).toStringAsFixed(1)}%                               ║');
    debugPrint('║ Total Created: ${stats.totalCreated}                                       ║');
    debugPrint('║ Total Reused: ${stats.totalReused}                                        ║');
    debugPrint('╚═══════════════════════════════════════════════════════════════╝');
    debugPrint('');
  }

  void _printRecommendations() {
    debugPrint('╔═══════════════════════════════════════════════════════════════╗');
    debugPrint('║ 5. RECOMMENDATIONS                                            ║');
    debugPrint('╠═══════════════════════════════════════════════════════════════╣');

    final recommendations = <String>[];

    // Check MapPage rebuilds
    if (_mapPageFullRebuilds > 10) {
      recommendations.add('⚠️ MapPage: ${_mapPageFullRebuilds} full rebuilds - Add const widgets');
    }

    // Check MarkerLayer
    if (_markerLayerRebuilds > 20) {
      recommendations.add('⚠️ MarkerLayer: ${_markerLayerRebuilds} rebuilds - Use RepaintBoundary');
    }

    // Check excessive widgets
    final excessive = _rebuildCounts.entries
        .where((e) => e.value > 20)
        .toList()
      ..sort((a, b) => b.value.compareTo(a.value));

    for (final entry in excessive) {
      if (entry.key != 'MapPage' && entry.key != 'MarkerLayer') {
        recommendations.add('⚠️ ${entry.key}: ${entry.value} rebuilds - Optimize');
      }
    }

    // Frame timing
    if (_severeJankFrames > 0) {
      recommendations.add('🔴 $_severeJankFrames frames >100ms - Critical optimization needed');
    }

    if (recommendations.isEmpty) {
      debugPrint('║ ✅ No critical issues detected                                ║');
      debugPrint('║ ✅ Keep rebuilds <10/frame for optimal performance            ║');
    } else {
      for (final rec in recommendations) {
        debugPrint('║ $rec');
      }
    }

    debugPrint('╚═══════════════════════════════════════════════════════════════╝');
    debugPrint('');
  }

  String _getRebuildStatus(int count, double rate) {
    if (count > 50 || rate > 5.0) {
      return '🔴'; // Critical
    } else if (count > 20 || rate > 2.0) {
      return '🟠'; // Warning
    } else if (count > 10) {
      return '🟡'; // Caution
    } else {
      return '🟢'; // Good
    }
  }

  String _getCriticalStatus(int count, int threshold) {
    if (count == 0) return '✅ No rebuilds (excellent)';
    if (count < threshold) return '✅ Within target (<$threshold)';
    if (count < threshold * 2) return '⚠️ Above target (optimize)';
    return '🔴 Excessive (critical)';
  }

  void _reset() {
    _rebuildTimestamps.clear();
    _rebuildCounts.clear();
    _frames.clear();
    _jankFrames = 0;
    _severeJankFrames = 0;
    _markerLayerRebuilds = 0;
    _mapPageFullRebuilds = 0;
  }

  bool get isAnalyzing => _isAnalyzing;
}

class _FrameData {
  const _FrameData({
    required this.buildMs,
    required this.rasterMs,
    required this.totalMs,
    required this.timestamp,
  });

  final int buildMs;
  final int rasterMs;
  final int totalMs;
  final DateTime timestamp;
}
