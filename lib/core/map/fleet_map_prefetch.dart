import 'dart:async';
import 'dart:math';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:my_app_gps/core/map/ai_map_optimizer.dart';
import 'package:my_app_gps/core/map/map_perf_monitor.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Fleet Map Prefetch & Snapshot Cache Manager
///
/// Responsibilities:
/// 1. Tile Prefetch: Warm up visible region tiles before map display
/// 2. Camera Smoothing: Debounced/animated camera movements
/// 3. Snapshot Cache: Save/restore last view state for instant reopen
///
/// Performance Targets:
/// - Map load time: < 600ms (with snapshot)
/// - Camera animation: Smooth 60fps, < 12ms frame time
/// - Tile prefetch: Parallel loading before first paint
/// - Snapshot restore: < 100ms

class FleetMapPrefetchManager {
  FleetMapPrefetchManager({
    required this.prefs,
    this.debugMode = false,
    this.perfMonitor,
    this.aiOptimizer,
  });

  final SharedPreferences prefs;
  final bool debugMode;
  final MapPerfMonitor? perfMonitor;
  final AiMapOptimizer? aiOptimizer;

  // Snapshot cache keys
  static const String _keySnapshotImage = 'fleet_map_snapshot_image';
  static const String _keySnapshotLat = 'fleet_map_snapshot_lat';
  static const String _keySnapshotLng = 'fleet_map_snapshot_lng';
  static const String _keySnapshotZoom = 'fleet_map_snapshot_zoom';
  static const String _keySnapshotTimestamp = 'fleet_map_snapshot_timestamp';

  // Camera animation queue
  final List<_CameraMove> _cameraMoveQueue = [];
  Timer? _cameraAnimationTimer;
  bool _isAnimating = false;
  bool _isDisposed = false;

  // Tile prefetch tracking
  final Set<String> _prefetchedTiles = {};
  bool _isPrefetching = false;

  // Snapshot state
  Uint8List? _cachedSnapshot;
  LatLng? _cachedCenter;
  double? _cachedZoom;
  DateTime? _cachedTimestamp;

  // AI optimization config
  MapOptimizationConfig _aiConfig = MapOptimizationConfig.defaults();

  /// Initialize and load cached snapshot
  Future<void> initialize() async {
    final stopwatch = Stopwatch()..start();

    try {
      // Load snapshot metadata
      final lat = prefs.getDouble(_keySnapshotLat);
      final lng = prefs.getDouble(_keySnapshotLng);
      final zoom = prefs.getDouble(_keySnapshotZoom);
      final timestampMs = prefs.getInt(_keySnapshotTimestamp);

      if (lat != null && lng != null && zoom != null && timestampMs != null) {
        _cachedCenter = LatLng(lat, lng);
        _cachedZoom = zoom;
        _cachedTimestamp = DateTime.fromMillisecondsSinceEpoch(timestampMs);

        // Load snapshot image (base64 encoded)
        final snapshotBase64 = prefs.getString(_keySnapshotImage);
        if (snapshotBase64 != null && snapshotBase64.isNotEmpty) {
          // Decode base64 to bytes
          try {
            _cachedSnapshot = Uint8List.fromList(
              snapshotBase64.codeUnits.map((c) => c & 0xFF).toList(),
            );
          } catch (e) {
            debugPrint('[FleetMapPrefetch] ✗ Snapshot decode failed: $e');
            _cachedSnapshot = null;
          }
        }

        final age = DateTime.now().difference(_cachedTimestamp!);
        if (debugMode) {
          debugPrint(
            '[FleetMapPrefetch] ✓ Loaded snapshot: '
            'center=$_cachedCenter, zoom=$_cachedZoom, age=${age.inMinutes}m',
          );
        }
      } else {
        if (debugMode) {
          debugPrint('[FleetMapPrefetch] ⓘ No cached snapshot found');
        }
      }
    } catch (e) {
      debugPrint('[FleetMapPrefetch] ✗ Init error: $e');
    }

    stopwatch.stop();
    if (debugMode) {
      debugPrint(
        '[FleetMapPrefetch] ✅ Initialized in ${stopwatch.elapsedMilliseconds}ms',
      );
    }
  }

  /// Get cached snapshot for instant display
  MapSnapshot? getCachedSnapshot() {
    if (_cachedSnapshot != null &&
        _cachedCenter != null &&
        _cachedZoom != null &&
        _cachedTimestamp != null) {
      // Validate snapshot age (reject if > 24 hours old)
      final age = DateTime.now().difference(_cachedTimestamp!);
      if (age.inHours > 24) {
        if (debugMode) {
          debugPrint(
            '[FleetMapPrefetch] ⚠️ Snapshot too old (${age.inHours}h)',
          );
        }
        return null;
      }

      return MapSnapshot(
        imageBytes: _cachedSnapshot!,
        center: _cachedCenter!,
        zoom: _cachedZoom!,
        timestamp: _cachedTimestamp!,
      );
    }
    return null;
  }

  /// Capture and save current map view snapshot
  Future<void> captureSnapshot({
    required GlobalKey mapKey,
    required LatLng center,
    required double zoom,
  }) async {
    if (_isPrefetching) {
      if (debugMode) {
        debugPrint(
          '[FleetMapPrefetch] ⏭️ Skip snapshot (prefetch in progress)',
        );
      }
      return;
    }

    final stopwatch = Stopwatch()..start();

    try {
      // Find RenderRepaintBoundary
      final boundary =
          mapKey.currentContext?.findRenderObject() as RenderRepaintBoundary?;

      if (boundary == null) {
        if (debugMode) {
          debugPrint('[FleetMapPrefetch] ✗ Map boundary not found');
        }
        return;
      }

      // Capture image at reduced resolution to save memory (0.5x scale)
      final image = await boundary.toImage(pixelRatio: 0.5);
      final byteData = await image.toByteData(format: ui.ImageByteFormat.png);

      if (byteData == null) {
        if (debugMode) {
          debugPrint('[FleetMapPrefetch] ✗ Failed to encode snapshot');
        }
        return;
      }

      final bytes = byteData.buffer.asUint8List();

      // Convert to base64-like string for SharedPreferences (simple encoding)
      final encoded = String.fromCharCodes(bytes);

      // Save to SharedPreferences
      await Future.wait([
        prefs.setString(_keySnapshotImage, encoded),
        prefs.setDouble(_keySnapshotLat, center.latitude),
        prefs.setDouble(_keySnapshotLng, center.longitude),
        prefs.setDouble(_keySnapshotZoom, zoom),
        prefs.setInt(
          _keySnapshotTimestamp,
          DateTime.now().millisecondsSinceEpoch,
        ),
      ]);

      // Update cache
      _cachedSnapshot = bytes;
      _cachedCenter = center;
      _cachedZoom = zoom;
      _cachedTimestamp = DateTime.now();

      stopwatch.stop();
      if (debugMode) {
        debugPrint(
          '[FleetMapPrefetch] ✅ Captured snapshot: '
          '${(bytes.length / 1024).toStringAsFixed(1)}KB in ${stopwatch.elapsedMilliseconds}ms',
        );
      }
    } catch (e) {
      debugPrint('[FleetMapPrefetch] ✗ Snapshot capture error: $e');
    }
  }

  /// Prefetch tiles for visible region (before map display)
  Future<void> prefetchVisibleTiles({
    required MapController controller,
    required LatLng center,
    required double zoom,
  }) async {
    if (_isPrefetching) {
      if (debugMode) {
        debugPrint('[FleetMapPrefetch] ⏭️ Prefetch already in progress');
      }
      return;
    }

    _isPrefetching = true;
    final stopwatch = Stopwatch()..start();

    try {
      // Move camera to target position (instant, no animation)
      controller.move(center, zoom);

      // Wait for next frame to ensure map has updated
      await Future<void>.delayed(const Duration(milliseconds: 16));

      // Get visible region bounds
      final bounds = controller.camera.visibleBounds;
      final currentZoom = controller.camera.zoom.floor();

      // Calculate tile coordinates for visible region
      final tiles = _calculateVisibleTiles(bounds, currentZoom);

      if (debugMode) {
        debugPrint(
          '[FleetMapPrefetch] 🔍 Prefetching ${tiles.length} tiles at zoom $currentZoom',
        );
      }

      // Prefetch tiles in parallel (batches - use AI-optimized batch size)
      final batchSize = _aiConfig.tilePrefetchBatch;
      var loadedCount = 0;
      final tileLoadStopwatch = Stopwatch();

      for (var i = 0; i < tiles.length; i += batchSize) {
        final batch = tiles.skip(i).take(batchSize).toList();
        
        tileLoadStopwatch.reset();
        tileLoadStopwatch.start();
        
        final futures = batch.map(_prefetchTile);
        final results = await Future.wait(futures);
        
        tileLoadStopwatch.stop();
        
        // Track tile load time for AI telemetry
        perfMonitor?.onTileLoaded(Duration(milliseconds: tileLoadStopwatch.elapsedMilliseconds));
        
        loadedCount += results.where((success) => success).length;

        // Small delay between batches to avoid blocking UI
        if (i + batchSize < tiles.length) {
          await Future<void>.delayed(const Duration(milliseconds: 10));
        }
      }

      stopwatch.stop();
      if (debugMode) {
        debugPrint(
          '[FleetMapPrefetch] ✅ Prefetched $loadedCount/${tiles.length} tiles '
          'in ${stopwatch.elapsedMilliseconds}ms',
        );
      }
    } catch (e) {
      debugPrint('[FleetMapPrefetch] ✗ Prefetch error: $e');
    } finally {
      _isPrefetching = false;
    }
  }

  /// Calculate tile coordinates for visible region
  List<TileCoordinate> _calculateVisibleTiles(
    LatLngBounds bounds,
    int zoom,
  ) {
    final tiles = <TileCoordinate>[];

    // Convert lat/lng bounds to tile coordinates
    final nwTile = _latLngToTile(
      LatLng(bounds.north, bounds.west),
      zoom,
    );
    final seTile = _latLngToTile(
      LatLng(bounds.south, bounds.east),
      zoom,
    );

    // Generate all tiles in the grid (with safety limit)
    const maxTiles = 100; // Prevent excessive tile loading
    for (var x = nwTile.x; x <= seTile.x && tiles.length < maxTiles; x++) {
      for (var y = nwTile.y; y <= seTile.y && tiles.length < maxTiles; y++) {
        tiles.add(TileCoordinate(x: x, y: y, z: zoom));
      }
    }

    return tiles;
  }

  /// Convert lat/lng to tile coordinates
  TileCoordinate _latLngToTile(LatLng latLng, int zoom) {
    final n = (1 << zoom).toDouble();
    final x = ((latLng.longitude + 180.0) / 360.0 * n).floor();
    final latRad = latLng.latitude * pi / 180.0;
    // asinh(x) = ln(x + sqrt(x*x + 1))
    final asinhValue = log(tan(latRad) + sqrt(tan(latRad) * tan(latRad) + 1));
    final y = ((1.0 - asinhValue / pi) / 2.0 * n).floor();
    return TileCoordinate(x: x, y: y, z: zoom);
  }

  /// Prefetch a single tile (mock implementation - actual tile loading handled by flutter_map)
  Future<bool> _prefetchTile(TileCoordinate tile) async {
    final key = '${tile.z}/${tile.x}/${tile.y}';

    // Skip if already prefetched
    if (_prefetchedTiles.contains(key)) {
      return true;
    }

    try {
      // In production, this would trigger the tile provider to cache the tile
      // For now, we just mark it as prefetched and rely on flutter_map_tile_caching
      _prefetchedTiles.add(key);
      return true;
    } catch (e) {
      return false;
    }
  }

  /// Smooth camera move with animation queue
  void smoothMoveTo({
    required MapController controller,
    required LatLng target,
    required double zoom,
    Duration duration = const Duration(milliseconds: 300),
    Curve curve = Curves.easeInOut,
  }) {
    if (_isDisposed) return; // Don't queue moves after dispose

    // Track zoom start for AI telemetry
    perfMonitor?.onZoomStart(controller.camera.zoom);

    // Use AI-optimized duration if available
    final optimizedDuration = _aiConfig.zoomAnimationDuration;

    // Add move to queue
    _cameraMoveQueue.add(
      _CameraMove(
        target: target,
        zoom: zoom,
        duration: optimizedDuration,
        curve: curve,
      ),
    );

    // Start animation processor if not running
    if (!_isAnimating) {
      _processCameraMoveQueue(controller);
    }
  }

  /// Process camera move queue with smooth animations
  Future<void> _processCameraMoveQueue(MapController controller) async {
    if (_cameraMoveQueue.isEmpty || _isDisposed) {
      _isAnimating = false;
      return;
    }

    _isAnimating = true;
    final move = _cameraMoveQueue.removeAt(0);

    try {
      // Animate camera using custom interpolation
      await _animateCameraMove(
        controller: controller,
        target: move.target,
        zoom: move.zoom,
        duration: move.duration,
        curve: move.curve,
      );
    } catch (e) {
      debugPrint('[FleetMapPrefetch] ✗ Camera animation error: $e');
    }

    // Process next move (check if disposed)
    if (_cameraMoveQueue.isNotEmpty && !_isDisposed) {
      await _processCameraMoveQueue(controller);
    } else {
      _isAnimating = false;
    }
  }

  /// Animate camera move with custom curve interpolation
  Future<void> _animateCameraMove({
    required MapController controller,
    required LatLng target,
    required double zoom,
    required Duration duration,
    required Curve curve,
  }) async {
    final start = controller.camera.center;
    final startZoom = controller.camera.zoom;
    final stopwatch = Stopwatch()..start();

    const frameRate = 60;
    const frameDuration = Duration(milliseconds: 1000 ~/ frameRate);
    final totalFrames = duration.inMilliseconds ~/ frameDuration.inMilliseconds;

    for (var frame = 0; frame <= totalFrames && !_isDisposed; frame++) {
      final t = curve.transform(frame / totalFrames);

      // Interpolate position
      final lat = start.latitude + (target.latitude - start.latitude) * t;
      final lng = start.longitude + (target.longitude - start.longitude) * t;
      final currentZoom = startZoom + (zoom - startZoom) * t;

      // Move camera
      controller.move(LatLng(lat, lng), currentZoom);

      // Wait for next frame (check for dispose)
      if (frame < totalFrames && !_isDisposed) {
        await Future<void>.delayed(frameDuration);
      }
    }

    stopwatch.stop();
    
    // Track zoom end for AI telemetry
    perfMonitor?.onZoomEnd(zoom);
    
    if (debugMode && !_isDisposed) {
      debugPrint(
        '[FleetMapPrefetch] ✓ Camera animation completed in ${stopwatch.elapsedMilliseconds}ms',
      );
    }
  }

  /// Debounced camera move (prevents excessive updates)
  Timer? _debounceTimer;
  void debouncedMoveTo({
    required MapController controller,
    required LatLng target,
    required double zoom,
    Duration debounce = const Duration(milliseconds: 300),
    Duration animationDuration = const Duration(milliseconds: 300),
  }) {
    _debounceTimer?.cancel();
    _debounceTimer = Timer(debounce, () {
      smoothMoveTo(
        controller: controller,
        target: target,
        zoom: zoom,
        duration: animationDuration,
      );
    });
  }

  /// Clear snapshot cache
  Future<void> clearSnapshot() async {
    await Future.wait([
      prefs.remove(_keySnapshotImage),
      prefs.remove(_keySnapshotLat),
      prefs.remove(_keySnapshotLng),
      prefs.remove(_keySnapshotZoom),
      prefs.remove(_keySnapshotTimestamp),
    ]);

    _cachedSnapshot = null;
    _cachedCenter = null;
    _cachedZoom = null;
    _cachedTimestamp = null;

    if (debugMode) {
      debugPrint('[FleetMapPrefetch] ✓ Snapshot cache cleared');
    }
  }

  /// Update AI optimization config
  void updateAiConfig(MapOptimizationConfig config) {
    _aiConfig = config;
    
    if (debugMode) {
      debugPrint('[FleetMapPrefetch] 🤖 AI config updated:');
      debugPrint('  - Zoom debounce: ${config.zoomDebounceDuration.inMilliseconds}ms');
      debugPrint('  - Zoom animation: ${config.zoomAnimationDuration.inMilliseconds}ms');
      debugPrint('  - Tile batch: ${config.tilePrefetchBatch}');
      debugPrint('  - Marker cache: ${config.markerCacheSize}');
    }
  }

  /// Get current AI config
  MapOptimizationConfig get aiConfig => _aiConfig;

  /// Dispose resources
  void dispose() {
    _isDisposed = true;
    _cameraAnimationTimer?.cancel();
    _debounceTimer?.cancel();
    _prefetchedTiles.clear();
    _cameraMoveQueue.clear();

    if (debugMode) {
      debugPrint('[FleetMapPrefetch] ✓ Disposed');
    }
  }
}

/// Camera move request
class _CameraMove {
  _CameraMove({
    required this.target,
    required this.zoom,
    required this.duration,
    required this.curve,
  });

  final LatLng target;
  final double zoom;
  final Duration duration;
  final Curve curve;
}

/// Tile coordinate
class TileCoordinate {
  TileCoordinate({required this.x, required this.y, required this.z});

  final int x;
  final int y;
  final int z;

  @override
  String toString() => 'Tile($z/$x/$y)';
}

/// Map snapshot data
class MapSnapshot {
  MapSnapshot({
    required this.imageBytes,
    required this.center,
    required this.zoom,
    required this.timestamp,
  });

  final Uint8List imageBytes;
  final LatLng center;
  final double zoom;
  final DateTime timestamp;

  /// Get age of snapshot
  Duration get age => DateTime.now().difference(timestamp);

  /// Check if snapshot is fresh (< 1 hour)
  bool get isFresh => age.inHours < 1;
}
