import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:my_app_gps/core/data/vehicle_data_cache.dart';
import 'package:my_app_gps/core/data/vehicle_data_snapshot.dart';
import 'package:my_app_gps/core/database/dao/telemetry_dao.dart';
import 'package:my_app_gps/core/database/entities/telemetry_record.dart';
import 'package:my_app_gps/core/utils/shared_prefs_holder.dart';
import 'package:my_app_gps/features/map/data/position_model.dart';
import 'package:my_app_gps/providers/connectivity_provider.dart';
import 'package:my_app_gps/services/device_service.dart';
import 'package:my_app_gps/services/positions_service.dart';
import 'package:my_app_gps/services/traccar_socket_service.dart';
import 'package:my_app_gps/services/websocket_manager_enhanced.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Provider for cache (requires SharedPreferences) - PUBLIC for override in main
final vehicleDataCacheProvider = Provider<VehicleDataCache>((ref) {
  final prefs = ref.watch(sharedPreferencesProvider);
  return VehicleDataCache(prefs: prefs);
});

/// Provider for SharedPreferences (async init) - PUBLIC for override in main
final sharedPreferencesProvider = Provider<SharedPreferences>((ref) {
  final fromHolder = SharedPrefsHolder.instance;
  if (fromHolder != null) return fromHolder;
  throw UnimplementedError('SharedPreferences must be overridden in main.dart');
});

/// Provider for the vehicle data repository singleton
final vehicleDataRepositoryProvider = Provider<VehicleDataRepository>((ref) {
  final cache = ref.watch(vehicleDataCacheProvider);
  final devSvc = ref.watch(deviceServiceProvider);
  final posSvc = ref.watch(positionsServiceProvider);
  final socketSvc = ref.watch(traccarSocketServiceProvider);
  final telemetryDao = ref.watch(telemetryDaoProvider);

  final repo = VehicleDataRepository(
    cache: cache,
    deviceService: devSvc,
    positionsService: posSvc,
    socketService: socketSvc,
    telemetryDao: telemetryDao,
  );

  // Listen to unified connectivity and update repository/WS behavior
  ref.listen(connectivityProvider, (previous, next) {
    // Update repository offline flag to guard REST calls and timers
    repo.setOffline(next.isOffline);

    // Auto-manage WebSocket lifecycle to prevent retry spam when offline
    final wsManager = ref.read(webSocketManagerProvider.notifier);
    if (next.isOffline) {
      wsManager.suspend();
    } else {
      wsManager.resume();
      // Kick a refresh on reconnect (best-effort)
      repo.refreshAll();
    }
  });

  ref.onDispose(repo.dispose);
  return repo;
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
    required this.telemetryDao,
  }) {
    _init();
  }

  final VehicleDataCache cache;
  final DeviceService deviceService;
  final PositionsService positionsService;
  final TraccarSocketService socketService;
  final TelemetryDaoBase telemetryDao;

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

  // Connection state flags
  bool _isWebSocketConnected = false;
  bool _isOffline = false; // unified offline flag (network or backend)

  static const _debounceDelay = Duration(milliseconds: 300);
  static const _minFetchInterval = Duration(seconds: 5);
  static const _restFallbackInterval = Duration(seconds: 10);

  // Test-mode flag to disable background timers in widget tests
  // Set from test setup: VehicleDataRepository.testMode = true;
  static bool testMode = false;

  void _init() {
    // Pre-warm cache synchronously (safe - only reads SharedPreferences)
    _prewarmCache();

    // Fire-and-forget: apply telemetry retention policy (30 days) on startup
    unawaited(_applyTelemetryRetention());

    // Defer WebSocket subscription to after provider initialization completes
    Future.microtask(() {
      // Subscribe to WebSocket updates (connect returns a stream)
      _socketSub = socketService.connect().listen(_handleSocketMessage);

      // Start REST fallback timer (disabled in tests)
      if (!VehicleDataRepository.testMode) {
        _startFallbackPolling();
      } else if (kDebugMode) {
        debugPrint('[VehicleRepo][TEST] Skipping REST fallback timer');
      }

      if (kDebugMode) {
        debugPrint('[VehicleRepo] Initialized with deferred WebSocket connection');
      }
    });
  }

  /// Update offline state from connectivity provider
  void setOffline(bool offline) {
    if (_isOffline == offline) return;
    _isOffline = offline;
    if (kDebugMode) {
      debugPrint('[VehicleRepo] Connectivity changed → offline=$_isOffline');
    }
    if (_isOffline) {
      _fallbackTimer?.cancel();
    } else {
      if (!VehicleDataRepository.testMode) {
        _startFallbackPolling();
      }
    }
  }

  /// Deletes telemetry records older than 30 days.
  Future<void> _applyTelemetryRetention() async {
    try {
      final cutoff = DateTime.now().toUtc().subtract(const Duration(days: 30));
      await telemetryDao.deleteOlderThan(cutoff);
      if (kDebugMode) {
        debugPrint('[VehicleRepo] Telemetry retention applied. Cutoff: $cutoff');
      }
    } catch (e) {
      if (kDebugMode) {
        debugPrint('[VehicleRepo] Telemetry retention failed: $e');
      }
    }
  }

  /// Pre-warm cache by loading all cached snapshots into notifiers
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
  Future<void> _handleSocketMessage(TraccarSocketMessage msg) async {
    if (msg.type == 'connected') {
      _isWebSocketConnected = true;
      if (kDebugMode) {
        debugPrint('[VehicleRepo] WebSocket connected');
      }
      return;
    }

    // Standard positions payload (fast path)
    if (msg.type == 'positions' && msg.positions != null) {
      _handlePositionUpdates(msg.positions!);
      return;
    }

    // Events payload: may include positionId or deviceId and attributes (e.g., ignition)
    if (msg.type == 'events' && msg.payload != null) {
      try {
        if (kDebugMode) {
          debugPrint('[VehicleRepo][WS] events payload: ${msg.payload}');
        }
        final payload = msg.payload;
        final events =
            payload is List ? List<dynamic>.from(payload) : <dynamic>[payload];
        for (final e in events) {
          if (e is Map<String, dynamic>) {
            final posId = e['positionId'] as int?;
            final deviceId = e['deviceId'] as int?;
            if (kDebugMode) {
              debugPrint('[VehicleRepo][WS] event for deviceId=$deviceId posId=$posId');
            }
            // If event contains a positionId, fetch that position (likely contains attributes)
            if (posId != null) {
              try {
                final p = await positionsService.latestByPositionId(posId);
                if (p != null) {
                  if (kDebugMode) {
                    debugPrint('[VehicleRepo][WS] fetched Position for posId=$posId -> device=${p.deviceId}');
                  }
                  _handlePositionUpdates([p]);
                }
              } catch (e) {
                if (kDebugMode) {
                  debugPrint('[VehicleRepo] Failed to fetch position for positionId=$posId: $e');
                }
              }
            }

            // Apply attribute-only updates (ignition/motion) immediately
            if (deviceId != null) {
              final attrs = e['attributes'];
              if (attrs is Map<String, dynamic>) {
                final ignition = attrs['ignition'];
                EngineState? engineState;
                if (ignition is bool) {
                  engineState = ignition ? EngineState.on : EngineState.off;
                } else if (attrs['motion'] is bool && attrs['motion'] == true) {
                  engineState = EngineState.on;
                }
                if (engineState != null) {
                  final rawTime = (e['eventTime'] ?? e['serverTime'] ?? e['deviceTime']) as String?;
                  DateTime ts;
                  try {
                    ts = rawTime != null ? DateTime.parse(rawTime).toUtc() : DateTime.now().toUtc();
                  } catch (_) {
                    ts = DateTime.now().toUtc();
                  }
                  // Ensure newer than any cached snapshot
                  ts = ts.add(const Duration(milliseconds: 1));
                  final partial = VehicleDataSnapshot(
                    deviceId: deviceId,
                    timestamp: ts,
                    engineState: engineState,
                    lastUpdate: ts,
                  );
                  if (kDebugMode) {
                    debugPrint('[VehicleRepo][WS] applying event-based engine update for device=$deviceId -> $engineState at $ts');
                  }
                  _updateDeviceSnapshot(partial);
                }
              }

              // Also refresh device data if no positionId to keep other fields fresh
              if (posId == null) {
                _lastFetchTime.remove(deviceId);
                if (kDebugMode) {
                  debugPrint('[VehicleRepo][WS] refreshing device data for deviceId=$deviceId (event)');
                }
                unawaited(_fetchDeviceData(deviceId));
              }
            }
          }
        }
      } catch (e) {
        if (kDebugMode) debugPrint('[VehicleRepo] Event handling error: $e');
      }
      return;
    }

    // Devices payload: updated device metadata or positionId may be present
    if (msg.type == 'devices' && msg.payload != null) {
      try {
        if (kDebugMode) {
          debugPrint('[VehicleRepo][WS] devices payload: ${msg.payload}');
        }
        final payload = msg.payload;
        final devices =
            payload is List ? List<dynamic>.from(payload) : <dynamic>[payload];
        for (final d in devices) {
          if (d is Map<String, dynamic>) {
            final posId = d['positionId'] as int?;
            final deviceId = d['id'] as int?;
            if (kDebugMode) {
              debugPrint('[VehicleRepo][WS] device update for deviceId=$deviceId posId=$posId');
            }
            if (posId != null) {
              try {
                final p = await positionsService.latestByPositionId(posId);
                if (p != null) {
                  if (kDebugMode) {
                    debugPrint('[VehicleRepo][WS] fetched Position for device posId=$posId -> device=${p.deviceId}');
                  }
                  _handlePositionUpdates([p]);
                }
              } catch (e) {
                if (kDebugMode) {
                  debugPrint('[VehicleRepo] Failed to fetch position for device update posId=$posId: $e');
                }
              }
            }

            if (deviceId != null) {
              // Apply attribute-only ignition updates from device payload if present
              final attrs = d['attributes'];
              if (attrs is Map<String, dynamic>) {
                final ignition = attrs['ignition'];
                EngineState? engineState;
                if (ignition is bool) {
                  engineState = ignition ? EngineState.on : EngineState.off;
                } else if (attrs['motion'] is bool && attrs['motion'] == true) {
                  engineState = EngineState.on;
                }
                if (engineState != null) {
                  final ts = DateTime.now().toUtc().add(const Duration(milliseconds: 1));
                  final partial = VehicleDataSnapshot(
                    deviceId: deviceId,
                    timestamp: ts,
                    engineState: engineState,
                    lastUpdate: ts,
                  );
                  if (kDebugMode) {
                    debugPrint('[VehicleRepo][WS] applying device-based engine update for device=$deviceId -> $engineState at $ts');
                  }
                  _updateDeviceSnapshot(partial);
                }
              }

              // Refresh device data if no positionId to keep other fields fresh
              if (posId == null) {
                if (kDebugMode) {
                  debugPrint('[VehicleRepo][WS] refreshing device data for deviceId=$deviceId (device update)');
                }
                _lastFetchTime.remove(deviceId);
                unawaited(_fetchDeviceData(deviceId));
              }
            }
          }
        }
      } catch (e) {
        if (kDebugMode) debugPrint('[VehicleRepo] Devices handling error: $e');
      }
      return;
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
    if (kDebugMode) {
      final existing = _notifiers[snapshot.deviceId]?.value;
      debugPrint('[VehicleRepo] Updating snapshot for device=${snapshot.deviceId}');
      debugPrint('[VehicleRepo]   incoming: $snapshot');
      debugPrint('[VehicleRepo]   existing: $existing');

      // Log engine state changes explicitly
      if (snapshot.engineState != null && snapshot.engineState != existing?.engineState) {
        debugPrint('[VehicleRepo] 🔧 ENGINE STATE CHANGE: ${existing?.engineState} → ${snapshot.engineState}');
      }
    }

    // Update cache
    cache.put(snapshot);

    // Persist telemetry record (history) - best-effort, ignore failures
    try {
      telemetryDao.put(
        TelemetryRecord(
          deviceId: snapshot.deviceId,
          timestampMs: snapshot.timestamp.toUtc().millisecondsSinceEpoch,
          speed: snapshot.speed,
          battery: snapshot.batteryLevel,
          signal: snapshot.signal,
          engine: snapshot.engineState?.name,
          odometer: snapshot.odometer,
          motion: snapshot.motion,
        ),
      );
    } catch (_) {
      // Swallow errors to keep UI pipeline unaffected
    }

    // Get or create notifier
    final notifier = _notifiers[snapshot.deviceId];
    if (notifier != null) {
      final existing = notifier.value;
      final merged = existing?.merge(snapshot) ?? snapshot;

      // CRITICAL: Always create a new object reference to trigger ValueNotifier updates
      notifier.value = merged;

      if (kDebugMode) {
        debugPrint('[VehicleRepo]   merged: $merged');
        debugPrint('[VehicleRepo]   ✅ Notifier updated - listeners will be notified');
      }
    } else {
      _notifiers[snapshot.deviceId] = ValueNotifier<VehicleDataSnapshot?>(snapshot);
      if (kDebugMode) {
        debugPrint('[VehicleRepo]   ✅ New notifier created for device ${snapshot.deviceId}');
      }
    }
  }

  /// Get or create a ValueNotifier for a device
  ValueNotifier<VehicleDataSnapshot?> getNotifier(int deviceId) {
    return _notifiers.putIfAbsent(deviceId, () {
      final cached = cache.get(deviceId);
      final notifier = ValueNotifier<VehicleDataSnapshot?>(cached);
      if (cached == null) {
        _fetchDeviceData(deviceId);
      }
      return notifier;
    });
  }

  /// Fetch data for a single device (with memoization)
  Future<void> _fetchDeviceData(int deviceId) async {
    if (_isOffline) {
      if (kDebugMode) {
        debugPrint('[VehicleRepo] Offline → skip fetch for device $deviceId');
      }
      return; // Use cached data only
    }

    final lastFetch = _lastFetchTime[deviceId];
    if (lastFetch != null && DateTime.now().difference(lastFetch) < _minFetchInterval) {
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
          if (kDebugMode) {
            debugPrint('[VehicleRepo] Overlayed engine from device attrs for $deviceId -> $engineState');
          }
        }
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
    if (_isOffline) {
      if (kDebugMode) {
        debugPrint('[VehicleRepo] Offline → skip parallel fetch for ${deviceIds.length} devices');
      }
      return; // Use cached data only
    }

    try {
      if (kDebugMode) {
        debugPrint('[VehicleRepo] Fetching ${deviceIds.length} devices in parallel');
      }

      // Fetch all devices
      final devices = await deviceService.fetchDevices();
      final deviceMap = {for (final d in devices) d['id']: d};

      // Fetch positions using latestForDevices (already optimized)
      final deviceList = deviceIds
          .where(deviceMap.containsKey)
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
    _fallbackTimer?.cancel();
    _fallbackTimer = Timer.periodic(_restFallbackInterval, (_) {
      if (_isOffline) {
        if (kDebugMode) {
          debugPrint('[VehicleRepo] Offline → skipping REST fallback tick');
        }
        return; // No network activity while offline
      }
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
