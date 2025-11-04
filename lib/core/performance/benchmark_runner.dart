import 'dart:convert';
import 'dart:io';
import 'package:firebase_performance/firebase_performance.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/scheduler.dart';
import 'package:path_provider/path_provider.dart';

/// Comprehensive benchmark runner for production verification
/// 
/// Features:
/// - Frame time monitoring with jank detection
/// - Firebase Performance trace integration
/// - Network efficiency metrics
/// - Memory profiling helpers
/// - JSON benchmark report generation
class BenchmarkRunner {
  BenchmarkRunner({required this.testName});

  final String testName;
  final _metrics = <String, dynamic>{};
  final _frameTimeSamples = <int>[];
  final _networkRequests = <NetworkRequestMetric>[];
  
  Trace? _activeTrace;
  Stopwatch? _testStopwatch;
  bool _isMonitoring = false;
  
  /// Start benchmark test
  Future<void> start() async {
    if (_isMonitoring) {
      debugPrint('[Benchmark] ⚠️ Already running, call stop() first');
      return;
    }
    
    _isMonitoring = true;
    _testStopwatch = Stopwatch()..start();
    _frameTimeSamples.clear();
    _networkRequests.clear();
    _metrics.clear();
    
    // Start Firebase trace
    try {
      _activeTrace = FirebasePerformance.instance.newTrace('benchmark_$testName');
      await _activeTrace?.start();
      debugPrint('[Benchmark] 🚀 Started benchmark: $testName');
    } catch (e) {
      debugPrint('[Benchmark] ⚠️ Firebase trace failed to start: $e');
    }
    
    // Start frame monitoring
    SchedulerBinding.instance.addTimingsCallback(_onFrameTimings);
  }
  
  /// Stop benchmark and generate report
  Future<BenchmarkReport> stop() async {
    if (!_isMonitoring) {
      throw StateError('Benchmark not running');
    }
    
    _isMonitoring = false;
    _testStopwatch?.stop();
    
    // Stop frame monitoring
    SchedulerBinding.instance.removeTimingsCallback(_onFrameTimings);
    
    // Stop Firebase trace
    try {
      await _activeTrace?.stop();
      debugPrint('[Benchmark] ⏹️ Stopped benchmark: $testName');
    } catch (e) {
      debugPrint('[Benchmark] ⚠️ Firebase trace failed to stop: $e');
    }
    
    return _generateReport();
  }
  
  /// Record network request metrics
  void recordNetworkRequest({
    required String url,
    required int statusCode,
    required Duration latency,
    required int responseBytes,
    bool isRetry = false,
  }) {
    final metric = NetworkRequestMetric(
      url: url,
      statusCode: statusCode,
      latency: latency,
      responseBytes: responseBytes,
      isRetry: isRetry,
      timestamp: DateTime.now(),
    );
    
    _networkRequests.add(metric);
    
    debugPrint(
      '[Benchmark] 🛰️ Network: ${metric.statusCode} ${metric.url} '
      '(${metric.latency.inMilliseconds}ms, ${metric.responseBytes} bytes)',
    );
  }
  
  /// Record custom metric
  void recordMetric(String key, dynamic value) {
    _metrics[key] = value;
  }
  
  void _onFrameTimings(List<FrameTiming> timings) {
    if (!_isMonitoring) return;
    
    for (final timing in timings) {
      final frameTimeMs = timing.totalSpan.inMilliseconds;
      _frameTimeSamples.add(frameTimeMs);
    }
  }
  
  BenchmarkReport _generateReport() {
    final report = BenchmarkReport(
      testName: testName,
      duration: _testStopwatch?.elapsed ?? Duration.zero,
      frameMetrics: _calculateFrameMetrics(),
      networkMetrics: _calculateNetworkMetrics(),
      customMetrics: Map.from(_metrics),
      timestamp: DateTime.now(),
    );
    
    _logReport(report);
    return report;
  }
  
  FrameMetrics _calculateFrameMetrics() {
    if (_frameTimeSamples.isEmpty) {
      return FrameMetrics(
        totalFrames: 0,
        droppedFrames: 0,
        droppedPercent: 0.0,
        avgFrameTimeMs: 0.0,
        p95FrameTimeMs: 0,
        maxFrameTimeMs: 0,
      );
    }
    
    _frameTimeSamples.sort();
    
    final totalFrames = _frameTimeSamples.length;
    final droppedFrames = _frameTimeSamples.where((t) => t > 16).length;
    final droppedPercent = (droppedFrames / totalFrames * 100);
    
    final avgFrameTimeMs = _frameTimeSamples.reduce((a, b) => a + b) / totalFrames;
    final p95Index = (totalFrames * 0.95).round().clamp(0, totalFrames - 1);
    final p95FrameTimeMs = _frameTimeSamples[p95Index];
    final maxFrameTimeMs = _frameTimeSamples.last;
    
    return FrameMetrics(
      totalFrames: totalFrames,
      droppedFrames: droppedFrames,
      droppedPercent: droppedPercent,
      avgFrameTimeMs: avgFrameTimeMs,
      p95FrameTimeMs: p95FrameTimeMs,
      maxFrameTimeMs: maxFrameTimeMs,
    );
  }
  
  NetworkMetrics _calculateNetworkMetrics() {
    if (_networkRequests.isEmpty) {
      return NetworkMetrics(
        totalRequests: 0,
        successfulRequests: 0,
        retryCount: 0,
        avgLatencyMs: 0.0,
        maxLatencyMs: 0,
        totalBytesTransferred: 0,
      );
    }
    
    final totalRequests = _networkRequests.length;
    final successfulRequests = _networkRequests.where((r) => r.statusCode == 200).length;
    final retryCount = _networkRequests.where((r) => r.isRetry).length;
    
    final latencies = _networkRequests.map((r) => r.latency.inMilliseconds).toList();
    final avgLatencyMs = latencies.reduce((a, b) => a + b) / latencies.length;
    final maxLatencyMs = latencies.reduce((a, b) => a > b ? a : b);
    
    final totalBytesTransferred = _networkRequests
        .map((r) => r.responseBytes)
        .fold<int>(0, (sum, bytes) => sum + bytes);
    
    return NetworkMetrics(
      totalRequests: totalRequests,
      successfulRequests: successfulRequests,
      retryCount: retryCount,
      avgLatencyMs: avgLatencyMs,
      maxLatencyMs: maxLatencyMs,
      totalBytesTransferred: totalBytesTransferred,
    );
  }
  
  void _logReport(BenchmarkReport report) {
    final frame = report.frameMetrics;
    final network = report.networkMetrics;
    
    debugPrint('\n========================================');
    debugPrint('📊 Benchmark Report: ${report.testName}');
    debugPrint('========================================');
    debugPrint('⏱️  Duration: ${report.duration.inMilliseconds}ms');
    debugPrint('');
    debugPrint('🎬 Frame Performance:');
    debugPrint('   • Total Frames: ${frame.totalFrames}');
    debugPrint('   • Avg Frame Time: ${frame.avgFrameTimeMs.toStringAsFixed(1)}ms');
    debugPrint('   • P95 Frame Time: ${frame.p95FrameTimeMs}ms');
    debugPrint('   • Max Frame Time: ${frame.maxFrameTimeMs}ms');
    debugPrint('   • Dropped Frames: ${frame.droppedFrames} (${frame.droppedPercent.toStringAsFixed(1)}%)');
    
    final frameStatus = frame.avgFrameTimeMs < 16 && frame.droppedPercent < 1.0
        ? '✅ PASS'
        : '❌ FAIL';
    debugPrint('   • Status: $frameStatus');
    debugPrint('');
    
    if (network.totalRequests > 0) {
      debugPrint('🛰️  Network Performance:');
      debugPrint('   • Total Requests: ${network.totalRequests}');
      debugPrint('   • Successful: ${network.successfulRequests}');
      debugPrint('   • Retries: ${network.retryCount}');
      debugPrint('   • Avg Latency: ${network.avgLatencyMs.toStringAsFixed(0)}ms');
      debugPrint('   • Max Latency: ${network.maxLatencyMs}ms');
      debugPrint('   • Bytes Transferred: ${_formatBytes(network.totalBytesTransferred)}');
      
      final networkStatus = network.avgLatencyMs < 200 && network.retryCount <= 3
          ? '✅ PASS'
          : '❌ FAIL';
      debugPrint('   • Status: $networkStatus');
      debugPrint('');
    }
    
    if (report.customMetrics.isNotEmpty) {
      debugPrint('📈 Custom Metrics:');
      report.customMetrics.forEach((key, value) {
        debugPrint('   • $key: $value');
      });
      debugPrint('');
    }
    
    debugPrint('========================================\n');
  }
  
  String _formatBytes(int bytes) {
    if (bytes < 1024) return '${bytes}B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)}KB';
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)}MB';
  }
}

/// Frame performance metrics
class FrameMetrics {
  const FrameMetrics({
    required this.totalFrames,
    required this.droppedFrames,
    required this.droppedPercent,
    required this.avgFrameTimeMs,
    required this.p95FrameTimeMs,
    required this.maxFrameTimeMs,
  });

  final int totalFrames;
  final int droppedFrames;
  final double droppedPercent;
  final double avgFrameTimeMs;
  final int p95FrameTimeMs;
  final int maxFrameTimeMs;

  Map<String, dynamic> toJson() => {
    'total_frames': totalFrames,
    'dropped_frames': droppedFrames,
    'dropped_percent': droppedPercent,
    'avg_frame_time_ms': avgFrameTimeMs,
    'p95_frame_time_ms': p95FrameTimeMs,
    'max_frame_time_ms': maxFrameTimeMs,
  };
}

/// Network performance metrics
class NetworkMetrics {
  const NetworkMetrics({
    required this.totalRequests,
    required this.successfulRequests,
    required this.retryCount,
    required this.avgLatencyMs,
    required this.maxLatencyMs,
    required this.totalBytesTransferred,
  });

  final int totalRequests;
  final int successfulRequests;
  final int retryCount;
  final double avgLatencyMs;
  final int maxLatencyMs;
  final int totalBytesTransferred;

  Map<String, dynamic> toJson() => {
    'total_requests': totalRequests,
    'successful_requests': successfulRequests,
    'retry_count': retryCount,
    'avg_latency_ms': avgLatencyMs,
    'max_latency_ms': maxLatencyMs,
    'total_bytes_transferred': totalBytesTransferred,
  };
}

/// Single network request metric
class NetworkRequestMetric {
  const NetworkRequestMetric({
    required this.url,
    required this.statusCode,
    required this.latency,
    required this.responseBytes,
    required this.isRetry,
    required this.timestamp,
  });

  final String url;
  final int statusCode;
  final Duration latency;
  final int responseBytes;
  final bool isRetry;
  final DateTime timestamp;
}

/// Complete benchmark report
class BenchmarkReport {
  const BenchmarkReport({
    required this.testName,
    required this.duration,
    required this.frameMetrics,
    required this.networkMetrics,
    required this.customMetrics,
    required this.timestamp,
  });

  final String testName;
  final Duration duration;
  final FrameMetrics frameMetrics;
  final NetworkMetrics networkMetrics;
  final Map<String, dynamic> customMetrics;
  final DateTime timestamp;

  Map<String, dynamic> toJson() => {
    'test_name': testName,
    'duration_ms': duration.inMilliseconds,
    'timestamp': timestamp.toIso8601String(),
    'frame_metrics': frameMetrics.toJson(),
    'network_metrics': networkMetrics.toJson(),
    'custom_metrics': customMetrics,
  };

  /// Save report to file
  Future<void> saveToFile() async {
    try {
      final directory = await getApplicationDocumentsDirectory();
      final benchmarksDir = Directory('${directory.path}/benchmarks');
      
      if (!await benchmarksDir.exists()) {
        await benchmarksDir.create(recursive: true);
      }
      
      final file = File('${benchmarksDir.path}/last_run.json');
      final jsonString = jsonEncode(toJson());
      
      await file.writeAsString(jsonString);
      debugPrint('[Benchmark] 💾 Report saved to: ${file.path}');
    } catch (e) {
      debugPrint('[Benchmark] ⚠️ Failed to save report: $e');
    }
  }
}
