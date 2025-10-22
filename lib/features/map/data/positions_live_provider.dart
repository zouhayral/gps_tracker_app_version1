import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:my_app_gps/features/dashboard/controller/devices_notifier.dart';
import 'package:my_app_gps/features/map/data/position_model.dart';
import 'package:my_app_gps/services/customer/customer_websocket.dart';

/// Live positions via WebSocket: consumes Traccar /api/socket and maintains the latest map.
final positionsLiveProvider =
    StreamProvider.autoDispose<Map<int, Position>>((ref) {
  // Ensure devices are loaded for downstream consumers
  ref.watch(devicesNotifierProvider);

  final controller = StreamController<Map<int, Position>>.broadcast();
  final subscription = ref.listen<AsyncValue<CustomerWebSocketMessage>>(
    customerWebSocketProvider,
    (_, next) {
      next.whenData((msg) {
        if (msg is! CustomerPositionsMessage) {
          return;
        }
        final positions = <int, Position>{
          for (final position in msg.positions) position.deviceId: position,
        };
        if (!controller.isClosed) {
          controller.add(Map<int, Position>.unmodifiable(positions));
        }
      });
    },
  );

  ref.onDispose(() {
    subscription.close();
    // StreamController.close returns Future<void>; we don't await in onDispose
    unawaited(controller.close());
  });

  return controller.stream;
});
