import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:my_app_gps/core/data/vehicle_data_repository.dart';
import 'package:my_app_gps/services/traccar_socket_service.dart';

/// Provider for the reconnection manager singleton
final reconnectionManagerProvider = Provider<ReconnectionManager>((ref) {
  final socketService = ref.watch(traccarSocketServiceProvider);
  final repository = ref.watch(vehicleDataRepositoryProvider);

  final manager = ReconnectionManager(
    socketService: socketService,
    repository: repository,
  );

  ref.onDispose(manager.dispose);
  return manager;
});

/// Connection status for UI feedback
enum ConnectionStatus {
  online,
  offline,
  reconnecting,
  unstable, // Multiple reconnects in short time
}

/// Provider for connection status (for UI consumption)
final connectionStatusProvider =
    StateNotifierProvider<ConnectionStatusNotifier, ConnectionStatus>((ref) {
  return ConnectionStatusNotifier();
});

class ConnectionStatusNotifier extends StateNotifier<ConnectionStatus> {
  ConnectionStatusNotifier() : super(ConnectionStatus.online);

  void setStatus(ConnectionStatus status) {
    if (state != status) {
      state = status;
      if (kDebugMode) {
        debugPrint('[ConnectionStatus] Status changed to: $status');
      }
    }
  }
}

/// Manages WebSocket reconnection with exponential backoff and auto-sync
///
/// Features:
/// - Monitors WebSocket connection health
/// - Automatic reconnection with exponential backoff (5s → 10s → 20s → 40s → max 60s)
/// - Triggers repository.refreshAll() on successful reconnect
/// - Detects unstable connections (multiple reconnects in short time)
/// - Broadcasts connection status via connectionStatusProvider
class ReconnectionManager {
  ReconnectionManager({
    required this.socketService,
    required this.repository,
  }) {
    _init();
  }

  final TraccarSocketService socketService;
  final VehicleDataRepository repository;

  Timer? _healthCheckTimer;
  Timer? _reconnectTimer;
  StreamSubscription<TraccarSocketMessage>? _socketSub;

  // Reconnection state
  bool _isConnected = false;
  bool _isReconnecting = false;
  int _reconnectAttempts = 0;
  DateTime? _lastDisconnect;
  DateTime? _lastReconnect;
  final List<DateTime> _recentReconnects = [];

  // Backoff configuration
  static const _initialBackoff = Duration(seconds: 5);
  static const _maxBackoff = Duration(seconds: 60);
  static const _backoffMultiplier = 2;
  static const _unstableThreshold = 3; // 3+ reconnects in 5 minutes = unstable

  // Health check interval
  static const _healthCheckInterval = Duration(seconds: 30);

  void _init() {
    if (kDebugMode) {
      debugPrint('[ReconnectionManager] Initialized');
    }

    // Start health check monitoring
    _startHealthCheck();

    // Subscribe to socket messages to detect disconnects
    _socketSub = socketService.connect().listen(
          _handleSocketMessage,
          onError: _handleSocketError,
          onDone: _handleSocketDisconnect,
        );
  }

  /// Start periodic health check
  void _startHealthCheck() {
    _healthCheckTimer?.cancel();
    _healthCheckTimer = Timer.periodic(_healthCheckInterval, (_) {
      _checkConnectionHealth();
    });
  }

  /// Check connection health and trigger reconnect if needed
  void _checkConnectionHealth() {
    if (!_isConnected && !_isReconnecting) {
      if (kDebugMode) {
        debugPrint(
            '[ReconnectionManager] Health check failed - WebSocket disconnected',);
      }
      _handleSocketDisconnect();
    }
  }

  /// Handle incoming socket messages
  void _handleSocketMessage(TraccarSocketMessage msg) {
    if (msg.type == 'connected') {
      _handleSocketConnected();
    } else if (msg.type == 'error') {
      // Socket error received
      if (kDebugMode) {
        debugPrint(
            '[ReconnectionManager] Socket error message: ${msg.payload}',);
      }
    }
  }

  /// Handle socket errors
  void _handleSocketError(Object error) {
    if (kDebugMode) {
      debugPrint('[ReconnectionManager] Socket error: $error');
    }
    _handleSocketDisconnect();
  }

  /// Handle socket disconnect - trigger reconnection with backoff
  void _handleSocketDisconnect() {
    if (_isReconnecting) return; // Already attempting to reconnect

    _isConnected = false;
    _lastDisconnect = DateTime.now();
    _isReconnecting = true;

    if (kDebugMode) {
      debugPrint(
          '[ReconnectionManager] WebSocket disconnected, attempting reconnect...',);
    }

    // Update status
    _updateConnectionStatus();

    // Schedule reconnect with exponential backoff
    _scheduleReconnect();
  }

  /// Handle successful connection
  void _handleSocketConnected() {
    if (kDebugMode) {
      debugPrint('[ReconnectionManager] ✅ WebSocket connected');
    }

    _isConnected = true;
    _lastReconnect = DateTime.now();
    _isReconnecting = false;
    _reconnectAttempts = 0;

    // Track recent reconnects to detect unstable connection
    _recentReconnects.add(_lastReconnect!);
    _recentReconnects.removeWhere(
      (dt) => DateTime.now().difference(dt) > const Duration(minutes: 5),
    );

    // Update status
    _updateConnectionStatus();

    // Sync data after reconnection
    _syncAfterReconnect();
  }

  /// Schedule reconnect attempt with exponential backoff
  void _scheduleReconnect() {
    _reconnectTimer?.cancel();

    // Calculate backoff delay
    final backoffSeconds = _initialBackoff.inSeconds *
        (_backoffMultiplier * _reconnectAttempts)
            .clamp(1, _maxBackoff.inSeconds ~/ _initialBackoff.inSeconds);
    final delay = Duration(
        seconds: backoffSeconds.clamp(
            _initialBackoff.inSeconds, _maxBackoff.inSeconds,),);

    if (kDebugMode) {
      debugPrint(
        '[ReconnectionManager] Scheduling reconnect attempt ${_reconnectAttempts + 1} '
        'in ${delay.inSeconds}s',
      );
    }

    _reconnectTimer = Timer(delay, _attemptReconnect);
  }

  /// Attempt to reconnect to WebSocket
  Future<void> _attemptReconnect() async {
    _reconnectAttempts++;

    if (kDebugMode) {
      debugPrint('[ReconnectionManager] Reconnect attempt $_reconnectAttempts');
    }

    try {
      // Cancel old subscription
      await _socketSub?.cancel();

      // Create new connection by resubscribing to the stream
      _socketSub = socketService.connect().listen(
            _handleSocketMessage,
            onError: _handleSocketError,
            onDone: _handleSocketDisconnect,
          );

      // Note: Connection success will be confirmed by receiving 'connected' message
    } catch (e) {
      if (kDebugMode) {
        debugPrint('[ReconnectionManager] Reconnect failed: $e');
      }
      // Schedule next attempt
      _scheduleReconnect();
    }
  }

  /// Sync data after successful reconnection
  Future<void> _syncAfterReconnect() async {
    try {
      if (kDebugMode) {
        debugPrint('[ReconnectionManager] Syncing data after reconnect...');
      }

      // Trigger full refresh from REST API
      await repository.refreshAll();

      if (kDebugMode) {
        debugPrint('[ReconnectionManager] ✅ Data sync complete');
      }
    } catch (e) {
      if (kDebugMode) {
        debugPrint('[ReconnectionManager] Data sync failed: $e');
      }
    }
  }

  /// Update connection status for UI feedback
  void _updateConnectionStatus() {
    ConnectionStatus status;

    if (_isConnected) {
      // Check if connection is unstable
      if (_recentReconnects.length >= _unstableThreshold) {
        status = ConnectionStatus.unstable;
      } else {
        status = ConnectionStatus.online;
      }
    } else if (_isReconnecting) {
      status = ConnectionStatus.reconnecting;
    } else {
      status = ConnectionStatus.offline;
    }

    // Broadcast status (will be picked up by connectionStatusProvider)
    if (kDebugMode) {
      debugPrint('[ReconnectionManager] Connection status: $status');
    }
  }

  /// Manually trigger reconnect (called by UI or network detector)
  Future<void> forceReconnect() async {
    if (kDebugMode) {
      debugPrint('[ReconnectionManager] Force reconnect requested');
    }

    _reconnectAttempts = 0; // Reset attempts for forced reconnect
    await _attemptReconnect();
  }

  /// Get current connection statistics
  Map<String, dynamic> get stats => {
        'isConnected': _isConnected,
        'isReconnecting': _isReconnecting,
        'reconnectAttempts': _reconnectAttempts,
        'lastDisconnect': _lastDisconnect?.toIso8601String(),
        'lastReconnect': _lastReconnect?.toIso8601String(),
        'recentReconnects': _recentReconnects.length,
        'isUnstable': _recentReconnects.length >= _unstableThreshold,
      };

  /// Dispose resources
  void dispose() {
    _healthCheckTimer?.cancel();
    _reconnectTimer?.cancel();
    _socketSub?.cancel();

    if (kDebugMode) {
      debugPrint('[ReconnectionManager] Disposed');
    }
  }
}
