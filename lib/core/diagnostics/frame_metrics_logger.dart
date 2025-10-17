import 'package:flutter/foundation.dart';
import 'package:flutter/scheduler.dart';
import 'package:my_app_gps/core/diagnostics/diagnostics_config.dart';

/// Lightweight frame metrics logger for performance validation
///
/// Tracks:
/// - Frame build time (ms)
/// - Jank detection (>16ms frames for 60 FPS target)
/// - Rolling average and statistics
///
/// Usage:
/// ```dart
/// final logger = FrameMetricsLogger.instance;
/// logger.start();
/// // ... perform actions ...
/// logger.printSummary();
/// logger.stop();
/// ```
class FrameMetricsLogger {
  FrameMetricsLogger._();

  static final instance = FrameMetricsLogger._();

  bool _isRunning = false;
  final List<FrameTiming> _frameTimings = [];
  final List<double> _buildTimes = [];
  int _jankCount = 0;
  DateTime? _startTime;

  // Frame timing thresholds
  static const double _jankThreshold = 16.67; // Frames over this are "janky"

  /// Start collecting frame metrics
  void start() {
    if (_isRunning) {
      debugPrint('[FrameMetrics] Already running');
      return;
    }

    _isRunning = true;
    _frameTimings.clear();
    _buildTimes.clear();
    _jankCount = 0;
    _startTime = DateTime.now();

    SchedulerBinding.instance.addTimingsCallback(_onFrameTiming);
    if (kDebugMode && DiagnosticsConfig.enablePerfLogs) {
      debugPrint('[FrameMetrics] ✅ Started collecting metrics');
    }
  }

  /// Stop collecting frame metrics
  void stop() {
    if (!_isRunning) {
      debugPrint('[FrameMetrics] Not running');
      return;
    }

    _isRunning = false;
    SchedulerBinding.instance.removeTimingsCallback(_onFrameTiming);
    if (kDebugMode && DiagnosticsConfig.enablePerfLogs) {
      debugPrint('[FrameMetrics] ⏹️  Stopped collecting metrics');
    }
  }

  /// Callback for frame timings
  void _onFrameTiming(List<FrameTiming> timings) {
    if (!_isRunning) return;

    for (final timing in timings) {
      _frameTimings.add(timing);

      // Calculate total frame time (build + raster)
      final buildTime = timing.buildDuration.inMicroseconds / 1000.0;
      final rasterTime = timing.rasterDuration.inMicroseconds / 1000.0;
      final totalTime = buildTime + rasterTime;

      _buildTimes.add(totalTime);

      // Detect jank (frame took longer than target)
      if (totalTime > _jankThreshold) {
        _jankCount++;
        if (kDebugMode && DiagnosticsConfig.enablePerfLogs) {
          debugPrint(
              '[FrameMetrics] ⚠️  JANK: ${totalTime.toStringAsFixed(2)}ms (build: ${buildTime.toStringAsFixed(2)}ms, raster: ${rasterTime.toStringAsFixed(2)}ms)');
        }
      }
    }
  }

  /// Get average frame time
  double get averageFrameTime {
    if (_buildTimes.isEmpty) return 0.0;
    return _buildTimes.reduce((a, b) => a + b) / _buildTimes.length;
  }

  /// Get maximum frame time (worst case)
  double get maxFrameTime {
    if (_buildTimes.isEmpty) return 0.0;
    return _buildTimes.reduce((a, b) => a > b ? a : b);
  }

  /// Get minimum frame time (best case)
  double get minFrameTime {
    if (_buildTimes.isEmpty) return 0.0;
    return _buildTimes.reduce((a, b) => a < b ? a : b);
  }

  /// Get 95th percentile frame time
  double get p95FrameTime {
    if (_buildTimes.isEmpty) return 0.0;
    final sorted = List<double>.from(_buildTimes)..sort();
    final index = (sorted.length * 0.95).floor();
    return sorted[index];
  }

  /// Get 99th percentile frame time
  double get p99FrameTime {
    if (_buildTimes.isEmpty) return 0.0;
    final sorted = List<double>.from(_buildTimes)..sort();
    final index = (sorted.length * 0.99).floor();
    return sorted[index];
  }

  /// Get total frame count
  int get totalFrames => _buildTimes.length;

  /// Get jank count
  int get jankCount => _jankCount;

  /// Get jank percentage
  double get jankPercentage {
    if (_buildTimes.isEmpty) return 0.0;
    return (_jankCount / _buildTimes.length) * 100;
  }

  /// Get frames per second estimate
  double get estimatedFps {
    if (averageFrameTime == 0) return 0.0;
    return 1000 / averageFrameTime;
  }

  /// Get duration since start
  Duration get elapsedTime {
    if (_startTime == null) return Duration.zero;
    return DateTime.now().difference(_startTime!);
  }

  /// Print summary statistics
  void printSummary() {
    if (_buildTimes.isEmpty) {
      debugPrint('[FrameMetrics] No frames recorded yet');
      return;
    }

    final elapsed = elapsedTime.inMilliseconds / 1000.0;

    if (kDebugMode && DiagnosticsConfig.enablePerfLogs) {
      debugPrint('');
      debugPrint(
          '╔═══════════════════════════════════════════════════════════╗');
      debugPrint(
          '║           FRAME METRICS SUMMARY                           ║');
      debugPrint(
          '╠═══════════════════════════════════════════════════════════╣');
      debugPrint('║ Duration:        ${elapsed.toStringAsFixed(1)}s');
      debugPrint('║ Total Frames:    $totalFrames');
      debugPrint(
          '║ Avg Frame Time:  ${averageFrameTime.toStringAsFixed(2)} ms');
      debugPrint('║ Min Frame Time:  ${minFrameTime.toStringAsFixed(2)} ms');
      debugPrint('║ Max Frame Time:  ${maxFrameTime.toStringAsFixed(2)} ms');
      debugPrint('║ P95 Frame Time:  ${p95FrameTime.toStringAsFixed(2)} ms');
      debugPrint('║ P99 Frame Time:  ${p99FrameTime.toStringAsFixed(2)} ms');
      debugPrint('║ Estimated FPS:   ${estimatedFps.toStringAsFixed(1)}');
      debugPrint(
          '╠═══════════════════════════════════════════════════════════╣');
      debugPrint(
          '║ Jank Frames:     $_jankCount/${_buildTimes.length} (${jankPercentage.toStringAsFixed(1)}%)');
      debugPrint(
          '║ Jank Threshold:  ${_jankThreshold.toStringAsFixed(2)} ms (60 FPS target)');
      debugPrint(
          '╠═══════════════════════════════════════════════════════════╣');

      if (jankPercentage < 1.0) {
        debugPrint(
            '║ Status: ✅ EXCELLENT - Smooth performance                  ║');
      } else if (jankPercentage < 5.0) {
        debugPrint(
            '║ Status: ✅ GOOD - Minor jank detected                      ║');
      } else if (jankPercentage < 10.0) {
        debugPrint(
            '║ Status: ⚠️  WARNING - Noticeable jank                      ║');
      } else {
        debugPrint(
            '║ Status: ❌ POOR - Significant performance issues           ║');
      }

      debugPrint(
          '╚═══════════════════════════════════════════════════════════╝');
      debugPrint('');

      // One-line summary for quick validation
      debugPrint(
          '[FrameMetrics] Frame avg: ${averageFrameTime.toStringAsFixed(1)} ms | Jank: $_jankCount/$totalFrames | FPS: ${estimatedFps.toStringAsFixed(1)}');
    }
  }

  /// Print compact summary (one line)
  void printCompactSummary() {
    if (_buildTimes.isEmpty) {
      if (kDebugMode && DiagnosticsConfig.enablePerfLogs) {
        debugPrint('[FrameMetrics] No data');
      }
      return;
    }

    debugPrint(
        '[FrameMetrics] Frame avg: ${averageFrameTime.toStringAsFixed(1)} ms | Jank: $_jankCount/$totalFrames | FPS: ${estimatedFps.toStringAsFixed(1)}');
  }

  /// Reset all metrics
  void reset() {
    _frameTimings.clear();
    _buildTimes.clear();
    _jankCount = 0;
    _startTime = null;
    debugPrint('[FrameMetrics] Reset');
  }

  /// Export metrics for analysis
  Map<String, dynamic> exportMetrics() {
    return {
      'totalFrames': totalFrames,
      'averageFrameTime': averageFrameTime,
      'minFrameTime': minFrameTime,
      'maxFrameTime': maxFrameTime,
      'p95FrameTime': p95FrameTime,
      'p99FrameTime': p99FrameTime,
      'jankCount': jankCount,
      'jankPercentage': jankPercentage,
      'estimatedFps': estimatedFps,
      'elapsedSeconds': elapsedTime.inMilliseconds / 1000.0,
      'rawBuildTimes': _buildTimes,
    };
  }
}

/// Convenience wrapper for automatic start/stop
class FrameMetricsSession {
  FrameMetricsSession() {
    FrameMetricsLogger.instance.reset();
    FrameMetricsLogger.instance.start();
  }

  void printSummary() {
    FrameMetricsLogger.instance.printSummary();
  }

  void printCompact() {
    FrameMetricsLogger.instance.printCompactSummary();
  }

  void end() {
    FrameMetricsLogger.instance.stop();
    FrameMetricsLogger.instance.printSummary();
  }

  Map<String, dynamic> export() {
    return FrameMetricsLogger.instance.exportMetrics();
  }
}
