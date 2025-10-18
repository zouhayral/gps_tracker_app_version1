import 'dart:async';
import 'dart:convert';

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

  test('duplicate device payloads are skipped (five identical -> one update)', () async {
    final socket = _FakeSocket();

    final prefs = await SharedPreferences.getInstance();

    VehicleDataRepository.testMode = true;

    final container = ProviderContainer(overrides: [
      vehicleDataCacheProvider.overrideWithValue(VehicleDataCache(prefs: prefs)),
      traccarSocketServiceProvider.overrideWith((ref) => socket),
      deviceServiceProvider.overrideWith((ref) => DeviceService(Dio(BaseOptions(baseUrl: 'https://example.com')))),
      positionsServiceProvider.overrideWith((ref) => PositionsService(Dio(BaseOptions(baseUrl: 'https://example.com')))),
      telemetryDaoProvider.overrideWithValue(_FakeTelemetryDao()),
    ]);

    addTearDown(container.dispose);

    // Access repo (which subscribes to socket)
    final repo = container.read(vehicleDataRepositoryProvider);

    // Listen to notifier updates for device 1
    final notifier = repo.getNotifier(1);
    var updateCount = 0;
    notifier.addListener(() {
      if (notifier.value != null) updateCount++;
    });

    // Build an example device payload
    final devicePayload = <String, dynamic>{
      'id': 1,
      'name': 'fmb920',
      'uniqueId': '353201359774459',
      'status': 'online',
      'positionId': 100,
      'lastUpdate': '2025-10-18T21:00:40.248+00:00',
      'attributes': {
        'ignition': false,
        'motion': false,
      },
    };

    // Send the same device payload 5 times via socket
    final text = jsonEncode({'devices': [devicePayload]});
    for (var i = 0; i < 5; i++) {
      // The TraccarSocketService normally parses incoming text and emits
      // TraccarSocketMessage.devices(payload). For the fake socket, we directly
      // create the message the repository listens for.
      socket.push(TraccarSocketMessage.devices(jsonDecode(text)['devices']));
      await Future<void>.delayed(const Duration(milliseconds: 5));
    }

    // Allow repository debounce/timers to settle
    await Future<void>.delayed(const Duration(milliseconds: 400));

    // Expect only a single update despite five identical messages
    expect(updateCount, 1);

    // Summary log
    // ignore: avoid_print
    print('✅ Device payload dedup test passed (1 update from 5 messages)');
  },);
}
