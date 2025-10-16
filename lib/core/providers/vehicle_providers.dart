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
final vehiclePositionProvider = Provider.family<Position?, int>((ref, deviceId) {
  final notifier = ref.watch(vehicleSnapshotProvider(deviceId));
  return notifier.value?.position;
});

/// Provider for a device's engine state
final vehicleEngineProvider = Provider.family<EngineState?, int>((ref, deviceId) {
  final notifier = ref.watch(vehicleSnapshotProvider(deviceId));
  return notifier.value?.engineState;
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
  Position? watchPosition(int deviceId) => watch(vehiclePositionProvider(deviceId));
  
  /// Watch a device's engine state and rebuild only when it changes
  EngineState? watchEngine(int deviceId) => watch(vehicleEngineProvider(deviceId));
  
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
