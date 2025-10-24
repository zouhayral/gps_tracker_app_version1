import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:my_app_gps/core/database/dao/devices_dao.dart';
import 'package:my_app_gps/core/database/dao/events_dao.dart';
import 'package:my_app_gps/core/database/dao/positions_dao.dart';
import 'package:my_app_gps/core/database/dao/telemetry_dao.dart';
import 'package:my_app_gps/core/database/entities/device_entity.dart';
import 'package:my_app_gps/core/database/entities/event_entity.dart';
import 'package:my_app_gps/features/dashboard/controller/devices_notifier.dart';
import 'package:my_app_gps/features/map/data/position_model.dart';
import 'package:my_app_gps/features/map/data/positions_last_known_provider.dart';
import 'package:my_app_gps/features/map/data/positions_live_provider.dart';
import 'package:my_app_gps/features/map/view/map_page.dart';
import 'package:my_app_gps/providers/notification_providers.dart';
import 'package:my_app_gps/repositories/notifications_repository.dart';
import 'package:my_app_gps/services/device_service.dart';
import 'package:my_app_gps/services/event_service.dart';
import 'package:my_app_gps/services/websocket_manager.dart';

import 'test_utils/test_config.dart';

void main() {
  setUpAll(() async {
    await setupTestEnvironment();
  });

  testWidgets('Offline device shows last-known marker and info',
      (tester) async {
    final lastKnown = {
      1: Position(
        deviceId: 1,
        latitude: 40,
        longitude: -3,
        speed: 0,
        course: 0,
        deviceTime: DateTime.utc(2024),
        serverTime: DateTime.utc(2024, 1, 1, 0, 0, 1),
        attributes: const {},
      ),
    };
    final devices = [
      {
        'id': 1,
        'name': 'Truck 1',
        'latitude': 0.0,
        'longitude': 0.0,
        'positionId': 10,
      },
    ];

    final container = ProviderContainer(overrides: [
      webSocketProvider.overrideWith(() {
        WebSocketManager.testMode = true;
        return WebSocketManager();
      }),
      // Provide a safe notifications repository to avoid early DAO reads in banner init
      notificationsRepositoryProvider.overrideWith((ref) {
        // Use a real EventService instance; we won't trigger network calls in this test
        // DAOs are in-memory fakes defined below
        final eventService = EventService(dio: Dio(), ref: ref);
        return NotificationsRepository(
          eventService: eventService,
          eventsDao: _EventsDaoFake(),
          devicesDao: _DevicesDaoFake(),
          ref: ref,
        );
      }),
      // Avoid ObjectBox-backed DAOs in this widget test
      telemetryDaoProvider.overrideWithValue(TelemetryDaoNoop()),
      eventsDaoProvider.overrideWith((ref) async => _EventsDaoFake()),
      devicesDaoProvider.overrideWith((ref) async => _DevicesDaoFake()),
      // Devices list
      devicesNotifierProvider
          .overrideWith((ref) => _DevicesNotifierFixed(devices)),
      // Live positions empty
      positionsLiveProvider
          .overrideWith((ref) => const Stream<Map<int, Position>>.empty()),
      // Last-known provider returns given map directly
      positionsLastKnownProvider
          .overrideWith(() => PositionsLastKnownNotifierFixed(lastKnown)),
      // DAO provider not used in this widget test
      positionsDaoProvider.overrideWith((ref) async => _DaoNoop()),
    ],);
    addTearDown(container.dispose);

    await tester.pumpWidget(UncontrolledProviderScope(
      container: container,
      child: const Directionality(
        textDirection: TextDirection.ltr,
        child: MaterialApp(home: MapPage(preselectedIds: {1})),
      ),
    ),);

    // Allow frames to settle
    await tester.pumpAndSettle(const Duration(milliseconds: 200));

    // Expect device name in the info panel (selected)
    expect(find.textContaining('Truck 1'), findsOneWidget);
  });
}

class _DaoNoop implements PositionsDaoBase {
  @override
  Future<Map<int, Position>> loadAll() async => {};
  @override
  Future<Position?> latestByDevice(int deviceId) async => null;
  @override
  Future<void> upsert(Position p) async {}
}

class _DevicesNotifierFixed extends DevicesNotifier {
  _DevicesNotifierFixed(List<Map<String, dynamic>> initial)
      : super(_DeviceServiceDummy()) {
    state = AsyncValue.data(initial);
  }
}

class _DeviceServiceDummy extends DeviceService {
  _DeviceServiceDummy() : super(Dio());
}

class PositionsLastKnownNotifierFixed extends PositionsLastKnownNotifier {
  PositionsLastKnownNotifierFixed(this.map);
  final Map<int, Position> map;
  @override
  Future<Map<int, Position>> build() async => map;
}

// ...existing code...

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
