import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:my_app_gps/core/map/async_marker_warm_cache.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  /// Helper to pump frames until warm-up queue is processed
  /// 
  /// SchedulerBinding.addPostFrameCallback requires explicit frame pumping in tests.
  /// This helper pumps frames until the warm-up queue is empty and all batches complete.
  Future<void> pumpUntilWarmUpComplete(AsyncMarkerWarmCache cache, {int maxPumps = 50}) async {
    var pumps = 0;
    while (cache.queuedCount > 0 && pumps < maxPumps) {
      // Trigger frame callbacks by simulating frame
      WidgetsBinding.instance.handleBeginFrame(Duration(milliseconds: pumps * 16));
      WidgetsBinding.instance.handleDrawFrame();
      pumps++;
      
      // Small delay to allow async rendering
      await Future<void>.delayed(const Duration(milliseconds: 10));
    }
    
    if (pumps >= maxPumps) {
      throw Exception('pumpUntilWarmUpComplete exceeded max pumps ($maxPumps)');
    }
  }

  group('AsyncMarkerWarmCache', () {
    late AsyncMarkerWarmCache cache;

    setUp(() {
      cache = AsyncMarkerWarmCache.instance;
      cache.clear();
    });

    tearDown(() {
      cache.clear();
    });

    test('singleton instance is same', () {
      final instance1 = AsyncMarkerWarmCache.instance;
      final instance2 = AsyncMarkerWarmCache.instance;

      expect(identical(instance1, instance2), true);
    });

    test('generates and caches marker on first access', () async {
      final state = MarkerRenderState(
        name: 'Vehicle 1',
        online: true,
        engineOn: true,
        moving: true,
        speed: 50,
      );

      expect(cache.cachedCount, 0);

      final image = await cache.getOrGenerate(state.cacheKey, state);

      expect(image, isNotNull);
      expect(cache.cachedCount, 1);
      expect(cache.stats.hits, 0);
      expect(cache.stats.misses, 1);
    });

    test('returns cached marker on second access', () async {
      final state = MarkerRenderState(
        name: 'Vehicle 1',
        online: true,
        engineOn: true,
        moving: true,
        speed: 50,
      );

      // First access - miss
      final image1 = await cache.getOrGenerate(state.cacheKey, state);
      expect(cache.stats.misses, 1);
      expect(cache.stats.hits, 0);

      // Second access - hit
      final image2 = await cache.getOrGenerate(state.cacheKey, state);
      expect(cache.stats.hits, 1);
      expect(cache.stats.misses, 1);

      expect(identical(image1, image2), true, reason: 'Should return same cached instance');
    });

    test('warm-up caches multiple markers', () async {
      final states = List.generate(
        10,
        (i) => MarkerRenderState(
          name: 'Vehicle $i',
          online: true,
          engineOn: true,
          moving: i % 2 == 0,
          speed: 40.0 + i,
        ),
      );

      expect(cache.cachedCount, 0);

      // Enqueue markers for warm-up (non-blocking)
      cache.warmUp(states);

      // Pump frames until queue is processed
      await pumpUntilWarmUpComplete(cache);

      expect(cache.cachedCount, 10, reason: 'All 10 markers should be cached');
      expect(cache.stats.warmUpCount, 10);
      expect(cache.queuedCount, 0, reason: 'Queue should be empty after completion');
    });

    test('warm-up skips already cached markers', () async {
      final state = MarkerRenderState(
        name: 'Vehicle 1',
        online: true,
        engineOn: true,
        moving: true,
        speed: 50,
      );

      // Pre-cache one marker
      await cache.getOrGenerate(state.cacheKey, state);
      expect(cache.cachedCount, 1);

      // Warm-up with same marker included (non-blocking)
      cache.warmUp([state]);

      // Should not increase cache count
      expect(cache.cachedCount, 1);
      expect(cache.queuedCount, 0, reason: 'Should not enqueue already cached marker');
    });

    test('warm-up handles different marker states', () async {
      final states = [
        // Moving
        MarkerRenderState(
          name: 'Vehicle 1',
          online: true,
          engineOn: true,
          moving: true,
          speed: 60,
        ),
        // Idle engine on
        MarkerRenderState(
          name: 'Vehicle 1',
          online: true,
          engineOn: true,
          moving: false,
        ),
        // Idle engine off
        MarkerRenderState(
          name: 'Vehicle 1',
          online: true,
          engineOn: false,
          moving: false,
        ),
        // Offline
        MarkerRenderState(
          name: 'Vehicle 1',
          online: false,
          engineOn: false,
          moving: false,
        ),
      ];

      cache.warmUp(states);

      // Pump frames until queue is processed
      await pumpUntilWarmUpComplete(cache);

      expect(cache.cachedCount, 4, reason: 'All 4 states should be cached separately');
    });

    test('warmUpVehicle caches common states for single vehicle', () async {
      cache.warmUpVehicle(name: 'Vehicle 1');

      // Pump frames until queue is processed
      await pumpUntilWarmUpComplete(cache);

      // Should cache: moving (2 speeds), idle engine on, idle engine off, offline = 5 states
      expect(cache.cachedCount, greaterThanOrEqualTo(4));
    });

    test('has() returns true for cached markers', () async {
      final state = MarkerRenderState(
        name: 'Vehicle 1',
        online: true,
        engineOn: true,
        moving: true,
        speed: 50,
      );

      expect(cache.has(state.cacheKey), false);

      await cache.getOrGenerate(state.cacheKey, state);

      expect(cache.has(state.cacheKey), true);
    });

    test('operator[] returns cached image', () async {
      final state = MarkerRenderState(
        name: 'Vehicle 1',
        online: true,
        engineOn: true,
        moving: true,
        speed: 50,
      );

      expect(cache[state.cacheKey], isNull);

      final image = await cache.getOrGenerate(state.cacheKey, state);

      expect(cache[state.cacheKey], same(image));
    });

    test('clear removes all cached markers', () async {
      final states = List.generate(
        5,
        (i) => MarkerRenderState(
          name: 'Vehicle $i',
          online: true,
          engineOn: true,
          moving: true,
          speed: 50,
        ),
      );

      cache.warmUp(states);

      // Pump frames until queue is processed
      await pumpUntilWarmUpComplete(cache);

      expect(cache.cachedCount, 5);

      cache.clear();

      expect(cache.cachedCount, 0);
      expect(cache.pendingCount, 0);
      expect(cache.queuedCount, 0);
    });

    test('clearVehicle removes only specified vehicle markers', () async {
      cache.warmUpVehicle(name: 'Vehicle 1');
      cache.warmUpVehicle(name: 'Vehicle 2');

      // Pump frames until queue is processed
      await pumpUntilWarmUpComplete(cache);

      final countBefore = cache.cachedCount;
      expect(countBefore, greaterThan(0));

      cache.clearVehicle('Vehicle 1');

      expect(cache.cachedCount, lessThan(countBefore));
    });

    test('cache key is deterministic for same state', () {
      final state1 = MarkerRenderState(
        name: 'Vehicle 1',
        online: true,
        engineOn: true,
        moving: true,
        speed: 50,
      );

      final state2 = MarkerRenderState(
        name: 'Vehicle 1',
        online: true,
        engineOn: true,
        moving: true,
        speed: 50,
      );

      expect(state1.cacheKey, equals(state2.cacheKey));
    });

    test('cache key differs for different states', () {
      final state1 = MarkerRenderState(
        name: 'Vehicle 1',
        online: true,
        engineOn: true,
        moving: true,
        speed: 50,
      );

      final state2 = MarkerRenderState(
        name: 'Vehicle 1',
        online: true,
        engineOn: false, // Different
        moving: true,
        speed: 50,
      );

      expect(state1.cacheKey, isNot(equals(state2.cacheKey)));
    });

    test('MarkerRenderState equality works correctly', () {
      final state1 = MarkerRenderState(
        name: 'Vehicle 1',
        online: true,
        engineOn: true,
        moving: true,
        speed: 50,
      );

      final state2 = MarkerRenderState(
        name: 'Vehicle 1',
        online: true,
        engineOn: true,
        moving: true,
        speed: 50,
      );

      final state3 = MarkerRenderState(
        name: 'Vehicle 2', // Different
        online: true,
        engineOn: true,
        moving: true,
        speed: 50,
      );

      expect(state1, equals(state2));
      expect(state1, isNot(equals(state3)));
    });

    test('fromDevice creates correct state', () {
      final device = {
        'name': 'Vehicle 1',
        'status': 'online',
        'ignition': true,
        'position': {'speed': 50.0},
      };

      final state = MarkerRenderState.fromDevice(device);

      expect(state.name, 'Vehicle 1');
      expect(state.online, true);
      expect(state.engineOn, true);
      expect(state.speed, 50.0);
      expect(state.moving, true, reason: 'Speed > 1.0 should be moving');
    });

    test('fromDevice handles offline device', () {
      final device = {
        'name': 'Vehicle 2',
        'status': 'offline',
        'ignition': false,
      };

      final state = MarkerRenderState.fromDevice(device);

      expect(state.online, false);
      expect(state.engineOn, false);
      expect(state.moving, false);
    });

    test('fromDevice handles missing attributes', () {
      final device = {'name': 'Vehicle 3'};

      final state = MarkerRenderState.fromDevice(device);

      expect(state.name, 'Vehicle 3');
      expect(state.online, true, reason: 'Default to online if unknown');
      expect(state.engineOn, false);
      expect(state.moving, false);
    });

    test('stats provide accurate cache metrics', () async {
      final state = MarkerRenderState(
        name: 'Vehicle 1',
        online: true,
        engineOn: true,
        moving: true,
        speed: 50,
      );

      // Initial stats
      var stats = cache.stats;
      expect(stats.size, 0);
      expect(stats.hits, 0);
      expect(stats.misses, 0);

      // First access - miss
      await cache.getOrGenerate(state.cacheKey, state);
      stats = cache.stats;
      expect(stats.misses, 1);
      expect(stats.hits, 0);

      // Second access - hit
      await cache.getOrGenerate(state.cacheKey, state);
      stats = cache.stats;
      expect(stats.hits, 1);
      expect(stats.misses, 1);
      expect(stats.hitRate, 0.5);
    });

    test('high marker count scenario (50+ markers)', () async {
      final states = List.generate(
        50,
        (i) => MarkerRenderState(
          name: 'Vehicle $i',
          online: true,
          engineOn: i % 3 == 0,
          moving: i % 2 == 0,
          speed: 30.0 + i,
        ),
      );

      final stopwatch = Stopwatch()..start();
      cache.warmUp(states);
      
      // Pump frames until queue is processed
      await pumpUntilWarmUpComplete(cache);
      stopwatch.stop();

      expect(cache.cachedCount, 50);
      expect(
        stopwatch.elapsedMilliseconds,
        lessThan(5000),
        reason: 'Should complete in under 5 seconds',
      );

      print('✅ Warmed up 50 markers in ${stopwatch.elapsedMilliseconds}ms');
      print('   Batches processed: ${cache.stats.batchCount}');
    });

    test('concurrent access to same marker waits for pending render', () async {
      final state = MarkerRenderState(
        name: 'Vehicle 1',
        online: true,
        engineOn: true,
        moving: true,
        speed: 50,
      );

      // Start two renders concurrently
      final future1 = cache.getOrGenerate(state.cacheKey, state);
      final future2 = cache.getOrGenerate(state.cacheKey, state);

      final results = await Future.wait([future1, future2]);

      // Both should get the same image
      expect(identical(results[0], results[1]), true);

      // Should only count as one miss (one render)
      expect(cache.stats.misses, 1);
    });

    test('memory usage tracking', () async {
      final states = List.generate(
        10,
        (i) => MarkerRenderState(
          name: 'Vehicle $i',
          online: true,
          engineOn: true,
          moving: true,
          speed: 50,
        ),
      );

      expect(cache.memoryUsage, 0);

      cache.warmUp(states);

      // Pump frames until queue is processed
      await pumpUntilWarmUpComplete(cache);

      expect(cache.memoryUsage, greaterThan(0));
      expect(cache.memoryUsageMB, greaterThan(0));

      print('✅ 10 markers use ~${cache.memoryUsageMB.toStringAsFixed(2)} MB');
    });
  });
}
