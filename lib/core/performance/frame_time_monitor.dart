import 'package:flutter/foundation.dart';
import 'package:flutter/scheduler.dart';

/// Monitors frame rendering performance and reports metrics
/// 
/// Note: Firebase Performance integration is optional and will be added
/// when firebase_performance package is installed. This class works
/// standalone for local monitoring.
class FrameTimeMonitor {
  static final _instance = FrameTimeMonitor._();
  factory FrameTimeMonitor() => _instance;
  FrameTimeMonitor._();
  
  bool _isMonitoring = false;
  final List<int> _frameTimeSamples = [];
  static const _sampleSize = 60; // Monitor 60 frames (~1 second at 60 FPS)
  
  // Statistics
  int _totalFrames = 0;
  int _droppedFrames = 0;
  int _avgFrameTime = 0;
  int _p95FrameTime = 0;
  int _maxFrameTime = 0;
  
  /// Get current statistics
  Map<String, dynamic> get stats => {
    'total_frames': _totalFrames,
    'dropped_frames': _droppedFrames,
    'avg_frame_time_ms': _avgFrameTime,
    'p95_frame_time_ms': _p95FrameTime,
    'max_frame_time_ms': _maxFrameTime,
    'dropped_percent': _totalFrames > 0 
        ? (_droppedFrames / _totalFrames * 100).toStringAsFixed(1) 
        : '0.0',
  };
  
  /// Start monitoring frame times
  void start() {
    if (_isMonitoring) return;
    _isMonitoring = true;
    
    if (kDebugMode) {
      print('[FRAME_MONITOR] ✅ Started monitoring frame times');
    }
    
    SchedulerBinding.instance.addTimingsCallback(_onFrameTimings);
  }
  
  /// Stop monitoring
  void stop() {
    _isMonitoring = false;
    SchedulerBinding.instance.removeTimingsCallback(_onFrameTimings);
    
    if (kDebugMode) {
      print('[FRAME_MONITOR] ⏹️ Stopped monitoring. Final stats: $stats');
    }
  }
  
  void _onFrameTimings(List<FrameTiming> timings) {
    if (!_isMonitoring) return;
    
    for (final timing in timings) {
      final frameTimeMs = timing.totalSpan.inMilliseconds;
      _frameTimeSamples.add(frameTimeMs);
      _totalFrames++;
      
      // Track dropped frames (>16ms = missed 60 FPS target)
      if (frameTimeMs > 16) {
        _droppedFrames++;
      }
      
      // Report to Firebase every 60 frames
      if (_frameTimeSamples.length >= _sampleSize) {
        _reportMetrics();
      }
    }
  }
  
  void _reportMetrics() {
    if (_frameTimeSamples.isEmpty) return;
    
    // Calculate statistics
    _frameTimeSamples.sort();
    _avgFrameTime = _frameTimeSamples.reduce((a, b) => a + b) ~/ _frameTimeSamples.length;
    final p95Index = (_frameTimeSamples.length * 0.95).round();
    _p95FrameTime = _frameTimeSamples[p95Index];
    _maxFrameTime = _frameTimeSamples.last;
    
    // Count dropped frames in this batch
    final droppedInBatch = _frameTimeSamples.where((t) => t > 16).length;
    final droppedPercent = (droppedInBatch / _frameTimeSamples.length * 100).round();
    
    // Log if performance is degraded
    if (_avgFrameTime > 16 || _p95FrameTime > 20) {
      if (kDebugMode) {
        print('[FRAME_MONITOR] ⚠️ Performance degraded: avg=${_avgFrameTime}ms, p95=${_p95FrameTime}ms, dropped=$droppedPercent%');
      }
    } else {
      if (kDebugMode) {
        print('[FRAME_MONITOR] ✅ Good performance: avg=${_avgFrameTime}ms, p95=${_p95FrameTime}ms');
      }
    }
    
    // TODO: Report to Firebase Performance when package is added
    // PerformanceTraces.recordMetric('frame_time_avg_ms', _avgFrameTime);
    // PerformanceTraces.recordMetric('frame_time_p95_ms', _p95FrameTime);
    // PerformanceTraces.recordMetric('frame_time_max_ms', _maxFrameTime);
    // PerformanceTraces.recordMetric('dropped_frames_percent', droppedPercent);
    
    _frameTimeSamples.clear();
  }
  
  /// Reset all statistics
  void reset() {
    _totalFrames = 0;
    _droppedFrames = 0;
    _avgFrameTime = 0;
    _p95FrameTime = 0;
    _maxFrameTime = 0;
    _frameTimeSamples.clear();
    
    if (kDebugMode) {
      print('[FRAME_MONITOR] 🔄 Statistics reset');
    }
  }
}
