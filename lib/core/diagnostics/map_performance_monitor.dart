import 'dart:async';
import 'dart:io'; // For ProcessInfo
import 'package:flutter/foundation.dart';
import 'package:flutter/scheduler.dart';

/// Lightweight performance monitoring for map subsystem
/// 
/// Tracks:
/// - Frame timing (detect jank >16ms)
/// - Memory usage (RSS every 5s)
/// - Marker cache stats (when integrated with EnhancedMarkerCache)
/// 
/// Usage:
/// ```dart
/// if (kDebugMode) {
///   MapPerformanceMonitor.startProfiling();
/// }
/// ```
class MapPerformanceMonitor {
  static bool _isProfilingActive = false;
  static Timer? _memoryTimer;
  static final List<Duration> _frameTimes = [];
  static DateTime? _profilingStartTime;

  /// Start performance profiling
  /// 
  /// Safe to call multiple times - subsequent calls are no-ops
  static void startProfiling() {
    if (_isProfilingActive) {
      if (kDebugMode) {
        debugPrint('[PERF] ⚠️ Profiling already active');
      }
      return;
    }

    _isProfilingActive = true;
    _profilingStartTime = DateTime.now();
    _frameTimes.clear();

    if (kDebugMode) {
      debugPrint('[PERF] 🎬 Started profiling at ${_profilingStartTime?.toIso8601String()}');
    }

    // Frame timing callback
    SchedulerBinding.instance.addTimingsCallback(_recordFrameTiming);

    // Memory tracking (every 5 seconds)
    _memoryTimer = Timer.periodic(const Duration(seconds: 5), (_) {
      _logMemoryUsage();
    });
  }

  /// Stop performance profiling and print summary
  static void stopProfiling() {
    if (!_isProfilingActive) {
      if (kDebugMode) {
        debugPrint('[PERF] ⚠️ Profiling not active');
      }
      return;
    }

    _isProfilingActive = false;
    _memoryTimer?.cancel();
    _memoryTimer = null;

    // Print summary
    _printSummary();

    if (kDebugMode) {
      debugPrint('[PERF] 🛑 Stopped profiling');
    }
  }

  static void _recordFrameTiming(List<FrameTiming> timings) {
    if (!_isProfilingActive) return;

    for (final timing in timings) {
      final totalSpan = timing.totalSpan;
      _frameTimes.add(totalSpan);

      // Log jank events (>16ms for 60 FPS)
      if (totalSpan > const Duration(milliseconds: 16)) {
        final buildMs = timing.buildDuration.inMilliseconds;
        final rasterMs = timing.rasterDuration.inMilliseconds;
        if (kDebugMode) {
          debugPrint('[PERF] ⚠️ JANK detected: ${totalSpan.inMilliseconds}ms '
              '(build: ${buildMs}ms, raster: ${rasterMs}ms)');
        }
      }
    }
  }

  static void _logMemoryUsage() {
    if (!_isProfilingActive) return;

    try {
      final rssBytes = ProcessInfo.currentRss;
      final rssMb = rssBytes / (1024 * 1024);
      
      if (kDebugMode) {
        debugPrint('[PERF] Memory: ${rssMb.toStringAsFixed(1)} MB');
      }
    } catch (e) {
      if (kDebugMode) {
        debugPrint('[PERF] ⚠️ Failed to read memory: $e');
      }
    }
  }

  static void _printSummary() {
    if (_frameTimes.isEmpty) {
      if (kDebugMode) {
        debugPrint('[PERF] No frame data collected');
      }
      return;
    }

    // Calculate statistics
    final totalFrames = _frameTimes.length;
    final avgMs = _frameTimes
        .map((d) => d.inMilliseconds)
        .reduce((a, b) => a + b) / totalFrames;

    // Sort for percentiles
    final sortedTimes = List<Duration>.from(_frameTimes)..sort();
    final p50 = sortedTimes[(0.50 * totalFrames).floor()].inMilliseconds;
    final p95 = sortedTimes[(0.95 * totalFrames).floor()].inMilliseconds;
    final p99 = sortedTimes[(0.99 * totalFrames).floor()].inMilliseconds;

    // Count jank events
    final jankCount = _frameTimes
        .where((d) => d > const Duration(milliseconds: 16))
        .length;
    final jankPercent = (jankCount / totalFrames) * 100;

    if (kDebugMode) {
      debugPrint('[PERF] ═══════════════════════════════════════');
      debugPrint('[PERF] Performance Summary');
      debugPrint('[PERF] ═══════════════════════════════════════');
      debugPrint('[PERF] Total frames: $totalFrames');
      debugPrint('[PERF] Frame time (avg): ${avgMs.toStringAsFixed(1)}ms');
      debugPrint('[PERF] Frame time (p50): ${p50}ms');
      debugPrint('[PERF] Frame time (p95): ${p95}ms');
      debugPrint('[PERF] Frame time (p99): ${p99}ms');
      debugPrint('[PERF] Jank events: $jankCount (${jankPercent.toStringAsFixed(1)}%)');
      debugPrint('[PERF] Target: <10ms avg, <16ms p99, <5% jank');
      debugPrint('[PERF] ═══════════════════════════════════════');
    }
  }

  /// Log marker cache statistics
  /// 
  /// Call this from EnhancedMarkerCache to track reuse rates
  static void logMarkerCacheStats({
    required int totalMarkers,
    required int reused,
    required int created,
    required double reusePercent,
  }) {
    if (!_isProfilingActive) return;

    if (kDebugMode) {
      debugPrint('[PERF] Marker cache: $totalMarkers total, '
          '$reused reused (${reusePercent.toStringAsFixed(1)}%), '
          '$created created');
    }
  }

  /// Check if profiling is active
  static bool get isActive => _isProfilingActive;
}
