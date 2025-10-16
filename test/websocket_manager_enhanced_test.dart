import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:my_app_gps/services/traccar_socket_service.dart';
import 'package:my_app_gps/services/websocket_manager_enhanced.dart';
import 'package:my_app_gps/services/auth_service.dart';

// Fake TraccarSocketService that implements only the bits our tests need.
class FakeTraccarSocketService implements TraccarSocketService {
  final StreamController<TraccarSocketMessage> _ctrl = StreamController.broadcast();

  @override
  String get baseUrl => 'https://demo.traccar.org';

  // We don't need a real AuthService for these tests; satisfy the API.
  @override
  AuthService get auth => throw UnimplementedError('auth not used in tests');

  @override
  Stream<TraccarSocketMessage> connect() => _ctrl.stream;

  // Helper to push a message
  void push(TraccarSocketMessage msg) => _ctrl.add(msg);

  // Helper to close stream
  @override
  Future<void> close() async {
    await _ctrl.close();
  }
}

void main() {
  test('lastEventAt updates when messages arrive and isSilent works', () async {
    final container = ProviderContainer(overrides: [
      traccarSocketServiceProvider.overrideWith((ref) => FakeTraccarSocketService()),
    ]);

    addTearDown(container.dispose);

  final manager = container.read(webSocketManagerProvider.notifier);

    // Wait briefly for initial connect attempt
    await Future.delayed(const Duration(milliseconds: 50));
    // Ensure manager is started and reachable
    await manager.forceReconnect();

    final fake = container.read(traccarSocketServiceProvider) as FakeTraccarSocketService;

    // Initially lastEventAt may be set at connect; capture initial
    final before = container.read(webSocketManagerProvider).lastEventAt;

    // Push a positions message
    fake.push(TraccarSocketMessage.positions([]));
    await Future.delayed(const Duration(milliseconds: 20));

    final after = container.read(webSocketManagerProvider).lastEventAt;
    expect(after, isNotNull);
    if (before != null) {
      expect(after!.isAfter(before), isTrue);
    }

    // isSilent should be false for a small threshold (1s)
    expect(container.read(webSocketManagerProvider).isSilent(const Duration(seconds: 1)), isFalse);
  });

  test('reconnection scheduling increases retry count (basic)', () async {
    final fake = FakeTraccarSocketService();
    final container = ProviderContainer(overrides: [
      traccarSocketServiceProvider.overrideWith((ref) => fake),
    ]);
    addTearDown(container.dispose);

  final manager = container.read(webSocketManagerProvider.notifier);
  // Ensure manager has started
  await manager.forceReconnect();

  // Simulate error by closing the stream (onDone) - manager should schedule reconnect
  await fake.close();
  await Future.delayed(const Duration(milliseconds: 80));

  final state = container.read(webSocketManagerProvider);
  // Manager should be in retrying state or have incremented retry count
  expect(state.status == WebSocketStatus.retrying || state.retryCount >= 1, isTrue);
  });
}
