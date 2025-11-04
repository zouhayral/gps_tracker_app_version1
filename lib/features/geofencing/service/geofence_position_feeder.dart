import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:my_app_gps/core/data/vehicle_data_repository.dart';
import 'package:my_app_gps/features/dashboard/controller/devices_notifier.dart';
import 'package:my_app_gps/features/geofencing/providers/geofence_providers.dart';
import 'package:my_app_gps/features/map/data/position_model.dart';

/// Service that automatically feeds position updates to the geofence monitor
/// 
/// This bridges the gap between VehicleDataRepository (which provides position updates)
/// and GeofenceMonitorService (which needs positions to evaluate geofence transitions).
/// 
/// **Architecture**:
/// - Subscribes to per-device position streams from VehicleDataRepository
/// - Forwards positions to GeofenceMonitorService.processPosition()
/// - Dynamically adds/removes subscriptions as devices appear/disappear
/// - Only active when geofence monitoring is enabled
/// 
/// **Lifecycle**:
/// - Auto-starts when geofenceMonitorProvider is active
/// - Auto-stops when provider is disposed or monitoring stops
class GeofencePositionFeeder {
  final Ref ref;
  
  /// Map of device ID to position stream subscription
  final Map<int, StreamSubscription<Position?>> _subscriptions = {};
  bool _isActive = false;

  GeofencePositionFeeder(this.ref);

  /// Start feeding positions to geofence monitor
  Future<void> start() async {
    if (_isActive) {
      debugPrint('[GeofencePositionFeeder] Already active, updating subscriptions');
      _updateSubscriptions();
      return;
    }

    debugPrint('[GeofencePositionFeeder] Starting position feed...');
    _isActive = true;

    try {
      _updateSubscriptions();
      debugPrint('[GeofencePositionFeeder] ✅ Position feed active');
    } catch (e) {
      debugPrint('[GeofencePositionFeeder] ❌ Failed to start: $e');
      _isActive = false;
      rethrow;
    }
  }

  /// Update subscriptions based on current device list
  void _updateSubscriptions() {
    if (!_isActive) return;

    final devicesAsync = ref.read(devicesNotifierProvider);
    
    // Only proceed if we have device data
    if (!devicesAsync.hasValue) {
      debugPrint('[GeofencePositionFeeder] No device data available yet');
      return;
    }

    final devices = devicesAsync.value!;
    final vehicleRepo = ref.read(vehicleDataRepositoryProvider);
    
    final currentDeviceIds = devices
        .map((d) => d['id'] as int?)
        .whereType<int>()
        .toSet();
    final subscribedIds = _subscriptions.keys.toSet();

    // Remove subscriptions for devices that no longer exist
    final toRemove = subscribedIds.difference(currentDeviceIds);
    for (final deviceId in toRemove) {
      debugPrint('[GeofencePositionFeeder] Removing subscription for device $deviceId');
      _subscriptions[deviceId]?.cancel();
      _subscriptions.remove(deviceId);
    }

    // Add subscriptions for new devices
    final toAdd = currentDeviceIds.difference(subscribedIds);
    for (final deviceId in toAdd) {
      final device = devices.firstWhere((d) => d['id'] == deviceId);
      final deviceName = device['name'] as String? ?? 'Device $deviceId';
      debugPrint('[GeofencePositionFeeder] Adding subscription for device: $deviceName ($deviceId)');
      
      _subscriptions[deviceId] = vehicleRepo.positionStream(deviceId).listen(
        (Position? position) async {
          if (position == null) {
            debugPrint('[GeofencePositionFeeder] ⚠️ Received null position for device $deviceId');
            return;
          }
          
          if (!_isActive) {
            debugPrint('[GeofencePositionFeeder] ⚠️ Feeder not active, skipping position for device $deviceId');
            return;
          }

          // Get the monitor state
          final monitorState = ref.read(geofenceMonitorProvider);
          
          // Only process if monitoring is active
          if (!monitorState.isActive) {
            debugPrint('[GeofencePositionFeeder] ⚠️ Monitor not active, skipping position for device $deviceId');
            return;
          }

          // Log position received
          debugPrint('[GeofencePositionFeeder] 📍 Position received for device $deviceId: (${position.latitude}, ${position.longitude})');

          // Get the monitor controller to process positions
          final monitorController = ref.read(geofenceMonitorProvider.notifier);

          try {
            await monitorController.processPosition(position);
            debugPrint('[GeofencePositionFeeder] ✅ Position processed for device $deviceId');
          } catch (e) {
            debugPrint('[GeofencePositionFeeder] ❌ Error processing position for device $deviceId: $e');
          }
        },
        onError: (Object error) {
          debugPrint('[GeofencePositionFeeder] ❌ Position stream error for device $deviceId: $error');
        },
      );
    }

    if (toAdd.isNotEmpty || toRemove.isNotEmpty) {
      debugPrint(
        '[GeofencePositionFeeder] Updated subscriptions: ${_subscriptions.length} active (added: ${toAdd.length}, removed: ${toRemove.length})',
      );
    }
  }

  /// Stop feeding positions
  Future<void> stop() async {
    if (!_isActive) return;

    debugPrint('[GeofencePositionFeeder] Stopping position feed...');
    _isActive = false;

    for (final subscription in _subscriptions.values) {
      await subscription.cancel();
    }
    _subscriptions.clear();

    debugPrint('[GeofencePositionFeeder] ✅ Position feed stopped');
  }

  /// Dispose and clean up resources
  void dispose() {
    stop();
  }
}

/// Provider for GeofencePositionFeeder
/// 
/// Automatically starts feeding positions when the geofence monitor is active.
/// Also watches for device list changes and updates subscriptions accordingly.
/// 
/// **Usage**: This provider is automatically initialized by the app.
/// No manual interaction needed - it works in the background.
final geofencePositionFeederProvider = Provider.autoDispose<GeofencePositionFeeder>((ref) {
  final feeder = GeofencePositionFeeder(ref);

  // Watch monitor state and start/stop feeder accordingly
  ref.listen<GeofenceMonitorState>(
    geofenceMonitorProvider,
    (previous, next) {
      if (next.isActive && !feeder._isActive) {
        // Monitor activated - start feeding positions
        feeder.start();
        debugPrint('[GeofencePositionFeederProvider] Started feeding (monitor active)');
      } else if (!next.isActive && feeder._isActive) {
        // Monitor deactivated - stop feeding positions
        feeder.stop();
        debugPrint('[GeofencePositionFeederProvider] Stopped feeding (monitor inactive)');
      }
    },
  );

  // Watch device list changes and update subscriptions
  ref.listen<AsyncValue<List<Map<String, dynamic>>>>(
    devicesNotifierProvider,
    (previous, next) {
      if (feeder._isActive && next.hasValue) {
        debugPrint('[GeofencePositionFeederProvider] Device list changed, updating subscriptions');
        feeder._updateSubscriptions();
      }
    },
  );

  // Check initial state
  final initialState = ref.read(geofenceMonitorProvider);
  if (initialState.isActive) {
    // Start immediately if monitor is already active
    Future.microtask(() => feeder.start());
  }

  // Cleanup on dispose
  ref.onDispose(() {
    debugPrint('[GeofencePositionFeederProvider] Disposing feeder');
    feeder.dispose();
  });

  return feeder;
});


