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
  static const _wsUrl = 'wss://your.server/ws'; // TODO: Replace with actual URL
  static const _pingInterval = Duration(seconds: 30);
  static const _maxRetries = 5;
  static const _circuitBreakerTimeout = Duration(minutes: 2);

  static bool testMode = false;

  WebSocket? _socket;
  StreamController<Map<String, dynamic>>? _controller;
  Timer? _pingTimer;
  Timer? _circuitBreakerTimer;
  int _retryCount = 0;
  bool _disposed = false;
  DateTime? _lastPingSent;

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
    state = state.copyWith(status: WebSocketStatus.connecting);
    _log('[WS][INIT] Connecting...');
    try {
      _socket = await WebSocket.connect(_wsUrl);
      _retryCount = 0;
      state = state.copyWith(status: WebSocketStatus.connected, retryCount: 0);
      _log('[WS] Connected');
      _listen();
      _startPing();
    } catch (e) {
      _log('[WS][ERROR] $e');
      _handleReconnect(e.toString());
    }
  }

  void _listen() {
    _socket?.listen(
      (data) {
        if (data is String) {
          final msg = jsonDecode(data);
          if (msg is Map<String, dynamic> && msg['type'] == 'pong') {
            final latency = DateTime.now()
                .difference(_lastPingSent ?? DateTime.now())
                .inMilliseconds;
            state = state.copyWith(pingMs: latency);
            _log('[WS][PONG] latency: ${latency}ms');
          } else if (msg is Map<String, dynamic>) {
            _controller?.add(msg);
          }
        }
      },
      onDone: () {
        _log('[WS][CLOSE] Closed gracefully');
        _handleReconnect('Closed');
      },
      onError: (Object err) {
        _log('[WS][ERROR] $err');
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
    _retryCount++;
    state = state.copyWith(
        status: WebSocketStatus.retrying,
        retryCount: _retryCount,
        error: error);
    if (_retryCount > _maxRetries) {
      _log(
          '[WS][CIRCUIT BREAKER] Too many retries, pausing for ${_circuitBreakerTimeout.inMinutes}m');
      _circuitBreakerTimer = Timer(_circuitBreakerTimeout, () {
        _retryCount = 0;
        _connect();
      });
      return;
    }
    final delay = Duration(seconds: 1 << (_retryCount - 1));
    _log('[WS][RETRY] Attempt $_retryCount in ${delay.inSeconds}s');
    Future.delayed(delay, _connect);
  }

  void suspend() {
    _log('[WS][SUSPEND] Suspending connection');
    _pingTimer?.cancel();
    _socket?.close();
    state = state.copyWith(status: WebSocketStatus.disconnected);
  }

  void resume() {
    if (_socket == null || _socket?.readyState != WebSocket.open) {
      _log('[WS][RESUME] Resuming connection');
      _connect();
    }
  }

  void _dispose() {
    _disposed = true;
    _pingTimer?.cancel();
    _circuitBreakerTimer?.cancel();
    _socket?.close();
    _controller?.close();
    _log('[WS][DISPOSE] Disposed');
  }

  void _log(String msg) {
    debugPrint('${DateTime.now().toIso8601String()} $msg');
  }
}

final webSocketProvider =
    NotifierProvider<WebSocketManager, WebSocketState>(WebSocketManager.new);
