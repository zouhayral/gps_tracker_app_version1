import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:my_app_gps/core/data/vehicle_data_repository.dart';
import 'package:my_app_gps/core/data/vehicle_data_snapshot.dart';
import 'package:my_app_gps/features/map/data/position_model.dart';

/// Granular providers for vehicle metrics.
/// Each provider listens to the repository and rebuilds only when its specific data changes.
/// This prevents unnecessary rebuilds when other metrics update.

/// Provider for a device's complete snapshot
final vehicleSnapshotProvider = Provider.family<ValueListenable<VehicleDataSnapshot?>, int>((ref, deviceId) {
  final repo = ref.watch(vehicleDataRepositoryProvider);
  return repo.getNotifier(deviceId);
});

/// Provider for a device's position
/// IMPORTANT: Uses StreamProvider to properly listen to ValueNotifier changes!
final vehiclePositionProvider = StreamProvider.family<Position?, int>((ref, deviceId) async* {
  final notifier = ref.watch(vehicleSnapshotProvider(deviceId));
  
  // Emit initial value
  yield notifier.value?.position;
  
  if (kDebugMode && notifier.value?.position != null) {
    debugPrint('[VehicleProvider] Initial position for device $deviceId: '
        'lat=${notifier.value!.position!.latitude}, lon=${notifier.value!.position!.longitude}, '
        'ignition=${notifier.value!.position!.attributes['ignition']}, speed=${notifier.value!.position!.speed}');
  }
  
  // Listen to ValueNotifier changes
  final streamController = StreamController<Position?>();
  void listener() {
    final position = notifier.value?.position;
    if (kDebugMode && position != null) {
      debugPrint('[VehicleProvider] 🔄 Position updated for device $deviceId: '
          'lat=${position.latitude}, lon=${position.longitude}, '
          'ignition=${position.attributes['ignition']}, speed=${position.speed}');
    }
    streamController.add(position);
  }
  
  notifier.addListener(listener);
  ref.onDispose(() {
    streamController.close();
    notifier.removeListener(listener);
  });
  
  // Emit updates from the stream
  await for (final position in streamController.stream) {
    yield position;
  }
});

/// Provider for a device's engine state
/// IMPORTANT: Uses StreamProvider to properly listen to ValueNotifier changes!
final vehicleEngineProvider = StreamProvider.family<EngineState?, int>((ref, deviceId) async* {
  final notifier = ref.watch(vehicleSnapshotProvider(deviceId));
  
  // Emit initial value
  yield notifier.value?.engineState;
  
  if (kDebugMode) {
    debugPrint('[VehicleProvider] Initial engine state for device $deviceId: ${notifier.value?.engineState}');
  }
  
  // Listen to ValueNotifier changes
  final streamController = StreamController<EngineState?>();
  void listener() {
    final engineState = notifier.value?.engineState;
    if (kDebugMode) {
      debugPrint('[VehicleProvider] 🔄 Engine state updated for device $deviceId: $engineState');
    }
    streamController.add(engineState);
  }
  
  notifier.addListener(listener);
  ref.onDispose(() {
    streamController.close();
    notifier.removeListener(listener);
  });
  
  // Emit updates from the stream
  await for (final engineState in streamController.stream) {
    yield engineState;
  }
});

/// Provider for a device's speed (km/h)
final vehicleSpeedProvider = Provider.family<double?, int>((ref, deviceId) {
  final notifier = ref.watch(vehicleSnapshotProvider(deviceId));
  return notifier.value?.speed;
});

/// Provider for a device's distance (km)
final vehicleDistanceProvider = Provider.family<double?, int>((ref, deviceId) {
  final notifier = ref.watch(vehicleSnapshotProvider(deviceId));
  return notifier.value?.distance;
});

/// Provider for a device's last update time
final vehicleLastUpdateProvider = Provider.family<DateTime?, int>((ref, deviceId) {
  final notifier = ref.watch(vehicleSnapshotProvider(deviceId));
  return notifier.value?.lastUpdate;
});

/// Provider for a device's battery level
final vehicleBatteryProvider = Provider.family<double?, int>((ref, deviceId) {
  final notifier = ref.watch(vehicleSnapshotProvider(deviceId));
  return notifier.value?.batteryLevel;
});

/// Provider for a device's fuel level
final vehicleFuelProvider = Provider.family<double?, int>((ref, deviceId) {
  final notifier = ref.watch(vehicleSnapshotProvider(deviceId));
  return notifier.value?.fuelLevel;
});

/// Helper extension to easily watch specific metrics in widgets
extension VehicleDataX on WidgetRef {
  /// Watch a device's position and rebuild only when it changes
  /// Returns null if loading or on error
  Position? watchPosition(int deviceId) => watch(vehiclePositionProvider(deviceId)).valueOrNull;
  
  /// Watch a device's engine state and rebuild only when it changes
  /// Returns null if loading or on error
  EngineState? watchEngine(int deviceId) => watch(vehicleEngineProvider(deviceId)).valueOrNull;
  
  /// Watch a device's speed and rebuild only when it changes
  double? watchSpeed(int deviceId) => watch(vehicleSpeedProvider(deviceId));
  
  /// Watch a device's distance and rebuild only when it changes
  double? watchDistance(int deviceId) => watch(vehicleDistanceProvider(deviceId));
  
  /// Read snapshot notifier without watching (for manual listening)
  ValueListenable<VehicleDataSnapshot?> readSnapshot(int deviceId) {
    return read(vehicleSnapshotProvider(deviceId));
  }
}

/// StreamProvider variant for UI that needs to rebuild on every update
final vehicleSnapshotStreamProvider = StreamProvider.family<VehicleDataSnapshot?, int>((ref, deviceId) async* {
  final notifier = ref.watch(vehicleSnapshotProvider(deviceId));
  
  // Emit initial value
  yield notifier.value;
  
  // Listen to changes and emit
  void listener() {
    // Note: This will be called on next frame after value changes
  }
  
  notifier.addListener(listener);
  ref.onDispose(() => notifier.removeListener(listener));
  
  // Keep emitting current value periodically to detect changes
  await for (final _ in Stream<void>.periodic(const Duration(milliseconds: 100))) {
    yield notifier.value;
  }
});
