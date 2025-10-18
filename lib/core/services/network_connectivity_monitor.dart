import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:my_app_gps/core/data/vehicle_data_repository.dart';

/// Provider for network connectivity monitor
final networkConnectivityProvider = Provider<NetworkConnectivityMonitor>((ref) {
  final repository = ref.watch(vehicleDataRepositoryProvider);

  final monitor = NetworkConnectivityMonitor(repository: repository);
  ref.onDispose(monitor.dispose);

  return monitor;
});

/// Network state for UI feedback
enum NetworkState {
  online,
  offline,
  checking,
}

/// Provider for network state (for UI consumption)
final networkStateProvider =
    StateNotifierProvider<NetworkStateNotifier, NetworkState>((ref) {
  final monitor = ref.watch(networkConnectivityProvider);
  return NetworkStateNotifier(monitor);
});

class NetworkStateNotifier extends StateNotifier<NetworkState> {
  NetworkStateNotifier(this.monitor) : super(NetworkState.checking) {
    // Subscribe to network state changes
    _subscription = monitor.stateStream.listen((newState) {
      state = newState;
    });
  }

  final NetworkConnectivityMonitor monitor;
  StreamSubscription<NetworkState>? _subscription;

  @override
  void dispose() {
    _subscription?.cancel();
    super.dispose();
  }
}

/// Monitors network connectivity and triggers repository sync on reconnection
///
/// Features:
/// - Periodic network checks using simple HTTP HEAD request
/// - Detects offline → online transitions
/// - Triggers repository.refreshAll() when network restored
/// - Broadcasts network state via networkStateProvider
///
/// Note: For production, consider using connectivity_plus package for better
/// network type detection (WiFi, cellular, etc.) and battery efficiency
class NetworkConnectivityMonitor {
  NetworkConnectivityMonitor({required this.repository}) {
    _init();
  }

  final VehicleDataRepository repository;

  Timer? _checkTimer;
  NetworkState _currentState = NetworkState.checking;
  final _stateController = StreamController<NetworkState>.broadcast();

  // Configuration
  static const _checkInterval = Duration(seconds: 15);
  static const _checkTimeout = Duration(seconds: 5);
  static const _checkHost = 'google.com'; // Reliable check host

  // Test-mode toggle: when true, skip creating timers/network checks in tests
  // Set from test setup: NetworkConnectivityMonitor.testMode = true;
  static bool testMode = false;

  Stream<NetworkState> get stateStream => _stateController.stream;
  NetworkState get currentState => _currentState;

  void _init() {
    if (kDebugMode) {
      debugPrint('[NetworkMonitor] Initialized');
    }

    if (!testMode) {
      // Perform initial check
      _checkConnectivity();

      // Start periodic checks
      _startPeriodicChecks();
    } else {
      if (kDebugMode) {
        debugPrint('[NetworkMonitor][TEST] Skipping connectivity timers');
      }
    }
  }

  /// Start periodic network connectivity checks
  void _startPeriodicChecks() {
    _checkTimer?.cancel();
    _checkTimer = Timer.periodic(_checkInterval, (_) {
      _checkConnectivity();
    });
  }

  /// Check network connectivity using simple socket connection
  Future<void> _checkConnectivity() async {
    try {
      // Simple connectivity check: try to connect to reliable host
      final result =
          await InternetAddress.lookup(_checkHost).timeout(_checkTimeout);

      if (result.isNotEmpty && result[0].rawAddress.isNotEmpty) {
        _handleConnected();
      } else {
        _handleDisconnected();
      }
    } on SocketException catch (_) {
      // Network unreachable
      _handleDisconnected();
    } on TimeoutException catch (_) {
      // Connection timeout
      _handleDisconnected();
    } catch (e) {
      if (kDebugMode) {
        debugPrint('[NetworkMonitor] Check error: $e');
      }
      // Assume disconnected on unknown errors
      _handleDisconnected();
    }
  }

  /// Handle connected state
  void _handleConnected() {
    if (_currentState == NetworkState.offline) {
      // Transition from offline to online - trigger sync
      if (kDebugMode) {
        debugPrint(
            '[NetworkMonitor] ✅ Network restored - triggering data sync',);
      }

      _syncAfterReconnection();
    }

    _updateState(NetworkState.online);
  }

  /// Handle disconnected state
  void _handleDisconnected() {
    if (_currentState == NetworkState.online) {
      if (kDebugMode) {
        debugPrint('[NetworkMonitor] ⚠️ Network lost');
      }
    }

    _updateState(NetworkState.offline);
  }

  /// Update network state and broadcast
  void _updateState(NetworkState newState) {
    if (_currentState != newState) {
      _currentState = newState;
      _stateController.add(newState);

      if (kDebugMode) {
        debugPrint('[NetworkMonitor] Network state: $newState');
      }
    }
  }

  /// Sync data after network reconnection
  Future<void> _syncAfterReconnection() async {
    try {
      // Wait a bit for network to stabilize
      await Future<void>.delayed(const Duration(seconds: 2));

      // Trigger full refresh
      await repository.refreshAll();

      if (kDebugMode) {
        debugPrint('[NetworkMonitor] ✅ Data sync after reconnection complete');
      }
    } catch (e) {
      if (kDebugMode) {
        debugPrint('[NetworkMonitor] Sync after reconnection failed: $e');
      }
    }
  }

  /// Manually trigger connectivity check (called by UI)
  Future<void> forceCheck() async {
    if (kDebugMode) {
      debugPrint('[NetworkMonitor] Force check requested');
    }
    await _checkConnectivity();
  }

  /// Get connectivity statistics
  Map<String, dynamic> get stats => {
        'currentState': _currentState.toString(),
        'checkInterval': _checkInterval.inSeconds,
        'checkHost': _checkHost,
      };

  /// Dispose resources
  void dispose() {
    _checkTimer?.cancel();
    _stateController.close();

    if (kDebugMode) {
      debugPrint('[NetworkMonitor] Disposed');
    }
  }
}

/* 
 * PRODUCTION UPGRADE PATH:
 * 
 * For better network detection, add connectivity_plus to pubspec.yaml:
 * 
 * dependencies:
 *   connectivity_plus: ^6.0.0
 * 
 * Then replace InternetAddress.lookup with:
 * 
 * import 'package:connectivity_plus/connectivity_plus.dart';
 * 
 * final connectivity = Connectivity();
 * final result = await connectivity.checkConnectivity();
 * 
 * Benefits:
 * - Detect network type (WiFi, cellular, ethernet)
 * - More battery efficient (no periodic polling)
 * - Instant notification on network changes
 * - Works on all platforms (mobile, web, desktop)
 */
