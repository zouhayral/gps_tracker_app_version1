import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:my_app_gps/features/map/data/position_model.dart';
import 'package:my_app_gps/services/customer/customer_websocket.dart';

/// Provides a real-time map of device positions for the current customer
///
/// Listens to WebSocket position updates and maintains a map of the latest
/// position for each device.
///
/// Usage:
/// ```dart
/// final positions = ref.watch(customerDevicePositionsProvider).value;
/// if (positions != null) {
///   for (final deviceId in positions.keys) {
///     final position = positions[deviceId];
///     // Use position data
///   }
/// }
/// ```
final customerDevicePositionsProvider =
    StreamProvider.autoDispose<Map<int, Position>>((ref) async* {
  
  // 1. Watch the WebSocket stream
  final webSocketAsync = ref.watch(customerWebSocketProvider);
  
  if (!webSocketAsync.hasValue) return;

  // 2. Maintain a map of latest positions for each device
  final positions = <int, Position>{};

  // 3. Create a controller to process WebSocket messages
  final controller = StreamController<CustomerWebSocketMessage>();

  // 4. Listen to WebSocket and forward messages to controller
  ref.listen<AsyncValue<CustomerWebSocketMessage>>(
    customerWebSocketProvider,
    (previous, next) {
      next.whenData(controller.add);
    },
  );

  ref.onDispose(controller.close);

  // 5. Process messages and update positions map
  await for (final message in controller.stream) {
    if (message is CustomerPositionsMessage) {
      for (final position in message.positions) {
        positions[position.deviceId] = position;
      }

      // 6. Yield updated map - THIS TRIGGERS UI REBUILD
      yield Map.unmodifiable(positions);
    }
  }
});

/// Get position for a specific device from the customer positions map
///
/// Usage:
/// ```dart
/// final position = ref.watch(customerDevicePositionProvider(deviceId));
/// ```
final customerDevicePositionProvider =
    Provider.autoDispose.family<Position?, int>((ref, deviceId) {
  final positions = ref.watch(customerDevicePositionsProvider).value;
  return positions?[deviceId];
});

/// Get all device IDs that have positions
///
/// Usage:
/// ```dart
/// final deviceIds = ref.watch(customerDeviceIdsProvider);
/// for (final id in deviceIds) {
///   // Process each device
/// }
/// ```
final customerDeviceIdsProvider =
    Provider.autoDispose<List<int>>((ref) {
  final positions = ref.watch(customerDevicePositionsProvider).value;
  return positions?.keys.toList() ?? [];
});

/// Get the number of devices with positions
///
/// Usage:
/// ```dart
/// final count = ref.watch(customerDeviceCountProvider);
/// print('Tracking $count devices');
/// ```
final customerDeviceCountProvider =
    Provider.autoDispose<int>((ref) {
  final positions = ref.watch(customerDevicePositionsProvider).value;
  return positions?.length ?? 0;
});
