import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:my_app_gps/features/dashboard/controller/devices_notifier.dart';
import 'package:my_app_gps/features/map/data/position_model.dart';
import 'package:my_app_gps/services/traccar_connection_provider.dart';
import 'package:my_app_gps/services/traccar_socket_service.dart';

/// Live positions via WebSocket: consumes Traccar /api/socket and maintains the latest map.
final positionsLiveProvider =
    AutoDisposeAsyncNotifierProvider<PositionsLiveNotifier, Map<int, Position>>(
      PositionsLiveNotifier.new,
    );

class PositionsLiveNotifier
    extends AutoDisposeAsyncNotifier<Map<int, Position>> {
  StreamSubscription<TraccarSocketMessage>? _sub;
  final Map<int, Position> _latest = {};
  Timer? _cacheTimer;

  @override
  Future<Map<int, Position>> build() async {
    if (kDebugMode) {
      // ignore: avoid_print
      print('[positionsLive] init: building provider');
    }
    // Keep the provider alive for a period after the last listener is removed.
    final keep = ref.keepAlive();
    // When the last listener is removed, Riverpod will call onCancel.
    // We start a 10-minute timer to postpone disposal.
    ref.onCancel(() {
      if (kDebugMode) {
        // ignore: avoid_print
        print('[positionsLive] onCancel: starting 10-minute cache timer');
      }
      _cacheTimer?.cancel();
      _cacheTimer = Timer(const Duration(minutes: 10), () {
        if (kDebugMode) {
          // ignore: avoid_print
          print('[positionsLive] cache timer elapsed: allowing disposal');
        }
        // Allow disposal by closing the keep-alive link.
        keep.close();
      });
    });
    // If a new listener subscribes while the timer is running, cancel the timer to keep the instance alive.
    ref.onResume(() {
      if (_cacheTimer != null) {
        if (kDebugMode) {
          // ignore: avoid_print
          print(
            '[positionsLive] onResume: cancelling cache timer (new subscriber)',
          );
        }
        _cacheTimer?.cancel();
        _cacheTimer = null;
      }
    });
    final socket = ref.read(traccarSocketServiceProvider);
    final conn = ref.watch(traccarConnectionStatusProvider);
    // Ensure devices list is loaded (for ID filtering if needed later)
    ref.watch(devicesNotifierProvider);

    ref.onDispose(() async {
      if (kDebugMode) {
        // ignore: avoid_print
        print('[positionsLive] dispose: cleaning up stream and timers');
      }
      await _sub?.cancel();
      _sub = null;
      _cacheTimer?.cancel();
      _cacheTimer = null;
    });

    final stream = socket.connect();
    _sub = stream.listen((TraccarSocketMessage msg) {
      if (kDebugMode) {
        // ignore: avoid_print
        print('[positionsLive] Socket message type=${msg.type}');
      }

      // Allow position updates during reconnecting/retrying - only block on initial connecting
      if (conn == ConnectionStatus.connecting) {
        if (kDebugMode) {
          // ignore: avoid_print
          print('[positionsLive] Skipping update - still connecting (status=$conn)');
        }
        return;
      }

      if (msg.type == 'positions' && msg.positions != null) {
        for (final p in msg.positions!) {
          _latest[p.deviceId] = p;
        }
        if (kDebugMode) {
          // ignore: avoid_print
          print(
            '[positionsLive] ✅ Received ${msg.positions!.length} positions, total cached=${_latest.length}',
          );
        }
        state = AsyncData(Map<int, Position>.unmodifiable(_latest));
      }
    });

    // Initial value
    return Map<int, Position>.unmodifiable(_latest);
  }
}
