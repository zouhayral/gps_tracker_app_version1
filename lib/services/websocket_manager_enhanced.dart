import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

enum WebSocketStatus { connecting, connected, disconnected, retrying }

class WebSocketState {
  final WebSocketStatus status;
  final int retryCount;
  final String? error;
  final int? pingMs;
  final DateTime? lastConnected;

  const WebSocketState({
    required this.status,
    this.retryCount = 0,
    this.error,
    this.pingMs,
    this.lastConnected,
  });

  WebSocketState copyWith({
    WebSocketStatus? status,
    int? retryCount,
    String? error,
    int? pingMs,
    DateTime? lastConnected,
  }) {
    return WebSocketState(
      status: status ?? this.status,
      retryCount: retryCount ?? this.retryCount,
      error: error,
      pingMs: pingMs ?? this.pingMs,
      lastConnected: lastConnected ?? this.lastConnected,
    );
  }
}

/// Enhanced WebSocket Manager with automatic reconnection on app resume
/// and lifecycle-aware connection management
class WebSocketManager extends Notifier<WebSocketState> {
  static const _wsUrl = 'wss://your.server/ws'; // TODO: Replace with actual Traccar URL
  static const _pingInterval = Duration(seconds: 30);
  static const _maxRetries = 10; // Increased for better resilience
  static const _initialRetryDelay = Duration(seconds: 2);
  static const _maxRetryDelay = Duration(seconds: 30);

  static bool testMode = false;

  WebSocket? _socket;
  StreamController<Map<String, dynamic>>? _controller;
  Timer? _pingTimer;
  Timer? _reconnectTimer;
  int _retryCount = 0;
  bool _disposed = false;
  bool _intentionalDisconnect = false; // Track user-initiated disconnects
  DateTime? _lastPingSent;
  DateTime? _lastSuccessfulConnect;

  Stream<Map<String, dynamic>> get stream => _controller?.stream ?? const Stream.empty();
  
  bool get isConnected => state.status == WebSocketStatus.connected;
  bool get isDisconnected => state.status == WebSocketStatus.disconnected;

  @override
  WebSocketState build() {
    _controller = StreamController<Map<String, dynamic>>.broadcast();
    if (!testMode) {
      _connect();
    }
    ref.onDispose(_dispose);
    ref.keepAlive();
    return const WebSocketState(status: WebSocketStatus.connecting);
  }

  /// Connect or reconnect to WebSocket
  Future<void> _connect() async {
    if (_disposed || _intentionalDisconnect) return;
    
    // Cancel any pending reconnect timer
    _reconnectTimer?.cancel();
    
    state = state.copyWith(status: WebSocketStatus.connecting);
    _log('[WS][CONNECTING] Attempt ${_retryCount + 1}...');
    
    try {
      _socket = await WebSocket.connect(_wsUrl).timeout(
        const Duration(seconds: 10),
        onTimeout: () {
          throw TimeoutException('WebSocket connection timeout');
        },
      );
      
      _retryCount = 0;
      _lastSuccessfulConnect = DateTime.now();
      state = state.copyWith(
        status: WebSocketStatus.connected,
        retryCount: 0,
        error: null,
        lastConnected: _lastSuccessfulConnect,
      );
      _log('[WS] ✅ Connected successfully');
      
      _listen();
      _startPing();
    } catch (e) {
      _log('[WS][ERROR] Connection failed: $e');
      _scheduleReconnect(e.toString());
    }
  }

  void _listen() {
    _socket?.listen(
      (data) {
        if (_disposed) return;
        
        if (data is String) {
          try {
            final msg = jsonDecode(data);
            if (msg is Map<String, dynamic>) {
              if (msg['type'] == 'pong') {
                final latency = DateTime.now().difference(_lastPingSent ?? DateTime.now()).inMilliseconds;
                state = state.copyWith(pingMs: latency);
                _log('[WS][PONG] latency: ${latency}ms');
              } else {
                // Forward message to listeners
                _controller?.add(msg);
              }
            }
          } catch (e) {
            _log('[WS][ERROR] Failed to parse message: $e');
          }
        }
      },
      onDone: () {
        if (!_disposed && !_intentionalDisconnect) {
          _log('[WS][CLOSED] Connection closed by server');
          _scheduleReconnect('Connection closed');
        }
      },
      onError: (Object err) {
        if (!_disposed && !_intentionalDisconnect) {
          _log('[WS][ERROR] Socket error: $err');
          _scheduleReconnect(err.toString());
        }
      },
      cancelOnError: false,
    );
  }

  void _startPing() {
    _pingTimer?.cancel();
    _pingTimer = Timer.periodic(_pingInterval, (_) {
      if (_disposed) return;
      
      if (_socket?.readyState == WebSocket.open) {
        _lastPingSent = DateTime.now();
        try {
          _socket?.add(jsonEncode({'type': 'ping'}));
        } catch (e) {
          _log('[WS][ERROR] Failed to send ping: $e');
          _scheduleReconnect('Ping failed');
        }
      } else {
        _log('[WS][ERROR] Socket not open, reconnecting...');
        _scheduleReconnect('Socket not open');
      }
    });
  }

  /// Schedule reconnection with exponential backoff
  void _scheduleReconnect(String error) {
    if (_disposed || _intentionalDisconnect) return;
    
    _retryCount++;
    _pingTimer?.cancel();
    _socket?.close().catchError((_) {});
    
    state = state.copyWith(
      status: WebSocketStatus.retrying,
      retryCount: _retryCount,
      error: error,
    );
    
    // Exponential backoff with max delay
    final delay = _calculateBackoffDelay(_retryCount);
    _log('[WS][RETRY] Reconnecting in ${delay.inSeconds}s (attempt $_retryCount/$_maxRetries)');
    
    _reconnectTimer = Timer(delay, () {
      if (!_disposed && !_intentionalDisconnect) {
        _connect();
      }
    });
  }

  /// Calculate exponential backoff delay
  Duration _calculateBackoffDelay(int attempt) {
    final seconds = _initialRetryDelay.inSeconds * (1 << (attempt - 1).clamp(0, 5));
    return Duration(seconds: seconds.clamp(
      _initialRetryDelay.inSeconds,
      _maxRetryDelay.inSeconds,
    ));
  }

  /// Manually trigger reconnection (call when app resumes or map page opens)
  Future<void> forceReconnect() async {
    _log('[WS][FORCE_RECONNECT] Manual reconnection triggered');
    _intentionalDisconnect = false;
    _retryCount = 0;
    _reconnectTimer?.cancel();
    
    if (_socket?.readyState == WebSocket.open) {
      _log('[WS] Already connected');
      return;
    }
    
    await _socket?.close().catchError((_) {});
    await _connect();
  }

  /// Suspend connection (call when app goes to background)
  void suspend() {
    _log('[WS][SUSPEND] Suspending connection');
    _intentionalDisconnect = true;
    _reconnectTimer?.cancel();
    _pingTimer?.cancel();
    _socket?.close().catchError((_) {});
    state = state.copyWith(status: WebSocketStatus.disconnected);
  }

  /// Resume connection (call when app comes to foreground)
  Future<void> resume() async {
    _log('[WS][RESUME] Resuming connection');
    _intentionalDisconnect = false;
    
    if (_socket == null || _socket?.readyState != WebSocket.open) {
      await forceReconnect();
    } else {
      _log('[WS] Already connected');
    }
  }

  /// Check connection health and reconnect if needed
  void checkHealth() {
    if (_disposed || _intentionalDisconnect) return;
    
    if (_socket?.readyState != WebSocket.open) {
      _log('[WS][HEALTH_CHECK] Connection unhealthy, reconnecting...');
      forceReconnect();
    } else if (_lastSuccessfulConnect != null) {
      final timeSinceConnect = DateTime.now().difference(_lastSuccessfulConnect!);
      if (timeSinceConnect > const Duration(minutes: 5) && state.pingMs == null) {
        _log('[WS][HEALTH_CHECK] No ping response in 5 minutes, reconnecting...');
        forceReconnect();
      }
    }
  }

  void _dispose() {
    _disposed = true;
    _intentionalDisconnect = true;
    _reconnectTimer?.cancel();
    _pingTimer?.cancel();
    _socket?.close().catchError((_) {});
    _controller?.close();
    _log('[WS][DISPOSE] Disposed');
  }

  void _log(String msg) {
    if (kDebugMode) {
      debugPrint('${DateTime.now().toIso8601String()} $msg');
    }
  }
}

final webSocketProvider = NotifierProvider<WebSocketManager, WebSocketState>(WebSocketManager.new);
