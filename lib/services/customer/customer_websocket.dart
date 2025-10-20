/// Customer WebSocket adapter
///
/// Wraps TraccarSocketService and exposes a typed message stream for
/// the multi-customer providers.
library;

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:my_app_gps/features/map/data/position_model.dart';
import 'package:my_app_gps/services/customer/customer_session.dart';
import 'package:my_app_gps/services/traccar_socket_service.dart';

// Discriminated customer message hierarchy consumed by providers
sealed class CustomerWebSocketMessage {}

class CustomerConnectedMessage extends CustomerWebSocketMessage {
  CustomerConnectedMessage();
}

class CustomerPositionsMessage extends CustomerWebSocketMessage {
  CustomerPositionsMessage(this.positions);
  final List<Position> positions;
}

class CustomerEventsMessage extends CustomerWebSocketMessage {
  CustomerEventsMessage(this.events);
  final dynamic events;
}

class CustomerDevicesMessage extends CustomerWebSocketMessage {
  CustomerDevicesMessage(this.devices);
  final dynamic devices;
}

class CustomerErrorMessage extends CustomerWebSocketMessage {
  CustomerErrorMessage(this.error);
  final String error;
}

/// Stream of customer websocket messages, bound to current session
final customerWebSocketProvider =
    StreamProvider.autoDispose<CustomerWebSocketMessage>((ref) async* {
  final session = await ref.watch(customerSessionProvider.future);
  // If not authenticated, don't connect
  if (!session.isAuthenticated) {
    if (kDebugMode) {
      // ignore: avoid_print
      print('[CustomerWebSocket] Session not authenticated; skipping connect');
    }
    return;
  }

  final socket = ref.watch(traccarSocketServiceProvider);
  final controller = StreamController<CustomerWebSocketMessage>();
  final sub = socket.connect().listen((msg) {
    switch (msg.type) {
      case 'connected':
        controller.add(CustomerConnectedMessage());
      case 'positions':
        controller.add(CustomerPositionsMessage(msg.positions ?? const []));
      case 'events':
        controller.add(CustomerEventsMessage(msg.payload));
      case 'devices':
        controller.add(CustomerDevicesMessage(msg.payload));
      case 'error':
        controller.add(CustomerErrorMessage(msg.payload?.toString() ?? 'error'));
      default:
        break;
    }
  });

  ref.onDispose(() async {
    await sub.cancel();
    await controller.close();
  });

  yield* controller.stream;
});
