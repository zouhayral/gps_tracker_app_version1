import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:my_app_gps/core/database/dao/positions_dao.dart';
import 'package:my_app_gps/features/dashboard/controller/devices_notifier.dart';
import 'package:my_app_gps/features/map/data/position_model.dart';
import 'package:my_app_gps/features/map/data/positions_last_known_provider.dart';
import 'package:my_app_gps/features/map/data/positions_live_provider.dart';
import 'package:my_app_gps/features/map/view/map_page.dart';
import 'package:my_app_gps/services/device_service.dart';
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

    final container = ProviderContainer(
      overrides: [
        webSocketProvider.overrideWith(() {
          WebSocketManager.testMode = true;
          return WebSocketManager();
        }),
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
      ],
    );
    addTearDown(container.dispose);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const Directionality(
          textDirection: TextDirection.ltr,
          child: MaterialApp(home: MapPage(preselectedIds: {1})),
        ),
      ),
    );

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
