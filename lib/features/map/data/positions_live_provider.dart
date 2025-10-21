// ...existing code...
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:my_app_gps/features/dashboard/controller/devices_notifier.dart';
import 'package:my_app_gps/features/map/data/position_model.dart';
import 'package:my_app_gps/services/customer/customer_websocket.dart';

/// Live positions via WebSocket: consumes Traccar /api/socket and maintains the latest map.
final positionsLiveProvider =
    StreamProvider.autoDispose<Map<int, Position>>((ref) async* {
  // Ensure devices are loaded for downstream consumers
  ref.watch(devicesNotifierProvider);

  // Listen to customerWebSocketProvider and map positions payloads
  final wsStream = ref.watch(customerWebSocketProvider.stream);
  await for (final msg in wsStream) {
    if (msg is CustomerPositionsMessage) {
      final positions = <int, Position>{};
      for (final p in msg.positions) {
        positions[p.deviceId] = p;
      }
      yield Map<int, Position>.unmodifiable(positions);
    }
  }
});

// ...existing code...
