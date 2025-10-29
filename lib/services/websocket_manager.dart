import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:my_app_gps/core/services/connection_notification_service.dart';
import 'package:my_app_gps/core/utils/app_logger.dart';
import 'package:my_app_gps/core/network/reconnection_coordinator.dart';
import 'package:my_app_gps/features/map/data/position_model.dart';
import 'package:my_app_gps/services/traccar_socket_service.dart';

enum WebSocketStatus { connecting, connected, disconnected, retrying }

class WebSocketState {
  final WebSocketStatus status;
  final int retryCount;
  final String? error;
  final DateTime? lastConnected;
  final DateTime? lastEventAt; // Track last message received

  const WebSocketState({
    required this.status,
    this.retryCount = 0,
    this.error,
    this.lastConnected,
    this.lastEventAt,
  });

  WebSocketState copyWith({
    WebSocketStatus? status,
    int? retryCount,
    String? error,
    DateTime? lastConnected,
    DateTime? lastEventAt,
  }) {
    return WebSocketState(
      status: status ?? this.status,
      retryCount: retryCount ?? this.retryCount,
      error: error,
      lastConnected: lastConnected ?? this.lastConnected,
      lastEventAt: lastEventAt ?? this.lastEventAt,
    );
  }

  /// Check if WebSocket has been silent for too long
  bool isSilent(Duration threshold) {
    if (lastEventAt == null) return true;
    return DateTime.now().difference(lastEventAt!) > threshold;
  }
}

/// WebSocket Manager with Traccar authentication and automatic reconnection
/// Wraps TraccarSocketService with lifecycle management and enhanced monitoring
class WebSocketManager extends Notifier<WebSocketState> {
  static final _log = 'WebSocket'.logger;
  
  // Centralized reconnection coordinator
  final ReconnectionCoordinator _coordinator = ReconnectionCoordinator.instance;
  
  // Toggle to enable very verbose heartbeat logs
  static bool verboseSocketLogs = false;

  // Test-mode toggle: when true, do not auto-connect or schedule timers
  // Set from tests: WebSocketManagerEnhanced.testMode = true;
  static bool testMode = false;

  StreamSubscription<TraccarSocketMessage>? _socketSub;
  Timer? _reconnectTimer;
  int _retryCount = 0;
  bool _disposed = false;
  bool _intentionalDisconnect = false;
  DateTime? _lastSuccessfulConnect;
  DateTime? _lastEventAt;
  bool _socketAvailable = true;
  DateTime? _lastResumeTime; // Track last resume call for debouncing

  late final TraccarSocketService _socketService;

  // Callback for when position data is received
  final void Function(Position)? onPosition;

  WebSocketManager({this.onPosition});

  /// Getter for last event timestamp
  DateTime? get lastEventAt => _lastEventAt;

  bool get isConnected => state.status == WebSocketStatus.connected;
  bool get isDisconnected => state.status == WebSocketStatus.disconnected;

  @override
  WebSocketState build() {
    // Get dependencies from Riverpod
    try {
      _socketService = ref.watch(traccarSocketServiceProvider);
      _socketAvailable = true;
    } catch (_) {
      // In tests, provider may be overridden with a throwing mock. Avoid connecting.
      _socketAvailable = false;
    }

    // Configure coordinator connector once
    _coordinator.setConnector(_connectOnce);

    // Defer connection to after build completes to avoid reading uninitialized providers
    if (!testMode && _socketAvailable) {
      Future.microtask(() {
        if (!_disposed && !_intentionalDisconnect) {
          // Kick off centralized reconnection flow
          unawaited(_coordinator.trigger('init'));
        }
      });
    } else {
      _log.debug('[TEST] Skipping auto-connect');
    }

    ref.onDispose(_dispose);
    ref.keepAlive();

    return const WebSocketState(status: WebSocketStatus.connecting);
  }

  /// Single connection attempt used by ReconnectionCoordinator.
  /// Returns true if connected successfully, false otherwise.
  Future<bool> _connectOnce() async {
    if (_disposed || _intentionalDisconnect) return false;
    if (testMode) return false;
    if (!_socketAvailable) {
      _log.warning('Socket provider unavailable; skipping connect');
      return false;
    }

    state = state.copyWith(status: WebSocketStatus.connecting);
    _log.debug('Connecting... (attempt ${_retryCount + 1})');

    try {
      // Cancel existing subscription if any
      await _socketSub?.cancel();

      // Connect to Traccar WebSocket (handles authentication internally)
      _socketSub = _socketService.connect().listen(
        _handleSocketMessage,
        onError: (Object error) {
          _log.error('Socket error', error: error);
          
          // 🔔 Show connection lost notification
          unawaited(
            ConnectionNotificationService.instance.showDisconnected(),
          );
          
          // Delegate to coordinator (no local timers)
          unawaited(_coordinator.trigger('error:$error'));
        },
        onDone: () {
          if (!_disposed && !_intentionalDisconnect) {
            _log.warning('Connection closed by server');
            
            // 🔔 Show connection lost notification
            unawaited(
              ConnectionNotificationService.instance.showDisconnected(),
            );
            
            unawaited(_coordinator.trigger('onDone'));
          }
        },
        
      );

      _retryCount = 0;
      _lastSuccessfulConnect = DateTime.now();
      _lastEventAt = DateTime.now();

      state = state.copyWith(
        status: WebSocketStatus.connected,
        retryCount: 0,
        lastConnected: _lastSuccessfulConnect,
        lastEventAt: _lastEventAt,
      );

      _log.info('✅ Connected successfully');
      
      // 🔔 Show connection restored notification
      unawaited(
        ConnectionNotificationService.instance.showReconnected(),
      );
      
      return true;
    } catch (e) {
      _log.error('Connection failed', error: e);
      // Do not schedule locally; return false to let coordinator back off
      return false;
    }
  }

  /// Handle incoming WebSocket messages
  void _handleSocketMessage(TraccarSocketMessage msg) {
    if (_disposed) return;

    // Update last event timestamp
    _lastEventAt = DateTime.now();
    state = state.copyWith(lastEventAt: _lastEventAt);

    if (msg.type == 'positions' && msg.positions != null) {
      _log.info('📍 Received ${msg.positions!.length} position(s)');

      // Forward positions to callback
      if (onPosition != null) {
        for (final pos in msg.positions!) {
          onPosition!(pos);
        }
      }
      
      // 🔔 Optional: Show data sync notification for first position update
      // This is throttled internally to avoid spam
      if (msg.positions!.isNotEmpty) {
        unawaited(
          ConnectionNotificationService.instance.showDataSynced(
            deviceCount: msg.positions!.length,
          ),
        );
      }
    } else if (msg.type == 'connected') {
      _log.debug('Connection confirmed');
    } else if (verboseSocketLogs) {
      _log.debug('Pong');
    }
  }

  // Local scheduling removed in favor of ReconnectionCoordinator

  /// Manually trigger reconnection (call when app resumes or map page opens)
  Future<void> forceReconnect() async {
    _log.info('🔄 Force reconnect requested');
    _intentionalDisconnect = false;
    _retryCount = 0;

    if (isConnected) {
      _log.debug('Already connected, skipping');
      return;
    }
    await _coordinator.trigger('force');
  }

  /// Suspend connection (call when app goes to background)
  void suspend() {
    _log.debug('⏸️ Suspending connection');
    _intentionalDisconnect = true;
    _socketSub?.cancel();
    _socketSub = null;
    state = state.copyWith(status: WebSocketStatus.disconnected);
  }

  /// Resume connection (call when app comes to foreground)
  Future<void> resume() async {
    // Debounce: prevent redundant resume calls within 300ms
    final now = DateTime.now();
    if (_lastResumeTime != null) {
      final timeSinceLastResume = now.difference(_lastResumeTime!);
      if (timeSinceLastResume < const Duration(milliseconds: 300)) {
        _log.debug('⏭️ Resume debounced (${timeSinceLastResume.inMilliseconds}ms since last call)');
        return;
      }
    }
    _lastResumeTime = now;

    _log.debug('▶️ Resuming connection');
    _intentionalDisconnect = false;

    if (!isConnected) {
      await _coordinator.trigger('resume');
    } else {
      _log.debug('Already connected');
    }
  }

  /// Check connection health and reconnect if needed
  void checkHealth() {
    if (_disposed || _intentionalDisconnect) return;

    if (!isConnected) {
      _log.warning('🏥 Health check: reconnecting...');
      forceReconnect();
    } else if (_lastSuccessfulConnect != null) {
      final timeSinceConnect =
          DateTime.now().difference(_lastSuccessfulConnect!);
      final timeSinceEvent = _lastEventAt != null
          ? DateTime.now().difference(_lastEventAt!)
          : Duration.zero;

      if (timeSinceConnect > const Duration(minutes: 5) &&
          timeSinceEvent > const Duration(minutes: 2)) {
        _log.warning('🏥 Health check: no activity detected, reconnecting...');
        forceReconnect();
      }
    }
  }

  void _dispose() {
    _disposed = true;
    _intentionalDisconnect = true;
    _reconnectTimer?.cancel();
    _socketSub?.cancel();
    _log.debug('🗑️ Disposed');
  }

  /// 🎯 PHASE 2: Check if REST fallback should be suppressed
  /// Returns true if WebSocket reconnected successfully within 3 seconds
  bool shouldSuppressFallback() {
    if (_lastSuccessfulConnect == null) return false;
    
    final timeSinceReconnect = DateTime.now().difference(_lastSuccessfulConnect!);
    const suppressionWindow = Duration(seconds: 3);
    final shouldSuppress = timeSinceReconnect < suppressionWindow;
    
    if (shouldSuppress) {
      _log.debug('✋ Suppressing REST fallback (reconnected ${timeSinceReconnect.inMilliseconds}ms ago)');
    }
    
    return shouldSuppress;
  }

  /// 🎯 PHASE 2: Get connection stability metrics
  Map<String, dynamic> getConnectionMetrics() {
    return {
      'retryCount': _retryCount,
      'isConnected': isConnected,
      'lastSuccessfulConnect': _lastSuccessfulConnect?.toIso8601String(),
      'timeSinceLastSuccess': _lastSuccessfulConnect != null
          ? DateTime.now().difference(_lastSuccessfulConnect!).inSeconds
          : null,
      'lastEventAt': _lastEventAt?.toIso8601String(),
      'timeSinceLastEvent': _lastEventAt != null
          ? DateTime.now().difference(_lastEventAt!).inSeconds
          : null,
    };
  }
}

/// Provider for the WebSocket manager
final webSocketManagerProvider =
    NotifierProvider<WebSocketManager, WebSocketState>(
        WebSocketManager.new,);
