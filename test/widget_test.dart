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
import 'package:my_app_gps/core/database/entities/device_entity.dart';
import 'package:my_app_gps/core/database/entities/event_entity.dart';
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
          telemetryDaoProvider.overrideWithValue(TelemetryDaoNoop()),
          eventsDaoProvider.overrideWith((ref) async => _EventsDaoFake()),
          devicesDaoProvider.overrideWith((ref) async => _DevicesDaoFake()),
        ],
        child: const MaterialApp(home: AppRoot()),
      ),
    );
    // Allow initial async auth check and first build frames to complete.
    await tester.pump(const Duration(milliseconds: 100));
    await tester.pumpAndSettle(const Duration(milliseconds: 100));

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
  Future<List<EventEntity>> getAll() async => <EventEntity>[];

  @override
  Future<List<EventEntity>> getByDevice(int deviceId) async => <EventEntity>[];

  @override
  Future<List<EventEntity>> getByDeviceAndType(int deviceId, String eventType) async => <EventEntity>[];

  @override
  Future<List<EventEntity>> getByDeviceInRange(int deviceId, DateTime startTime, DateTime endTime) async => <EventEntity>[];

  @override
  Future<EventEntity?> getById(String eventId) async => null;

  @override
  Future<List<EventEntity>> getByType(String eventType) async => <EventEntity>[];

  @override
  Future<void> upsert(EventEntity event) async {}

  @override
  Future<void> upsertMany(List<EventEntity> events) async {}
}

class _DevicesDaoFake implements DevicesDaoBase {
  @override
  Future<void> delete(int deviceId) async {}

  @override
  Future<void> deleteAll() async {}

  @override
  Future<List<DeviceEntity>> getAll() async => <DeviceEntity>[];

  @override
  Future<DeviceEntity?> getById(int deviceId) async => null;

  @override
  Future<List<DeviceEntity>> getByStatus(String status) async => <DeviceEntity>[];

  @override
  Future<void> upsert(DeviceEntity device) async {}

  @override
  Future<void> upsertMany(List<DeviceEntity> devices) async {}
}
