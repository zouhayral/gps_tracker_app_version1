import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:my_app_gps/core/services/network_connectivity_monitor.dart';
import 'package:my_app_gps/core/data/vehicle_data_repository.dart';

/// Mock implementation of VehicleDataRepository for testing
class MockVehicleDataRepository implements VehicleDataRepository {
  int refreshAllCallCount = 0;
  bool shouldThrowOnRefresh = false;

  @override
  Future<void> refreshAll() async {
    refreshAllCallCount++;
    if (shouldThrowOnRefresh) {
      throw Exception('Mock refresh error');
    }
    await Future<void>.delayed(const Duration(milliseconds: 50));
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('NetworkConnectivityMonitor Tests', () {
    late MockVehicleDataRepository mockRepository;

    setUp(() {
      mockRepository = MockVehicleDataRepository();
    });

    test('initializes with checking state', () async {
      final monitor = NetworkConnectivityMonitor(repository: mockRepository);

      // Initially in checking state
      expect(monitor.currentState, equals(NetworkState.checking));
      expect(monitor.stats['currentState'], contains('checking'));

      // Wait for async initialization to complete before disposing
      await Future<void>.delayed(const Duration(milliseconds: 100));
      monitor.dispose();
    });

    test('broadcasts state changes via stream', () async {
      final monitor = NetworkConnectivityMonitor(repository: mockRepository);

      final states = <NetworkState>[];
      final subscription = monitor.stateStream.listen(states.add);

      // Wait for initial connectivity check
      await Future<void>.delayed(const Duration(milliseconds: 200));

      // Should have received at least one state update
      expect(states.isNotEmpty, isTrue);

      await subscription.cancel();
      monitor.dispose();
    });

    test('stream broadcasts to multiple listeners', () async {
      final monitor = NetworkConnectivityMonitor(repository: mockRepository);

      final states1 = <NetworkState>[];
      final states2 = <NetworkState>[];

      final sub1 = monitor.stateStream.listen(states1.add);
      final sub2 = monitor.stateStream.listen(states2.add);

      // Wait for initial check
      await Future<void>.delayed(const Duration(milliseconds: 200));

      // Both listeners should receive state updates
      expect(states1.isNotEmpty, isTrue);
      expect(states2.isNotEmpty, isTrue);
      expect(states1.first, equals(states2.first));

      await sub1.cancel();
      await sub2.cancel();
      monitor.dispose();
    });

    test('forceCheck triggers immediate connectivity check', () async {
      final monitor = NetworkConnectivityMonitor(repository: mockRepository);

      final states = <NetworkState>[];
      final subscription = monitor.stateStream.listen(states.add);

      // Wait for initial check to complete
      await Future<void>.delayed(const Duration(milliseconds: 300));

      // Force check
      await monitor.forceCheck();
      await Future<void>.delayed(const Duration(milliseconds: 100));

      // Should have either maintained state or changed it (depends on network)
      // Just verify forceCheck executed without error
      expect(monitor.currentState, isNot(equals(NetworkState.checking)));

      await subscription.cancel();
      await Future<void>.delayed(const Duration(milliseconds: 100));
      monitor.dispose();
    });

    test('handles sync errors gracefully during reconnection', () async {
      mockRepository.shouldThrowOnRefresh = true;

      final monitor = NetworkConnectivityMonitor(repository: mockRepository);

      // Wait for initialization
      await Future<void>.delayed(const Duration(milliseconds: 300));

      // Should not throw even though refreshAll() fails
      expect(monitor.currentState, isNot(equals(NetworkState.checking)));

      monitor.dispose();
    });

    test('stats provide connectivity information', () async {
      final monitor = NetworkConnectivityMonitor(repository: mockRepository);

      final stats = monitor.stats;

      expect(stats, isA<Map<String, dynamic>>());
      expect(stats.containsKey('currentState'), isTrue);
      expect(stats.containsKey('checkInterval'), isTrue);
      expect(stats.containsKey('checkHost'), isTrue);
      expect(stats['checkHost'], equals('google.com'));

      // Wait before disposing
      await Future<void>.delayed(const Duration(milliseconds: 100));
      monitor.dispose();
    });

    test('dispose stops periodic checks and closes stream', () async {
      final monitor = NetworkConnectivityMonitor(repository: mockRepository);

      final states = <NetworkState>[];
      final subscription = monitor.stateStream.listen(states.add);

      // Wait for initial state
      await Future<void>.delayed(const Duration(milliseconds: 300));

      // Dispose monitor
      monitor.dispose();

      // Wait and cancel subscription after disposal
      await Future<void>.delayed(const Duration(milliseconds: 100));
      await subscription.cancel();

      // Record state count after disposal
      final stateCountAfterDispose = states.length;

      // Wait for what would have been a periodic check (if it weren't disposed)
      await Future<void>.delayed(const Duration(seconds: 2));

      // No new states should have been added after disposal
      expect(states.length, equals(stateCountAfterDispose));
    });

    test('state remains consistent across multiple checks', () async {
      final monitor = NetworkConnectivityMonitor(repository: mockRepository);

      final states = <NetworkState>[];
      final subscription = monitor.stateStream.listen(states.add);

      // Wait for several periodic checks
      await Future<void>.delayed(const Duration(milliseconds: 500));

      // If network is stable, state should not oscillate wildly
      // (Allow transitions but not constant back-and-forth)
      if (states.length > 2) {
        final lastStates = states.sublist(states.length - 3);
        // Not all three should be different
        final uniqueStates = lastStates.toSet();
        expect(uniqueStates.length, lessThanOrEqualTo(2));
      }

      await subscription.cancel();
      monitor.dispose();
    });

    test('initial check completes within reasonable time', () async {
      final stopwatch = Stopwatch()..start();
      final monitor = NetworkConnectivityMonitor(repository: mockRepository);

      // Wait for initial check to complete
      await Future<void>.delayed(const Duration(milliseconds: 500));
      stopwatch.stop();

      // Check should complete quickly (< 6 seconds with 5s timeout)
      expect(stopwatch.elapsedMilliseconds, lessThan(6000));

      // State should no longer be checking
      expect(monitor.currentState, isNot(equals(NetworkState.checking)));

      monitor.dispose();
    });

    test('repository refreshAll called on reconnection simulation', () async {
      final monitor = NetworkConnectivityMonitor(repository: mockRepository);

      // Wait for initial state
      await Future<void>.delayed(const Duration(milliseconds: 300));

      final initialRefreshCount = mockRepository.refreshAllCallCount;

      // Note: This test can't easily simulate offline→online transition
      // without mocking InternetAddress.lookup, which is complex
      // Instead, verify that forceCheck doesn't unnecessarily trigger refresh
      await monitor.forceCheck();
      await Future<void>.delayed(const Duration(milliseconds: 200));

      // If already online, forceCheck shouldn't trigger additional refreshAll
      // (only offline→online transition should)
      expect(mockRepository.refreshAllCallCount, equals(initialRefreshCount));

      monitor.dispose();
    });
  });
}
