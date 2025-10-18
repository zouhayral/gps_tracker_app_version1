import 'package:flutter_test/flutter_test.dart';
import 'package:my_app_gps/core/map/enhanced_marker_cache.dart';
import 'package:my_app_gps/features/map/data/position_model.dart';

void main() {
  group('Marker Delta Rebuild', () {
    late EnhancedMarkerCache cache;

    setUp(() {
      cache = EnhancedMarkerCache();
    });

    tearDown(() {
      cache.clear();
    });

    Position _makePosition({
      required int id,
      required int deviceId,
      required double lat,
      required double lon,
      double speed = 0,
      double course = 0,
      Map<String, dynamic>? attributes,
    }) {
      return Position(
        id: id,
        deviceId: deviceId,
        latitude: lat,
        longitude: lon,
        speed: speed,
        course: course,
        deviceTime: DateTime.now().toUtc(),
        serverTime: DateTime.now().toUtc(),
        attributes: attributes ?? const {},
      );
    }

    Map<String, dynamic> _makeDevice(int id, String name) {
      return {'id': id, 'name': name};
    }

    test('only rebuilds changed markers', () async {
      // Initial update: 2 markers should be created
      final pos1 = _makePosition(id: 1, deviceId: 1, lat: 0, lon: 0);
      final pos2 = _makePosition(id: 2, deviceId: 2, lat: 1, lon: 1);
      final devices = [
        _makeDevice(1, 'Device 1'),
        _makeDevice(2, 'Device 2'),
      ];

      var result = cache.getMarkersWithDiff(
        {1: pos1, 2: pos2},
        devices,
        const {},
        '',
      );

      expect(result.markers.length, 2, reason: 'Should create 2 markers initially');
      expect(result.created, 2, reason: 'Both markers are new');
      expect(result.reused, 0, reason: 'No markers to reuse initially');
      expect(result.modified, 0, reason: 'No modifications on first update');

      // Wait for throttle window to pass
      await Future<void>.delayed(const Duration(milliseconds: 350));

      // Send identical update → no rebuild (all reused)
      result = cache.getMarkersWithDiff(
        {1: pos1, 2: pos2},
        devices,
        const {},
        '',
      );

      expect(result.markers.length, 2, reason: 'Should still have 2 markers');
      expect(result.created, 0, reason: 'No new markers');
      expect(result.reused, 2, reason: 'Both markers should be reused');
      expect(result.modified, 0, reason: 'No modifications');

      // Wait for throttle window to pass
      await Future<void>.delayed(const Duration(milliseconds: 350));

      // Change one position slightly → only one rebuild
      final pos1Changed = _makePosition(
        id: 1,
        deviceId: 1,
        lat: 0.001,
        lon: 0.0,
      );

      result = cache.getMarkersWithDiff(
        {1: pos1Changed, 2: pos2},
        devices,
        const {},
        '',
      );

      expect(result.markers.length, 2, reason: 'Should still have 2 markers');
      expect(result.created, 0, reason: 'No new markers (already existed)');
      expect(result.reused, 1, reason: 'Device 2 marker should be reused');
      expect(result.modified, 1, reason: 'Device 1 marker should be modified');
    });

    test('detects speed changes', () async {
      final pos1 = _makePosition(
        id: 1,
        deviceId: 1,
        lat: 0,
        lon: 0,
        speed: 50,
      );
      final devices = [_makeDevice(1, 'Device 1')];

      var result = cache.getMarkersWithDiff(
        {1: pos1},
        devices,
        const {},
        '',
      );

      expect(result.created, 1, reason: 'Initial marker created');

      // Wait for throttle
      await Future<void>.delayed(const Duration(milliseconds: 350));

      // Same position, different speed
      final pos1Faster = _makePosition(
        id: 1,
        deviceId: 1,
        lat: 0,
        lon: 0,
        speed: 80,
      );

      result = cache.getMarkersWithDiff(
        {1: pos1Faster},
        devices,
        const {},
        '',
      );

      expect(result.modified, 1, reason: 'Speed change should trigger rebuild');
      expect(result.reused, 0, reason: 'Should not reuse with different speed');
    });

    test('detects course/heading changes', () async {
      final pos1 = _makePosition(
        id: 1,
        deviceId: 1,
        lat: 0,
        lon: 0,
        course: 90,
      );
      final devices = [_makeDevice(1, 'Device 1')];

      var result = cache.getMarkersWithDiff(
        {1: pos1},
        devices,
        const {},
        '',
      );

      expect(result.created, 1);

      await Future<void>.delayed(const Duration(milliseconds: 350));

      // Same position, different course
      final pos1Turned = _makePosition(
        id: 1,
        deviceId: 1,
        lat: 0,
        lon: 0,
        course: 180,
      );

      result = cache.getMarkersWithDiff(
        {1: pos1Turned},
        devices,
        const {},
        '',
      );

      expect(result.modified, 1, reason: 'Course change should trigger rebuild');
    });

    test('detects selection state changes', () async {
      final pos1 = _makePosition(id: 1, deviceId: 1, lat: 0, lon: 0);
      final devices = [_makeDevice(1, 'Device 1')];

      // Not selected
      var result = cache.getMarkersWithDiff(
        {1: pos1},
        devices,
        const {},
        '',
      );

      expect(result.created, 1);

      await Future<void>.delayed(const Duration(milliseconds: 350));

      // Now selected
      result = cache.getMarkersWithDiff(
        {1: pos1},
        devices,
        const {1},
        '',
      );

      expect(result.modified, 1, reason: 'Selection change should trigger rebuild');
      expect(result.reused, 0);
    });

    test('handles marker removal', () async {
      final pos1 = _makePosition(id: 1, deviceId: 1, lat: 0, lon: 0);
      final pos2 = _makePosition(id: 2, deviceId: 2, lat: 1, lon: 1);
      final devices = [
        _makeDevice(1, 'Device 1'),
        _makeDevice(2, 'Device 2'),
      ];

      // Create both markers
      var result = cache.getMarkersWithDiff(
        {1: pos1, 2: pos2},
        devices,
        const {},
        '',
      );

      expect(result.created, 2);

      await Future<void>.delayed(const Duration(milliseconds: 350));

      // Remove one marker
      result = cache.getMarkersWithDiff(
        {1: pos1},
        devices,
        const {},
        '',
      );

      expect(result.markers.length, 1, reason: 'Should only have 1 marker now');
      expect(result.removed, 1, reason: 'One marker was removed');
      expect(result.reused, 1, reason: 'Device 1 marker reused');
    });

    test('high marker count scenario (50+ markers)', () async {
      final positions = <int, Position>{};
      final devices = <Map<String, dynamic>>[];

      // Create 50 markers
      for (var i = 1; i <= 50; i++) {
        positions[i] = _makePosition(
          id: i,
          deviceId: i,
          lat: i.toDouble(),
          lon: i.toDouble(),
        );
        devices.add(_makeDevice(i, 'Device $i'));
      }

      var result = cache.getMarkersWithDiff(
        positions,
        devices,
        const {},
        '',
      );

      expect(result.created, 50);

      await Future<void>.delayed(const Duration(milliseconds: 350));

      // Update only 2 markers
      positions[1] = _makePosition(
        id: 1,
        deviceId: 1,
        lat: 1.001,
        lon: 1.0,
      );
      positions[25] = _makePosition(
        id: 25,
        deviceId: 25,
        lat: 25.001,
        lon: 25.0,
      );

      result = cache.getMarkersWithDiff(
        positions,
        devices,
        const {},
        '',
      );

      expect(result.modified, 2, reason: 'Only 2 markers changed');
      expect(result.reused, 48, reason: '48 markers should be reused');
      expect(result.markers.length, 50);

      // Verify efficiency
      final efficiency = result.efficiency;
      expect(efficiency, greaterThan(0.95), reason: 'Should have >95% reuse rate');
    });

    test('query filter reduces marker count', () async {
      final pos1 = _makePosition(id: 1, deviceId: 1, lat: 0, lon: 0);
      final pos2 = _makePosition(id: 2, deviceId: 2, lat: 1, lon: 1);
      final devices = [
        _makeDevice(1, 'Alpha'),
        _makeDevice(2, 'Beta'),
      ];

      // No filter
      var result = cache.getMarkersWithDiff(
        {1: pos1, 2: pos2},
        devices,
        const {},
        '',
      );

      expect(result.markers.length, 2);

      await Future<void>.delayed(const Duration(milliseconds: 350));

      // Filter by "alpha"
      result = cache.getMarkersWithDiff(
        {1: pos1, 2: pos2},
        devices,
        const {},
        'alpha',
      );

      expect(result.markers.length, 1, reason: 'Only "Alpha" should match');
    });
  });
}
