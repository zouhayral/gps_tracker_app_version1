import 'package:firebase_performance/firebase_performance.dart';
import 'package:flutter/foundation.dart';

/// Custom performance traces for async optimization monitoring
class PerformanceTraces {
  static final _instance = PerformanceTraces._();
  factory PerformanceTraces() => _instance;
  PerformanceTraces._();
  
  // Trace for WebSocket JSON parsing
  Trace? _jsonParseTrace;
  
  // Trace for position update batching
  Trace? _positionBatchTrace;
  
  // Trace for map rendering
  Trace? _mapRenderTrace;
  
  /// Start tracking WebSocket JSON parsing performance
  Future<void> startJsonParseTrace(int payloadSize) async {
    try {
      _jsonParseTrace = FirebasePerformance.instance.newTrace('ws_json_parse');
      _jsonParseTrace?.setMetric('payload_size_bytes', payloadSize);
      await _jsonParseTrace?.start();
    } catch (e) {
      if (kDebugMode) {
        print('[PERFORMANCE] Failed to start JSON parse trace: $e');
      }
    }
  }
  
  /// Stop JSON parse trace and record metrics
  Future<void> stopJsonParseTrace({
    required bool usedIsolate,
    required int deviceCount,
  }) async {
    try {
      _jsonParseTrace?.setMetric('used_isolate', usedIsolate ? 1 : 0);
      _jsonParseTrace?.setMetric('device_count', deviceCount);
      await _jsonParseTrace?.stop();
      _jsonParseTrace = null;
    } catch (e) {
      if (kDebugMode) {
        print('[PERFORMANCE] Failed to stop JSON parse trace: $e');
      }
    }
  }
  
  /// Start tracking position update batch
  Future<void> startPositionBatchTrace(int updateCount) async {
    try {
      _positionBatchTrace = FirebasePerformance.instance.newTrace('position_batch');
      _positionBatchTrace?.setMetric('update_count', updateCount);
      await _positionBatchTrace?.start();
    } catch (e) {
      if (kDebugMode) {
        print('[PERFORMANCE] Failed to start position batch trace: $e');
      }
    }
  }
  
  /// Stop position batch trace
  Future<void> stopPositionBatchTrace({
    required int flushedCount,
    required int batchWindowMs,
  }) async {
    try {
      _positionBatchTrace?.setMetric('flushed_count', flushedCount);
      _positionBatchTrace?.setMetric('batch_window_ms', batchWindowMs);
      await _positionBatchTrace?.stop();
      _positionBatchTrace = null;
    } catch (e) {
      if (kDebugMode) {
        print('[PERFORMANCE] Failed to stop position batch trace: $e');
      }
    }
  }
  
  /// Start tracking map render performance
  Future<void> startMapRenderTrace() async {
    try {
      _mapRenderTrace = FirebasePerformance.instance.newTrace('map_render');
      await _mapRenderTrace?.start();
    } catch (e) {
      if (kDebugMode) {
        print('[PERFORMANCE] Failed to start map render trace: $e');
      }
    }
  }
  
  /// Stop map render trace with metrics
  Future<void> stopMapRenderTrace({
    required int markerCount,
    required int cacheHits,
    required int cacheMisses,
  }) async {
    try {
      _mapRenderTrace?.setMetric('marker_count', markerCount);
      _mapRenderTrace?.setMetric('cache_hits', cacheHits);
      _mapRenderTrace?.setMetric('cache_misses', cacheMisses);
      final hitRate = cacheHits + cacheMisses > 0
          ? (cacheHits / (cacheHits + cacheMisses) * 100).round()
          : 0;
      _mapRenderTrace?.setMetric('cache_hit_rate_percent', hitRate);
      await _mapRenderTrace?.stop();
      _mapRenderTrace = null;
    } catch (e) {
      if (kDebugMode) {
        print('[PERFORMANCE] Failed to stop map render trace: $e');
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
    } catch (e) {
      if (kDebugMode) {
        print('[PERFORMANCE] Failed to record metric $name: $e');
      }
    }
  }
  
  /// Record frame time metric
  static Future<void> recordFrameTime(int frameTimeMs) async {
    try {
      final trace = FirebasePerformance.instance.newTrace('frame_time');
      trace.setMetric('frame_time_ms', frameTimeMs);
      await trace.start();
      await trace.stop();
    } catch (e) {
      if (kDebugMode) {
        print('[PERFORMANCE] Failed to record frame time: $e');
      }
    }
  }
  
  /// Record CPU usage metric
  static Future<void> recordCpuUsage(double cpuPercent) async {
    try {
      final trace = FirebasePerformance.instance.newTrace('cpu_usage');
      trace.setMetric('cpu_percent', (cpuPercent * 100).round());
      await trace.start();
      await trace.stop();
    } catch (e) {
      if (kDebugMode) {
        print('[PERFORMANCE] Failed to record CPU usage: $e');
      }
    }
  }
}
