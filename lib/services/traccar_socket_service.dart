import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:my_app_gps/features/map/data/position_model.dart';
import 'package:my_app_gps/services/auth_service.dart';
import 'package:my_app_gps/services/ws_connect_stub.dart'
    if (dart.library.io) 'package:my_app_gps/services/ws_connect_io.dart'
    if (dart.library.html) 'package:my_app_gps/services/ws_connect_web.dart';
import 'package:web_socket_channel/status.dart' as ws_status;
import 'package:web_socket_channel/web_socket_channel.dart';

/// Provides a singleton TraccarSocketService.
final traccarSocketServiceProvider = Provider<TraccarSocketService>((ref) {
  final auth = ref.watch(authServiceProvider);
  final dio = ref.watch(dioProvider);
  return TraccarSocketService(baseUrl: dio.options.baseUrl, auth: auth);
});

/// A lightweight WebSocket client for Traccar /api/socket that emits live positions/events.
class TraccarSocketService {
  TraccarSocketService({required this.baseUrl, required this.auth});
  final String baseUrl;
  final AuthService auth;

  WebSocketChannel? _channel;
  StreamController<TraccarSocketMessage>? _controller;
  Timer? _reconnectTimer;
  int _reconnectAttempts = 0;
  bool _manuallyClosed = false;

  Stream<TraccarSocketMessage> connect() {
    _manuallyClosed = false;
    _controller ??= StreamController<TraccarSocketMessage>.broadcast(
      onListen: _ensureConnected,
    );
    _ensureConnected();
    return _controller!.stream;
  }

  Future<void> _ensureConnected() async {
    if (_channel != null) return;
    final cookie = await auth.getStoredJSessionId();
    final wsUrl = _toWsUrl(baseUrl);
    final uri = Uri.parse(wsUrl);
    if (kDebugMode) {
      // ignore: avoid_print
      print('[SOCKET] ═══════════════════════════════════════');
      print('[SOCKET] Attempting WebSocket connection...');
      print('[SOCKET] URL: $wsUrl');
      print('[SOCKET] Host: ${uri.host}');
      print('[SOCKET] Port: ${uri.port}');
      print('[SOCKET] Scheme: ${uri.scheme}');
      print(
          '[SOCKET] Cookie: ${cookie != null ? 'present (${cookie.substring(0, 10)}...)' : 'MISSING'}',);
      print('[SOCKET] ═══════════════════════════════════════');
    }
    try {
      final headers = <String, dynamic>{};
      if (cookie != null) headers['Cookie'] = 'JSESSIONID=$cookie';

      if (kDebugMode) {
        // ignore: avoid_print
        print('[SOCKET] Creating WebSocket channel...');
      }

      _channel = connectWebSocket(uri, headers);
      _reconnectAttempts = 0;

      if (kDebugMode) {
        // ignore: avoid_print
        print('[SOCKET] ✅ WebSocket channel created');
        print('[SOCKET] Waiting for connection confirmation...');
      }

      _controller?.add(TraccarSocketMessage.connected());

      _channel!.stream.listen(
        _onData,
        onError: (Object e, StackTrace st) {
          if (kDebugMode) {
            // ignore: avoid_print
            print('[SOCKET] ❌ Stream error: $e');
            print('[SOCKET] StackTrace: $st');
          }
          _onError(e);
        },
        onDone: () {
          if (kDebugMode) {
            // ignore: avoid_print
            print('[SOCKET] ⚠️ Stream closed (onDone)');
          }
          _onDone();
        },
        cancelOnError: true,
      );

      if (kDebugMode) {
        // ignore: avoid_print
        print('[SOCKET] ✅ WebSocket stream listener attached');
      }
    } catch (e, st) {
      if (kDebugMode) {
        // ignore: avoid_print
        print('[SOCKET] ❌ Connection exception: $e');
        print('[SOCKET] Exception type: ${e.runtimeType}');
        print('[SOCKET] StackTrace: $st');
      }
      _scheduleReconnect('connect-failed: $e');
    }
  }

  void _onData(dynamic data) {
    try {
      final text = data is String ? data : utf8.decode(data as List<int>);

      if (kDebugMode) {
        // ignore: avoid_print
        print('[SOCKET] 📨 RAW WebSocket message received:');
        print(
            '[SOCKET] ${text.length > 500 ? '${text.substring(0, 500)}...' : text}',);
      }

      final jsonObj = jsonDecode(text);
      if (jsonObj is Map<String, dynamic>) {
        // positions
        if (jsonObj.containsKey('positions')) {
          final list = (jsonObj['positions'] as List<dynamic>?)
                  ?.whereType<Map<String, dynamic>>()
                  .toList() ??
              const <Map<String, dynamic>>[];
          final positions = list.map(Position.fromJson).toList();
          if (kDebugMode) {
            // ignore: avoid_print
            print(
                '[SOCKET] 📍 Received ${positions.length} positions from WebSocket',);
            for (final pos in positions) {
              print(
                  '[SOCKET]   Device ${pos.deviceId}: ignition=${pos.attributes['ignition']}, speed=${pos.speed}',);
            }
          }
          _controller?.add(TraccarSocketMessage.positions(positions));
        }
        // events (opaque here)
        if (jsonObj.containsKey('events')) {
          if (kDebugMode) {
            // ignore: avoid_print
            print('[SOCKET] 🔔 Received events from WebSocket');
            print('[SOCKET] Events payload: ${jsonObj['events']}');
          }
          _controller?.add(TraccarSocketMessage.events(jsonObj['events']));
        }
        // devices updates (optional)
        if (jsonObj.containsKey('devices')) {
          if (kDebugMode) {
            // ignore: avoid_print
            print('[SOCKET] 📱 Received device updates from WebSocket');
            print('[SOCKET] Devices payload: ${jsonObj['devices']}');
          }
          _controller?.add(TraccarSocketMessage.devices(jsonObj['devices']));
        }
      }
    } catch (e) {
      if (kDebugMode) {
        // ignore: avoid_print
        print('[SOCKET] ❌ Parse error: $e');
      }
    }
  }

  void _onError(Object e) {
    _controller?.add(TraccarSocketMessage.error(e.toString()));
    _scheduleReconnect('onError: $e');
  }

  void _onDone() {
    _channel = null;
    if (_manuallyClosed) return;
    _scheduleReconnect('onDone');
  }

  void _scheduleReconnect(String reason) {
    if (_manuallyClosed) return;
    _channel = null;
    // Capped exponential backoff: 2s, 4s, 8s, 16s, 32s
    final exp = _reconnectAttempts.clamp(0, 4);
    final baseSeconds = math.min(32, 2 << exp);
    final nextAttempt = _reconnectAttempts + 1;
    _reconnectAttempts = nextAttempt;
    if (kDebugMode) {
      // ignore: avoid_print
      print(
        '[SOCKET][RETRY] attempt #$nextAttempt in ${baseSeconds}s (reason=$reason)',
      );
    }
    _reconnectTimer?.cancel();
    _reconnectTimer = Timer(Duration(seconds: baseSeconds), _ensureConnected);
  }

  Future<void> close() async {
    _manuallyClosed = true;
    _reconnectTimer?.cancel();
    _reconnectTimer = null;
    try {
      await _channel?.sink.close(ws_status.normalClosure);
    } catch (_) {}
    _channel = null;
    await _controller?.close();
    _controller = null;
  }

  String _toWsUrl(String base) {
    // http(s)://host[:port]/... -> ws(s)://host[:port]/api/socket
    final u = Uri.parse(base);
    final scheme = u.scheme == 'https' ? 'wss' : 'ws';
    return Uri(
      scheme: scheme,
      host: u.host,
      port: u.hasPort ? u.port : null,
      path: '/api/socket',
    ).toString();
  }
}

/// Discriminated socket messages
class TraccarSocketMessage {
  final String type;
  final List<Position>? positions;
  final dynamic payload;
  const TraccarSocketMessage._(this.type, {this.positions, this.payload});
  factory TraccarSocketMessage.connected() =>
      const TraccarSocketMessage._('connected');
  factory TraccarSocketMessage.positions(List<Position> p) =>
      TraccarSocketMessage._('positions', positions: p);
  factory TraccarSocketMessage.events(dynamic events) =>
      TraccarSocketMessage._('events', payload: events);
  factory TraccarSocketMessage.devices(dynamic devices) =>
      TraccarSocketMessage._('devices', payload: devices);
  factory TraccarSocketMessage.error(String error) =>
      TraccarSocketMessage._('error', payload: error);
}
