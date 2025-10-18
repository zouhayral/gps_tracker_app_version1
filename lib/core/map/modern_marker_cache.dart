import 'dart:typed_data';

import 'package:my_app_gps/core/map/modern_marker_generator.dart';

/// Memory cache for generated marker images
///
/// Features:
/// - LRU eviction when memory limit reached
/// - Automatic cache warming for common states
/// - Per-device marker caching
/// - Size-aware (full vs compact) caching
///
/// Usage:
/// ```dart
/// final cache = ModernMarkerCache();
/// await cache.warmUp(['Vehicle 1', 'Vehicle 2']);
///
/// final bytes = await cache.getOrGenerate(
///   name: 'Vehicle 1',
///   online: true,
///   engineOn: true,
///   moving: true,
/// );
/// ```

class ModernMarkerCache {
  ModernMarkerCache({
    this.maxCacheSize = 100,
    this.pixelRatio = 2.0,
  });

  /// Maximum number of cached markers
  final int maxCacheSize;

  /// Pixel ratio for rendering
  final double pixelRatio;

  /// Cache storage: cacheKey -> bytes
  final Map<String, Uint8List> _cache = {};

  /// Access order for LRU eviction
  final List<String> _accessOrder = [];

  /// Cache statistics
  int _hits = 0;
  int _misses = 0;
  int _evictions = 0;

  /// Get marker bytes (from cache or generate)
  Future<Uint8List> getOrGenerate({
    required String name,
    required bool online,
    required bool engineOn,
    required bool moving,
    bool compact = false,
    double? speed,
  }) async {
    final cacheKey = _buildCacheKey(
      name: name,
      online: online,
      engineOn: engineOn,
      moving: moving,
      compact: compact,
      speed: speed,
    );

    // Check cache
    if (_cache.containsKey(cacheKey)) {
      _hits++;
      _updateAccessOrder(cacheKey);
      return _cache[cacheKey]!;
    }

    // Generate new marker
    _misses++;
    final bytes = await ModernMarkerGenerator.generateMarkerBytes(
      name: name,
      online: online,
      engineOn: engineOn,
      moving: moving,
      compact: compact,
      speed: speed,
      pixelRatio: pixelRatio,
    );

    // Store in cache
    _put(cacheKey, bytes);

    return bytes;
  }

  /// Get marker with state helper
  Future<Uint8List> getOrGenerateWithState({
    required String name,
    required MarkerState state,
    bool compact = false,
  }) async {
    return getOrGenerate(
      name: name,
      online: state.online,
      engineOn: state.engineOn,
      moving: state.moving,
      compact: compact,
      speed: state.speed,
    );
  }

  /// Warm up cache with common marker states for given vehicle names
  ///
  /// Generates markers for all common states (online/moving, online/idle, etc.)
  /// This is useful to call during app startup or when entering the map page
  Future<void> warmUp(List<String> vehicleNames, {bool compact = false}) async {
    for (final name in vehicleNames) {
      await _warmUpVehicle(name, compact: compact);
    }
  }

  /// Warm up cache for a single vehicle (all common states)
  Future<void> _warmUpVehicle(String name, {required bool compact}) async {
    final states = [
      {'online': true, 'engineOn': true, 'moving': true, 'speed': 60.0},
      {'online': true, 'engineOn': true, 'moving': false},
      {'online': true, 'engineOn': false, 'moving': false},
      {'online': false, 'engineOn': false, 'moving': false},
    ];

    for (final state in states) {
      await getOrGenerate(
        name: name,
        online: state['online']! as bool,
        engineOn: state['engineOn']! as bool,
        moving: state['moving']! as bool,
        compact: compact,
        speed: state['speed'] as double?,
      );
    }
  }

  /// Put marker in cache with LRU eviction
  void _put(String key, Uint8List bytes) {
    // Evict if at capacity
    if (_cache.length >= maxCacheSize && !_cache.containsKey(key)) {
      _evictLRU();
    }

    _cache[key] = bytes;
    _updateAccessOrder(key);
  }

  /// Update access order for LRU
  void _updateAccessOrder(String key) {
    _accessOrder.remove(key);
    _accessOrder.add(key);
  }

  /// Evict least recently used marker
  void _evictLRU() {
    if (_accessOrder.isEmpty) return;

    final lruKey = _accessOrder.removeAt(0);
    _cache.remove(lruKey);
    _evictions++;
  }

  /// Build cache key from marker attributes
  String _buildCacheKey({
    required String name,
    required bool online,
    required bool engineOn,
    required bool moving,
    required bool compact,
    double? speed,
  }) {
    // Round speed to reduce cache fragmentation
    final speedStr = speed != null ? (speed / 10).round() * 10 : 'null';
    return 'marker_${name}_${online}_${engineOn}_${moving}_${speedStr}_$compact';
  }

  /// Clear entire cache
  void clear() {
    _cache.clear();
    _accessOrder.clear();
  }

  /// Remove markers for specific vehicle
  void clearVehicle(String name) {
    final keysToRemove = _cache.keys.where((k) => k.contains('_${name}_')).toList();
    for (final key in keysToRemove) {
      _cache.remove(key);
      _accessOrder.remove(key);
    }
  }

  /// Cache statistics
  CacheStats get stats => CacheStats(
        size: _cache.length,
        maxSize: maxCacheSize,
        hits: _hits,
        misses: _misses,
        evictions: _evictions,
        hitRate: _hits + _misses > 0 ? _hits / (_hits + _misses) : 0.0,
      );

  /// Memory usage estimate (bytes)
  int get memoryUsage {
    return _cache.values.fold<int>(0, (sum, bytes) => sum + bytes.length);
  }

  /// Memory usage in MB
  double get memoryUsageMB => memoryUsage / (1024 * 1024);
}

/// Cache statistics
class CacheStats {
  CacheStats({
    required this.size,
    required this.maxSize,
    required this.hits,
    required this.misses,
    required this.evictions,
    required this.hitRate,
  });

  final int size;
  final int maxSize;
  final int hits;
  final int misses;
  final int evictions;
  final double hitRate;

  @override
  String toString() {
    return 'CacheStats(size: $size/$maxSize, hits: $hits, misses: $misses, '
        'evictions: $evictions, hitRate: ${(hitRate * 100).toStringAsFixed(1)}%)';
  }
}
