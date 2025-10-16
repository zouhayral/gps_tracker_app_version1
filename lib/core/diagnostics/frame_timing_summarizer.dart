import 'package:flutter/foundation.dart';
import 'package:flutter/scheduler.dart';
import 'package:my_app_gps/core/diagnostics/diagnostics_config.dart';

/// Frame timing summarizer for identifying widget tree bottlenecks
/// Collects frame timing data and reports slow frames
class FrameTimingSummarizer {
  FrameTimingSummarizer._();
  
  static final FrameTimingSummarizer instance = FrameTimingSummarizer._();
  
  final List<FrameTiming> _recentFrames = [];
  final int _maxFrameHistory = 120; // 2 seconds at 60fps
  
  bool _isEnabled = false;
  int _slowFrameCount = 0;
  int _totalFrameCount = 0;
  
  // Thresholds (60fps = 16.67ms target)
  static const Duration _slowFrameThreshold = Duration(milliseconds: 20); // >20ms is considered slow
  static const Duration _jankyFrameThreshold = Duration(milliseconds: 33); // >33ms is janky (dropped frame)
  
  /// Enable frame timing collection
  void enable() {
    if (_isEnabled) return;
    
    _isEnabled = true;
    _slowFrameCount = 0;
    _totalFrameCount = 0;
    _recentFrames.clear();
    
    // Start listening to frame timings
    SchedulerBinding.instance.addTimingsCallback(_onFrameTiming);
    
    if (kDebugMode && DiagnosticsConfig.enablePerfLogs) {
      debugPrint('[FrameTiming] Enabled - monitoring for slow frames');
    }
  }
  
  /// Disable frame timing collection
  void disable() {
    if (!_isEnabled) return;
    
    _isEnabled = false;
    SchedulerBinding.instance.removeTimingsCallback(_onFrameTiming);
    
    if (kDebugMode && DiagnosticsConfig.enablePerfLogs) {
      debugPrint('[FrameTiming] Disabled');
    }
  }
  
  /// Frame timing callback
  void _onFrameTiming(List<FrameTiming> timings) {
    if (!_isEnabled) return;
    
    for (final timing in timings) {
      _totalFrameCount++;
      
      // Calculate total frame time
      final buildDuration = timing.buildDuration;
      final rasterDuration = timing.rasterDuration;
      final totalDuration = buildDuration + rasterDuration;
      
      // Track slow frames
      if (totalDuration > _slowFrameThreshold) {
        _slowFrameCount++;
        
        if (kDebugMode && DiagnosticsConfig.enablePerfLogs && totalDuration > _jankyFrameThreshold) {
          debugPrint(
            '[FrameTiming] JANKY FRAME detected! '
            'Build: ${buildDuration.inMicroseconds / 1000}ms, '
            'Raster: ${rasterDuration.inMicroseconds / 1000}ms, '
            'Total: ${totalDuration.inMicroseconds / 1000}ms'
          );
        }
      }
      
      // Keep recent frames
      _recentFrames.add(timing);
      if (_recentFrames.length > _maxFrameHistory) {
        _recentFrames.removeAt(0);
      }
      // Log periodic summaries (every 120 frames) instead of printing per-frame
      // to avoid console jank. 120 frames ≈ 2 seconds at 60fps.
      if (_totalFrameCount % 120 == 0) {
        if (kDebugMode && DiagnosticsConfig.enablePerfLogs) {
          // Print a compact stats summary every 120 frames
          debugPrint('[FrameTiming] Summary (every 120 frames):');
          printStats();
        }
      }
    }
  }
  
  /// Get frame timing statistics
  FrameTimingStats getStats() {
    if (_recentFrames.isEmpty) {
      return FrameTimingStats.empty();
    }
    
    final buildTimes = <double>[];
    final rasterTimes = <double>[];
    final totalTimes = <double>[];
    
    for (final timing in _recentFrames) {
      final buildMs = timing.buildDuration.inMicroseconds / 1000;
      final rasterMs = timing.rasterDuration.inMicroseconds / 1000;
      final totalMs = buildMs + rasterMs;
      
      buildTimes.add(buildMs);
      rasterTimes.add(rasterMs);
      totalTimes.add(totalMs);
    }
    
    buildTimes.sort();
    rasterTimes.sort();
    totalTimes.sort();
    
    return FrameTimingStats(
      avgBuildTime: _average(buildTimes),
      avgRasterTime: _average(rasterTimes),
      avgTotalTime: _average(totalTimes),
      p50TotalTime: _percentile(totalTimes, 0.50),
      p90TotalTime: _percentile(totalTimes, 0.90),
      p99TotalTime: _percentile(totalTimes, 0.99),
      maxTotalTime: totalTimes.last,
      slowFrameCount: _slowFrameCount,
      totalFrameCount: _totalFrameCount,
      slowFramePercentage: _totalFrameCount > 0 
          ? (_slowFrameCount / _totalFrameCount) * 100 
          : 0.0,
    );
  }
  
  /// Reset statistics
  void reset() {
    _slowFrameCount = 0;
    _totalFrameCount = 0;
    _recentFrames.clear();
    
    if (kDebugMode) {
      debugPrint('[FrameTiming] Stats reset');
    }
  }
  
  /// Print current statistics
  void printStats() {
    final stats = getStats();
    if (kDebugMode && DiagnosticsConfig.enablePerfLogs) {
      debugPrint('''
[FrameTiming] Statistics:
  Total Frames: ${stats.totalFrameCount}
  Slow Frames: ${stats.slowFrameCount} (${stats.slowFramePercentage.toStringAsFixed(1)}%)
  Avg Build: ${stats.avgBuildTime.toStringAsFixed(2)}ms
  Avg Raster: ${stats.avgRasterTime.toStringAsFixed(2)}ms
  Avg Total: ${stats.avgTotalTime.toStringAsFixed(2)}ms
  P50: ${stats.p50TotalTime.toStringAsFixed(2)}ms
  P90: ${stats.p90TotalTime.toStringAsFixed(2)}ms
  P99: ${stats.p99TotalTime.toStringAsFixed(2)}ms
  Max: ${stats.maxTotalTime.toStringAsFixed(2)}ms
  Target FPS: ${stats.estimatedFPS.toStringAsFixed(1)}
''');
    }
  }
  
  double _average(List<double> values) {
    if (values.isEmpty) return 0.0;
    return values.reduce((a, b) => a + b) / values.length;
  }
  
  double _percentile(List<double> sortedValues, double percentile) {
    if (sortedValues.isEmpty) return 0.0;
    final index = (sortedValues.length * percentile).floor();
    return sortedValues[index.clamp(0, sortedValues.length - 1)];
  }
}

/// Frame timing statistics
class FrameTimingStats {
  const FrameTimingStats({
    required this.avgBuildTime,
    required this.avgRasterTime,
    required this.avgTotalTime,
    required this.p50TotalTime,
    required this.p90TotalTime,
    required this.p99TotalTime,
    required this.maxTotalTime,
    required this.slowFrameCount,
    required this.totalFrameCount,
    required this.slowFramePercentage,
  });
  
  factory FrameTimingStats.empty() {
    return const FrameTimingStats(
      avgBuildTime: 0.0,
      avgRasterTime: 0.0,
      avgTotalTime: 0.0,
      p50TotalTime: 0.0,
      p90TotalTime: 0.0,
      p99TotalTime: 0.0,
      maxTotalTime: 0.0,
      slowFrameCount: 0,
      totalFrameCount: 0,
      slowFramePercentage: 0.0,
    );
  }
  
  final double avgBuildTime;
  final double avgRasterTime;
  final double avgTotalTime;
  final double p50TotalTime;
  final double p90TotalTime;
  final double p99TotalTime;
  final double maxTotalTime;
  final int slowFrameCount;
  final int totalFrameCount;
  final double slowFramePercentage;
  
  /// Estimated FPS based on average frame time
  double get estimatedFPS {
    if (avgTotalTime <= 0) return 60.0;
    return 1000.0 / avgTotalTime;
  }
  
  /// Whether performance is acceptable (>90% frames under 16.67ms)
  bool get isPerformanceGood {
    return slowFramePercentage < 10.0 && estimatedFPS >= 55.0;
  }
}
