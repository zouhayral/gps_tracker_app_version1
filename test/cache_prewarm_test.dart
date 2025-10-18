import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:my_app_gps/core/data/vehicle_data_cache.dart';
import 'package:my_app_gps/core/data/vehicle_data_snapshot.dart';
import 'package:my_app_gps/features/map/data/position_model.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('VehicleDataCache Pre-warming Tests', () {
    late SharedPreferences prefs;

    setUp(() async {
      SharedPreferences.setMockInitialValues({});
      prefs = await SharedPreferences.getInstance();
    });

    test('loadAll() completes in under 100ms for instant loading', () async {
      // Pre-populate cache with test data (use recent timestamps to avoid staleness)
      final now = DateTime.now();
      final snapshots = <int, Map<String, dynamic>>{};
      for (var i = 1; i <= 50; i++) {
        final pos = Position(
          id: 100 + i,
          deviceId: i,
          deviceTime:
              now.subtract(Duration(seconds: i)), // Use seconds, not minutes
          serverTime: now.subtract(Duration(seconds: i)),
          latitude: 45.0 + i * 0.01,
          longitude: -73.0 + i * 0.01,
          altitude: 100,
          speed: 50,
          course: 180,
          accuracy: 10,
          attributes: const {'ignition': true},
        );

        final snapshot = VehicleDataSnapshot(
          deviceId: i,
          timestamp: pos.serverTime,
          position: pos,
          lastUpdate: pos.deviceTime,
        );

        snapshots[i] = snapshot.toJson();
        await prefs.setString(
            'vehicle_cache_$i', jsonEncode(snapshot.toJson()),);
      }

      // Measure load time (happens in constructor)
      final stopwatch = Stopwatch()..start();
      final cache = VehicleDataCache(prefs: prefs);
      final allSnapshots = cache.loadAll();
      stopwatch.stop();

      expect(stopwatch.elapsedMilliseconds, lessThan(100),
          reason: 'Cache pre-warming must complete in under 100ms',);
      expect(allSnapshots.length, equals(50));
      expect(cache.get(1), isNotNull);
      expect(cache.get(50), isNotNull);
    });

    test('handles empty cache gracefully', () async {
      final stopwatch = Stopwatch()..start();
      final cache = VehicleDataCache(prefs: prefs);
      final allSnapshots = cache.loadAll();
      stopwatch.stop();

      expect(stopwatch.elapsedMilliseconds, lessThan(50));
      expect(allSnapshots.length, equals(0));
      expect(cache.get(1), isNull);
    });

    test('cache entry count matches saved data', () async {
      for (var i = 1; i <= 15; i++) {
        final pos = Position(
          id: 200 + i,
          deviceId: i,
          deviceTime: DateTime.now(),
          serverTime: DateTime.now(),
          latitude: 45,
          longitude: -73,
          altitude: 0,
          speed: 0,
          course: 0,
          accuracy: 10,
          attributes: const {},
        );

        final snapshot = VehicleDataSnapshot(
          deviceId: i,
          timestamp: pos.serverTime,
          position: pos,
          lastUpdate: pos.deviceTime,
        );

        await prefs.setString(
            'vehicle_cache_$i', jsonEncode(snapshot.toJson()),);
      }

      final cache = VehicleDataCache(prefs: prefs);
      final allSnapshots = cache.loadAll();

      expect(allSnapshots.length, equals(15));
      expect(cache.cachedDeviceIds.length, equals(15));
    });

    test('handles corrupted cache data during pre-warm', () async {
      // Store invalid JSON
      await prefs.setString('vehicle_cache_1', 'invalid-json-{]');
      await prefs.setString('vehicle_cache_2', '{"incomplete": true');

      // Should not throw, should handle gracefully
      final cache = VehicleDataCache(prefs: prefs);

      expect(cache.get(1), isNull);
      expect(cache.get(2), isNull);
      expect(cache.loadAll().length, equals(0));
    });

    test('cache validity - stale entries excluded', () async {
      final now = DateTime.now();

      // Fresh position
      final freshPos = Position(
        id: 301,
        deviceId: 1,
        deviceTime: now.subtract(const Duration(minutes: 1)),
        serverTime: now.subtract(const Duration(minutes: 1)),
        latitude: 45,
        longitude: -73,
        altitude: 0,
        speed: 0,
        course: 0,
        accuracy: 10,
        attributes: const {},
      );

      final freshSnapshot = VehicleDataSnapshot(
        deviceId: 1,
        timestamp: freshPos.serverTime,
        position: freshPos,
        lastUpdate: freshPos.deviceTime,
      );

      await prefs.setString(
          'vehicle_cache_1', jsonEncode(freshSnapshot.toJson()),);

      // Stale position (>30 minutes old)
      final stalePos = Position(
        id: 302,
        deviceId: 2,
        deviceTime: now.subtract(const Duration(hours: 2)),
        serverTime: now.subtract(const Duration(hours: 2)),
        latitude: 46,
        longitude: -74,
        altitude: 0,
        speed: 0,
        course: 0,
        accuracy: 10,
        attributes: const {},
      );

      final staleSnapshot = VehicleDataSnapshot(
        deviceId: 2,
        timestamp: stalePos.serverTime,
        position: stalePos,
        lastUpdate: stalePos.deviceTime,
      );

      await prefs.setString(
          'vehicle_cache_2', jsonEncode(staleSnapshot.toJson()),);

      final cache = VehicleDataCache(prefs: prefs);

      // Fresh entry should be loaded
      expect(cache.get(1), isNotNull);

      // Stale entry should be excluded during load
      expect(cache.get(2), isNull);

      final allSnapshots = cache.loadAll();
      expect(allSnapshots.length, equals(1));
    });

    test('large dataset pre-warming performance (100 devices)', () async {
      for (var i = 1; i <= 100; i++) {
        final pos = Position(
          id: 400 + i,
          deviceId: i,
          deviceTime: DateTime.now().subtract(Duration(seconds: i)),
          serverTime: DateTime.now().subtract(Duration(seconds: i)),
          latitude: 45.0 + i * 0.001,
          longitude: -73.0 + i * 0.001,
          altitude: 100,
          speed: 40,
          course: 180,
          accuracy: 10,
          attributes: const {'ignition': true},
        );

        final snapshot = VehicleDataSnapshot(
          deviceId: i,
          timestamp: pos.serverTime,
          position: pos,
          lastUpdate: pos.deviceTime,
        );

        await prefs.setString(
            'vehicle_cache_$i', jsonEncode(snapshot.toJson()),);
      }

      final stopwatch = Stopwatch()..start();
      final cache = VehicleDataCache(prefs: prefs);
      final allSnapshots = cache.loadAll();
      stopwatch.stop();

      // Even with 100 devices, should load quickly
      expect(stopwatch.elapsedMilliseconds, lessThan(200),
          reason: '100 device cache should pre-warm in under 200ms',);

      expect(allSnapshots.length, equals(100));
      expect(cache.get(1), isNotNull);
      expect(cache.get(50), isNotNull);
      expect(cache.get(100), isNotNull);
    });

    test('cache hit ratio tracking after pre-warm', () async {
      for (var i = 1; i <= 10; i++) {
        final pos = Position(
          id: 500 + i,
          deviceId: i,
          deviceTime: DateTime.now(),
          serverTime: DateTime.now(),
          latitude: 45,
          longitude: -73,
          altitude: 0,
          speed: 0,
          course: 0,
          accuracy: 10,
          attributes: const {},
        );

        final snapshot = VehicleDataSnapshot(
          deviceId: i,
          timestamp: pos.serverTime,
          position: pos,
          lastUpdate: pos.deviceTime,
        );

        await prefs.setString(
            'vehicle_cache_$i', jsonEncode(snapshot.toJson()),);
      }

      final cache = VehicleDataCache(prefs: prefs);
      cache.resetMetrics();

      // All should hit
      for (var i = 1; i <= 10; i++) {
        expect(cache.get(i), isNotNull);
      }

      expect(cache.hitRatio, equals(1.0));
      expect(cache.stats['hits'], equals(10));
      expect(cache.stats['misses'], equals(0));
    });
  });
}
