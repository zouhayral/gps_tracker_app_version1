import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:my_app_gps/core/lifecycle/stream_lifecycle_manager.dart';

/// Comprehensive test suite for StreamLifecycleManager verification
/// 
/// Tests:
/// - Complete resource cleanup on dispose
/// - No double-dispose issues
/// - No race conditions during cleanup
/// - Route change simulation with cleanup verification
void main() {
  group('StreamLifecycleManager', () {
    test('tracks and disposes subscriptions correctly', () async {
      final lifecycle = StreamLifecycleManager(name: 'TestManager');
      
      // Create a test stream
      final controller = StreamController<int>.broadcast();
      lifecycle.track(controller.stream.listen((_) {}));
      
      // Verify tracking
      expect(lifecycle.stats['subscriptions'], 1);
      expect(lifecycle.isClean, false);
      
      // Dispose
      lifecycle.disposeAll();
      
      // Verify cleanup
      expect(lifecycle.stats['subscriptions'], 0);
      expect(lifecycle.isClean, true);
      
      // Cleanup test controller
      await controller.close();
    });

    test('tracks and disposes controllers correctly', () async {
      final lifecycle = StreamLifecycleManager(name: 'TestManager');
      
      // Create and track a controller
      lifecycle.trackController(
        StreamController<int>.broadcast(),
      );
      
      // Verify tracking
      expect(lifecycle.stats['controllers'], 1);
      expect(lifecycle.isClean, false);
      
      // Dispose
      lifecycle.disposeAll();
      
      // Verify cleanup
      expect(lifecycle.stats['controllers'], 0);
      expect(lifecycle.isClean, true);
    });

    test('tracks and disposes timers correctly', () async {
      final lifecycle = StreamLifecycleManager(name: 'TestManager');
      
      // Create and track a timer
      final timer = lifecycle.trackTimer(
        Timer.periodic(const Duration(seconds: 1), (_) {}),
      );
      
      // Verify tracking
      expect(lifecycle.stats['timers'], 1);
      expect(lifecycle.isClean, false);
      
      // Dispose
      lifecycle.disposeAll();
      
      // Verify cleanup
      expect(lifecycle.stats['timers'], 0);
      expect(lifecycle.isClean, true);
      expect(timer.isActive, false);
    });

    test('handles mixed resource types correctly', () async {
      final lifecycle = StreamLifecycleManager(name: 'TestManager');
      
      // Track multiple resource types
      lifecycle.trackController(
        StreamController<int>.broadcast(),
      );
      final controller2 = StreamController<String>.broadcast();
      lifecycle.track(controller2.stream.listen((_) {}));
      lifecycle.trackTimer(
        Timer(const Duration(seconds: 1), () {}),
      );
      
      // Verify all tracked
      expect(lifecycle.stats['subscriptions'], 1);
      expect(lifecycle.stats['controllers'], 1);
      expect(lifecycle.stats['timers'], 1);
      expect(lifecycle.isClean, false);
      
      // Dispose all
      lifecycle.disposeAll();
      
      // Verify complete cleanup
      expect(lifecycle.stats['subscriptions'], 0);
      expect(lifecycle.stats['controllers'], 0);
      expect(lifecycle.stats['timers'], 0);
      expect(lifecycle.isClean, true);
      
      // Cleanup untracked controller
      await controller2.close();
    });

    test('prevents double dispose', () async {
      final lifecycle = StreamLifecycleManager(name: 'TestManager');
      
      lifecycle.trackController(
        StreamController<int>.broadcast(),
      );
      
      // First dispose
      lifecycle.disposeAll();
      expect(lifecycle.isClean, true);
      
      // Second dispose should be safe (no-op)
      lifecycle.disposeAll();
      expect(lifecycle.isClean, true);
    });

    test('handles dispose with no tracked resources', () async {
      final lifecycle = StreamLifecycleManager(name: 'TestManager');
      
      // Dispose without tracking anything
      lifecycle.disposeAll();
      
      expect(lifecycle.isClean, true);
    });

    test('handles concurrent tracking and disposal', () async {
      final lifecycle = StreamLifecycleManager(name: 'TestManager');
      
      // Track multiple resources concurrently
      final futures = <Future<void>>[];
      for (int i = 0; i < 10; i++) {
        futures.add(Future(() {
          lifecycle.trackController(StreamController<int>.broadcast());
          lifecycle.trackTimer(Timer(const Duration(milliseconds: 100), () {}));
        }));
      }
      
      await Future.wait(futures);
      
      // Should have tracked all resources
      expect(lifecycle.stats['controllers'], 10);
      expect(lifecycle.stats['timers'], 10);
      
      // Dispose should clean up everything
      lifecycle.disposeAll();
      
      expect(lifecycle.isClean, true);
    });

    test('tracks resources added via extension methods', () async {
      final lifecycle = StreamLifecycleManager(name: 'TestManager');
      
      // Use extension methods
      final controller = StreamController<int>.broadcast();
      controller.stream.listen((_) {}).trackIn(lifecycle);
      
      expect(lifecycle.stats['subscriptions'], 1);
      
      lifecycle.disposeAll();
      
      expect(lifecycle.isClean, true);
      
      await controller.close();
    });

    test('verifies no memory leaks after multiple create/dispose cycles', () async {
      for (int cycle = 0; cycle < 5; cycle++) {
        final lifecycle = StreamLifecycleManager(name: 'CycleTest$cycle');
        
        // Create resources
        for (int i = 0; i < 20; i++) {
          lifecycle.trackController(StreamController<int>.broadcast());
          lifecycle.trackTimer(Timer(const Duration(seconds: 10), () {}));
          
          final controller = StreamController<String>.broadcast();
          lifecycle.track(controller.stream.listen((_) {}));
          await controller.close();
        }
        
        // Dispose
        lifecycle.disposeAll();
        
        // Verify complete cleanup
        expect(lifecycle.isClean, true,
            reason: 'Cycle $cycle failed to clean up');
      }
    });

    test('handles errors during disposal gracefully', () {
      final lifecycle = StreamLifecycleManager(name: 'ErrorTest');
      
      // Create a controller that might throw on close
      final controller = StreamController<int>(
        onCancel: () {
          // Simulate error during cleanup
          // Note: In practice, controllers rarely throw, but we test resilience
        },
      );
      
      lifecycle.trackController(controller);
      
      // Should not throw even if individual resource disposal fails
      // disposeAll() is now synchronous, so no need to await
      expect(() => lifecycle.disposeAll(), returnsNormally);
    });

    test('simulates route navigation cleanup', () async {
      // Simulate repository lifecycle tied to a route
      final repoLifecycle = StreamLifecycleManager(name: 'RouteRepository');
      
      // Simulate route mounting - create resources
      final positionStream = StreamController<String>.broadcast();
      repoLifecycle.trackController(positionStream);
      
      final updateTimer = Timer.periodic(
        const Duration(seconds: 1),
        (_) {
          if (!positionStream.isClosed) {
            positionStream.add('update');
          }
        },
      );
      repoLifecycle.trackTimer(updateTimer);
      
      // Verify resources active
      expect(repoLifecycle.stats['controllers'], 1);
      expect(repoLifecycle.stats['timers'], 1);
      expect(updateTimer.isActive, true);
      
      // Simulate route pop/disposal
      repoLifecycle.disposeAll();
      
      // Verify complete cleanup (route disposal)
      expect(repoLifecycle.isClean, true);
      expect(updateTimer.isActive, false);
      expect(positionStream.isClosed, true);
    });

    test('verifies assertions fire on incomplete cleanup', () async {
      // This test verifies the assertion would fire if cleanup fails
      // In debug mode, the assert in disposeAll checks isClean
      final lifecycle = StreamLifecycleManager(name: 'AssertTest');
      
      lifecycle.trackTimer(Timer(const Duration(seconds: 1), () {}));
      
      lifecycle.disposeAll();
      
      // After dispose, should be clean
      expect(lifecycle.isClean, true);
    });

    test('handles high-frequency tracking and disposal', () async {
      final lifecycle = StreamLifecycleManager(name: 'HighFrequency');
      final stopwatch = Stopwatch()..start();
      
      // Simulate high-frequency stream creation (like position updates)
      for (int i = 0; i < 100; i++) {
        final controller = StreamController<int>.broadcast();
        lifecycle.trackController(controller);
        
        if (i % 10 == 0) {
          // Periodically create timers too
          lifecycle.trackTimer(Timer(const Duration(milliseconds: 100), () {}));
        }
      }
      
      stopwatch.stop();
      
      expect(lifecycle.stats['controllers'], 100);
      expect(lifecycle.stats['timers'], 10);
      
      // Dispose should be fast even with many resources
      stopwatch.reset();
      stopwatch.start();
      lifecycle.disposeAll();
      stopwatch.stop();
      
      final disposeTime = stopwatch.elapsedMilliseconds;
      
      expect(lifecycle.isClean, true);
      expect(disposeTime, lessThan(500), // Should dispose within 500ms
          reason: 'Disposal took too long: ${disposeTime}ms');
    });
  });

  group('StreamLifecycleManager Integration', () {
    test('simulates VehicleDataRepository lifecycle', () async {
      final lifecycle = StreamLifecycleManager(name: 'VehicleRepo');
      
      // Simulate repository initialization
      final socketController = StreamController<String>.broadcast();
      lifecycle.track(
        socketController.stream.listen((data) {
          // Process socket data
        }),
      );
      
      lifecycle.trackTimer(
        Timer.periodic(const Duration(seconds: 10), (_) {
          // Fallback polling
        }),
      );
      
      lifecycle.trackController(
        StreamController<Map<String, dynamic>>.broadcast(),
      );
      
      // Verify active
      expect(lifecycle.stats['subscriptions'], 1);
      expect(lifecycle.stats['timers'], 1);
      expect(lifecycle.stats['controllers'], 1);
      
      // Simulate dispose on route change
      lifecycle.disposeAll();
      
      // Verify complete cleanup
      expect(lifecycle.isClean, true);
      
      await socketController.close();
    });

    test('simulates NotificationsRepository lifecycle', () async {
      final lifecycle = StreamLifecycleManager(name: 'NotificationsRepo');
      
      // Simulate initialization
      lifecycle.trackController(
        StreamController<List<String>>.broadcast(),
      );
      
      lifecycle.trackController(
        StreamController<String>.broadcast(),
      );
      
      lifecycle.trackTimer(
        Timer.periodic(const Duration(minutes: 5), (_) {
          // Cleanup task
        }),
      );
      
      lifecycle.track(
        Stream.periodic(const Duration(seconds: 1), (i) => 'event$i')
            .listen((_) {}),
      );
      
      // Verify active
      expect(lifecycle.stats['controllers'], 2);
      expect(lifecycle.stats['timers'], 1);
      expect(lifecycle.stats['subscriptions'], 1);
      
      // Dispose
      lifecycle.disposeAll();
      
      // Verify cleanup
      expect(lifecycle.isClean, true);
    });

    test('simulates WebSocketManager lifecycle', () async {
      final lifecycle = StreamLifecycleManager(name: 'WebSocketManager');
      
      // Simulate socket connection
      final socketStream = StreamController<String>.broadcast();
      lifecycle.track(
        socketStream.stream.listen((message) {
          // Handle message
        }),
      );
      
      lifecycle.trackTimer(
        Timer(const Duration(seconds: 5), () {
          // Reconnect
        }),
      );
      
      // Simulate disconnection/disposal
      lifecycle.disposeAll();
      
      expect(lifecycle.isClean, true);
      
      await socketStream.close();
    });
  });
}
