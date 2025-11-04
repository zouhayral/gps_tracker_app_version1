import 'dart:async';

import 'package:my_app_gps/core/data/vehicle_data_snapshot.dart';
import 'package:my_app_gps/core/utils/app_logger.dart';
import 'package:my_app_gps/features/map/data/position_model.dart';
import 'package:my_app_gps/services/device_service.dart';
import 'package:my_app_gps/services/positions_service.dart';

/// Service responsible for network API operations.
/// 
/// **Responsibilities:**
/// - REST API polling and fetching
/// - Device and position data retrieval
/// - Parallel fetching for multiple devices
/// - Memoization/throttling of API calls
/// - Fallback polling when WebSocket disconnected
/// 
/// **Extracted from:** VehicleDataRepository (lines ~950-1150, ~1090-1140)
class VehicleDataNetworkService {
  static final _log = 'VehicleNetworkSvc'.logger;

  VehicleDataNetworkService({
    required this.deviceService,
    required this.positionsService,
  });

  final DeviceService deviceService;
  final PositionsService positionsService;

  // Callbacks for delegation (set by repository after construction)
  void Function(List<int>)? onRefreshMultiple;

  // Memoization: Track last fetch time to prevent redundant calls
  final Map<int, DateTime> _lastFetchTime = {};

  // Connection state flags
  bool _isOffline = false;
  bool _isDisposed = false;

  // REST fallback timer
  Timer? _fallbackTimer;

  static const _minFetchInterval = Duration(seconds: 5);
  static const _restFallbackInterval = Duration(seconds: 10);

  // Test-mode flag to disable background timers in widget tests
  static bool testMode = false;

  /// Set offline state
  void setOffline({required bool offline}) {
    _isOffline = offline;
    _log.debug('Offline mode: ${offline ? 'ON' : 'OFF'}');
  }

  /// Fetch a single device by ID and return snapshot
  /// Callback is invoked to update device name cache
  Future<VehicleDataSnapshot?> fetchDeviceData(
    int deviceId, {
    required void Function(Map<String, dynamic>) onDeviceCached,
  }) async {
    if (_isOffline) {
      _log.debug('Offline → skip fetch for device $deviceId');
      return null;
    }

    final lastFetch = _lastFetchTime[deviceId];
    if (lastFetch != null &&
        DateTime.now().difference(lastFetch) < _minFetchInterval) {
      _log.debug('Skipping fetch for device $deviceId (fetched recently)');
      return null;
    }

    _lastFetchTime[deviceId] = DateTime.now();

    try {
      // Fetch device info
      final devices = await deviceService.fetchDevices();
      
      // Cache all device names from this call
      for (final d in devices) {
        onDeviceCached(d);
      }

      final device = devices.firstWhere(
        (d) => d['id'] == deviceId,
        orElse: () => <String, dynamic>{},
      );

      if (device.isEmpty) {
        _log.debug('Device $deviceId not found');
        return null;
      }

      // Fetch position using positionId or fallback
      final posId = device['positionId'];
      Position? position;

      if (posId is int) {
        position = await positionsService.latestByPositionId(posId);
      }

      // Fallback: fetch recent history if no positionId
      if (position == null) {
        final recent = await positionsService.fetchLatestPositions(
          deviceIds: [deviceId],
        );
        if (recent.isNotEmpty) {
          position = recent.first;
        }
      }

      if (position != null) {
        var snapshot = VehicleDataSnapshot.fromPosition(position);
        
        // Overlay engine state from device attributes if present
        final devAttrs = (device['attributes'] is Map)
            ? Map<String, dynamic>.from(device['attributes'] as Map)
            : const <String, dynamic>{};
        final ign = devAttrs['ignition'];
        EngineState? engineState;
        if (ign is bool) {
          engineState = ign ? EngineState.on : EngineState.off;
        } else if (devAttrs['motion'] is bool && devAttrs['motion'] == true) {
          engineState = EngineState.on;
        }
        
        if (engineState != null && engineState != snapshot.engineState) {
          snapshot = VehicleDataSnapshot(
            deviceId: snapshot.deviceId,
            timestamp: snapshot.timestamp.add(const Duration(milliseconds: 1)),
            position: snapshot.position,
            engineState: engineState,
            speed: snapshot.speed,
            distance: snapshot.distance,
            lastUpdate: snapshot.lastUpdate,
            batteryLevel: snapshot.batteryLevel,
            fuelLevel: snapshot.fuelLevel,
          );
          _log.debug('Overlayed engine from device attrs for $deviceId -> $engineState');
        }
        
        return snapshot;
      }
    } catch (e) {
      _log.error('Fetch error for device $deviceId', error: e);
    }
    
    return null;
  }

  /// Parallel fetch for multiple devices
  Future<Map<int, VehicleDataSnapshot>> fetchMultipleDevices(
    List<int> deviceIds, {
    required void Function(Map<String, dynamic>) onDeviceCached,
  }) async {
    final results = <int, VehicleDataSnapshot>{};
    
    if (deviceIds.isEmpty) return results;
    if (_isOffline) {
      _log.debug('Offline → skip parallel fetch for ${deviceIds.length} devices');
      return results;
    }

    try {
      _log.debug('Fetching ${deviceIds.length} devices in parallel');

      // Fetch all devices
      final devices = await deviceService.fetchDevices();
      final deviceMap = {for (final d in devices) d['id']: d};

      // Fetch positions using latestForDevices (already optimized)
      final deviceList = deviceIds
          .where(deviceMap.containsKey)
          .map((id) => deviceMap[id]!)
          .toList();

      // Update device name cache from fetched devices
      for (final d in deviceList) {
        onDeviceCached(d);
      }

      final positions = await positionsService.latestForDevices(deviceList);

      // Create snapshots
      for (final entry in positions.entries) {
        results[entry.key] = VehicleDataSnapshot.fromPosition(entry.value);
      }

      _log.debug('✅ Fetched ${positions.length} positions');
    } catch (e) {
      _log.error('Parallel fetch error', error: e);
    }
    
    return results;
  }

  /// Start REST polling fallback (only when WebSocket disconnected)
  void startFallbackPolling({
    required bool Function() isWebSocketConnected,
    required bool Function() shouldSuppressFallback,
    required Future<void> Function(List<int>) onRefreshMultiple,
    required List<int> Function() getActiveDeviceIds,
  }) {
    if (testMode) return;
    
    _fallbackTimer?.cancel();
    _fallbackTimer = Timer.periodic(_restFallbackInterval, (_) async {
      if (_isDisposed) {
        _log.debug('🧩 Fallback tick skipped: service disposed');
        return;
      }
      if (_isOffline) {
        _log.debug('Offline → skipping REST fallback tick');
        return;
      }
      
      // Suppress fallback if WebSocket just reconnected
      if (shouldSuppressFallback()) {
        _log.debug('[FALLBACK-SUPPRESS] ✋ Skipping REST fallback - WS just reconnected');
        return;
      }
      
      if (!isWebSocketConnected()) {
        final deviceIds = getActiveDeviceIds();
        if (deviceIds.isNotEmpty) {
          _log.debug('WebSocket disconnected, using REST fallback');
          await onRefreshMultiple(deviceIds);
        }
      }
    });
    
    _log.debug('🔄 Fallback polling started (every ${_restFallbackInterval.inSeconds}s)');
  }

  /// Stop fallback polling
  void stopFallbackPolling() {
    _fallbackTimer?.cancel();
    _fallbackTimer = null;
    _log.debug('🔄 Fallback polling stopped');
  }

  /// Clear memoization for a device (force refresh)
  void clearFetchMemoization(int deviceId) {
    _lastFetchTime.remove(deviceId);
  }

  /// Clear all memoization (force refresh all)
  void clearAllFetchMemoization() {
    _lastFetchTime.clear();
  }

  /// Dispose resources
  void dispose() {
    if (_isDisposed) return;
    _isDisposed = true;

    _fallbackTimer?.cancel();
    _log.debug('Network service disposed');
  }
}
