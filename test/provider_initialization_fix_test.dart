import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:my_app_gps/services/traccar_socket_service.dart';
import 'package:my_app_gps/services/websocket_manager.dart';

/// Tests to verify provider initialization doesn't crash
/// Regression test for: "Bad state: Tried to read the state of an uninitialized provider"
void main() {
  group('Provider Initialization Tests', () {
    test('WebSocketManagerEnhanced initializes without crashing', () async {
      // Create a ProviderContainer (mimics ProviderScope)
      final container = ProviderContainer(
        overrides: [
          // Override dependencies to prevent actual network calls
          traccarSocketServiceProvider.overrideWith((ref) {
            throw UnimplementedError('Mock socket service');
          }),
        ],
      );

      // This should NOT throw "uninitialized provider" error
      expect(
        () => container.read(webSocketManagerProvider),
        returnsNormally,
      );

      // Wait for microtask to complete
      await Future.microtask(() {});

      // Verify state is valid
      final state = container.read(webSocketManagerProvider);
      expect(state.status, isNotNull);

      container.dispose();
    });

    test('Multiple providers can be read simultaneously', () async {
      final container = ProviderContainer(
        overrides: [
          traccarSocketServiceProvider.overrideWith((ref) {
            throw UnimplementedError('Mock socket service');
          }),
        ],
      );

      // Read provider multiple times in quick succession
      // Should not crash with uninitialized provider error
      expect(() {
        container.read(webSocketManagerProvider);
        container.read(webSocketManagerProvider);
      }, returnsNormally,);

      await Future.microtask(() {});

      container.dispose();
    });

    test('Providers survive hot reload simulation', () async {
      // Simulate hot reload by creating and disposing containers
      for (var i = 0; i < 3; i++) {
        final container = ProviderContainer(
          overrides: [
            traccarSocketServiceProvider.overrideWith((ref) {
              throw UnimplementedError('Mock socket service');
            }),
          ],
        );

        // Should initialize cleanly each time
        expect(
          () => container.read(webSocketManagerProvider),
          returnsNormally,
        );

        await Future.microtask(() {});

        container.dispose();
      }
    });
  });
}
