import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:my_app_gps/features/geofencing/service/geofence_evaluator_service.dart';

/// High-performance in-memory cache for geofence states with TTL eviction.
///
/// Responsibilities:
/// - Maintain per-device, per-geofence state mappings
/// - Provide O(1) lookups for evaluator
/// - Automatic TTL-based eviction (default: 24 hours)
/// - Optional ObjectBox persistence (Phase 3)
/// - Memory usage monitoring and statistics
///
/// Architecture:
/// ```text
/// GeofenceMonitoringService
///     ↓
/// GeofenceEvaluatorService
///     ↓
/// GeofenceStateCache (this class)
///     ↓
/// Map<deviceId, Map<geofenceId, CachedState>>
/// ```
///
/// Performance:
/// - Get: O(1)
/// - Set: O(1)
/// - Remove: O(1)
/// - Prune: O(n) where n = total cached states
/// - Target: Prune 1000 states < 5ms
///
/// Example:
/// ```dart
/// final cache = GeofenceStateCache(
///   ttl: Duration(hours: 24),
///   autoPruneInterval: Duration(minutes: 30),
/// );
///
/// // Store state
/// cache.set('device123', 'geofence-001', state);
///
/// // Retrieve state
/// final state = cache.get('device123', 'geofence-001');
///
/// // Check statistics
/// print('Cache size: ${cache.stats.totalStates}');
/// print('Hit rate: ${cache.stats.hitRate}%');
///
/// // Cleanup
/// cache.dispose();
/// ```
class GeofenceStateCache {
  GeofenceStateCache({
    this.ttl = const Duration(hours: 24),
    this.autoPruneInterval = const Duration(minutes: 30),
    this.enableStatistics = true,
  }) {
    _init();
  }

  /// Time-to-live for cached states (default: 24 hours)
  final Duration ttl;

  /// Automatic pruning interval (default: 30 minutes)
  final Duration autoPruneInterval;

  /// Enable statistics collection (default: true)
  final bool enableStatistics;

  /// Internal cache structure: deviceId → geofenceId → CachedState
  final Map<String, Map<String, _CachedState>> _cache = {};

  /// Statistics tracking
  final _stats = _CacheStatistics();

  /// Auto-prune timer
  Timer? _pruneTimer;

  /// Statistics stream controller
  final _statsController = StreamController<CacheStatistics>.broadcast();

  /// Cache initialization
  void _init() {
    _log('Initializing GeofenceStateCache');
    _log('TTL: ${ttl.inHours}h, Auto-prune: ${autoPruneInterval.inMinutes}m');

    // Start automatic pruning
    _pruneTimer = Timer.periodic(autoPruneInterval, (_) {
      pruneExpired();
      _emitStats();
    });
  }

  /// Get cached state for device-geofence pair
  ///
  /// Returns null if:
  /// - State not in cache (cache miss)
  /// - State expired (beyond TTL)
  ///
  /// Performance: O(1)
  GeofenceState? get(String deviceId, String geofenceId) {
    if (enableStatistics) _stats._recordLookup();

    final deviceCache = _cache[deviceId];
    if (deviceCache == null) {
      if (enableStatistics) _stats._recordMiss();
      return null;
    }

    final cachedState = deviceCache[geofenceId];
    if (cachedState == null) {
      if (enableStatistics) _stats._recordMiss();
      return null;
    }

    // Check if expired
    final now = DateTime.now().millisecondsSinceEpoch;
    if (_isExpired(cachedState, now)) {
      // Lazy eviction: Remove expired entry
      deviceCache.remove(geofenceId);
      if (deviceCache.isEmpty) {
        _cache.remove(deviceId);
      }
      if (enableStatistics) {
        _stats._recordMiss();
        _stats._recordEviction();
      }
      return null;
    }

    // Cache hit
    if (enableStatistics) _stats._recordHit();
    return cachedState.state;
  }

  /// Store state in cache
  ///
  /// Updates existing entry or creates new one.
  /// Automatically sets timestamp for TTL tracking.
  ///
  /// Performance: O(1)
  void set(String deviceId, String geofenceId, GeofenceState state) {
    // Get or create device cache
    final deviceCache = _cache.putIfAbsent(deviceId, () => {});

    final now = DateTime.now().millisecondsSinceEpoch;
    final cachedState = _CachedState(
      state: state,
      timestampMs: now,
    );

    final isUpdate = deviceCache.containsKey(geofenceId);
    deviceCache[geofenceId] = cachedState;

    if (enableStatistics) {
      if (isUpdate) {
        _stats._recordUpdate();
      } else {
        _stats._recordInsert();
      }
    }
  }

  /// Remove specific state from cache
  ///
  /// Performance: O(1)
  void remove(String deviceId, String geofenceId) {
    final deviceCache = _cache[deviceId];
    if (deviceCache == null) return;

    final removed = deviceCache.remove(geofenceId);
    if (removed != null && enableStatistics) {
      _stats._recordRemoval();
    }

    // Clean up empty device cache
    if (deviceCache.isEmpty) {
      _cache.remove(deviceId);
    }
  }

  /// Remove all states for a device
  ///
  /// Performance: O(m) where m = number of geofences for device
  void removeDevice(String deviceId) {
    final deviceCache = _cache.remove(deviceId);
    if (deviceCache != null && enableStatistics) {
      _stats._recordRemovals(deviceCache.length);
    }
    _log('Removed all states for device: $deviceId');
  }

  /// Remove all states for a geofence (across all devices)
  ///
  /// Performance: O(n) where n = number of devices
  void removeGeofence(String geofenceId) {
    var removedCount = 0;

    for (final deviceCache in _cache.values) {
      if (deviceCache.remove(geofenceId) != null) {
        removedCount++;
      }
    }

    // Clean up empty device caches
    _cache.removeWhere((_, deviceCache) => deviceCache.isEmpty);

    if (enableStatistics) {
      _stats._recordRemovals(removedCount);
    }
    _log('Removed geofence $geofenceId from $removedCount devices');
  }

  /// Prune expired entries based on TTL
  ///
  /// Iterates through all cached states and removes expired ones.
  /// Automatically called by timer at `autoPruneInterval`.
  ///
  /// Performance: O(n) where n = total cached states
  /// Target: < 5ms for 1000 states
  void pruneExpired() {
    final startTime = DateTime.now().millisecondsSinceEpoch;
    final now = startTime;
    var prunedCount = 0;

    // Iterate through all devices
    final devicesToRemove = <String>[];

    for (final entry in _cache.entries) {
      final deviceId = entry.key;
      final deviceCache = entry.value;

      // Find expired geofences for this device
      final geofencesToRemove = <String>[];

      for (final geofenceEntry in deviceCache.entries) {
        final geofenceId = geofenceEntry.key;
        final cachedState = geofenceEntry.value;

        if (_isExpired(cachedState, now)) {
          geofencesToRemove.add(geofenceId);
        }
      }

      // Remove expired geofences
      for (final geofenceId in geofencesToRemove) {
        deviceCache.remove(geofenceId);
        prunedCount++;
      }

      // Mark device for removal if empty
      if (deviceCache.isEmpty) {
        devicesToRemove.add(deviceId);
      }
    }

    // Remove empty device caches
    for (final deviceId in devicesToRemove) {
      _cache.remove(deviceId);
    }

    final elapsedMs = DateTime.now().millisecondsSinceEpoch - startTime;

    if (enableStatistics) {
      _stats._recordEvictions(prunedCount);
    }

    if (prunedCount > 0) {
      _log('Pruned $prunedCount expired states in ${elapsedMs}ms');
    }
  }

  /// Check if cached state is expired
  bool _isExpired(_CachedState cached, int nowMs) {
    final ageMs = nowMs - cached.timestampMs;
    return ageMs > ttl.inMilliseconds;
  }

  /// Clear all cached states
  ///
  /// Use with caution - removes all state history.
  void clear() {
    final count = stats.totalStates;
    _cache.clear();

    if (enableStatistics) {
      _stats._recordRemovals(count);
    }

    _log('Cleared all cached states ($count entries)');
  }

  /// Get all states for a device
  ///
  /// Returns immutable map of geofenceId → GeofenceState
  Map<String, GeofenceState> getDeviceStates(String deviceId) {
    final deviceCache = _cache[deviceId];
    if (deviceCache == null) return const {};

    final now = DateTime.now().millisecondsSinceEpoch;
    final result = <String, GeofenceState>{};

    for (final entry in deviceCache.entries) {
      if (!_isExpired(entry.value, now)) {
        result[entry.key] = entry.value.state;
      }
    }

    return Map.unmodifiable(result);
  }

  /// Get all active devices (those with cached states)
  List<String> get activeDevices => List.unmodifiable(_cache.keys);

  /// Get current cache statistics
  CacheStatistics get stats {
    return CacheStatistics(
      totalStates: _countTotalStates(),
      totalDevices: _cache.length,
      totalLookups: _stats._lookups,
      cacheHits: _stats._hits,
      cacheMisses: _stats._misses,
      inserts: _stats._inserts,
      updates: _stats._updates,
      removals: _stats._removals,
      evictions: _stats._evictions,
      hitRate: _stats.hitRate,
      missRate: _stats.missRate,
      averageStatesPerDevice: _stats._lookups > 0
          ? _countTotalStates() / _cache.length
          : 0.0,
    );
  }

  /// Stream of cache statistics (updated after each prune)
  Stream<CacheStatistics> get statsStream => _statsController.stream;

  /// Count total cached states across all devices
  int _countTotalStates() {
    return _cache.values.fold(0, (sum, deviceCache) => sum + deviceCache.length);
  }

  /// Emit statistics to stream
  void _emitStats() {
    if (!_statsController.isClosed) {
      _statsController.add(stats);
    }
  }

  /// Logging helper
  void _log(String message) {
    if (kDebugMode) {
      debugPrint('[GeofenceStateCache] $message');
    }
  }

  /// Dispose resources
  void dispose() {
    _pruneTimer?.cancel();
    _statsController.close();
    _log('Cache disposed (${stats.totalStates} states, ${stats.hitRate.toStringAsFixed(1)}% hit rate)');
  }

  // =============================
  // ObjectBox Persistence (Optional - Phase 3)
  // =============================

  /// Persist all cached states to ObjectBox
  ///
  /// TODO: Implement when GeofenceStateEntity is created
  Future<void> persistAll() async {
    _log('⚠️ persistAll() not yet implemented (requires ObjectBox entity)');
    // Implementation:
    // 1. Create GeofenceStateEntity if not exists
    // 2. Convert _cache to entities
    // 3. Batch write to ObjectBox
    // 4. Track last persist timestamp
  }

  /// Restore cached states from ObjectBox
  ///
  /// TODO: Implement when GeofenceStateEntity is created
  Future<void> restore() async {
    _log('⚠️ restore() not yet implemented (requires ObjectBox entity)');
    // Implementation:
    // 1. Load GeofenceStateEntity from ObjectBox
    // 2. Filter by TTL (don't restore expired)
    // 3. Rebuild _cache from entities
    // 4. Log restoration stats
  }
}

/// Internal cached state wrapper with timestamp
class _CachedState {
  const _CachedState({
    required this.state,
    required this.timestampMs,
  });

  /// The actual geofence state
  final GeofenceState state;

  /// Cache timestamp in milliseconds since epoch
  final int timestampMs;
}

/// Statistics tracking for cache operations
class _CacheStatistics {
  int _lookups = 0;
  int _hits = 0;
  int _misses = 0;
  int _inserts = 0;
  int _updates = 0;
  int _removals = 0;
  int _evictions = 0;

  void _recordLookup() => _lookups++;
  void _recordHit() => _hits++;
  void _recordMiss() => _misses++;
  void _recordInsert() => _inserts++;
  void _recordUpdate() => _updates++;
  void _recordRemoval() => _removals++;
  void _recordRemovals(int count) => _removals += count;
  void _recordEviction() => _evictions++;
  void _recordEvictions(int count) => _evictions += count;

  double get hitRate => _lookups > 0 ? (_hits / _lookups) * 100 : 0.0;
  double get missRate => _lookups > 0 ? (_misses / _lookups) * 100 : 0.0;
}

/// Public cache statistics snapshot
class CacheStatistics {
  const CacheStatistics({
    required this.totalStates,
    required this.totalDevices,
    required this.totalLookups,
    required this.cacheHits,
    required this.cacheMisses,
    required this.inserts,
    required this.updates,
    required this.removals,
    required this.evictions,
    required this.hitRate,
    required this.missRate,
    required this.averageStatesPerDevice,
  });

  /// Total number of cached states
  final int totalStates;

  /// Number of devices with cached states
  final int totalDevices;

  /// Total cache lookups
  final int totalLookups;

  /// Successful cache hits
  final int cacheHits;

  /// Cache misses (not found or expired)
  final int cacheMisses;

  /// Number of new entries inserted
  final int inserts;

  /// Number of existing entries updated
  final int updates;

  /// Number of manual removals
  final int removals;

  /// Number of TTL-based evictions
  final int evictions;

  /// Cache hit rate percentage (0-100)
  final double hitRate;

  /// Cache miss rate percentage (0-100)
  final double missRate;

  /// Average states per device
  final double averageStatesPerDevice;

  @override
  String toString() => 'CacheStatistics('
      'states: $totalStates, '
      'devices: $totalDevices, '
      'hits: $cacheHits/$totalLookups (${hitRate.toStringAsFixed(1)}%), '
      'evictions: $evictions'
      ')';
}

// =============================
// Example Usage
// =============================

/// Example usage of GeofenceStateCache
///
/// ```dart
/// void main() async {
///   // Initialize cache
///   final cache = GeofenceStateCache(
///     ttl: Duration(hours: 24),
///     autoPruneInterval: Duration(minutes: 30),
///     enableStatistics: true,
///   );
///
///   // Listen to statistics
///   cache.statsStream.listen((stats) {
///     print('Cache: ${stats.totalStates} states, ${stats.hitRate.toStringAsFixed(1)}% hit rate');
///   });
///
///   // Create sample states
///   final insideState = GeofenceState(
///     deviceId: 'device123',
///     geofenceId: 'office-001',
///     geofenceName: 'Office Building',
///     isInside: true,
///     enterTimestamp: DateTime.now(),
///     lastSeenTimestamp: DateTime.now(),
///   );
///
///   final outsideState = GeofenceState(
///     deviceId: 'device123',
///     geofenceId: 'home-001',
///     geofenceName: 'Home',
///     isInside: false,
///     lastSeenTimestamp: DateTime.now(),
///   );
///
///   // Store states
///   cache.set('device123', 'office-001', insideState);
///   cache.set('device123', 'home-001', outsideState);
///
///   print('Stored 2 states');
///
///   // Retrieve states
///   final retrievedOffice = cache.get('device123', 'office-001');
///   print('Office state: ${retrievedOffice?.isInside}');
///
///   final retrievedHome = cache.get('device123', 'home-001');
///   print('Home state: ${retrievedHome?.isInside}');
///
///   // Check statistics
///   final stats = cache.stats;
///   print('Total states: ${stats.totalStates}');
///   print('Total devices: ${stats.totalDevices}');
///   print('Cache hits: ${stats.cacheHits}/${stats.totalLookups}');
///   print('Hit rate: ${stats.hitRate.toStringAsFixed(1)}%');
///
///   // Get all states for device
///   final deviceStates = cache.getDeviceStates('device123');
///   print('Device123 has ${deviceStates.length} states');
///
///   // Remove specific state
///   cache.remove('device123', 'home-001');
///   print('Removed home state');
///
///   // Prune expired entries
///   cache.pruneExpired();
///
///   // Clear all
///   cache.clear();
///
///   // Cleanup
///   cache.dispose();
/// }
/// ```
///
/// Integration with GeofenceEvaluatorService:
/// ```dart
/// class GeofenceMonitoringService {
///   final GeofenceEvaluatorService _evaluator;
///   final GeofenceStateCache _stateCache;
///
///   void _handlePosition(Position position) {
///     // Restore previous states from cache
///     for (final geofence in _activeGeofences) {
///       final cachedState = _stateCache.get(position.deviceId, geofence.id);
///       if (cachedState != null) {
///         // Inject cached state into evaluator
///         _evaluator._activeStates['${position.deviceId}:${geofence.id}'] = cachedState;
///       }
///     }
///
///     // Evaluate position
///     final events = _evaluator.evaluate(
///       deviceId: position.deviceId,
///       position: LatLng(position.latitude, position.longitude),
///       timestamp: position.timestamp,
///       activeGeofences: _activeGeofences,
///     );
///
///     // Cache updated states
///     for (final geofence in _activeGeofences) {
///       final state = _evaluator.getState(position.deviceId, geofence.id);
///       if (state != null) {
///         _stateCache.set(position.deviceId, geofence.id, state);
///       }
///     }
///
///     // Process events...
///   }
/// }
/// ```
