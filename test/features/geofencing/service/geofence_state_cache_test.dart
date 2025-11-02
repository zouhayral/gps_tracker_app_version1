import 'package:flutter_test/flutter_test.dart';
import 'package:my_app_gps/features/geofencing/service/geofence_evaluator_service.dart';
import 'package:my_app_gps/features/geofencing/service/geofence_state_cache.dart';

void main() {
  group('GeofenceStateCache', () {
    late GeofenceStateCache cache;

    setUp(() {
      cache = GeofenceStateCache(
        ttl: const Duration(hours: 1),
        autoPruneInterval: const Duration(seconds: 10),
      );
    });

    tearDown(() {
      cache.dispose();
    });

    group('Basic Operations', () {
      test('set and get state works', () {
        final state = GeofenceState(
          deviceId: 'device1',
          geofenceId: 'geo1',
          geofenceName: 'Test',
          isInside: true,
          enterTimestamp: DateTime.now(),
          lastSeenTimestamp: DateTime.now(),
        );

        cache.set('device1', 'geo1', state);
        final retrieved = cache.get('device1', 'geo1');

        expect(retrieved, isNotNull);
        expect(retrieved!.deviceId, 'device1');
        expect(retrieved.geofenceId, 'geo1');
        expect(retrieved.isInside, true);
      });

      test('get returns null for non-existent state', () {
        final retrieved = cache.get('device1', 'geo1');
        expect(retrieved, isNull);
      });

      test('set updates existing state', () {
        final state1 = GeofenceState(
          deviceId: 'device1',
          geofenceId: 'geo1',
          geofenceName: 'Test',
          isInside: false,
          lastSeenTimestamp: DateTime.now(),
        );

        final state2 = GeofenceState(
          deviceId: 'device1',
          geofenceId: 'geo1',
          geofenceName: 'Test',
          isInside: true,
          enterTimestamp: DateTime.now(),
          lastSeenTimestamp: DateTime.now(),
        );

        cache.set('device1', 'geo1', state1);
        cache.set('device1', 'geo1', state2);

        final retrieved = cache.get('device1', 'geo1');
        expect(retrieved!.isInside, true);
      });

      test('remove deletes specific state', () {
        final state = GeofenceState(
          deviceId: 'device1',
          geofenceId: 'geo1',
          geofenceName: 'Test',
          isInside: true,
          lastSeenTimestamp: DateTime.now(),
        );

        cache.set('device1', 'geo1', state);
        expect(cache.get('device1', 'geo1'), isNotNull);

        cache.remove('device1', 'geo1');
        expect(cache.get('device1', 'geo1'), isNull);
      });

      test('remove non-existent state is safe', () {
        expect(() => cache.remove('device1', 'geo1'), returnsNormally);
      });

      test('clear removes all states', () {
        final state1 = GeofenceState(
          deviceId: 'device1',
          geofenceId: 'geo1',
          geofenceName: 'Test',
          isInside: true,
          lastSeenTimestamp: DateTime.now(),
        );

        final state2 = GeofenceState(
          deviceId: 'device2',
          geofenceId: 'geo2',
          geofenceName: 'Test',
          isInside: false,
          lastSeenTimestamp: DateTime.now(),
        );

        cache.set('device1', 'geo1', state1);
        cache.set('device2', 'geo2', state2);

        expect(cache.stats.totalStates, 2);

        cache.clear();

        expect(cache.stats.totalStates, 0);
        expect(cache.get('device1', 'geo1'), isNull);
        expect(cache.get('device2', 'geo2'), isNull);
      });
    });

    group('Multi-State Operations', () {
      test('multiple states for same device', () {
        final state1 = GeofenceState(
          deviceId: 'device1',
          geofenceId: 'geo1',
          geofenceName: 'Test1',
          isInside: true,
          lastSeenTimestamp: DateTime.now(),
        );

        final state2 = GeofenceState(
          deviceId: 'device1',
          geofenceId: 'geo2',
          geofenceName: 'Test2',
          isInside: false,
          lastSeenTimestamp: DateTime.now(),
        );

        cache.set('device1', 'geo1', state1);
        cache.set('device1', 'geo2', state2);

        expect(cache.get('device1', 'geo1')!.isInside, true);
        expect(cache.get('device1', 'geo2')!.isInside, false);
        expect(cache.stats.totalStates, 2);
        expect(cache.stats.totalDevices, 1);
      });

      test('same geofence for multiple devices', () {
        final state1 = GeofenceState(
          deviceId: 'device1',
          geofenceId: 'geo1',
          geofenceName: 'Test',
          isInside: true,
          lastSeenTimestamp: DateTime.now(),
        );

        final state2 = GeofenceState(
          deviceId: 'device2',
          geofenceId: 'geo1',
          geofenceName: 'Test',
          isInside: false,
          lastSeenTimestamp: DateTime.now(),
        );

        cache.set('device1', 'geo1', state1);
        cache.set('device2', 'geo1', state2);

        expect(cache.get('device1', 'geo1')!.isInside, true);
        expect(cache.get('device2', 'geo1')!.isInside, false);
        expect(cache.stats.totalStates, 2);
        expect(cache.stats.totalDevices, 2);
      });

      test('removeDevice removes all geofences for device', () {
        final state1 = GeofenceState(
          deviceId: 'device1',
          geofenceId: 'geo1',
          geofenceName: 'Test1',
          isInside: true,
          lastSeenTimestamp: DateTime.now(),
        );

        final state2 = GeofenceState(
          deviceId: 'device1',
          geofenceId: 'geo2',
          geofenceName: 'Test2',
          isInside: false,
          lastSeenTimestamp: DateTime.now(),
        );

        cache.set('device1', 'geo1', state1);
        cache.set('device1', 'geo2', state2);

        expect(cache.stats.totalStates, 2);

        cache.removeDevice('device1');

        expect(cache.stats.totalStates, 0);
        expect(cache.get('device1', 'geo1'), isNull);
        expect(cache.get('device1', 'geo2'), isNull);
      });

      test('removeGeofence removes from all devices', () {
        final state1 = GeofenceState(
          deviceId: 'device1',
          geofenceId: 'geo1',
          geofenceName: 'Test',
          isInside: true,
          lastSeenTimestamp: DateTime.now(),
        );

        final state2 = GeofenceState(
          deviceId: 'device2',
          geofenceId: 'geo1',
          geofenceName: 'Test',
          isInside: false,
          lastSeenTimestamp: DateTime.now(),
        );

        final state3 = GeofenceState(
          deviceId: 'device1',
          geofenceId: 'geo2',
          geofenceName: 'Other',
          isInside: true,
          lastSeenTimestamp: DateTime.now(),
        );

        cache.set('device1', 'geo1', state1);
        cache.set('device2', 'geo1', state2);
        cache.set('device1', 'geo2', state3);

        expect(cache.stats.totalStates, 3);

        cache.removeGeofence('geo1');

        expect(cache.stats.totalStates, 1);
        expect(cache.get('device1', 'geo1'), isNull);
        expect(cache.get('device2', 'geo1'), isNull);
        expect(cache.get('device1', 'geo2'), isNotNull);
      });

      test('getDeviceStates returns all states for device', () {
        final state1 = GeofenceState(
          deviceId: 'device1',
          geofenceId: 'geo1',
          geofenceName: 'Test1',
          isInside: true,
          lastSeenTimestamp: DateTime.now(),
        );

        final state2 = GeofenceState(
          deviceId: 'device1',
          geofenceId: 'geo2',
          geofenceName: 'Test2',
          isInside: false,
          lastSeenTimestamp: DateTime.now(),
        );

        cache.set('device1', 'geo1', state1);
        cache.set('device1', 'geo2', state2);

        final deviceStates = cache.getDeviceStates('device1');

        expect(deviceStates.length, 2);
        expect(deviceStates['geo1']!.isInside, true);
        expect(deviceStates['geo2']!.isInside, false);
      });

      test('activeDevices returns list of devices', () {
        final state1 = GeofenceState(
          deviceId: 'device1',
          geofenceId: 'geo1',
          geofenceName: 'Test',
          isInside: true,
          lastSeenTimestamp: DateTime.now(),
        );

        final state2 = GeofenceState(
          deviceId: 'device2',
          geofenceId: 'geo1',
          geofenceName: 'Test',
          isInside: false,
          lastSeenTimestamp: DateTime.now(),
        );

        cache.set('device1', 'geo1', state1);
        cache.set('device2', 'geo1', state2);

        final devices = cache.activeDevices;

        expect(devices.length, 2);
        expect(devices, contains('device1'));
        expect(devices, contains('device2'));
      });
    });

    group('TTL and Expiration', () {
      test('expired state returns null (lazy eviction)', () async {
        // Create cache with short TTL for testing
        final shortTtlCache = GeofenceStateCache(
          ttl: const Duration(milliseconds: 100),
          autoPruneInterval: const Duration(seconds: 10),
        );

        final state = GeofenceState(
          deviceId: 'device1',
          geofenceId: 'geo1',
          geofenceName: 'Test',
          isInside: true,
          lastSeenTimestamp: DateTime.now(),
        );

        shortTtlCache.set('device1', 'geo1', state);
        expect(shortTtlCache.get('device1', 'geo1'), isNotNull);

        // Wait for expiration
        await Future<void>.delayed(const Duration(milliseconds: 150));

        // Should return null (lazy eviction on get)
        expect(shortTtlCache.get('device1', 'geo1'), isNull);

        shortTtlCache.dispose();
      });

      test('pruneExpired removes old entries', () async {
        // Create cache with short TTL
        final shortTtlCache = GeofenceStateCache(
          ttl: const Duration(milliseconds: 100),
          autoPruneInterval: const Duration(seconds: 10),
        );

        final state1 = GeofenceState(
          deviceId: 'device1',
          geofenceId: 'geo1',
          geofenceName: 'Test',
          isInside: true,
          lastSeenTimestamp: DateTime.now(),
        );

        shortTtlCache.set('device1', 'geo1', state1);
        expect(shortTtlCache.stats.totalStates, 1);

        // Wait for expiration
        await Future<void>.delayed(const Duration(milliseconds: 150));

        // Prune expired
        shortTtlCache.pruneExpired();

        expect(shortTtlCache.stats.totalStates, 0);

        shortTtlCache.dispose();
      });

      test('pruneExpired keeps non-expired entries', () async {
        // Create cache with short TTL
        final shortTtlCache = GeofenceStateCache(
          ttl: const Duration(milliseconds: 200),
          autoPruneInterval: const Duration(seconds: 10),
        );

        final state1 = GeofenceState(
          deviceId: 'device1',
          geofenceId: 'geo1',
          geofenceName: 'Test1',
          isInside: true,
          lastSeenTimestamp: DateTime.now(),
        );

        shortTtlCache.set('device1', 'geo1', state1);

        // Wait partially
        await Future<void>.delayed(const Duration(milliseconds: 100));

        // Add new state (won't be expired)
        final state2 = GeofenceState(
          deviceId: 'device1',
          geofenceId: 'geo2',
          geofenceName: 'Test2',
          isInside: false,
          lastSeenTimestamp: DateTime.now(),
        );

        shortTtlCache.set('device1', 'geo2', state2);

        // Wait for first to expire
        await Future<void>.delayed(const Duration(milliseconds: 150));

        // Prune
        shortTtlCache.pruneExpired();

        // First should be removed, second should remain
        expect(shortTtlCache.get('device1', 'geo1'), isNull);
        expect(shortTtlCache.get('device1', 'geo2'), isNotNull);

        shortTtlCache.dispose();
      });

      test('pruneExpired performance target', () {
        // Add 1000 states
        for (var i = 0; i < 1000; i++) {
          final state = GeofenceState(
            deviceId: 'device${i % 10}',
            geofenceId: 'geo$i',
            geofenceName: 'Test',
            isInside: i % 2 == 0,
            lastSeenTimestamp: DateTime.now(),
          );
          cache.set('device${i % 10}', 'geo$i', state);
        }

        expect(cache.stats.totalStates, 1000);

        // Measure prune time
        final stopwatch = Stopwatch()..start();
        cache.pruneExpired();
        stopwatch.stop();

        // Should be < 5ms (generous target, usually < 1ms)
        expect(stopwatch.elapsedMilliseconds, lessThan(10));
      });
    });

    group('Statistics', () {
      test('tracks lookups, hits, and misses', () {
        final state = GeofenceState(
          deviceId: 'device1',
          geofenceId: 'geo1',
          geofenceName: 'Test',
          isInside: true,
          lastSeenTimestamp: DateTime.now(),
        );

        // Miss
        cache.get('device1', 'geo1');

        // Set and hit
        cache.set('device1', 'geo1', state);
        cache.get('device1', 'geo1');

        // Another miss
        cache.get('device1', 'geo2');

        final stats = cache.stats;
        expect(stats.totalLookups, 3);
        expect(stats.cacheHits, 1);
        expect(stats.cacheMisses, 2);
        expect(stats.hitRate, closeTo(33.3, 0.1));
        expect(stats.missRate, closeTo(66.7, 0.1));
      });

      test('tracks inserts and updates', () {
        final state1 = GeofenceState(
          deviceId: 'device1',
          geofenceId: 'geo1',
          geofenceName: 'Test',
          isInside: true,
          lastSeenTimestamp: DateTime.now(),
        );

        final state2 = GeofenceState(
          deviceId: 'device1',
          geofenceId: 'geo1',
          geofenceName: 'Test',
          isInside: false,
          lastSeenTimestamp: DateTime.now(),
        );

        cache.set('device1', 'geo1', state1); // Insert
        cache.set('device1', 'geo1', state2); // Update

        final stats = cache.stats;
        expect(stats.inserts, 1);
        expect(stats.updates, 1);
      });

      test('tracks removals', () {
        final state = GeofenceState(
          deviceId: 'device1',
          geofenceId: 'geo1',
          geofenceName: 'Test',
          isInside: true,
          lastSeenTimestamp: DateTime.now(),
        );

        cache.set('device1', 'geo1', state);
        cache.remove('device1', 'geo1');

        final stats = cache.stats;
        expect(stats.removals, 1);
      });

      test('tracks evictions', () async {
        final shortTtlCache = GeofenceStateCache(
          ttl: const Duration(milliseconds: 100),
          autoPruneInterval: const Duration(seconds: 10),
        );

        final state = GeofenceState(
          deviceId: 'device1',
          geofenceId: 'geo1',
          geofenceName: 'Test',
          isInside: true,
          lastSeenTimestamp: DateTime.now(),
        );

        shortTtlCache.set('device1', 'geo1', state);

        await Future<void>.delayed(const Duration(milliseconds: 150));
        shortTtlCache.pruneExpired();

        final stats = shortTtlCache.stats;
        expect(stats.evictions, 1);

        shortTtlCache.dispose();
      });

      test('calculates average states per device', () {
        final state1 = GeofenceState(
          deviceId: 'device1',
          geofenceId: 'geo1',
          geofenceName: 'Test',
          isInside: true,
          lastSeenTimestamp: DateTime.now(),
        );

        final state2 = GeofenceState(
          deviceId: 'device1',
          geofenceId: 'geo2',
          geofenceName: 'Test',
          isInside: false,
          lastSeenTimestamp: DateTime.now(),
        );

        final state3 = GeofenceState(
          deviceId: 'device2',
          geofenceId: 'geo1',
          geofenceName: 'Test',
          isInside: true,
          lastSeenTimestamp: DateTime.now(),
        );

        cache.set('device1', 'geo1', state1);
        cache.set('device1', 'geo2', state2);
        cache.set('device2', 'geo1', state3);

        // Trigger lookups for average calculation
        cache.get('device1', 'geo1');

        final stats = cache.stats;
        expect(stats.totalStates, 3);
        expect(stats.totalDevices, 2);
        expect(stats.averageStatesPerDevice, 1.5);
      });

      test('stats stream emits on prune', () async {
        final shortTtlCache = GeofenceStateCache(
          ttl: const Duration(milliseconds: 100),
          autoPruneInterval: const Duration(milliseconds: 200),
        );

        final receivedStats = <CacheStatistics>[];
        shortTtlCache.statsStream.listen(receivedStats.add);

        final state = GeofenceState(
          deviceId: 'device1',
          geofenceId: 'geo1',
          geofenceName: 'Test',
          isInside: true,
          lastSeenTimestamp: DateTime.now(),
        );

        shortTtlCache.set('device1', 'geo1', state);

        // Wait for auto-prune
        await Future<void>.delayed(const Duration(milliseconds: 300));

        expect(receivedStats.length, greaterThan(0));

        shortTtlCache.dispose();
      });
    });

    group('Performance', () {
      test('get operation is O(1)', () {
        // Add many states
        for (var i = 0; i < 1000; i++) {
          final state = GeofenceState(
            deviceId: 'device${i % 10}',
            geofenceId: 'geo$i',
            geofenceName: 'Test',
            isInside: true,
            lastSeenTimestamp: DateTime.now(),
          );
          cache.set('device${i % 10}', 'geo$i', state);
        }

        // Measure get time
        final stopwatch = Stopwatch()..start();
        cache.get('device5', 'geo500');
        stopwatch.stop();

        // Should be < 1ms (usually microseconds)
        expect(stopwatch.elapsedMilliseconds, lessThan(5));
      });

      test('set operation is O(1)', () {
        // Add many states
        for (var i = 0; i < 1000; i++) {
          final state = GeofenceState(
            deviceId: 'device${i % 10}',
            geofenceId: 'geo$i',
            geofenceName: 'Test',
            isInside: true,
            lastSeenTimestamp: DateTime.now(),
          );
          cache.set('device${i % 10}', 'geo$i', state);
        }

        // Measure set time for new state
        final state = GeofenceState(
          deviceId: 'device5',
          geofenceId: 'geoNew',
          geofenceName: 'Test',
          isInside: true,
          lastSeenTimestamp: DateTime.now(),
        );

        final stopwatch = Stopwatch()..start();
        cache.set('device5', 'geoNew', state);
        stopwatch.stop();

        // Should be < 1ms
        expect(stopwatch.elapsedMilliseconds, lessThan(5));
      });
    });

    group('Edge Cases', () {
      test('handles empty device ID', () {
        final state = GeofenceState(
          deviceId: '',
          geofenceId: 'geo1',
          geofenceName: 'Test',
          isInside: true,
          lastSeenTimestamp: DateTime.now(),
        );

        expect(() => cache.set('', 'geo1', state), returnsNormally);
        expect(cache.get('', 'geo1'), isNotNull);
      });

      test('handles empty geofence ID', () {
        final state = GeofenceState(
          deviceId: 'device1',
          geofenceId: '',
          geofenceName: 'Test',
          isInside: true,
          lastSeenTimestamp: DateTime.now(),
        );

        expect(() => cache.set('device1', '', state), returnsNormally);
        expect(cache.get('device1', ''), isNotNull);
      });

      test('getDeviceStates returns empty map for non-existent device', () {
        final states = cache.getDeviceStates('non-existent');
        expect(states.isEmpty, true);
      });

      test('removeDevice handles non-existent device', () {
        expect(() => cache.removeDevice('non-existent'), returnsNormally);
      });

      test('removeGeofence handles non-existent geofence', () {
        expect(() => cache.removeGeofence('non-existent'), returnsNormally);
      });
    });
  });

  group('CacheStatistics', () {
    test('toString provides readable summary', () {
      const stats = CacheStatistics(
        totalStates: 10,
        totalDevices: 2,
        totalLookups: 100,
        cacheHits: 75,
        cacheMisses: 25,
        inserts: 10,
        updates: 5,
        removals: 2,
        evictions: 3,
        hitRate: 75,
        missRate: 25,
        averageStatesPerDevice: 5,
      );

      final str = stats.toString();
      expect(str, contains('states: 10'));
      expect(str, contains('devices: 2'));
      expect(str, contains('hits: 75/100'));
      expect(str, contains('75.0%'));
      expect(str, contains('evictions: 3'));
    });
  });
}
