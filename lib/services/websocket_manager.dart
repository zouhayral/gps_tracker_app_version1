import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:my_app_gps/core/lifecycle/stream_lifecycle_manager.dart';
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
  
  // 🧹 LIFECYCLE: Unified stream and timer manager
  final _lifecycle = StreamLifecycleManager(name: 'WebSocketManager');
  
  // 🎯 PHASE 9: Use BackoffManager for exponential reconnection delays
  final _backoff = BackoffManager();
  
  // Toggle to enable very verbose heartbeat logs
  static bool verboseSocketLogs = false;
  // Optional lightweight ping every [_pingEvery] (disabled on web servers that don't support it)
  bool _pingEnabled = true;
  Duration _pingEvery = const Duration(seconds: 30);

  // Test-mode toggle: when true, do not auto-connect or schedule timers
  // Set from tests: WebSocketManagerEnhanced.testMode = true;
  static bool testMode = false;

  StreamSubscription<TraccarSocketMessage>? _socketSub;
  Timer? _reconnectTimer;
  Timer? _healthTimer; // Periodic health monitor (single-shot rearm)
  int _retryCount = 0;
  bool _disposed = false;
  bool _intentionalDisconnect = false;
  DateTime? _lastSuccessfulConnect;
  DateTime? _lastEventAt;
  bool _socketAvailable = true;
  DateTime? _lastResumeTime; // Track last resume call for debouncing
  DateTime? _lastForceReconnectTime; // Debounce force reconnects
  bool _isConnecting = false; // Prevent overlapping connects
  DateTime? _lastPingAt; // Track last ping time for rate-limiting
  int _pingCount = 0; // Diagnostics: number of app-layer pings sent

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
          _startHealthMonitor();
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

    // Prevent overlapping connection attempts
    if (_isConnecting || state.status == WebSocketStatus.connecting) {
      _log.debug('Connect skipped: already connecting');
      return;
    }

    // Cancel any pending reconnect timer
    _reconnectTimer?.cancel();

    state = state.copyWith(status: WebSocketStatus.connecting);
    _log.debug('Connecting... (attempt ${_retryCount + 1})');

    try {
      _isConnecting = true;
      // Cancel existing subscription if any
      await _socketSub?.cancel();

      // Connect to Traccar WebSocket (handles authentication internally) - TRACKED
      _socketSub = _lifecycle.track(
        _socketService.connect().listen(
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
          
        ),
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
      // Ensure health monitor is running when connected
      _startHealthMonitor();
    } catch (e) {
      _log.error('Connection failed', error: e);
      _scheduleReconnect(e.toString());
    }
    finally {
      _isConnecting = false;
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

    _reconnectTimer = _lifecycle.trackTimer(
      Timer(delay, () {
        if (!_disposed && !_intentionalDisconnect) {
          _connect();
        }
      }),
    );
  }

  /// Manually trigger reconnection (call when app resumes or map page opens)
  Future<void> forceReconnect() async {
    _log.info('🔄 Force reconnect requested');
    _intentionalDisconnect = false;
    _retryCount = 0;
    _reconnectTimer?.cancel();
    
    // 🎯 PHASE 9: Reset backoff on manual reconnect
    _backoff.reset();

    // Debounce force reconnects to avoid "Already connected" spam
    final now = DateTime.now();
    if (_lastForceReconnectTime != null) {
      final since = now.difference(_lastForceReconnectTime!);
      if (since < const Duration(milliseconds: 500)) {
        _log.debug('⏭️ Force reconnect debounced (${since.inMilliseconds}ms)');
        return;
      }
    }
    _lastForceReconnectTime = now;

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

      // More proactive reconnection: if socket is connected but silent for >25s, reconnect.
      if (timeSinceEvent > const Duration(seconds: 25)) {
        _log.warning('🏥 Health check: silent for ${timeSinceEvent.inSeconds}s → reconnecting');
        forceReconnect();
        return;
      }

      // Legacy guard: long-lived connection with no activity
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
    
    // 🧹 LIFECYCLE: Dispose all tracked resources (_socketSub, _reconnectTimer)
    _lifecycle.disposeAll();
    _lifecycle.logStatus();
    _stopHealthMonitor();
    
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
      'pingEnabled': _pingEnabled,
      'pingEverySeconds': _pingEvery.inSeconds,
      'lastPingAt': _lastPingAt?.toIso8601String(),
      'pingCount': _pingCount,
    };
  }

  // ---- Health monitor & ping -------------------------------------------------
  void _startHealthMonitor() {
    if (_disposed || testMode) return;
    // Single-shot timer that re-arms itself every 10 seconds
    _healthTimer?.cancel();
    _healthTimer = _lifecycle.trackTimer(
      Timer(const Duration(seconds: 10), () {
        try {
          if (!_disposed && !_intentionalDisconnect) {
            // 1) Check liveness and reconnect on silence >25s (kept per requirement)
            checkHealth();
            // 2) Optional ping to keep connection healthy (esp. web where pingInterval isn't available)
            if (_pingEnabled && isConnected) {
              final now = DateTime.now();
              if (_lastPingAt == null || now.difference(_lastPingAt!) >= _pingEvery) {
                _lastPingAt = now;
                try {
                  _socketService.ping();
                  if (verboseSocketLogs) {
                    _log.debug('🫧 Ping sent');
                  }
                  _pingCount++;
                } catch (e) {
                  // Non-fatal
                  _log.debug('Ping failed: $e');
                }
              }
            }
          }
        } finally {
          // Re-arm regardless
          if (!_disposed && !_intentionalDisconnect) {
            _startHealthMonitor();
          }
        }
      }),
    );
  }

  void _stopHealthMonitor() {
    _healthTimer?.cancel();
    _healthTimer = null;
  }

  /// Configure optional ping behavior (enabled by default; 30s interval)
  void configurePing({bool? enabled, Duration? every}) {
    if (enabled != null) _pingEnabled = enabled;
    if (every != null) _pingEvery = every;
    if (_pingEnabled) {
      _startHealthMonitor();
    } else {
      // Keep health monitor running for silence checks; only pings are disabled
    }
  }
}

/// Provider for the WebSocket manager
final webSocketManagerProvider =
    NotifierProvider<WebSocketManager, WebSocketState>(
        WebSocketManager.new,);
