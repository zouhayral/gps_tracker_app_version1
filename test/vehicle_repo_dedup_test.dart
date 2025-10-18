import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:my_app_gps/core/data/vehicle_data_cache.dart';
import 'package:my_app_gps/core/data/vehicle_data_repository.dart';
import 'package:my_app_gps/core/database/dao/telemetry_dao.dart';
import 'package:my_app_gps/core/database/entities/telemetry_record.dart';
import 'package:my_app_gps/features/map/data/position_model.dart';
import 'package:my_app_gps/services/auth_service.dart';
import 'package:my_app_gps/services/device_service.dart';
import 'package:my_app_gps/services/positions_service.dart';
import 'package:my_app_gps/services/traccar_socket_service.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'test_utils/test_config.dart' as testenv;

// Fake telemetry DAO (no-op)
class _FakeTelemetryDao implements TelemetryDaoBase {
  @override
  Future<void> deleteOlderThan(DateTime cutoff) async {}

  @override
  Future<List<TelemetryRecord>> byDeviceInRange(
    int deviceId,
    DateTime start,
    DateTime end,
  ) async => <TelemetryRecord>[];

  @override
  Future<int> countForDevice(int deviceId) async => 0;

  @override
  Future<void> put(TelemetryRecord record) async {}

  @override
  Future<void> putMany(List<TelemetryRecord> records) async {}
}

// Fake TraccarSocketService to emit controlled messages
class _FakeSocket implements TraccarSocketService {
  final _ctrl = StreamController<TraccarSocketMessage>.broadcast();
  @override
  String get baseUrl => 'https://example.com';
  @override
  AuthService get auth => throw UnimplementedError('auth not used');
  @override
  Stream<TraccarSocketMessage> connect() => _ctrl.stream;
  void push(TraccarSocketMessage m) => _ctrl.add(m);
  @override
  Future<void> close() async => _ctrl.close();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    await testenv.setupTestEnvironment();
  });

  test(
      'duplicate positions are skipped (five identical -> one update)', () async {
    // Prepare container with overrides
    final socket = _FakeSocket();

    // Provide a simple in-memory cache using mock prefs
    final prefs = await SharedPreferences.getInstance();

    // Disable timers/background polling in repository for tests
    VehicleDataRepository.testMode = true;

    final container = ProviderContainer(overrides: [
      // Cache provider
      vehicleDataCacheProvider.overrideWithValue(VehicleDataCache(prefs: prefs)),
      // Socket provider
      traccarSocketServiceProvider.overrideWith((ref) => socket),
      // Device service (not used in this test)
      deviceServiceProvider.overrideWith((ref) => DeviceService(Dio(BaseOptions(baseUrl: 'https://example.com')))),
      // Positions service (not used directly here)
      positionsServiceProvider.overrideWith((ref) => PositionsService(Dio(BaseOptions(baseUrl: 'https://example.com')))),
      // Telemetry DAO
      telemetryDaoProvider.overrideWithValue(_FakeTelemetryDao()),
    ]);

    addTearDown(container.dispose);

    // Access repo (which will subscribe to socket)
    final repo = container.read(vehicleDataRepositoryProvider);

    // Listen to notifier updates for device 1
    final notifier = repo.getNotifier(1);
    var updateCount = 0;
    notifier.addListener(() {
      // Count only non-null updates
      if (notifier.value != null) updateCount++;
    });

    // Build a base position
    final base = Position(
      id: 42,
      deviceId: 1,
      latitude: 35,
      longitude: -5,
      speed: 0,
      course: 0,
      deviceTime: DateTime.now().toUtc(),
      serverTime: DateTime.now().toUtc(),
      attributes: const {'ignition': false},
    );

    // Send the same position 5 times via socket
    for (var i = 0; i < 5; i++) {
      socket.push(TraccarSocketMessage.positions(<Position>[base]));
      await Future<void>.delayed(const Duration(milliseconds: 5));
    }

    // Allow debounce timer to fire in repo
    await Future<void>.delayed(const Duration(milliseconds: 400));

    // Expect only a single update despite five identical messages
    expect(updateCount, 1);
  },
  );
}
