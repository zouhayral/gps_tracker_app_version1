import 'dart:async';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/scheduler.dart';

import 'package:my_app_gps/core/map/modern_marker_generator.dart';

/// Async marker warm cache with frame-budgeted main-thread batching
///
/// Pre-renders and caches marker bitmaps on the main thread using frame-aware
/// batching to prevent UI jank. Renders markers in small batches (4 per frame)
/// with a 6ms time budget to ensure smooth 60 FPS.
///
/// Replaces previous isolate-based approach (which failed due to dart:ui
/// limitations requiring root isolate for Canvas/PictureRecorder operations).
///
/// Features:
/// - Frame-budgeted batching (4 markers per frame, 6ms budget)
/// - Prevents duplicate work with pending futures
/// - LRU eviction when cache limit reached
/// - Batch warm-up API for fleet initialization
/// - Zero UI blocking via SchedulerBinding frame callbacks
///
/// Usage:
/// ```dart
/// // Warm up cache on map init (non-blocking)
/// final states = devices.map((d) => MarkerRenderState.fromDevice(d)).toList();
/// AsyncMarkerWarmCache.instance.warmUp(states);
///
/// // Later, get cached or generate
/// final image = await AsyncMarkerWarmCache.instance.getOrGenerate(key, state);
/// ```
class AsyncMarkerWarmCache {
  AsyncMarkerWarmCache._();

  /// Singleton instance
  static final AsyncMarkerWarmCache instance = AsyncMarkerWarmCache._();

  /// Cached marker images: cacheKey -> ui.Image
  final Map<String, ui.Image> _cache = {};

  /// Pending render operations: cacheKey -> Future<ui.Image>
  final Map<String, Future<ui.Image>> _pending = {};

  /// Access order for LRU eviction
  final List<String> _accessOrder = [];

  /// Warm-up queue for batch processing
  final List<_QueuedMarker> _warmUpQueue = [];

  /// Cache statistics
  int _hits = 0;
  int _misses = 0;
  int _evictions = 0;
  int _warmUpCount = 0;
  int _batchCount = 0;

  /// Maximum number of cached images (increased for fleet use)
  static const int _maxCacheSize = 200;

  /// Markers to render per frame during warm-up
  static const int _maxPerFrame = 4;

  /// Maximum time budget per frame (ms) to avoid jank
  static const int _maxFrameBudgetMs = 6;

  /// Whether warm-up batch is currently scheduled
  bool _isWarmUpScheduled = false;

  /// Get or generate marker image
  ///
  /// Returns cached image if available, otherwise renders on main thread.
  /// If another request is already rendering this marker, waits for it.
  Future<ui.Image> getOrGenerate(String key, MarkerRenderState state) async {
    // 1️⃣ Return if already cached
    if (_cache.containsKey(key)) {
      _hits++;
      _updateAccessOrder(key);
      return _cache[key]!;
    }

    // 2️⃣ If another request is already generating → wait for it
    if (_pending.containsKey(key)) {
      return _pending[key]!;
    }

    // 3️⃣ Otherwise render on main thread
    _misses++;
    final completer = Completer<ui.Image>();
    _pending[key] = completer.future;

    try {
      // Render marker on main thread (dart:ui requires root isolate)
      final image = await _renderMarker(state);

      // Store in cache with LRU eviction
      _putInCache(key, image);
      completer.complete(image);

      return image;
    } catch (e, s) {
      debugPrint('[MARKER-CACHE] ❌ Error rendering marker: $e');
      completer.completeError(e, s);
      rethrow;
    } finally {
      _pending.remove(key);
    }
  }

  /// Render marker on main thread (required by dart:ui)
  Future<ui.Image> _renderMarker(MarkerRenderState state) async {
    // Generate marker bytes using existing generator
    final bytes = await ModernMarkerGenerator.generateMarkerBytes(
      name: state.name,
      online: state.online,
      engineOn: state.engineOn,
      moving: state.moving,
      compact: state.compact,
      speed: state.speed,
      pixelRatio: state.pixelRatio,
    );

    // Decode bytes to ui.Image
    final codec = await ui.instantiateImageCodec(bytes);
    final frame = await codec.getNextFrame();

    return frame.image;
  }

  /// Put image in cache with LRU eviction
  void _putInCache(String key, ui.Image image) {
    // Evict if at capacity
    if (_cache.length >= _maxCacheSize && !_cache.containsKey(key)) {
      _evictLRU();
    }

    _cache[key] = image;
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
    final image = _cache.remove(lruKey);
    image?.dispose(); // Free GPU memory
    _evictions++;
  }

  /// Warm up cache for multiple markers (batch pre-rendering with frame budgeting)
  ///
  /// Enqueues markers for gradual rendering across multiple frames.
  /// Does not block UI thread - renders 4 markers per frame with 6ms budget.
  /// Skips markers already cached or pending.
  void warmUp(List<MarkerRenderState> states) {
    if (states.isEmpty) return;

    final toRender = <_QueuedMarker>[];

    // Filter out already cached/pending
    for (final state in states) {
      final key = state.cacheKey;
      if (!_cache.containsKey(key) && 
          !_pending.containsKey(key) &&
          !_warmUpQueue.any((q) => q.key == key)) {
        toRender.add(_QueuedMarker(key: key, state: state));
      }
    }

    if (toRender.isEmpty) {
      debugPrint(
        '[MARKER-CACHE] 🔁 All ${states.length} markers already cached or enqueued',
      );
      return;
    }

    debugPrint(
      '[MARKER-CACHE] 🧊 Warm-up enqueued: +${toRender.length} markers '
      '(${states.length - toRender.length} already cached)',
    );

    // Add to queue
    _warmUpQueue.addAll(toRender);

    // Schedule batch processing if not already running
    if (!_isWarmUpScheduled) {
      _scheduleNextBatch();
    }
  }

  /// Schedule next batch of markers to render on next frame
  void _scheduleNextBatch() {
    if (_warmUpQueue.isEmpty) {
      _isWarmUpScheduled = false;
      return;
    }

    _isWarmUpScheduled = true;

    // Use post-frame callback to avoid blocking current frame
    SchedulerBinding.instance.addPostFrameCallback((_) {
      _processBatch();
    });
  }

  /// Process one batch of markers (up to _maxPerFrame with time budget)
  Future<void> _processBatch() async {
    if (_warmUpQueue.isEmpty) {
      _isWarmUpScheduled = false;
      return;
    }

    final stopwatch = Stopwatch()..start();
    var rendered = 0;

    // Render up to _maxPerFrame markers or until time budget exceeded
    while (_warmUpQueue.isNotEmpty && 
           rendered < _maxPerFrame && 
           stopwatch.elapsedMilliseconds < _maxFrameBudgetMs) {
      final queued = _warmUpQueue.removeAt(0);

      try {
        // Check if still needed (might have been cached by direct request)
        if (!_cache.containsKey(queued.key) && !_pending.containsKey(queued.key)) {
          final image = await _renderMarker(queued.state);
          _putInCache(queued.key, image);
          _warmUpCount++;
          rendered++;
        }
      } catch (e) {
        debugPrint('[MARKER-CACHE] ⚠️ Failed to render ${queued.key}: $e');
      }

      // Yield to allow other microtasks if we've been running a while
      if (stopwatch.elapsedMilliseconds >= _maxFrameBudgetMs ~/ 2) {
        await Future<void>.delayed(Duration.zero);
      }
    }

    stopwatch.stop();
    _batchCount++;

    if (rendered > 0) {
      debugPrint(
        '[MARKER-CACHE] ✅ Warmed $rendered markers in ${stopwatch.elapsedMilliseconds}ms; '
        'remaining=${_warmUpQueue.length}',
      );
    }

    // Schedule next batch if queue not empty
    if (_warmUpQueue.isNotEmpty) {
      _scheduleNextBatch();
    } else {
      _isWarmUpScheduled = false;
      debugPrint('[MARKER-CACHE] 🎉 Warm-up complete! Total warmed: $_warmUpCount');
    }
  }

  /// Warm up cache for single vehicle with all common states
  ///
  /// Generates markers for: online/moving, online/idle (engine on/off), offline
  /// Uses frame-budgeted batching to avoid UI jank.
  void warmUpVehicle({
    required String name,
    bool compact = false,
    double pixelRatio = 2.0,
  }) {
    final states = [
      // Moving states
      MarkerRenderState(
        name: name,
        online: true,
        engineOn: true,
        moving: true,
        speed: 60,
        compact: compact,
        pixelRatio: pixelRatio,
      ),
      MarkerRenderState(
        name: name,
        online: true,
        engineOn: true,
        moving: true,
        speed: 40,
        compact: compact,
        pixelRatio: pixelRatio,
      ),
      // Idle with engine on
      MarkerRenderState(
        name: name,
        online: true,
        engineOn: true,
        moving: false,
        compact: compact,
        pixelRatio: pixelRatio,
      ),
      // Idle with engine off
      MarkerRenderState(
        name: name,
        online: true,
        engineOn: false,
        moving: false,
        compact: compact,
        pixelRatio: pixelRatio,
      ),
      // Offline
      MarkerRenderState(
        name: name,
        online: false,
        engineOn: false,
        moving: false,
        compact: compact,
        pixelRatio: pixelRatio,
      ),
    ];

    warmUp(states);
  }

  /// Check if marker is cached
  bool has(String key) => _cache.containsKey(key);

  /// Get cached image (null if not cached)
  ui.Image? operator [](String key) => _cache[key];

  /// Clear entire cache
  void clear() {
    // Dispose all images to free GPU memory
    for (final image in _cache.values) {
      image.dispose();
    }
    _cache.clear();
    _accessOrder.clear();
    _pending.clear();
    _warmUpQueue.clear();
    _isWarmUpScheduled = false;
    
    // Reset statistics
    _hits = 0;
    _misses = 0;
    _evictions = 0;
    _warmUpCount = 0;
    _batchCount = 0;
    
    debugPrint('[MARKER-CACHE] 🗑️ Cache cleared');
  }

  /// Remove markers for specific vehicle
  void clearVehicle(String name) {
    final keysToRemove =
        _cache.keys.where((k) => k.contains('_${name}_')).toList();

    for (final key in keysToRemove) {
      final image = _cache.remove(key);
      image?.dispose();
      _accessOrder.remove(key);
    }

    // Also remove from warm-up queue
    _warmUpQueue.removeWhere((q) => q.state.name == name);

    if (keysToRemove.isNotEmpty) {
      debugPrint(
        '[MARKER-CACHE] 🗑️ Cleared ${keysToRemove.length} markers for vehicle: $name',
      );
    }
  }

  /// Cache statistics
  CacheStats get stats => CacheStats(
        size: _cache.length,
        maxSize: _maxCacheSize,
        hits: _hits,
        misses: _misses,
        evictions: _evictions,
        warmUpCount: _warmUpCount,
        batchCount: _batchCount,
        queuedCount: _warmUpQueue.length,
        hitRate: _hits + _misses > 0 ? _hits / (_hits + _misses) : 0.0,
      );

  /// Number of cached markers
  int get cachedCount => _cache.length;

  /// Number of pending renders
  int get pendingCount => _pending.length;

  /// Number of queued warm-up markers
  int get queuedCount => _warmUpQueue.length;

  /// Memory usage estimate (approximate, GPU memory not included)
  int get memoryUsage {
    // Each ui.Image holds GPU memory, hard to measure exactly
    // Estimate: width * height * 4 bytes per pixel
    var totalBytes = 0;
    for (final image in _cache.values) {
      totalBytes += image.width * image.height * 4;
    }
    return totalBytes;
  }

  /// Memory usage in MB
  double get memoryUsageMB => memoryUsage / (1024 * 1024);
}

/// Queued marker for batch warm-up
class _QueuedMarker {
  _QueuedMarker({required this.key, required this.state});

  final String key;
  final MarkerRenderState state;
}

/// Marker render state (for isolate communication)
///
/// Must be simple data types (no ui.Image, no BuildContext) for compute()
class MarkerRenderState {
  MarkerRenderState({
    required this.name,
    required this.online,
    required this.engineOn,
    required this.moving,
    this.speed,
    this.compact = false,
    this.pixelRatio = 2.0,
  });

  final String name;
  final bool online;
  final bool engineOn;
  final bool moving;
  final double? speed;
  final bool compact;
  final double pixelRatio;

  /// Create from device data
  factory MarkerRenderState.fromDevice(
    Map<String, dynamic> device, {
    bool compact = false,
    double pixelRatio = 2.0,
  }) {
    final name = (device['name']?.toString() ?? '').trim();
    final statusStr = (device['status']?.toString() ?? '').toLowerCase();
    final online = statusStr.isEmpty ? true : statusStr == 'online';

    // Extract engine state
    final engineOn = device['ignition'] == true ||
        device['engineOn'] == true ||
        (device['attributes']?['ignition'] == true) ||
        false;

    // Extract motion state
    final speed = _parseSpeed(device);
    final moving = speed != null && speed > 1.0;

    return MarkerRenderState(
      name: name,
      online: online,
      engineOn: engineOn,
      moving: moving,
      speed: speed,
      compact: compact,
      pixelRatio: pixelRatio,
    );
  }

  static double? _parseSpeed(Map<String, dynamic> device) {
    try {
      // Try position.speed first
      if (device['position'] != null) {
        final position = device['position'];
        if (position is Map && position['speed'] != null) {
          return double.tryParse(position['speed'].toString());
        }
      }

      // Try direct speed attribute
      if (device['speed'] != null) {
        return double.tryParse(device['speed'].toString());
      }

      return null;
    } catch (_) {
      return null;
    }
  }

  /// Generate cache key
  String get cacheKey {
    // Round speed to reduce cache fragmentation
    final speedStr = speed != null ? (speed! / 10).round() * 10 : 'null';
    return 'marker_${name}_${online}_${engineOn}_${moving}_${speedStr}_$compact';
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is MarkerRenderState &&
        other.name == name &&
        other.online == online &&
        other.engineOn == engineOn &&
        other.moving == moving &&
        other.speed == speed &&
        other.compact == compact;
  }

  @override
  int get hashCode =>
      name.hashCode ^
      online.hashCode ^
      engineOn.hashCode ^
      moving.hashCode ^
      (speed?.hashCode ?? 0) ^
      compact.hashCode;
}

/// Cache statistics
class CacheStats {
  CacheStats({
    required this.size,
    required this.maxSize,
    required this.hits,
    required this.misses,
    required this.evictions,
    required this.warmUpCount,
    required this.batchCount,
    required this.queuedCount,
    required this.hitRate,
  });

  final int size;
  final int maxSize;
  final int hits;
  final int misses;
  final int evictions;
  final int warmUpCount;
  final int batchCount;
  final int queuedCount;
  final double hitRate;

  @override
  String toString() {
    return 'CacheStats(size: $size/$maxSize, hits: $hits, misses: $misses, '
        'evictions: $evictions, warmUp: $warmUpCount, batches: $batchCount, '
        'queued: $queuedCount, hitRate: ${(hitRate * 100).toStringAsFixed(1)}%)';
  }
}
