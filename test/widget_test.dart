// This is a basic Flutter widget test.
//
// To perform an interaction with a widget in your test, use the WidgetTester
// utility in the flutter_test package. For example, you can send tap and scroll
// gestures. You can also use WidgetTester to find child widgets in the widget
// tree, read text, and verify that the values of widget properties are correct.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:my_app_gps/app/app_root.dart';
import 'package:my_app_gps/core/database/dao/devices_dao.dart';
import 'package:my_app_gps/core/database/dao/events_dao.dart';
import 'package:my_app_gps/core/database/dao/telemetry_dao.dart';
import 'package:my_app_gps/data/models/event.dart';
import 'test_utils/test_config.dart';

void main() {
  setUpAll(() async {
    // Initialize test environment: in-memory SharedPreferences, disable timers/network, etc.
    await setupTestEnvironment();
  });

  testWidgets('App boots and shows either Login or Map', (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          // Avoid ObjectBox in widget tests
          telemetryDaoProvider.overrideWithValue(_TelemetryDaoFake()),
          eventsDaoProvider.overrideWith((ref) async => _EventsDaoFake()),
          devicesDaoProvider.overrideWith((ref) async => _DevicesDaoFake()),
        ],
        child: const MaterialApp(home: AppRoot()),
      ),
    );
    // Allow initial async auth check and first build frames to complete.
    await tester.pump(const Duration(milliseconds: 100));
    await tester.pumpAndSettle();

    // Expect either login welcome text or map navigation label.
    final loginFinder = find.text('welcome back');
    final mapFinder = find.text('Map');
    final foundLogin = loginFinder.evaluate().isNotEmpty;
    final foundMap = mapFinder.evaluate().isNotEmpty;
    expect(
      foundLogin || foundMap,
      isTrue,
      reason: 'Should show login welcome or map navigation bar at startup',
    );
  });
}

class _EventsDaoFake implements EventsDaoBase {
  @override
  Future<void> delete(String eventId) async {}

  @override
  Future<void> deleteAll() async {}

  @override
  Future<List<Event>> getAll() async => <Event>[];

  @override
  Future<List<Event>> getByDevice(int deviceId) async => <Event>[];

  @override
  Future<List<Event>> getByDeviceAndType(int deviceId, String eventType) async => <Event>[];

  @override
  Future<List<Event>> getByDeviceInRange(int deviceId, DateTime startTime, DateTime endTime) async => <Event>[];

  @override
  Future<Event?> getById(String eventId) async => null;

  @override
  Future<List<Event>> getByType(String eventType) async => <Event>[];

  @override
  Future<void> upsert(Event event) async {}

  @override
  Future<void> upsertMany(List<Event> events) async {}
}

class _DevicesDaoFake implements DevicesDaoBase {
  @override
  Future<void> delete(int deviceId) async {}

  @override
  Future<void> deleteAll() async {}

  @override
  Future<List<DeviceRecord>> getAll() async => <DeviceRecord>[];

  @override
  Future<DeviceRecord?> getById(int deviceId) async => null;

  @override
  Future<List<DeviceRecord>> getByStatus(String status) async => <DeviceRecord>[];

  @override
  Future<void> upsert(DeviceRecord device) async {}

  @override
  Future<void> upsertMany(List<DeviceRecord> devices) async {}
}

class _TelemetryDaoFake implements TelemetryDaoBase {
  @override
  Future<List<TelemetrySample>> byDeviceInRange(
    int deviceId,
    DateTime start,
    DateTime end,
  ) async => <TelemetrySample>[];

  @override
  Future<int> countForDevice(int deviceId) async => 0;

  @override
  Future<void> deleteOlderThan(DateTime cutoff) async {}

  @override
  Future<void> put(TelemetrySample record) async {}

  @override
  Future<void> putMany(List<TelemetrySample> records) async {}
}
