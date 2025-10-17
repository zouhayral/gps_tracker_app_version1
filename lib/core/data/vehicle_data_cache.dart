import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:my_app_gps/core/data/vehicle_data_snapshot.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Two-tier cache for vehicle data:
/// - Hot cache (in-memory Map): Instant access
/// - Cold cache (SharedPreferences): Survives app restarts
///
/// Strategy:
/// - All reads check hot cache first, then cold cache
/// - All writes update both caches
/// - Stale entries (>30 min) are pruned on read
/// - Cache hit/miss metrics tracked for monitoring
class VehicleDataCache {
  VehicleDataCache({
    required SharedPreferences prefs,
    this.maxAge = const Duration(minutes: 30),
  }) : _prefs = prefs {
    _loadFromDisk();
  }

  final SharedPreferences _prefs;
  final Duration maxAge;

  // Hot cache (in-memory)
  final Map<int, VehicleDataSnapshot> _hotCache = {};

  // Metrics
  int _hits = 0;
  int _misses = 0;

  static const String _keyPrefix = 'vehicle_cache_';

  /// Load all cached snapshots from disk into hot cache
  void _loadFromDisk() {
    try {
      final keys = _prefs.getKeys().where((k) => k.startsWith(_keyPrefix));
      var loaded = 0;
      var skipped = 0;

      for (final key in keys) {
        final deviceId = int.tryParse(key.replaceFirst(_keyPrefix, ''));
        if (deviceId == null) continue;

        final json = _prefs.getString(key);
        if (json == null) continue;

        try {
          final data = jsonDecode(json) as Map<String, dynamic>;
          final snapshot = VehicleDataSnapshot.fromJson(data);

          // Skip stale entries
          if (snapshot.isStale(maxAge)) {
            skipped++;
            _prefs.remove(key); // Clean up stale disk entry
            continue;
          }

          _hotCache[deviceId] = snapshot;
          loaded++;
        } catch (e) {
          if (kDebugMode) {
            debugPrint('[VehicleCache] Failed to load $key: $e');
          }
          _prefs.remove(key); // Remove corrupted entry
        }
      }

      if (kDebugMode) {
        debugPrint(
          '[VehicleCache] Loaded $loaded snapshots from disk, skipped $skipped stale entries',
        );
      }
    } catch (e) {
      if (kDebugMode) {
        debugPrint('[VehicleCache] Disk load error: $e');
      }
    }
  }

  /// Get cached snapshot for a device (hot cache → cold cache → null)
  VehicleDataSnapshot? get(int deviceId) {
    // Check hot cache first
    var snapshot = _hotCache[deviceId];

    // If stale, evict and return null
    if (snapshot != null && snapshot.isStale(maxAge)) {
      if (kDebugMode) {
        debugPrint('[VehicleCache] Evicting stale entry for device $deviceId');
      }
      _hotCache.remove(deviceId);
      _prefs.remove('$_keyPrefix$deviceId');
      snapshot = null;
    }

    if (snapshot != null) {
      _hits++;
      if (kDebugMode) {
        debugPrint(
          '[VehicleCache] HIT device=$deviceId (hits=$_hits misses=$_misses)',
        );
      }
      return snapshot;
    }

    _misses++;
    if (kDebugMode) {
      debugPrint(
        '[VehicleCache] MISS device=$deviceId (hits=$_hits misses=$_misses)',
      );
    }
    return null;
  }

  /// Put snapshot into both hot and cold caches
  Future<void> put(VehicleDataSnapshot snapshot) async {
    try {
      // Update hot cache
      final existing = _hotCache[snapshot.deviceId];
      _hotCache[snapshot.deviceId] = existing?.merge(snapshot) ?? snapshot;

      // Update cold cache (async, fire-and-forget for performance)
      unawaited(_writeToDisk(snapshot.deviceId));
    } catch (e) {
      if (kDebugMode) {
        debugPrint(
          '[VehicleCache] Put error for device ${snapshot.deviceId}: $e',
        );
      }
    }
  }

  /// Batch put multiple snapshots
  Future<void> putAll(Iterable<VehicleDataSnapshot> snapshots) async {
    for (final snapshot in snapshots) {
      await put(snapshot);
    }
  }

  /// Write a snapshot to SharedPreferences
  Future<void> _writeToDisk(int deviceId) async {
    try {
      final snapshot = _hotCache[deviceId];
      if (snapshot == null) return;

      final json = jsonEncode(snapshot.toJson());
      await _prefs.setString('$_keyPrefix$deviceId', json);
    } catch (e) {
      if (kDebugMode) {
        debugPrint('[VehicleCache] Disk write error for device $deviceId: $e');
      }
    }
  }

  /// Clear cache for a specific device
  Future<void> remove(int deviceId) async {
    _hotCache.remove(deviceId);
    await _prefs.remove('$_keyPrefix$deviceId');
  }

  /// Clear all cached data
  Future<void> clear() async {
    _hotCache.clear();
    _hits = 0;
    _misses = 0;

    final keys = _prefs.getKeys().where((k) => k.startsWith(_keyPrefix));
    for (final key in keys) {
      await _prefs.remove(key);
    }

    if (kDebugMode) {
      debugPrint('[VehicleCache] Cleared all cache entries');
    }
  }

  /// Get all cached device IDs
  List<int> get cachedDeviceIds => _hotCache.keys.toList();

  /// Load all cached snapshots (for pre-warming)
  Map<int, VehicleDataSnapshot> loadAll() {
    // Return copy of hot cache (already loaded from disk in constructor)
    return Map.unmodifiable(_hotCache);
  }

  /// Get cache hit ratio (0.0 to 1.0)
  double get hitRatio {
    final total = _hits + _misses;
    return total == 0 ? 0.0 : _hits / total;
  }

  /// Get cache statistics
  Map<String, dynamic> get stats => {
        'hot_cache_size': _hotCache.length,
        'hits': _hits,
        'misses': _misses,
        'hit_ratio': '${(hitRatio * 100).toStringAsFixed(1)}%',
      };

  /// Reset metrics
  void resetMetrics() {
    _hits = 0;
    _misses = 0;
  }
}
