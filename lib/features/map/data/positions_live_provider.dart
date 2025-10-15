// ...existing code...
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:my_app_gps/features/dashboard/controller/devices_notifier.dart';
import 'package:my_app_gps/features/map/data/position_model.dart';
import 'package:my_app_gps/services/websocket_manager.dart';

/// Live positions via WebSocket: consumes Traccar /api/socket and maintains the latest map.
final positionsLiveProvider = StreamProvider.autoDispose<Map<int, Position>>((ref) {
  final wsManager = ref.read(webSocketProvider.notifier);
  ref.watch(devicesNotifierProvider); // Ensure devices are loaded for downstream consumers

  // Listen to the unified WebSocket stream and map incoming position updates
  return wsManager.stream
      .where((msg) => msg['type'] == 'positions' && msg['positions'] is List)
      .map((msg) {
        final positions = <int, Position>{};
        for (final p in (msg['positions'] as List)) {
          final pos = Position.fromJson(p as Map<String, dynamic>);
          positions[pos.deviceId] = pos;
        }
        return Map<int, Position>.unmodifiable(positions);
      });
});

// ...existing code...
