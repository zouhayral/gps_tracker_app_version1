import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:my_app_gps/data/models/geofence.dart';
import 'package:my_app_gps/features/geofencing/service/geofence_evaluator_service.dart';

void main() {
  group('GeofenceEvaluatorService', () {
    late GeofenceEvaluatorService evaluator;

    setUp(() {
      evaluator = GeofenceEvaluatorService(
        boundaryToleranceMeters: 5.0,
        dwellThreshold: const Duration(minutes: 2),
      );
    });

    tearDown(() {
      evaluator.clearAllState();
    });

    group('Point-in-Circle Tests', () {
      test('point inside circle generates entry event', () {
        final geofence = Geofence.circle(
          id: 'circle-1',
          userId: 'user1',
          name: 'Test Circle',
          center: const LatLng(34.0522, -118.2437),
          radius: 100.0,
          onEnter: true,
          onExit: true,
        );

        // Position inside circle
        final position = const LatLng(34.0522, -118.2437);
        final timestamp = DateTime.now();

        final events = evaluator.evaluate(
          deviceId: 'device1',
          position: position,
          timestamp: timestamp,
          activeGeofences: [geofence],
        );

        expect(events.length, 1);
        expect(events[0].eventType, 'enter');
        expect(events[0].geofenceId, 'circle-1');
      });

      test('point outside circle generates no event', () {
        final geofence = Geofence.circle(
          id: 'circle-1',
          userId: 'user1',
          name: 'Test Circle',
          center: const LatLng(34.0522, -118.2437),
          radius: 100.0,
          onEnter: true,
          onExit: true,
        );

        // Position far outside circle (~1km away)
        final position = const LatLng(34.0600, -118.2437);
        final timestamp = DateTime.now();

        final events = evaluator.evaluate(
          deviceId: 'device1',
          position: position,
          timestamp: timestamp,
          activeGeofences: [geofence],
        );

        expect(events.length, 0);
      });

      test('exit from circle generates exit event', () {
        final geofence = Geofence.circle(
          id: 'circle-1',
          userId: 'user1',
          name: 'Test Circle',
          center: const LatLng(34.0522, -118.2437),
          radius: 100.0,
          onEnter: true,
          onExit: true,
        );

        final timestamp1 = DateTime.now();
        final timestamp2 = timestamp1.add(const Duration(seconds: 30));

        // First: inside circle
        final events1 = evaluator.evaluate(
          deviceId: 'device1',
          position: const LatLng(34.0522, -118.2437),
          timestamp: timestamp1,
          activeGeofences: [geofence],
        );

        expect(events1.length, 1);
        expect(events1[0].eventType, 'enter');

        // Second: outside circle
        final events2 = evaluator.evaluate(
          deviceId: 'device1',
          position: const LatLng(34.0600, -118.2437),
          timestamp: timestamp2,
          activeGeofences: [geofence],
        );

        expect(events2.length, 1);
        expect(events2[0].eventType, 'exit');
      });

      test('boundary tolerance prevents flapping', () {
        final geofence = Geofence.circle(
          id: 'circle-1',
          userId: 'user1',
          name: 'Test Circle',
          center: const LatLng(34.0522, -118.2437),
          radius: 100.0,
          onEnter: true,
          onExit: true,
        );

        // Position at ~102m (just outside radius but within tolerance)
        final position = const LatLng(34.0531, -118.2437);
        final timestamp = DateTime.now();

        final events = evaluator.evaluate(
          deviceId: 'device1',
          position: position,
          timestamp: timestamp,
          activeGeofences: [geofence],
        );

        // Should generate entry event due to tolerance buffer
        expect(events.length, 1);
        expect(events[0].eventType, 'enter');
      });
    });

    group('Point-in-Polygon Tests', () {
      test('point inside polygon generates entry event', () {
        final geofence = Geofence.polygon(
          id: 'poly-1',
          userId: 'user1',
          name: 'Test Polygon',
          vertices: const [
            LatLng(34.0520, -118.2440),
            LatLng(34.0520, -118.2430),
            LatLng(34.0530, -118.2430),
            LatLng(34.0530, -118.2440),
          ],
          onEnter: true,
          onExit: true,
        );

        // Position inside polygon
        final position = const LatLng(34.0525, -118.2435);
        final timestamp = DateTime.now();

        final events = evaluator.evaluate(
          deviceId: 'device1',
          position: position,
          timestamp: timestamp,
          activeGeofences: [geofence],
        );

        expect(events.length, 1);
        expect(events[0].eventType, 'enter');
      });

      test('point outside polygon generates no event', () {
        final geofence = Geofence.polygon(
          id: 'poly-1',
          userId: 'user1',
          name: 'Test Polygon',
          vertices: const [
            LatLng(34.0520, -118.2440),
            LatLng(34.0520, -118.2430),
            LatLng(34.0530, -118.2430),
            LatLng(34.0530, -118.2440),
          ],
          onEnter: true,
          onExit: true,
        );

        // Position outside polygon
        final position = const LatLng(34.0540, -118.2435);
        final timestamp = DateTime.now();

        final events = evaluator.evaluate(
          deviceId: 'device1',
          position: position,
          timestamp: timestamp,
          activeGeofences: [geofence],
        );

        expect(events.length, 0);
      });

      test('bounding box optimization works', () {
        final vertices = const [
          LatLng(34.0520, -118.2440),
          LatLng(34.0520, -118.2430),
          LatLng(34.0530, -118.2430),
          LatLng(34.0530, -118.2440),
        ];

        // Point inside bounding box
        expect(
          GeofenceEvaluatorService.testBoundingBox(
            const LatLng(34.0525, -118.2435),
            vertices,
          ),
          true,
        );

        // Point outside bounding box
        expect(
          GeofenceEvaluatorService.testBoundingBox(
            const LatLng(34.0600, -118.2435),
            vertices,
          ),
          false,
        );
      });
    });

    group('Dwell Event Tests', () {
      test('dwell event generated after threshold', () {
        final geofence = Geofence.circle(
          id: 'circle-1',
          userId: 'user1',
          name: 'Test Circle',
          center: const LatLng(34.0522, -118.2437),
          radius: 100.0,
          onEnter: true,
          onExit: true,
          dwellMs: 120000, // 2 minutes
        );

        final timestamp1 = DateTime.now();
        final timestamp2 = timestamp1.add(const Duration(minutes: 3));

        // First: enter
        final events1 = evaluator.evaluate(
          deviceId: 'device1',
          position: const LatLng(34.0522, -118.2437),
          timestamp: timestamp1,
          activeGeofences: [geofence],
        );

        expect(events1.length, 1);
        expect(events1[0].eventType, 'enter');

        // Second: still inside after 3 minutes (should trigger dwell)
        final events2 = evaluator.evaluate(
          deviceId: 'device1',
          position: const LatLng(34.0522, -118.2437),
          timestamp: timestamp2,
          activeGeofences: [geofence],
        );

        expect(events2.length, 1);
        expect(events2[0].eventType, 'dwell');
        expect(events2[0].dwellDurationMs, greaterThanOrEqualTo(120000));
      });

      test('dwell event not duplicated', () {
        final geofence = Geofence.circle(
          id: 'circle-1',
          userId: 'user1',
          name: 'Test Circle',
          center: const LatLng(34.0522, -118.2437),
          radius: 100.0,
          onEnter: true,
          onExit: true,
          dwellMs: 120000, // 2 minutes
        );

        final timestamp1 = DateTime.now();
        final timestamp2 = timestamp1.add(const Duration(minutes: 3));
        final timestamp3 = timestamp1.add(const Duration(minutes: 5));

        // First: enter
        evaluator.evaluate(
          deviceId: 'device1',
          position: const LatLng(34.0522, -118.2437),
          timestamp: timestamp1,
          activeGeofences: [geofence],
        );

        // Second: dwell event
        final events2 = evaluator.evaluate(
          deviceId: 'device1',
          position: const LatLng(34.0522, -118.2437),
          timestamp: timestamp2,
          activeGeofences: [geofence],
        );

        expect(events2.length, 1);
        expect(events2[0].eventType, 'dwell');

        // Third: still inside, should not generate another dwell
        final events3 = evaluator.evaluate(
          deviceId: 'device1',
          position: const LatLng(34.0522, -118.2437),
          timestamp: timestamp3,
          activeGeofences: [geofence],
        );

        expect(events3.length, 0);
      });

      test('dwell resets on exit and re-entry', () {
        final geofence = Geofence.circle(
          id: 'circle-1',
          userId: 'user1',
          name: 'Test Circle',
          center: const LatLng(34.0522, -118.2437),
          radius: 100.0,
          onEnter: true,
          onExit: true,
          dwellMs: 120000, // 2 minutes
        );

        final timestamp1 = DateTime.now();
        final timestamp2 = timestamp1.add(const Duration(minutes: 3));
        final timestamp3 = timestamp2.add(const Duration(seconds: 30));
        final timestamp4 = timestamp3.add(const Duration(minutes: 3));

        // First: enter
        evaluator.evaluate(
          deviceId: 'device1',
          position: const LatLng(34.0522, -118.2437),
          timestamp: timestamp1,
          activeGeofences: [geofence],
        );

        // Second: dwell
        evaluator.evaluate(
          deviceId: 'device1',
          position: const LatLng(34.0522, -118.2437),
          timestamp: timestamp2,
          activeGeofences: [geofence],
        );

        // Third: exit
        evaluator.evaluate(
          deviceId: 'device1',
          position: const LatLng(34.0600, -118.2437),
          timestamp: timestamp3,
          activeGeofences: [geofence],
        );

        // Fourth: re-enter
        evaluator.evaluate(
          deviceId: 'device1',
          position: const LatLng(34.0522, -118.2437),
          timestamp: timestamp4,
          activeGeofences: [geofence],
        );

        // Fifth: should generate new dwell event
        final timestamp5 = timestamp4.add(const Duration(minutes: 3));
        final events5 = evaluator.evaluate(
          deviceId: 'device1',
          position: const LatLng(34.0522, -118.2437),
          timestamp: timestamp5,
          activeGeofences: [geofence],
        );

        expect(events5.length, 1);
        expect(events5[0].eventType, 'dwell');
      });
    });

    group('Multi-Geofence Tests', () {
      test('multiple geofences evaluated correctly', () {
        final geofence1 = Geofence.circle(
          id: 'circle-1',
          userId: 'user1',
          name: 'Circle 1',
          center: const LatLng(34.0522, -118.2437),
          radius: 50.0, // Smaller radius
          onEnter: true,
        );

        final geofence2 = Geofence.circle(
          id: 'circle-2',
          userId: 'user1',
          name: 'Circle 2',
          center: const LatLng(34.0540, -118.2437), // Further away
          radius: 50.0,
          onEnter: true,
        );

        // Position inside circle-1, outside circle-2
        final position = const LatLng(34.0522, -118.2437);
        final timestamp = DateTime.now();

        final events = evaluator.evaluate(
          deviceId: 'device1',
          position: position,
          timestamp: timestamp,
          activeGeofences: [geofence1, geofence2],
        );

        expect(events.length, 1);
        expect(events[0].geofenceId, 'circle-1');
      });

      test('overlapping geofences both trigger', () {
        final geofence1 = Geofence.circle(
          id: 'circle-1',
          userId: 'user1',
          name: 'Circle 1',
          center: const LatLng(34.0522, -118.2437),
          radius: 100.0,
          onEnter: true,
        );

        final geofence2 = Geofence.circle(
          id: 'circle-2',
          userId: 'user1',
          name: 'Circle 2',
          center: const LatLng(34.0523, -118.2437),
          radius: 100.0,
          onEnter: true,
        );

        // Position inside both circles
        final position = const LatLng(34.05225, -118.2437);
        final timestamp = DateTime.now();

        final events = evaluator.evaluate(
          deviceId: 'device1',
          position: position,
          timestamp: timestamp,
          activeGeofences: [geofence1, geofence2],
        );

        expect(events.length, 2);
      });
    });

    group('Device Filtering Tests', () {
      test('device not in monitored list generates no event', () {
        final geofence = Geofence.circle(
          id: 'circle-1',
          userId: 'user1',
          name: 'Test Circle',
          center: const LatLng(34.0522, -118.2437),
          radius: 100.0,
          monitoredDevices: const ['device2', 'device3'], // device1 not monitored
          onEnter: true,
        );

        final position = const LatLng(34.0522, -118.2437);
        final timestamp = DateTime.now();

        final events = evaluator.evaluate(
          deviceId: 'device1',
          position: position,
          timestamp: timestamp,
          activeGeofences: [geofence],
        );

        expect(events.length, 0);
      });

      test('device in monitored list generates event', () {
        final geofence = Geofence.circle(
          id: 'circle-1',
          userId: 'user1',
          name: 'Test Circle',
          center: const LatLng(34.0522, -118.2437),
          radius: 100.0,
          monitoredDevices: const ['device1', 'device2'],
          onEnter: true,
        );

        final position = const LatLng(34.0522, -118.2437);
        final timestamp = DateTime.now();

        final events = evaluator.evaluate(
          deviceId: 'device1',
          position: position,
          timestamp: timestamp,
          activeGeofences: [geofence],
        );

        expect(events.length, 1);
      });

      test('empty monitored list accepts all devices', () {
        final geofence = Geofence.circle(
          id: 'circle-1',
          userId: 'user1',
          name: 'Test Circle',
          center: const LatLng(34.0522, -118.2437),
          radius: 100.0,
          monitoredDevices: const [], // Empty = monitor all
          onEnter: true,
        );

        final position = const LatLng(34.0522, -118.2437);
        final timestamp = DateTime.now();

        final events = evaluator.evaluate(
          deviceId: 'any-device',
          position: position,
          timestamp: timestamp,
          activeGeofences: [geofence],
        );

        expect(events.length, 1);
      });
    });

    group('Trigger Configuration Tests', () {
      test('onEnter disabled prevents entry event', () {
        final geofence = Geofence.circle(
          id: 'circle-1',
          userId: 'user1',
          name: 'Test Circle',
          center: const LatLng(34.0522, -118.2437),
          radius: 100.0,
          onEnter: false, // Disabled
          onExit: true,
        );

        final position = const LatLng(34.0522, -118.2437);
        final timestamp = DateTime.now();

        final events = evaluator.evaluate(
          deviceId: 'device1',
          position: position,
          timestamp: timestamp,
          activeGeofences: [geofence],
        );

        expect(events.length, 0);
      });

      test('onExit disabled prevents exit event', () {
        final geofence = Geofence.circle(
          id: 'circle-1',
          userId: 'user1',
          name: 'Test Circle',
          center: const LatLng(34.0522, -118.2437),
          radius: 100.0,
          onEnter: true,
          onExit: false, // Disabled
        );

        final timestamp1 = DateTime.now();
        final timestamp2 = timestamp1.add(const Duration(seconds: 30));

        // First: enter (should work)
        final events1 = evaluator.evaluate(
          deviceId: 'device1',
          position: const LatLng(34.0522, -118.2437),
          timestamp: timestamp1,
          activeGeofences: [geofence],
        );

        expect(events1.length, 1);

        // Second: exit (should not generate event)
        final events2 = evaluator.evaluate(
          deviceId: 'device1',
          position: const LatLng(34.0600, -118.2437),
          timestamp: timestamp2,
          activeGeofences: [geofence],
        );

        expect(events2.length, 0);
      });
    });

    group('State Management Tests', () {
      test('getState returns current state', () {
        final geofence = Geofence.circle(
          id: 'circle-1',
          userId: 'user1',
          name: 'Test Circle',
          center: const LatLng(34.0522, -118.2437),
          radius: 100.0,
          onEnter: true,
        );

        evaluator.evaluate(
          deviceId: 'device1',
          position: const LatLng(34.0522, -118.2437),
          timestamp: DateTime.now(),
          activeGeofences: [geofence],
        );

        final state = evaluator.getState('device1', 'circle-1');
        expect(state, isNotNull);
        expect(state!.isInside, true);
      });

      test('clearDeviceState removes device states', () {
        final geofence = Geofence.circle(
          id: 'circle-1',
          userId: 'user1',
          name: 'Test Circle',
          center: const LatLng(34.0522, -118.2437),
          radius: 100.0,
          onEnter: true,
        );

        evaluator.evaluate(
          deviceId: 'device1',
          position: const LatLng(34.0522, -118.2437),
          timestamp: DateTime.now(),
          activeGeofences: [geofence],
        );

        expect(evaluator.stateCount, 1);

        evaluator.clearDeviceState('device1');
        expect(evaluator.stateCount, 0);
      });

      test('clearGeofenceState removes geofence states', () {
        final geofence = Geofence.circle(
          id: 'circle-1',
          userId: 'user1',
          name: 'Test Circle',
          center: const LatLng(34.0522, -118.2437),
          radius: 100.0,
          onEnter: true,
        );

        evaluator.evaluate(
          deviceId: 'device1',
          position: const LatLng(34.0522, -118.2437),
          timestamp: DateTime.now(),
          activeGeofences: [geofence],
        );

        expect(evaluator.stateCount, 1);

        evaluator.clearGeofenceState('circle-1');
        expect(evaluator.stateCount, 0);
      });
    });

    group('Test Utilities', () {
      test('testPointInPolygon works correctly', () {
        final vertices = const [
          LatLng(34.0520, -118.2440),
          LatLng(34.0520, -118.2430),
          LatLng(34.0530, -118.2430),
          LatLng(34.0530, -118.2440),
        ];

        // Inside
        expect(
          GeofenceEvaluatorService.testPointInPolygon(
            const LatLng(34.0525, -118.2435),
            vertices,
          ),
          true,
        );

        // Outside
        expect(
          GeofenceEvaluatorService.testPointInPolygon(
            const LatLng(34.0540, -118.2435),
            vertices,
          ),
          false,
        );
      });

      test('testDistance calculates correctly', () {
        final distance = GeofenceEvaluatorService.testDistance(
          const LatLng(34.0522, -118.2437),
          const LatLng(34.0531, -118.2437),
        );

        // Should be approximately 100 meters
        expect(distance, greaterThan(95));
        expect(distance, lessThan(105));
      });
    });
  });

  group('GeofenceState', () {
    test('copyWith preserves unmodified fields', () {
      final state = GeofenceState(
        deviceId: 'device1',
        geofenceId: 'geo1',
        geofenceName: 'Test',
        isInside: true,
        enterTimestamp: DateTime.now(),
        lastSeenTimestamp: DateTime.now(),
        dwellEventSent: false,
      );

      final updated = state.copyWith(isInside: false);

      expect(updated.deviceId, state.deviceId);
      expect(updated.geofenceId, state.geofenceId);
      expect(updated.isInside, false);
    });

    test('dwellDuration calculated correctly', () {
      final enterTime = DateTime.now().subtract(const Duration(minutes: 5));
      final state = GeofenceState(
        deviceId: 'device1',
        geofenceId: 'geo1',
        geofenceName: 'Test',
        isInside: true,
        enterTimestamp: enterTime,
        lastSeenTimestamp: DateTime.now(),
      );

      final duration = state.dwellDuration;
      expect(duration, isNotNull);
      expect(duration!.inMinutes, greaterThanOrEqualTo(4));
      expect(duration.inMinutes, lessThanOrEqualTo(6));
    });

    test('dwellDuration null when outside', () {
      final state = GeofenceState(
        deviceId: 'device1',
        geofenceId: 'geo1',
        geofenceName: 'Test',
        isInside: false,
        lastSeenTimestamp: DateTime.now(),
      );

      expect(state.dwellDuration, isNull);
    });
  });
}
