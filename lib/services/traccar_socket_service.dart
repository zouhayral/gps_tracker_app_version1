import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:web_socket_channel/web_socket_channel.dart';
import 'ws_connect_stub.dart'
  if (dart.library.io) 'ws_connect_io.dart'
  if (dart.library.html) 'ws_connect_web.dart';
import 'package:web_socket_channel/status.dart' as ws_status;

import 'auth_service.dart';
import '../features/map/data/position_model.dart';

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
    _controller ??= StreamController<TraccarSocketMessage>.broadcast(onListen: _ensureConnected);
    _ensureConnected();
    return _controller!.stream;
  }

  void _ensureConnected() async {
    if (_channel != null) return;
    final cookie = await auth.getStoredJSessionId();
    final wsUrl = _toWsUrl(baseUrl);
    final uri = Uri.parse(wsUrl);
    try {
      final headers = <String, dynamic>{};
      if (cookie != null) headers['Cookie'] = 'JSESSIONID=$cookie';
      _channel = connectWebSocket(uri, headers);
      _reconnectAttempts = 0;
      _controller?.add(TraccarSocketMessage.connected());
      _channel!.stream.listen(
        (data) => _onData(data),
        onError: (e, st) => _onError(e),
        onDone: _onDone,
        cancelOnError: true,
      );
    } catch (e) {
      _scheduleReconnect('connect-failed: $e');
    }
  }

  void _onData(dynamic data) {
    try {
      final text = data is String ? data : utf8.decode(data as List<int>);
      final jsonObj = jsonDecode(text);
      if (jsonObj is Map<String, dynamic>) {
        // positions
        if (jsonObj.containsKey('positions')) {
          final list = (jsonObj['positions'] as List?)?.whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList() ?? const [];
          final positions = [for (final m in list) Position.fromJson(m)];
          _controller?.add(TraccarSocketMessage.positions(positions));
        }
        // events (opaque here)
        if (jsonObj.containsKey('events')) {
          _controller?.add(TraccarSocketMessage.events(jsonObj['events']));
        }
        // devices updates (optional)
        if (jsonObj.containsKey('devices')) {
          _controller?.add(TraccarSocketMessage.devices(jsonObj['devices']));
        }
      }
    } catch (e) {
      if (kDebugMode) {
        // ignore: avoid_print
        print('[traccar-socket] parse error: $e');
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
      print('[SOCKET][RETRY] attempt #$nextAttempt in ${baseSeconds}s (reason=$reason)');
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
    return Uri(scheme: scheme, host: u.host, port: u.hasPort ? u.port : null, path: '/api/socket').toString();
  }
}

/// Discriminated socket messages
class TraccarSocketMessage {
  final String type;
  final List<Position>? positions;
  final dynamic payload;
  const TraccarSocketMessage._(this.type, {this.positions, this.payload});
  factory TraccarSocketMessage.connected() => const TraccarSocketMessage._('connected');
  factory TraccarSocketMessage.positions(List<Position> p) => TraccarSocketMessage._('positions', positions: p);
  factory TraccarSocketMessage.events(dynamic events) => TraccarSocketMessage._('events', payload: events);
  factory TraccarSocketMessage.devices(dynamic devices) => TraccarSocketMessage._('devices', payload: devices);
  factory TraccarSocketMessage.error(String error) => TraccarSocketMessage._('error', payload: error);
}
