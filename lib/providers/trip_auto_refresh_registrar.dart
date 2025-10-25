import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:my_app_gps/providers/trip_providers.dart';
import 'package:my_app_gps/services/customer/customer_websocket.dart';

/// Debounces WebSocket reconnect-like events and triggers a silent trips refresh.
final tripAutoRefreshRegistrarProvider =
    Provider.family<void, int>((ref, deviceId) {
  Timer? debounce;

  final subscription = ref.listen<AsyncValue<CustomerWebSocketMessage>>(
    customerWebSocketProvider,
    (_, next) {
      next.whenData((msg) {
        if (msg is! CustomerConnectedMessage) {
          return;
        }
        debounce?.cancel();
        debounce = Timer(const Duration(seconds: 2), () {
          if (kDebugMode) {
            debugPrint('[TripProviders] Auto-refresh triggered by WS reconnect');
          }
          ref.read(tripListProvider(deviceId).notifier).refresh();
        });
      });
    },
  );

  ref.onDispose(() {
    debounce?.cancel();
    subscription.close();
  });
});
// EOF

