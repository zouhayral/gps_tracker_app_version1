import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:my_app_gps/services/traccar_socket_service.dart';

enum ConnectionStatus { connecting, connected, retrying }

/// Exposes current WebSocket connection status for UI (badges, banners) and guards.
final traccarConnectionStatusProvider = AutoDisposeNotifierProvider<
    TraccarConnectionStatusNotifier,
    ConnectionStatus>(TraccarConnectionStatusNotifier.new);

class TraccarConnectionStatusNotifier
    extends AutoDisposeNotifier<ConnectionStatus> {
  StreamSubscription<TraccarSocketMessage>? _sub;

  @override
  ConnectionStatus build() {
    state = ConnectionStatus.connecting;
    final socket = ref.read(traccarSocketServiceProvider);

    ref.onDispose(() async {
      await _sub?.cancel();
      _sub = null;
    });

    _sub = socket.connect().listen((msg) {
      switch (msg.type) {
        case 'connected':
          state = ConnectionStatus.connected;
        case 'error':
          // Service will schedule reconnect; reflect as retrying until we get connected again
          state = ConnectionStatus.retrying;
        default:
          // no-op for data messages
          break;
      }
    });

    return state;
  }
}
