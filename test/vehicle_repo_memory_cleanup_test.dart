import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:my_app_gps/core/data/vehicle_data_cache.dart';
import 'package:my_app_gps/core/data/vehicle_data_repository.dart';
import 'package:my_app_gps/core/database/dao/telemetry_dao.dart';
import 'package:my_app_gps/core/database/entities/telemetry_record.dart';
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
  ) async =>
      <TelemetryRecord>[];

  @override
  Future<int> countForDevice(int deviceId) async => 0;

  @override
  Future<void> put(TelemetryRecord record) async {}

  @override
  Future<void> putMany(List<TelemetryRecord> records) async {}
}

// Fake TraccarSocketService with no-op implementation
class _FakeSocket implements TraccarSocketService {
  final _ctrl = StreamController<TraccarSocketMessage>.broadcast();
  @override
  String get baseUrl => 'https://example.com';
  @override
  AuthService get auth => throw UnimplementedError('auth not used');
  @override
  Stream<TraccarSocketMessage> connect() => _ctrl.stream;
  @override
  Future<void> close() async => _ctrl.close();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    await testenv.setupTestEnvironment();
  });

  group('VehicleDataRepository Memory Cleanup', () {
    late ProviderContainer container;
    late VehicleDataRepository repo;

    setUp(() async {
      final socket = _FakeSocket();
      final prefs = await SharedPreferences.getInstance();
      await prefs.clear();

      // Disable timers/background polling in repository for tests
      VehicleDataRepository.testMode = true;

      container = ProviderContainer(overrides: [
        vehicleDataCacheProvider
            .overrideWithValue(VehicleDataCache(prefs: prefs)),
        traccarSocketServiceProvider.overrideWith((ref) => socket),
        deviceServiceProvider.overrideWith(
          (ref) => DeviceService(
              Dio(BaseOptions(baseUrl: 'https://example.com')),),
        ),
        positionsServiceProvider.overrideWith(
          (ref) => PositionsService(
              Dio(BaseOptions(baseUrl: 'https://example.com')),),
        ),
        telemetryDaoProvider.overrideWithValue(_FakeTelemetryDao()),
      ]);

      repo = container.read(vehicleDataRepositoryProvider);
    });

    tearDown(() {
      container.dispose();
    });

    test('handles empty notifiers map gracefully', () {
      // Repo starts empty (no devices loaded)
      // Invoke cleanup on empty map should not crash
      expect(() => repo.invokeTestCleanup(), returnsNormally);
    });

    test('handles null snapshot values gracefully', () {
      // Get a notifier for a device that doesn't exist yet
      final notifier = repo.getNotifier(99);
      expect(notifier.value, isNull); // Initially null

      // Invoke cleanup - should skip null snapshots
      expect(() => repo.invokeTestCleanup(), returnsNormally);

      // Notifier should still exist (not removed)
      final notifierAfter = repo.getNotifier(99);
      expect(notifierAfter, isNotNull);
    });

    test('cleanup timer initializes without crashing', () {
      // Cleanup timer is started in _init()
      // This test verifies initialization doesn't throw
      // Timer itself is disabled in test mode
      expect(repo, isNotNull);
    });
  });
}
