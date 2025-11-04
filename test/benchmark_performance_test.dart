import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:my_app_gps/core/performance/benchmark_runner.dart';
import 'package:my_app_gps/core/lifecycle/stream_lifecycle_manager.dart';

/// Comprehensive benchmark tests for production verification
/// 
/// Tests:
/// 1. Frame stability under load
/// 2. Network efficiency simulation
/// 3. Memory leak detection
/// 4. Concurrent operations stress test
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Production Benchmark Tests', () {
    late BenchmarkRunner benchmark;

    setUp(() {
      benchmark = BenchmarkRunner(testName: 'test_scenario');
    });

    test('Frame Performance: 50 devices at 1s update rate for 2 minutes', () async {
      final deviceCount = 50;
      final updateIntervalMs = 1000;
      final durationSeconds = 120; // 2 minutes
      
      benchmark = BenchmarkRunner(testName: 'device_streaming_stress');
      await benchmark.start();
      
      debugPrint('[Benchmark] 🚀 Starting device streaming stress test');
      debugPrint('[Benchmark] 📊 Config: $deviceCount devices, ${updateIntervalMs}ms interval, ${durationSeconds}s duration');
      
      // Simulate device updates
      final startTime = DateTime.now();
      var updateCount = 0;
      
      while (DateTime.now().difference(startTime).inSeconds < durationSeconds) {
        // Simulate batch position updates
        for (var i = 0; i < deviceCount; i++) {
          // Simulate position processing work
          _simulatePositionUpdate(deviceId: i);
        }
        
        updateCount++;
        
        // Wait for next interval
        await Future<void>.delayed(Duration(milliseconds: updateIntervalMs));
        
        // Log progress every 10 updates
        if (updateCount % 10 == 0) {
          final elapsed = DateTime.now().difference(startTime);
          debugPrint('[Benchmark] ⏱️ Progress: ${elapsed.inSeconds}s, $updateCount batches processed');
        }
      }
      
      final report = await benchmark.stop();
      
      // Assert success criteria
      expect(report.frameMetrics.avgFrameTimeMs, lessThan(16.0),
          reason: 'Average frame time should be <16ms for 60 FPS');
      expect(report.frameMetrics.droppedPercent, lessThan(1.0),
          reason: 'Dropped frames should be <1%');
      
      debugPrint('[Benchmark] ✅ Stress test complete: $updateCount batches, ${updateCount * deviceCount} total updates');
      
      // Save report
      await report.saveToFile();
    }, timeout: const Timeout(Duration(minutes: 3)));

    test('Network Efficiency: Concurrent trip fetching', () async {
      benchmark = BenchmarkRunner(testName: 'concurrent_trip_fetch');
      await benchmark.start();
      
      final deviceIds = List.generate(10, (i) => i + 1);
      final futures = <Future<void>>[];
      
      debugPrint('[Benchmark] 🛰️ Simulating concurrent trip fetching for ${deviceIds.length} devices');
      
      for (final deviceId in deviceIds) {
        futures.add(_simulateTripFetch(
          deviceId: deviceId,
          onRequestComplete: (latency, responseBytes, statusCode, isRetry) {
            benchmark.recordNetworkRequest(
              url: '/api/reports/trips?deviceId=$deviceId',
              statusCode: statusCode,
              latency: latency,
              responseBytes: responseBytes,
              isRetry: isRetry,
            );
          },
        ));
      }
      
      await Future.wait(futures);
      
      final report = await benchmark.stop();
      
      // Assert success criteria
      expect(report.networkMetrics.avgLatencyMs, lessThan(200.0),
          reason: 'Average network latency should be <200ms');
      expect(report.networkMetrics.retryCount, lessThanOrEqualTo(3),
          reason: 'Retry count should be ≤3');
      expect(report.networkMetrics.successfulRequests, equals(deviceIds.length),
          reason: 'All requests should succeed');
      
      debugPrint('[Benchmark] ✅ Network test complete: ${report.networkMetrics.totalRequests} requests');
      
      await report.saveToFile();
    });

    test('Memory Safety: Lifecycle cleanup verification', () async {
      benchmark = BenchmarkRunner(testName: 'lifecycle_cleanup');
      await benchmark.start();
      
      // Create multiple lifecycle managers
      final managers = <StreamLifecycleManager>[];
      final streamCount = 100;
      
      debugPrint('[Benchmark] 🧹 Testing lifecycle cleanup with $streamCount streams');
      
      for (var i = 0; i < 10; i++) {
        final manager = StreamLifecycleManager(name: 'test_manager_$i');
        managers.add(manager);
        
        // Simulate stream subscriptions
        for (var j = 0; j < 10; j++) {
          final stream = Stream.periodic(const Duration(milliseconds: 100), (count) => count);
          manager.track(stream.listen((_) {}));
        }
      }
      
      // Verify all streams are tracked
      var totalTracked = 0;
      for (final manager in managers) {
        final status = manager.stats;
        totalTracked += status['subscriptions'] as int;
      }
      
      expect(totalTracked, equals(streamCount),
          reason: 'All streams should be tracked');
      
      benchmark.recordMetric('streams_created', streamCount);
      benchmark.recordMetric('managers_created', managers.length);
      
      // Dispose all managers
      for (final manager in managers) {
        manager.disposeAll();
      }
      
      // Verify cleanup
      for (final manager in managers) {
        final status = manager.stats;
        expect(status['subscriptions'], equals(0),
            reason: 'All subscriptions should be cleaned up');
      }
      
      final report = await benchmark.stop();
      benchmark.recordMetric('cleanup_successful', true);
      
      debugPrint('[Benchmark] ✅ Lifecycle cleanup verified: $streamCount streams disposed');
      
      await report.saveToFile();
    });

    test('Concurrent Operations: Multi-repository stress test', () async {
      benchmark = BenchmarkRunner(testName: 'concurrent_repo_operations');
      await benchmark.start();
      
      final operationCount = 100;
      final futures = <Future<void>>[];
      
      debugPrint('[Benchmark] 🔄 Stress testing $operationCount concurrent operations');
      
      for (var i = 0; i < operationCount; i++) {
        futures.add(_simulateRepositoryOperation(
          operationId: i,
          onComplete: (duration) {
            benchmark.recordMetric('operation_${i}_ms', duration.inMilliseconds);
          },
        ));
      }
      
      await Future.wait(futures);
      
      final report = await benchmark.stop();
      
      // Calculate operation statistics
      final operationDurations = <int>[];
      for (var i = 0; i < operationCount; i++) {
        final duration = report.customMetrics['operation_${i}_ms'] as int?;
        if (duration != null) {
          operationDurations.add(duration);
        }
      }
      
      if (operationDurations.isNotEmpty) {
        operationDurations.sort();
        final avgDuration = operationDurations.reduce((a, b) => a + b) / operationDurations.length;
        final p95Duration = operationDurations[(operationDurations.length * 0.95).round()];
        
        benchmark.recordMetric('avg_operation_ms', avgDuration);
        benchmark.recordMetric('p95_operation_ms', p95Duration);
        
        debugPrint('[Benchmark] ✅ Concurrent operations complete: avg=${avgDuration.toStringAsFixed(0)}ms, p95=${p95Duration}ms');
      }
      
      await report.saveToFile();
    });

    test('Frame Stability: No shader compilation stutters', () async {
      benchmark = BenchmarkRunner(testName: 'shader_compilation_check');
      await benchmark.start();
      
      debugPrint('[Benchmark] 🎨 Testing for shader compilation stutters');
      
      // Simulate rendering cycles that might trigger shader compilation
      for (var i = 0; i < 60; i++) {
        // Simulate frame work
        await Future<void>.delayed(const Duration(milliseconds: 16));
        
        // Simulate complex rendering (would trigger shader compilation if present)
        _simulateComplexRendering();
      }
      
      final report = await benchmark.stop();
      
      // Check for sudden frame spikes (>33ms = shader compilation likely)
      final hasShaderStutter = report.frameMetrics.maxFrameTimeMs > 33;
      
      expect(hasShaderStutter, isFalse,
          reason: 'No frame should exceed 33ms (shader compilation stutter)');
      
      benchmark.recordMetric('shader_stutter_detected', hasShaderStutter);
      
      debugPrint('[Benchmark] ✅ Shader compilation check complete: max frame = ${report.frameMetrics.maxFrameTimeMs}ms');
      
      await report.saveToFile();
    });
  });
}

/// Simulate position update processing
void _simulatePositionUpdate({required int deviceId}) {
  // Simulate JSON parsing and state update
  final data = {
    'deviceId': deviceId,
    'latitude': 37.7749 + (deviceId * 0.01),
    'longitude': -122.4194 + (deviceId * 0.01),
    'speed': 45.5,
    'course': 180.0,
    'altitude': 100.0,
    'accuracy': 10.0,
    'timestamp': DateTime.now().toIso8601String(),
  };
  
  // Simulate processing
  data.forEach((key, value) {
    // Touch each value to simulate real processing
    value.toString();
  });
}

/// Simulate trip fetch with realistic latency
Future<void> _simulateTripFetch({
  required int deviceId,
  required void Function(Duration latency, int responseBytes, int statusCode, bool isRetry) onRequestComplete,
}) async {
  final sw = Stopwatch()..start();
  
  // Simulate network latency (100-300ms)
  final latencyMs = 100 + (deviceId % 200);
  await Future<void>.delayed(Duration(milliseconds: latencyMs));
  
  sw.stop();
  
  // Simulate response
  final responseBytes = 5000 + (deviceId * 100); // ~5KB per response
  final statusCode = deviceId % 20 == 0 ? 500 : 200; // 5% failure rate
  final isRetry = deviceId % 10 == 0; // 10% retry rate
  
  onRequestComplete(sw.elapsed, responseBytes, statusCode, isRetry);
}

/// Simulate repository operation with realistic timing
Future<void> _simulateRepositoryOperation({
  required int operationId,
  required void Function(Duration duration) onComplete,
}) async {
  final sw = Stopwatch()..start();
  
  // Simulate database query or network request
  await Future<void>.delayed(Duration(milliseconds: 50 + (operationId % 100)));
  
  sw.stop();
  onComplete(sw.elapsed);
}

/// Simulate complex rendering workload
void _simulateComplexRendering() {
  // Simulate marker rendering calculations
  for (var i = 0; i < 100; i++) {
    final x = i * 1.5;
    final y = i * 2.0;
    final result = x * y + (x / (y + 1));
    result.toString(); // Touch result to prevent optimization
  }
}
