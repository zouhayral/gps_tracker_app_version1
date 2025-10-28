import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:my_app_gps/core/database/dao/devices_dao.dart';
import 'package:my_app_gps/core/database/dao/events_dao.dart';
import 'package:my_app_gps/core/database/dao/positions_dao.dart';
import 'package:my_app_gps/core/database/dao/telemetry_dao.dart';
import 'package:my_app_gps/data/models/event.dart';
import 'package:my_app_gps/features/dashboard/controller/devices_notifier.dart';
import 'package:my_app_gps/features/map/data/position_model.dart';
import 'package:my_app_gps/features/map/data/positions_last_known_provider.dart';
import 'package:my_app_gps/features/map/data/positions_live_provider.dart';
import 'package:my_app_gps/features/map/view/map_page.dart';
import 'package:my_app_gps/l10n/app_localizations.dart';
import 'package:my_app_gps/providers/notification_providers.dart';
import 'package:my_app_gps/repositories/notifications_repository.dart';
import 'package:my_app_gps/services/auth_service.dart';
import 'package:my_app_gps/services/device_service.dart';
import 'package:my_app_gps/services/event_service.dart';
import 'package:my_app_gps/services/traccar_socket_service.dart';
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
      webSocketManagerProvider.overrideWith(() {
        WebSocketManager.testMode = true;
        return WebSocketManager();
      }),
      // Override TraccarSocketService to prevent actual WebSocket connections
        traccarSocketServiceProvider.overrideWith(
          (ref) => _TraccarSocketServiceFake.withAuth(ref.read(authServiceProvider)),
        ),
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
      telemetryDaoProvider.overrideWithValue(_TelemetryDaoFake()),
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
        child: MaterialApp(
          supportedLocales: AppLocalizations.supportedLocales,
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          home: MapPage(preselectedIds: {1}),
        ),
      ),
    ),);

    // Allow frames to settle; ensure any 500ms startup timers fire
    await tester.pumpAndSettle(const Duration(seconds: 1));

    // Expect device name in the info panel (selected)
    expect(find.textContaining('Truck 1'), findsOneWidget);

    // Clean up timers started by the notifications repository to avoid pending timers
    final repo = await container.read(notificationsRepositoryProvider.future);
    repo.dispose();
    await tester.pump(const Duration(milliseconds: 50));
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

// A benign fake that exposes a connect() stream without performing any network I/O.
class _TraccarSocketServiceFake extends TraccarSocketService {
  _TraccarSocketServiceFake.withAuth(AuthService auth)
      : super(baseUrl: 'http://localhost', auth: auth);

  final _controller = StreamController<TraccarSocketMessage>.broadcast();

  @override
  Stream<TraccarSocketMessage> connect() {
    // Optionally signal connected state, then remain idle.
    // _controller.add(TraccarSocketMessage.connected());
    return _controller.stream;
  }

  @override
  Future<void> close() async {
    await _controller.close();
  }
}
