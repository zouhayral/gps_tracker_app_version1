import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:my_app_gps/core/data/vehicle_data_cache.dart';
import 'package:my_app_gps/core/data/vehicle_data_snapshot.dart';
import 'package:my_app_gps/core/database/dao/telemetry_dao.dart';
import 'package:my_app_gps/core/database/entities/telemetry_record.dart';
import 'package:my_app_gps/core/utils/app_logger.dart';
import 'package:my_app_gps/features/map/data/position_model.dart';

/// Service responsible for cache management and TTL logic.
/// 
/// **Responsibilities:**
/// - Cache operations (put, get, loadAll)
/// - Device name caching and resolution
/// - Stale device cleanup
/// - Hash-based deduplication
/// - TTL/memory management
/// 
/// **Extracted from:** VehicleDataRepository (lines ~265-430, ~397-424)
class VehicleDataCacheService {
  static final _log = 'VehicleCacheSvc'.logger;

  VehicleDataCacheService({
    required this.cache,
    required this.telemetryDao,
  });

  final VehicleDataCache cache;
  final TelemetryDaoBase telemetryDao;

  // Per-device notifiers (managed by this service)
  final Map<int, ValueNotifier<VehicleDataSnapshot?>> _notifiers = {};

  // Device name cache
  final Map<int, String> _deviceNames = <int, String>{};

  // Deduplication state
  final Map<int, String> _lastPositionHash = <int, String>{};
  final Map<int, int> _lastPositionId = <int, int>{};
  final Map<int, String> _lastDevicePayloadHash = <int, String>{};

  // Memory cleanup timer
  Timer? _cleanupTimer;
  bool _isDisposed = false;

  // Test-mode flag to disable background timers in widget tests
  static bool testMode = false;

  /// Compute a stable hash string for a Position
  String hashPosition(Position p) {
    return '${p.latitude}-${p.longitude}-${p.speed}-${p.course}-${p.deviceTime.millisecondsSinceEpoch}';
  }

  /// Compute a stable hash string for device payload
  String hashDevicePayload(Map<String, dynamic> m) {
    final id = m['id'];
    final posId = m['positionId'];
    final name = m['name'];
    final attrs = m['attributes'];
    return '$id-$posId-$name-${attrs?.hashCode}';
  }

  /// Resolve a friendly device name with safe fallbacks.
  /// Returns a user-visible string; never null.
  String resolveDeviceName(int deviceId) {
    final name = _deviceNames[deviceId];
    if (name != null && name.trim().isNotEmpty) {
      return name;
    }
    return 'Unknown Device';
  }

  /// Cache a device map (e.g., from REST or WebSocket) to update name cache.
  void cacheDevice(Map<String, dynamic> device) {
    final id = device['id'];
    final name = device['name'];
    if (id is int && name is String && name.trim().isNotEmpty) {
      _deviceNames[id] = name;
    }
  }

  /// Start memory cleanup timer (runs every hour)
  void startCleanupTimer() {
    if (_cleanupTimer != null || testMode) return;

    _cleanupTimer = Timer.periodic(
      const Duration(hours: 1),
      (_) => _cleanupStaleDevices(),
    );

    _log.debug('🧹 Cleanup timer started (every 1 hour)');
  }

  /// Clean up devices with stale data (>7 days old)
  void _cleanupStaleDevices() {
    if (_isDisposed) {
      _log.debug('[CONCURRENCY] 🧩 Cleanup skipped: service disposed');
      return;
    }

    final now = DateTime.now();
    var removed = 0;

    _notifiers.removeWhere((deviceId, notifier) {
      final snapshot = notifier.value;
      if (snapshot == null) return false;

      final age = now.difference(snapshot.timestamp);
      if (age > const Duration(days: 7)) {
        notifier.dispose();
        removed++;
        return true;
      }
      return false;
    });

    _log.info('🧹 Cleaned up $removed stale devices at $now');
  }

  /// Test-only method to invoke cleanup (exposed for unit tests)
  @visibleForTesting
  void invokeTestCleanup() => _cleanupStaleDevices();

  /// Pre-warm cache by loading all cached snapshots into notifiers
  /// Also populates per-device position stream cache
  Map<int, Position?> prewarmCache() {
    final latestPositions = <int, Position?>{};
    
    try {
      final allCached = cache.loadAll();
      if (allCached.isEmpty) {
        _log.debug('No cached data to prewarm');
        return latestPositions;
      }
      
      for (final entry in allCached.entries) {
        final deviceId = entry.key;
        final snapshot = entry.value;
        _notifiers[deviceId] = ValueNotifier<VehicleDataSnapshot?>(snapshot);
        
        // Populate position stream cache for immediate offline availability
        if (snapshot.position != null) {
          latestPositions[deviceId] = snapshot.position;
          _log.debug('📡 Cached position loaded for device $deviceId');
        }
      }
      
      _log.info('✅ Pre-warmed cache with ${allCached.length} devices (notifiers + streams)');
    } catch (e) {
      _log.error('Cache pre-warm error', error: e);
    }
    
    return latestPositions;
  }

  /// Update cache and persist telemetry record
  void updateCache(VehicleDataSnapshot snapshot) {
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
  }

  /// Get or create a ValueNotifier for a device
  ValueNotifier<VehicleDataSnapshot?> getNotifier(int deviceId) {
    return _notifiers.putIfAbsent(deviceId, () {
      final cached = cache.get(deviceId);
      return ValueNotifier<VehicleDataSnapshot?>(cached);
    });
  }

  /// Update notifier with merged snapshot
  void updateNotifier(VehicleDataSnapshot snapshot) {
    final notifier = _notifiers[snapshot.deviceId];
    if (notifier != null) {
      final existing = notifier.value;
      final merged = existing?.merge(snapshot) ?? snapshot;
      
      // Only notify when content actually changed
      if (merged != existing) {
        notifier.value = merged;
        _log.debug('✅ Notifier updated for device ${snapshot.deviceId}');
      }
    } else {
      _notifiers[snapshot.deviceId] = ValueNotifier<VehicleDataSnapshot?>(snapshot);
      _log.debug('✅ New notifier created for device ${snapshot.deviceId}');
    }
  }

  /// Check if position is duplicate by ID
  bool isDuplicatePositionById(int deviceId, int? positionId) {
    if (positionId == null) return false;
    
    final lastId = _lastPositionId[deviceId];
    if (lastId != null && lastId == positionId) {
      return true;
    }
    
    _lastPositionId[deviceId] = positionId;
    return false;
  }

  /// Check if position is duplicate by hash
  bool isDuplicatePositionByHash(Position pos) {
    final hash = hashPosition(pos);
    final prev = _lastPositionHash[pos.deviceId];
    
    if (prev != null && prev == hash) {
      return true;
    }
    
    _lastPositionHash[pos.deviceId] = hash;
    return false;
  }

  /// Check if device payload is duplicate
  bool isDuplicateDevicePayload(int deviceId, Map<String, dynamic> device) {
    final hash = hashDevicePayload(device);
    final prev = _lastDevicePayloadHash[deviceId];
    
    if (prev != null && prev == hash) {
      return true;
    }
    
    _lastDevicePayloadHash[deviceId] = hash;
    return false;
  }

  /// Get all notifiers
  Map<int, ValueNotifier<VehicleDataSnapshot?>> get notifiers => _notifiers;

  /// Get all device names
  Map<int, String> get deviceNames => _deviceNames;

  /// Get cache statistics
  Map<String, dynamic> get cacheStats => cache.stats;

  /// Dispose resources
  void dispose() {
    if (_isDisposed) return;
    _isDisposed = true;

    _cleanupTimer?.cancel();
    
    for (final notifier in _notifiers.values) {
      notifier.dispose();
    }
    _notifiers.clear();
    
    _log.debug('Cache service disposed');
  }
}
