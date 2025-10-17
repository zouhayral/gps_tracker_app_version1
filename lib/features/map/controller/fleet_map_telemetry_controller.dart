import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:my_app_gps/core/data/vehicle_data_repository.dart';
import 'package:my_app_gps/services/device_service.dart';

/// State for Fleet Map Telemetry Controller
/// Holds devices and metadata for map/telemetry UI
class FMTCState {
  const FMTCState({
    required this.devices,
    required this.lastUpdated,
  });

  final List<Map<String, dynamic>> devices;
  final DateTime lastUpdated;

  FMTCState copyWith({
    List<Map<String, dynamic>>? devices,
    DateTime? lastUpdated,
  }) {
    return FMTCState(
      devices: devices ?? this.devices,
      lastUpdated: lastUpdated ?? this.lastUpdated,
    );
  }
}

/// Fleet Map Telemetry Controller - async-first, lightweight, non-blocking
///
/// Features:
/// - Loads devices asynchronously without blocking UI
/// - Manages loading/error/data states via AsyncNotifier
/// - Integrates with VehicleDataRepository for live telemetry
/// - Provides refresh capability for manual updates
class FleetMapTelemetryController extends AsyncNotifier<FMTCState> {
  @override
  Future<FMTCState> build() async {
    final stopwatch = Stopwatch()..start();
    if (kDebugMode) {
      debugPrint('[FMTC] Building state...');
    }

    final deviceService = ref.watch(deviceServiceProvider);
    final repo = ref.watch(vehicleDataRepositoryProvider);

    try {
      // Fetch devices asynchronously (non-blocking)
      final devices = await deviceService.fetchDevices();

      if (kDebugMode) {
        debugPrint(
          '[FMTC] ✅ Loaded ${devices.length} devices in ${stopwatch.elapsedMilliseconds}ms',
        );
      }

      // Trigger repository to fetch positions for all devices in parallel
      // (fire-and-forget, repository will update notifiers asynchronously)
      final deviceIds =
          devices.map((d) => d['id'] as int).where((id) => id > 0).toList();
      if (deviceIds.isNotEmpty) {
        // Don't await - let repository handle this in background
        repo.fetchMultipleDevices(deviceIds);
        if (kDebugMode) {
          debugPrint(
            '[FMTC] Triggered position fetch for ${deviceIds.length} devices',
          );
        }
      }

      return FMTCState(
        devices: devices,
        lastUpdated: DateTime.now(),
      );
    } catch (e, st) {
      if (kDebugMode) {
        debugPrint('[FMTC] ❌ Error loading devices: $e');
      }
      // Re-throw to let AsyncNotifier handle error state
      Error.throwWithStackTrace(e, st);
    }
  }

  /// Manually refresh devices and trigger telemetry update
  Future<void> refreshDevices() async {
    if (kDebugMode) {
      debugPrint('[FMTC] Manual refresh requested');
    }

    state = const AsyncLoading();

    state = await AsyncValue.guard(() async {
      final deviceService = ref.read(deviceServiceProvider);
      final repo = ref.read(vehicleDataRepositoryProvider);

      final devices = await deviceService.fetchDevices();

      // Trigger position refresh
      final deviceIds =
          devices.map((d) => d['id'] as int).where((id) => id > 0).toList();
      if (deviceIds.isNotEmpty) {
        await repo.fetchMultipleDevices(deviceIds);
      }

      if (kDebugMode) {
        debugPrint('[FMTC] ✅ Refresh complete: ${devices.length} devices');
      }

      return FMTCState(
        devices: devices,
        lastUpdated: DateTime.now(),
      );
    });
  }

  /// Clear state (useful for logout/user switch)
  void clear() {
    if (kDebugMode) {
      debugPrint('[FMTC] State cleared');
    }
    state = const AsyncLoading();
  }
}

/// Provider for Fleet Map Telemetry Controller
///
/// Usage in UI:
/// ```dart
/// final fmState = ref.watch(fleetMapTelemetryControllerProvider);
///
/// return fmState.when(
///   data: (state) => MapWidget(devices: state.devices),
///   loading: () => const Center(child: CircularProgressIndicator()),
///   error: (e, _) => ErrorWidget('Failed: $e'),
/// );
/// ```
final fleetMapTelemetryControllerProvider =
    AsyncNotifierProvider<FleetMapTelemetryController, FMTCState>(
  FleetMapTelemetryController.new,
);
