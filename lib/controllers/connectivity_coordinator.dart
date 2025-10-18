import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:connectivity_plus/connectivity_plus.dart';

/// Unified connectivity state combining network and backend reachability
///
/// Provides a single source of truth for app-wide offline/online status
/// that considers both device network connectivity AND Traccar backend availability.
@immutable
class ConnectivityState {
  /// Device has network connectivity (Wi-Fi, mobile, ethernet)
  final bool networkAvailable;

  /// Traccar backend is reachable via WebSocket or REST
  final bool backendReachable;

  /// Timestamp of last successful backend ping
  final DateTime? lastBackendPing;

  /// Number of consecutive successful pings
  final int consecutiveSuccessfulPings;

  /// Number of consecutive failed pings
  final int consecutiveFailedPings;

  const ConnectivityState({
    required this.networkAvailable,
    required this.backendReachable,
    this.lastBackendPing,
    this.consecutiveSuccessfulPings = 0,
    this.consecutiveFailedPings = 0,
  });

  /// App is effectively offline (no network OR backend unreachable)
  bool get isOffline => !networkAvailable || !backendReachable;

  /// App is fully online (both network and backend available)
  bool get isOnline => networkAvailable && backendReachable;

  /// Network exists but backend is down
  bool get hasNetworkButNoBackend => networkAvailable && !backendReachable;

  /// Duration since last successful backend ping
  Duration? get timeSinceLastPing =>
      lastBackendPing != null ? DateTime.now().difference(lastBackendPing!) : null;

  ConnectivityState copyWith({
    bool? networkAvailable,
    bool? backendReachable,
    DateTime? lastBackendPing,
    int? consecutiveSuccessfulPings,
    int? consecutiveFailedPings,
  }) {
    return ConnectivityState(
      networkAvailable: networkAvailable ?? this.networkAvailable,
      backendReachable: backendReachable ?? this.backendReachable,
      lastBackendPing: lastBackendPing ?? this.lastBackendPing,
      consecutiveSuccessfulPings:
          consecutiveSuccessfulPings ?? this.consecutiveSuccessfulPings,
      consecutiveFailedPings:
          consecutiveFailedPings ?? this.consecutiveFailedPings,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ConnectivityState &&
          networkAvailable == other.networkAvailable &&
          backendReachable == other.backendReachable;

  @override
  int get hashCode => Object.hash(networkAvailable, backendReachable);

  @override
  String toString() {
    final status = isOnline
        ? 'ONLINE'
        : hasNetworkButNoBackend
            ? 'NETWORK_ONLY'
            : 'OFFLINE';
    return 'ConnectivityState($status, net=$networkAvailable, backend=$backendReachable, '
        'successPings=$consecutiveSuccessfulPings, failedPings=$consecutiveFailedPings)';
  }
}

/// Coordinator managing unified connectivity state
///
/// Responsibilities:
/// - Monitor device network via connectivity_plus
/// - Monitor backend reachability via periodic pings
/// - Merge into unified ConnectivityState
/// - Control FMTC caching mode (online vs hit-only)
/// - Trigger map rebuilds on reconnect
///
/// Usage:
/// ```dart
/// final coordinator = ConnectivityCoordinator(
///   onBackendPing: () async => await checkBackendHealth(),
/// );
/// await coordinator.initialize();
/// coordinator.stateStream.listen((state) {
///   print('Connectivity: ${state.isOnline ? "ONLINE" : "OFFLINE"}');
/// });
/// ```
class ConnectivityCoordinator {
  /// Callback to check backend reachability
  /// Should return true if backend is responsive, false otherwise
  final Future<bool> Function() onBackendPing;

  /// Interval for periodic backend reachability checks
  final Duration pingInterval;

  /// Interval for more aggressive pings when backend is down
  final Duration offlinePingInterval;

  final _connectivity = Connectivity();
  final _stateController = StreamController<ConnectivityState>.broadcast();

  ConnectivityState _currentState = const ConnectivityState(
    networkAvailable: true,
    backendReachable: true,
  );

  StreamSubscription<List<ConnectivityResult>>? _networkSub;
  Timer? _pingTimer;
  bool _isDisposed = false;

  ConnectivityCoordinator({
    required this.onBackendPing,
    this.pingInterval = const Duration(seconds: 30),
    this.offlinePingInterval = const Duration(seconds: 10),
  });

  /// Current connectivity state
  ConnectivityState get state => _currentState;

  /// Stream of connectivity state changes
  Stream<ConnectivityState> get stateStream => _stateController.stream;

  /// Initialize coordinator and start monitoring
  Future<void> initialize() async {
    if (kDebugMode) {
      debugPrint('[CONNECTIVITY] 🎬 Initializing coordinator');
    }

    // Check initial network state
    final initialResults = await _connectivity.checkConnectivity();
    _updateNetworkState(initialResults);

    // Check initial backend state
    await _checkBackendReachability();

    // Subscribe to network changes
    _networkSub = _connectivity.onConnectivityChanged.listen(_updateNetworkState);

    // Start periodic backend pings
    _schedulePing();

    if (kDebugMode) {
      debugPrint('[CONNECTIVITY] ✅ Initialized: $_currentState');
    }
  }

  void _updateNetworkState(List<ConnectivityResult> results) {
    final hasNetwork = results.any(
      (r) =>
          r == ConnectivityResult.wifi ||
          r == ConnectivityResult.mobile ||
          r == ConnectivityResult.ethernet,
    );

    if (hasNetwork != _currentState.networkAvailable) {
      if (kDebugMode) {
        debugPrint(
          '[CONNECTIVITY] 📡 Network changed: ${_currentState.networkAvailable} → $hasNetwork',
        );
      }

      _currentState = _currentState.copyWith(networkAvailable: hasNetwork);
      _notifyStateChange();

      // If network came back, immediately check backend
      if (hasNetwork) {
        _checkBackendReachability();
      }
    }
  }

  Future<void> _checkBackendReachability() async {
    if (_isDisposed) return;

    final wasReachable = _currentState.backendReachable;
    bool isReachable = false;

    try {
      isReachable = await onBackendPing();
    } catch (e) {
      if (kDebugMode) {
        debugPrint('[CONNECTIVITY] ⚠️ Backend ping error: $e');
      }
    }

    if (_isDisposed) return;

    final now = DateTime.now();
    final newState = _currentState.copyWith(
      backendReachable: isReachable,
      lastBackendPing: isReachable ? now : _currentState.lastBackendPing,
      consecutiveSuccessfulPings:
          isReachable ? _currentState.consecutiveSuccessfulPings + 1 : 0,
      consecutiveFailedPings:
          isReachable ? 0 : _currentState.consecutiveFailedPings + 1,
    );

    if (wasReachable != isReachable) {
      if (kDebugMode) {
        debugPrint(
          '[CONNECTIVITY] 🔌 Backend changed: $wasReachable → $isReachable '
          '(success=${newState.consecutiveSuccessfulPings}, failed=${newState.consecutiveFailedPings})',
        );
      }
    }

    _currentState = newState;
    _notifyStateChange();

    // Reschedule with appropriate interval
    _schedulePing();
  }

  void _schedulePing() {
    _pingTimer?.cancel();

    if (_isDisposed) return;

    // Use aggressive interval when offline, normal when online
    final interval =
        _currentState.isOffline ? offlinePingInterval : pingInterval;

    _pingTimer = Timer(interval, _checkBackendReachability);
  }

  void _notifyStateChange() {
    _stateController.add(_currentState);
  }

  /// Force immediate backend reachability check
  Future<void> forceCheck() async {
    if (kDebugMode) {
      debugPrint('[CONNECTIVITY] 🔄 Force reachability check requested');
    }
    await _checkBackendReachability();
  }

  /// Dispose coordinator and release resources
  void dispose() {
    if (kDebugMode) {
      debugPrint('[CONNECTIVITY] 🗑️ Disposing coordinator');
    }
    _isDisposed = true;
    _networkSub?.cancel();
    _pingTimer?.cancel();
    _stateController.close();
  }
}
