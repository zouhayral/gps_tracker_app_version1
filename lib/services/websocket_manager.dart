import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:my_app_gps/core/diagnostics/dev_diagnostics.dart';

enum WebSocketStatus { connecting, connected, disconnected, retrying }

class WebSocketState {
  final WebSocketStatus status;
  final int retryCount;
  final String? error;
  final int? pingMs;

  const WebSocketState({
    required this.status,
    this.retryCount = 0,
    this.error,
    this.pingMs,
  });

  WebSocketState copyWith({
    WebSocketStatus? status,
    int? retryCount,
    String? error,
    int? pingMs,
  }) {
    return WebSocketState(
      status: status ?? this.status,
      retryCount: retryCount ?? this.retryCount,
      error: error,
      pingMs: pingMs ?? this.pingMs,
    );
  }
}

class WebSocketManager extends Notifier<WebSocketState> {
  // WebSocket URL for Traccar server
  static const _wsUrl = 'ws://37.60.238.215:8082/api/socket';
  static const _pingInterval = Duration(seconds: 30);
  static const _maxRetries = 10; // Increased for better exponential backoff
  static const _circuitBreakerTimeout = Duration(minutes: 2);
  static const _maxRetryDelay = Duration(seconds: 60); // Cap exponential backoff
  
  // 🎯 PHASE 2: Reconnect debouncing
  static const _reconnectDebounceWindow = Duration(seconds: 10); // Min time between reconnects
  static const _fallbackSuppressionWindow = Duration(seconds: 3); // Suppress fallback if WS recovers quickly

  // Toggle to reduce log spam for heartbeats
  static bool verboseSocketLogs = false;

  static bool testMode = false;

  WebSocket? _socket;
  StreamController<Map<String, dynamic>>? _controller;
  Timer? _pingTimer;
  Timer? _circuitBreakerTimer;
  Timer? _retryTimer; // Track scheduled retry
  int _retryCount = 0;
  bool _disposed = false;
  bool _circuitBreakerOpen = false;
  bool _isFullyConnected = false; // 🎯 NEW: debounced connection flag
  bool _isPaused = false; // 🎯 NEW: pause retries when offline
  DateTime? _lastPingSent;
  
  // 🎯 PHASE 2: Reconnect throttling state
  DateTime? _lastReconnectAttempt;
  DateTime? _lastSuccessfulConnection;
  int _successfulConnectionCount = 0;

  Stream<Map<String, dynamic>> get stream =>
      _controller?.stream ?? const Stream.empty();

  @override
  WebSocketState build() {
    _controller = StreamController<Map<String, dynamic>>.broadcast();

    // Defer connection to after build completes to avoid reading uninitialized providers
    if (!testMode) {
      Future.microtask(() {
        if (!_disposed) {
          _connect();
        }
      });
    }

    ref.onDispose(_dispose);
    ref.keepAlive();
    return const WebSocketState(status: WebSocketStatus.connecting);
  }

  Future<void> _connect() async {
    if (_disposed) return;

    // 🎯 NEW: Check if paused (offline mode)
    if (_isPaused) {
      _log('[WS] ⚠️ Paused (offline) - skipping connection attempt');
      return;
    }

    // 🎯 PHASE 2: Reconnect debouncing - prevent reconnect spam
    final now = DateTime.now();
    if (_lastReconnectAttempt != null &&
        now.difference(_lastReconnectAttempt!) < _reconnectDebounceWindow) {
      _log('[WS][DEBOUNCE] ⏸️ Reconnect skipped (last attempt ${now.difference(_lastReconnectAttempt!).inSeconds}s ago, min ${_reconnectDebounceWindow.inSeconds}s)');
      return;
    }
    _lastReconnectAttempt = now;

    // Circuit breaker: Skip connection if placeholder hostname detected
    if (_wsUrl.contains('your.server')) {
      _log('[WS] ⚠️ Invalid hostname: "your.server" - skipping connection');
      _log('[WS] 💡 Update _wsUrl in websocket_manager.dart with actual server URL');
      _circuitBreakerOpen = true;
      state = state.copyWith(
        status: WebSocketStatus.disconnected,
        error: 'Invalid WebSocket URL configuration',
      );
      return;
    }

    // Circuit breaker: Stop retrying if permanently failed
    if (_circuitBreakerOpen) {
      _log('[WS] ⛔ Circuit breaker open - not attempting connection');
      return;
    }

    state = state.copyWith(status: WebSocketStatus.connecting);
    _isFullyConnected = false; // Reset debounce flag
    _log('[WS][INIT] Connecting...');
    
    try {
      // 🎯 IMPROVED: Wrap WebSocket.connect in try/catch to handle all exceptions
      _socket = await WebSocket.connect(_wsUrl).timeout(
        const Duration(seconds: 10),
        onTimeout: () {
          throw TimeoutException('WebSocket connection timeout');
        },
      );
      
      // ⚠️ Do NOT log "Connected" yet - wait for first valid message or pong
      _log('[WS] 🔗 Socket opened, awaiting confirmation...');
      _retryCount = 0;
      _circuitBreakerOpen = false;
      
      // Update state to connecting (not connected yet)
      state = state.copyWith(status: WebSocketStatus.connecting, retryCount: 0);
      
      _listen();
      _startPing();
    } on SocketException catch (e) {
      _log('[WS] ❌ SocketException: ${e.message}');
      _handleReconnect('SocketException: ${e.message}');
    } on WebSocketException catch (e) {
      _log('[WS] ❌ WebSocketException: ${e.message}');
      _handleReconnect('WebSocketException: ${e.message}');
    } on TimeoutException catch (e) {
      _log('[WS] ❌ Timeout: ${e.message}');
      _handleReconnect('Connection timeout');
    } catch (e, stackTrace) {
      // 🎯 IMPROVED: Catch all exceptions including WebSocketChannelException
      _log('[WS] ❌ Connection error: $e');
      if (kDebugMode) {
        debugPrint('[WS] Stack trace: $stackTrace');
      }
      _handleReconnect(e.toString());
    }
  }

  void _listen() {
    _socket?.listen(
      (data) {
        try {
          if (data is String) {
            final msg = jsonDecode(data);
            
            // 🎯 NEW: Confirm connection on first valid message
            if (!_isFullyConnected) {
              _isFullyConnected = true;
              state = state.copyWith(status: WebSocketStatus.connected);
              
              // 🎯 PHASE 2: Track successful connection for fallback suppression
              _lastSuccessfulConnection = DateTime.now();
              _successfulConnectionCount++;
              
              final reconnectTime = _lastReconnectAttempt != null 
                  ? DateTime.now().difference(_lastReconnectAttempt!)
                  : Duration.zero;
              
              _log('[WS] ✅ Connection confirmed (first message received) - reconnect took ${reconnectTime.inMilliseconds}ms');
              
              // Dev diagnostics: count successful (re)connects in debug
              if (kDebugMode) {
                DevDiagnostics.instance.onWsConnected();
              }
            }
            
            if (msg is Map<String, dynamic> && msg['type'] == 'pong') {
              final latency = DateTime.now()
                  .difference(_lastPingSent ?? DateTime.now())
                  .inMilliseconds;
              state = state.copyWith(pingMs: latency);
              if (kDebugMode && verboseSocketLogs) {
                _log('[WS][PONG] latency: ${latency}ms');
              }
              if (kDebugMode) {
                DevDiagnostics.instance.recordPingLatency(latency.toDouble());
              }
            } else if (msg is Map<String, dynamic>) {
              _controller?.add(msg);
            }
          }
        } catch (e) {
          // 🎯 IMPROVED: Catch JSON decode errors
          _log('[WS] ⚠️ Failed to parse message: $e');
        }
      },
      onDone: () {
        _isFullyConnected = false;
        _log('[WS][CLOSE] Connection closed gracefully');
        _handleReconnect('Connection closed');
      },
      onError: (Object err) {
        // 🎯 IMPROVED: Log error type for debugging
        _isFullyConnected = false;
        _log('[WS][ERROR] Stream error: ${err.runtimeType} - $err');
        _handleReconnect(err.toString());
      },
      cancelOnError: true,
    );
  }

  void _startPing() {
    _pingTimer?.cancel();
    _pingTimer = Timer.periodic(_pingInterval, (_) {
      if (_socket?.readyState == WebSocket.open) {
        _lastPingSent = DateTime.now();
        _socket?.add(jsonEncode({'type': 'ping'}));
        Future.delayed(_pingInterval ~/ 2, () {
          if (state.pingMs == null) {
            _log('[WS][PONG TIMEOUT] Reconnecting...');
            _handleReconnect('Pong timeout');
          }
        });
      }
    });
  }

  void _handleReconnect(String error) {
    if (_disposed) return;
    
    // Cancel any existing retry timer
    _retryTimer?.cancel();
    _isFullyConnected = false;
    
    // 🎯 NEW: Don't retry if paused (offline)
    if (_isPaused) {
      _log('[WS] ⚠️ Paused (offline) - not scheduling retry');
      state = state.copyWith(
        status: WebSocketStatus.disconnected,
        error: 'Offline - paused',
      );
      return;
    }
    
    _retryCount++;
    state = state.copyWith(
      status: WebSocketStatus.retrying,
      retryCount: _retryCount,
      error: error,
    );
    
    // Circuit breaker after max retries
    if (_retryCount > _maxRetries) {
      _log(
        '[WS][CIRCUIT BREAKER] ⛔ Too many retries ($_retryCount), pausing for ${_circuitBreakerTimeout.inMinutes}m',
      );
      _circuitBreakerOpen = true;
      _circuitBreakerTimer = Timer(_circuitBreakerTimeout, () {
        _circuitBreakerOpen = false;
        _retryCount = 0;
        _log('[WS][CIRCUIT BREAKER] 🔓 Circuit breaker reset, resuming');
        _connect();
      });
      return;
    }
    
    // 🎯 IMPROVED: Exponential backoff with cap
    // Formula: min(2^(retryCount - 1), maxRetryDelay)
    final exponentialSeconds = (1 << (_retryCount - 1)).clamp(1, _maxRetryDelay.inSeconds);
    final delay = Duration(seconds: exponentialSeconds);
    
    _log('[WS] 🔄 Retry attempt #$_retryCount in ${delay.inSeconds}s (exponential backoff)');
    
    _retryTimer = Timer(delay, () {
      if (!_disposed && !_isPaused) {
        _connect();
      }
    });
  }

  /// 🎯 NEW: Pause retries when offline (called by ConnectivityProvider)
  void pause() {
    if (_isPaused) return;
    _isPaused = true;
    _log('[WS] ⏸️ PAUSED (offline detected) - stopping retries');
    
    // Cancel all timers
    _retryTimer?.cancel();
    _pingTimer?.cancel();
    _circuitBreakerTimer?.cancel();
    
    // Close socket if open
    _socket?.close();
    _isFullyConnected = false;
    
    state = state.copyWith(
      status: WebSocketStatus.disconnected,
      error: 'Network offline - paused',
    );
  }

  /// 🎯 NEW: Resume when back online (called by ConnectivityProvider)
  void resume() {
    if (!_isPaused) return;
    _isPaused = false;
    _retryCount = 0; // Reset retry count on reconnect
    _circuitBreakerOpen = false; // Reset circuit breaker
    _log('[WS] ▶️ RESUMED (network restored) - attempting reconnection');
    
    state = state.copyWith(
      status: WebSocketStatus.connecting,
      retryCount: 0,
    );
    
    _connect();
  }

  void suspend() {
    _log('[WS][SUSPEND] Suspending connection');
    _pingTimer?.cancel();
    _retryTimer?.cancel();
    _socket?.close();
    _isFullyConnected = false;
    state = state.copyWith(status: WebSocketStatus.disconnected);
  }

  /// 🎯 PHASE 2: Check if REST fallback should be suppressed
  /// Returns true if WebSocket reconnected successfully within the suppression window
  bool shouldSuppressFallback() {
    if (_lastSuccessfulConnection == null) return false;
    
    final timeSinceReconnect = DateTime.now().difference(_lastSuccessfulConnection!);
    final shouldSuppress = timeSinceReconnect < _fallbackSuppressionWindow;
    
    if (shouldSuppress && kDebugMode) {
      _log('[WS][FALLBACK-SUPPRESS] ✋ Suppressing REST fallback (reconnected ${timeSinceReconnect.inMilliseconds}ms ago)');
    }
    
    return shouldSuppress;
  }

  /// 🎯 PHASE 2: Get connection stability metrics
  Map<String, dynamic> getConnectionMetrics() {
    return {
      'successfulConnections': _successfulConnectionCount,
      'currentRetryCount': _retryCount,
      'isFullyConnected': _isFullyConnected,
      'lastSuccessfulConnection': _lastSuccessfulConnection?.toIso8601String(),
      'timeSinceLastSuccess': _lastSuccessfulConnection != null
          ? DateTime.now().difference(_lastSuccessfulConnection!).inSeconds
          : null,
    };
  }

  void _dispose() {
    _disposed = true;
    _isPaused = false;
    _isFullyConnected = false;
    _pingTimer?.cancel();
    _circuitBreakerTimer?.cancel();
    _retryTimer?.cancel(); // 🎯 NEW: Cancel retry timer
    _socket?.close();
    _controller?.close();
    _log('[WS][DISPOSE] ♻️ Disposed and cleaned up');
  }

  void _log(String msg) {
    if (kDebugMode) {
      debugPrint('${DateTime.now().toIso8601String()} $msg');
    }
  }
}

final webSocketProvider =
    NotifierProvider<WebSocketManager, WebSocketState>(WebSocketManager.new);
