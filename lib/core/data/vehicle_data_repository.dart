import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:my_app_gps/core/data/vehicle_data_cache.dart';
import 'package:my_app_gps/core/data/vehicle_data_snapshot.dart';
import 'package:my_app_gps/features/map/data/position_model.dart';
import 'package:my_app_gps/services/device_service.dart';
import 'package:my_app_gps/services/positions_service.dart';
import 'package:my_app_gps/services/traccar_socket_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Provider for the vehicle data repository singleton
final vehicleDataRepositoryProvider = Provider<VehicleDataRepository>((ref) {
  final cache = ref.watch(vehicleDataCacheProvider);
  final devSvc = ref.watch(deviceServiceProvider);
  final posSvc = ref.watch(positionsServiceProvider);
  final socketSvc = ref.watch(traccarSocketServiceProvider);

  final repo = VehicleDataRepository(
    cache: cache,
    deviceService: devSvc,
    positionsService: posSvc,
    socketService: socketSvc,
  );

  ref.onDispose(repo.dispose);
  return repo;
});

/// Provider for cache (requires SharedPreferences) - PUBLIC for override in main
final vehicleDataCacheProvider = Provider<VehicleDataCache>((ref) {
  final prefs = ref.watch(sharedPreferencesProvider);
  return VehicleDataCache(prefs: prefs);
});

/// Provider for SharedPreferences (async init) - PUBLIC for override in main
final sharedPreferencesProvider = Provider<SharedPreferences>((ref) {
  throw UnimplementedError('SharedPreferences must be overridden in main.dart');
});

/// Centralized repository for vehicle data.
/// 
/// Architecture:
/// - Merges REST API + WebSocket updates
/// - Maintains in-memory + disk cache
/// - Exposes per-device ValueNotifiers
/// - Implements parallel fetch and fallback strategies
/// - Debounces/throttles updates to prevent UI flooding
class VehicleDataRepository {
  VehicleDataRepository({
    required this.cache,
    required this.deviceService,
    required this.positionsService,
    required this.socketService,
  }) {
    _init();
  }

  final VehicleDataCache cache;
  final DeviceService deviceService;
  final PositionsService positionsService;
  final TraccarSocketService socketService;

  // Per-device notifiers
  final Map<int, ValueNotifier<VehicleDataSnapshot?>> _notifiers = {};

  // Debounce timers for each device
  final Map<int, Timer> _debounceTimers = {};

  // Memoization: Track last fetch time to prevent redundant calls
  final Map<int, DateTime> _lastFetchTime = {};

  // WebSocket subscription
  StreamSubscription<TraccarSocketMessage>? _socketSub;

  // REST fallback timer
  Timer? _fallbackTimer;

  // Connection state
  bool _isWebSocketConnected = false;

  static const _debounceDelay = Duration(milliseconds: 300);
  static const _minFetchInterval = Duration(seconds: 5);
  static const _restFallbackInterval = Duration(seconds: 10);

  void _init() {
    // Pre-warm cache: Load all cached snapshots into notifiers for instant startup
    _prewarmCache();

    // Subscribe to WebSocket updates (connect returns a stream)
    _socketSub = socketService.connect().listen(_handleSocketMessage);

    // Start REST fallback timer
    _startFallbackPolling();

    if (kDebugMode) {
      debugPrint('[VehicleRepo] Initialized');
    }
  }

  /// Pre-warm cache by loading all cached snapshots into notifiers
  /// This ensures instant marker rendering on app startup
  void _prewarmCache() {
    try {
      final allCached = cache.loadAll();
      
      if (allCached.isEmpty) {
        if (kDebugMode) {
          debugPrint('[VehicleRepo] No cached data to prewarm');
        }
        return;
      }

      for (final entry in allCached.entries) {
        final deviceId = entry.key;
        final snapshot = entry.value;
        
        // Create notifier with cached value
        _notifiers[deviceId] = ValueNotifier<VehicleDataSnapshot?>(snapshot);
      }

      if (kDebugMode) {
        debugPrint('[VehicleRepo] ✅ Pre-warmed cache with ${allCached.length} devices');
      }
    } catch (e) {
      if (kDebugMode) {
        debugPrint('[VehicleRepo] Cache pre-warm error: $e');
      }
    }
  }

  /// Handle incoming WebSocket messages
  void _handleSocketMessage(TraccarSocketMessage msg) {
    if (msg.type == 'connected') {
      _isWebSocketConnected = true;
      if (kDebugMode) {
        debugPrint('[VehicleRepo] WebSocket connected');
      }
    } else if (msg.type == 'positions' && msg.positions != null) {
      _handlePositionUpdates(msg.positions!);
    }
  }

  /// Process position updates (from WebSocket or REST)
  void _handlePositionUpdates(List<Position> positions) {
    if (positions.isEmpty) return;

    for (final pos in positions) {
      final snapshot = VehicleDataSnapshot.fromPosition(pos);

      // Debounce: Delay emitting to notifier to avoid flooding
      _debounceTimers[pos.deviceId]?.cancel();
      _debounceTimers[pos.deviceId] = Timer(_debounceDelay, () {
        _updateDeviceSnapshot(snapshot);
      });
    }

    if (kDebugMode) {
      debugPrint('[VehicleRepo] Processed ${positions.length} position updates');
    }
  }

  /// Update cache and notify listeners for a device
  void _updateDeviceSnapshot(VehicleDataSnapshot snapshot) {
    // Update cache
    cache.put(snapshot);

    // Notify listeners
    final notifier = _notifiers[snapshot.deviceId];
    if (notifier != null) {
      final existing = notifier.value;
      notifier.value = existing?.merge(snapshot) ?? snapshot;
    }
  }

  /// Get or create a ValueNotifier for a device
  ValueNotifier<VehicleDataSnapshot?> getNotifier(int deviceId) {
    return _notifiers.putIfAbsent(deviceId, () {
      // Try to load from cache immediately
      final cached = cache.get(deviceId);
      final notifier = ValueNotifier<VehicleDataSnapshot?>(cached);

      // If cache miss, trigger a fetch
      if (cached == null) {
        _fetchDeviceData(deviceId);
      }

      return notifier;
    });
  }

  /// Fetch data for a single device (with memoization to prevent redundant calls)
  Future<void> _fetchDeviceData(int deviceId) async {
    // Check if we fetched recently
    final lastFetch = _lastFetchTime[deviceId];
    if (lastFetch != null &&
        DateTime.now().difference(lastFetch) < _minFetchInterval) {
      if (kDebugMode) {
        debugPrint('[VehicleRepo] Skipping fetch for device $deviceId (fetched recently)');
      }
      return;
    }

    _lastFetchTime[deviceId] = DateTime.now();

    try {
      // Fetch device info
      final devices = await deviceService.fetchDevices();
      final device = devices.firstWhere(
        (d) => d['id'] == deviceId,
        orElse: () => <String, dynamic>{},
      );

      if (device.isEmpty) {
        if (kDebugMode) {
          debugPrint('[VehicleRepo] Device $deviceId not found');
        }
        return;
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
          fallbackMinutes: 30,
        );
        if (recent.isNotEmpty) {
          position = recent.first;
        }
      }

      if (position != null) {
        final snapshot = VehicleDataSnapshot.fromPosition(position);
        _updateDeviceSnapshot(snapshot);
      }
    } catch (e) {
      if (kDebugMode) {
        debugPrint('[VehicleRepo] Fetch error for device $deviceId: $e');
      }
    }
  }

  /// Parallel fetch for multiple devices (used on app start or WebSocket reconnect)
  Future<void> fetchMultipleDevices(List<int> deviceIds) async {
    if (deviceIds.isEmpty) return;

    try {
      if (kDebugMode) {
        debugPrint('[VehicleRepo] Fetching ${deviceIds.length} devices in parallel');
      }

      // Fetch all devices
      final devices = await deviceService.fetchDevices();
      final deviceMap = {for (var d in devices) d['id']: d};

      // Fetch positions using latestForDevices (already optimized)
      final deviceList = deviceIds
          .where((id) => deviceMap.containsKey(id))
          .map((id) => deviceMap[id]!)
          .toList();

      final positions = await positionsService.latestForDevices(deviceList);

      // Update cache and notifiers
      for (final entry in positions.entries) {
        final snapshot = VehicleDataSnapshot.fromPosition(entry.value);
        _updateDeviceSnapshot(snapshot);
      }

      if (kDebugMode) {
        debugPrint('[VehicleRepo] ✅ Fetched ${positions.length} positions');
      }
    } catch (e) {
      if (kDebugMode) {
        debugPrint('[VehicleRepo] Parallel fetch error: $e');
      }
    }
  }

  /// Start REST polling fallback (only when WebSocket disconnected)
  void _startFallbackPolling() {
    _fallbackTimer = Timer.periodic(_restFallbackInterval, (_) {
      if (!_isWebSocketConnected && _notifiers.isNotEmpty) {
        if (kDebugMode) {
          debugPrint('[VehicleRepo] WebSocket disconnected, using REST fallback');
        }
        final deviceIds = _notifiers.keys.toList();
        fetchMultipleDevices(deviceIds);
      }
    });
  }

  /// Manually refresh data for a device (used when user taps refresh)
  Future<void> refresh(int deviceId) async {
    _lastFetchTime.remove(deviceId); // Clear memoization
    await _fetchDeviceData(deviceId);
  }

  /// Refresh all active devices
  Future<void> refreshAll() async {
    _lastFetchTime.clear();
    await fetchMultipleDevices(_notifiers.keys.toList());
  }

  /// Get cache statistics for monitoring
  Map<String, dynamic> get cacheStats => cache.stats;

  /// Dispose resources
  void dispose() {
    _socketSub?.cancel();
    _fallbackTimer?.cancel();

    for (final timer in _debounceTimers.values) {
      timer.cancel();
    }
    _debounceTimers.clear();

    for (final notifier in _notifiers.values) {
      notifier.dispose();
    }
    _notifiers.clear();

    if (kDebugMode) {
      debugPrint('[VehicleRepo] Disposed');
    }
  }
}
