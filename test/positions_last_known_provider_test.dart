import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:my_app_gps/core/database/dao/positions_dao.dart';
import 'package:my_app_gps/features/dashboard/controller/devices_notifier.dart';
import 'package:my_app_gps/features/map/data/position_model.dart';
import 'package:my_app_gps/features/map/data/positions_last_known_provider.dart';
import 'package:my_app_gps/services/device_service.dart';
import 'package:my_app_gps/services/positions_service.dart';

import 'test_utils/test_config.dart';

class _FakeDao implements PositionsDaoBase {
  final Map<int, Position> store = {};
  @override
  Future<Map<int, Position>> loadAll() async => Map.of(store);
  @override
  Future<Position?> latestByDevice(int deviceId) async => store[deviceId];
  @override
  Future<void> upsert(Position p) async => store[p.deviceId] = p;
}

class _FakeService extends PositionsService {
  _FakeService(this.map) : super(Dio());
  final Map<int, Position> map;
  @override
  Future<Map<int, Position>> latestForDevices(
      List<Map<String, dynamic>> _,) async {
    // Simulate network latency so that DAO prefill is emitted first in tests.
    await Future<void>.delayed(const Duration(milliseconds: 50));
    return map;
  }
}

void main() {
  setUpAll(() async {
    await setupTestEnvironment();
  });
  test('Case 1: REST returns data → provider emits map', () async {
    final device = {'id': 1, 'name': 'A', 'positionId': 10};
    final restMap = {
      1: Position(
        deviceId: 1,
        latitude: 1,
        longitude: 2,
        speed: 0,
        course: 0,
        deviceTime: DateTime.utc(2024),
        serverTime: DateTime.utc(2024, 1, 1, 0, 0, 1),
        attributes: const {},
      ),
    };
    final fakeDevices = DevicesNotifierFake();
    final container = ProviderContainer(overrides: [
      positionsDaoProvider.overrideWith((ref) async => _FakeDao()),
      devicesNotifierProvider.overrideWith((ref) => fakeDevices),
      positionsServiceProvider.overrideWith((ref) => _FakeService(restMap)),
    ],);
    addTearDown(container.dispose);
    // Prime devices
    fakeDevices.setDevices([device]);

    final result = await container.read(positionsLastKnownProvider.future);
    expect(result.length, 1);
    expect(result[1]?.latitude, 1);
  });

  test('Case 2: Cached DAO data loads before REST', () async {
    final device = {'id': 1, 'name': 'A', 'positionId': 10};
    final dao = _FakeDao()
      ..store[1] = Position(
        deviceId: 1,
        latitude: 5,
        longitude: 6,
        speed: 0,
        course: 0,
        deviceTime: DateTime.utc(2023),
        serverTime: DateTime.utc(2023, 1, 1, 0, 0, 1),
        attributes: const {},
      );
    // REST returns a newer value
    final restMap = {
      1: Position(
        deviceId: 1,
        latitude: 7,
        longitude: 8,
        speed: 0,
        course: 0,
        deviceTime: DateTime.utc(2024),
        serverTime: DateTime.utc(2024, 1, 1, 0, 0, 1),
        attributes: const {},
      ),
    };
    final fakeDevices = DevicesNotifierFake();
    final container = ProviderContainer(overrides: [
      positionsDaoProvider.overrideWith((ref) async => dao),
      devicesNotifierProvider.overrideWith((ref) => fakeDevices),
      positionsServiceProvider.overrideWith((ref) => _FakeService(restMap)),
    ],);
    addTearDown(container.dispose);
    fakeDevices.setDevices([device]);

    // Start the provider and listen to intermediate states
    final sub = container.listen(
      positionsLastKnownProvider,
      (_, __) {},
      fireImmediately: true,
    );
    addTearDown(sub.close);

    // First, DAO prefill should be available via state.asData
    await Future<void>.delayed(const Duration(milliseconds: 10));
    final first = container.read(positionsLastKnownProvider);
    expect(first.asData?.value[1]?.latitude, 5);

    // Then, REST should replace it — wait up to 1s for the provider to emit the REST result.
    final end = DateTime.now().add(const Duration(seconds: 1));
    Map<int, Position>? finalMap;
    while (DateTime.now().isBefore(end)) {
      final state = container.read(positionsLastKnownProvider);
      finalMap = state.asData?.value;
      if (finalMap != null && finalMap[1]?.latitude == 7) break;
      await Future<void>.delayed(const Duration(milliseconds: 20));
    }
    expect(finalMap, isNotNull);
    expect(finalMap![1]?.latitude, 7);
  });
}

// Minimal fake DevicesNotifier to drive devices list
class DevicesNotifierFake extends DevicesNotifier {
  DevicesNotifierFake() : super(_DeviceServiceFake());
  void setDevices(List<Map<String, dynamic>> devices) {
    state = AsyncValue.data(devices);
  }
}

class _DeviceServiceFake extends DeviceService {
  _DeviceServiceFake() : super(Dio());
  @override
  Future<List<Map<String, dynamic>>> fetchDevices() async => [];
}
