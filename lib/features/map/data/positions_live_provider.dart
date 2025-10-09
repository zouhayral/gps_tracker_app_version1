import 'dart:async';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../services/traccar_socket_service.dart';
import '../../../services/traccar_connection_provider.dart';
import '../../dashboard/controller/devices_notifier.dart';
import 'position_model.dart';

/// Live positions via WebSocket: consumes Traccar /api/socket and maintains the latest map.
final positionsLiveProvider = AutoDisposeAsyncNotifierProvider<PositionsLiveNotifier, Map<int, Position>>(
  PositionsLiveNotifier.new,
);

class PositionsLiveNotifier extends AutoDisposeAsyncNotifier<Map<int, Position>> {
  StreamSubscription? _sub;
  final Map<int, Position> _latest = {};

  @override
  Future<Map<int, Position>> build() async {
    final socket = ref.read(traccarSocketServiceProvider);
    final conn = ref.watch(traccarConnectionStatusProvider);
    // Ensure devices list is loaded (for ID filtering if needed later)
    ref.watch(devicesNotifierProvider);

    ref.onDispose(() async {
      await _sub?.cancel();
      _sub = null;
    });

    final stream = socket.connect();
    _sub = stream.listen((msg) {
      // Avoid flicker during reconnects. Only apply updates when connected.
      if (conn != ConnectionStatus.connected) return;
      if (msg.type == 'positions' && msg.positions != null) {
        for (final p in msg.positions!) {
          _latest[p.deviceId] = p;
        }
        state = AsyncData(Map<int, Position>.unmodifiable(_latest));
      }
    });

    // Initial value
    return Map<int, Position>.unmodifiable(_latest);
  }
}
