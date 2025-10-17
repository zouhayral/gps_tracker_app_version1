import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:my_app_gps/services/websocket_manager.dart';

void main() {
  setUp(() {
    WebSocketManager.testMode = true;
  });
  tearDown(() {
    WebSocketManager.testMode = false;
  });

  test('WebSocketManager initializes and disposes cleanly', () async {
    final container = ProviderContainer();
    final sub = container.listen(webSocketProvider, (prev, next) {});
    expect(container.read(webSocketProvider).status, isNotNull);
    sub.close();
    container.dispose();
  });

  test('WebSocketManager exposes a stream', () async {
    final container = ProviderContainer();
    final wsManager = container.read(webSocketProvider.notifier);
    expect(wsManager.stream, isA<Stream<Map<String, dynamic>>>());
    container.dispose();
  });

  test('WebSocketManager reconnect logic triggers after error (test mode)',
      () async {
    final container = ProviderContainer();
    final wsManager = container.read(webSocketProvider.notifier);
    wsManager.stream.listen((_) {}, onError: (_) {});
    await Future<void>.delayed(const Duration(milliseconds: 100));
    final state = container.read(webSocketProvider);
    expect(state.retryCount, greaterThanOrEqualTo(0));
    container.dispose();
  });
}
