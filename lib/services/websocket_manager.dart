import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:my_app_gps/core/utils/app_logger.dart';
import 'package:my_app_gps/core/utils/backoff_manager.dart';
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
  
  // 🎯 PHASE 9: Use BackoffManager for exponential reconnection delays
  final _backoff = BackoffManager(
    initialDelay: const Duration(seconds: 1),
    maxDelay: const Duration(seconds: 60),
  );
  
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

    // Defer connection to after build completes to avoid reading uninitialized providers
    if (!testMode && _socketAvailable) {
      Future.microtask(() {
        if (!_disposed && !_intentionalDisconnect) {
          _connect();
        }
      });
    } else {
      _log.debug('[TEST] Skipping auto-connect');
    }

    ref.onDispose(_dispose);
    ref.keepAlive();

    return const WebSocketState(status: WebSocketStatus.connecting);
  }

  /// Connect or reconnect to WebSocket
  Future<void> _connect() async {
    if (_disposed || _intentionalDisconnect) return;
    if (testMode) return;
    if (!_socketAvailable) {
      _log.warning('Socket provider unavailable; skipping connect');
      return;
    }

    // Cancel any pending reconnect timer
    _reconnectTimer?.cancel();

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
          _scheduleReconnect(error.toString());
        },
        onDone: () {
          if (!_disposed && !_intentionalDisconnect) {
            _log.warning('Connection closed by server');
            _scheduleReconnect('Connection closed');
          }
        },
        cancelOnError: false,
      );

      _retryCount = 0;
      _lastSuccessfulConnect = DateTime.now();
      _lastEventAt = DateTime.now();
      
      // 🎯 PHASE 9: Reset backoff on successful connection
      _backoff.reset();

      state = state.copyWith(
        status: WebSocketStatus.connected,
        retryCount: 0,
        lastConnected: _lastSuccessfulConnect,
        lastEventAt: _lastEventAt,
      );

      _log.info('✅ Connected successfully');
    } catch (e) {
      _log.error('Connection failed', error: e);
      _scheduleReconnect(e.toString());
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
    } else if (msg.type == 'connected') {
      _log.debug('Connection confirmed');
    } else if (verboseSocketLogs) {
      _log.debug('Pong');
    }
  }

  /// Schedule reconnection with exponential backoff
  void _scheduleReconnect(String error) {
    if (_disposed || _intentionalDisconnect) return;
    if (testMode) return;
    if (!_socketAvailable) return;

    _retryCount++;

    state = state.copyWith(
      status: WebSocketStatus.retrying,
      retryCount: _retryCount,
      error: error,
    );

    // 🎯 PHASE 9: Use BackoffManager for exponential delay
    final delay = _backoff.nextDelay();
    _log.warning('⏳ Retry #$_retryCount in ${delay.inSeconds}s', error: error);

    _reconnectTimer = Timer(delay, () {
      if (!_disposed && !_intentionalDisconnect) {
        _connect();
      }
    });
  }

  /// Manually trigger reconnection (call when app resumes or map page opens)
  Future<void> forceReconnect() async {
    _log.info('🔄 Force reconnect requested');
    _intentionalDisconnect = false;
    _retryCount = 0;
    _reconnectTimer?.cancel();
    
    // 🎯 PHASE 9: Reset backoff on manual reconnect
    _backoff.reset();

    if (isConnected) {
      _log.debug('Already connected, skipping');
      return;
    }

    await _connect();
  }

  /// Suspend connection (call when app goes to background)
  void suspend() {
    _log.debug('⏸️ Suspending connection');
    _intentionalDisconnect = true;
    _reconnectTimer?.cancel();
    _socketSub?.cancel();
    _socketSub = null;
    state = state.copyWith(status: WebSocketStatus.disconnected);
  }

  /// Resume connection (call when app comes to foreground)
  Future<void> resume() async {
    _log.debug('▶️ Resuming connection');
    _intentionalDisconnect = false;

    if (!isConnected) {
      await forceReconnect();
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
