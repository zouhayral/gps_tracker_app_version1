import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_map_marker_cluster/flutter_map_marker_cluster.dart';
import 'package:my_app_gps/features/map/core/map_adapter.dart';

/// Cached marker layer options for reuse across frames
/// Dramatically reduces rebuild cost by caching MarkerClusterLayerOptions
class MarkerLayerOptionsCache {
  MarkerLayerOptionsCache._();

  static final MarkerLayerOptionsCache instance = MarkerLayerOptionsCache._();

  // Cache key: hash of marker IDs and selection state
  final Map<String, MarkerClusterLayerOptions> _optionsCache = {};
  final Map<String, List<Marker>> _markersCache = {};

  // Cache size limits
  static const int _maxCacheSize = 10;

  /// Get or create cached marker layer options
  MarkerClusterLayerOptions getCachedOptions({
    required List<MapMarkerData> markers,
    required void Function(String)? onMarkerTap,
    required Widget Function(BuildContext, List<Marker>) clusterBuilder,
    required Widget Function(MapMarkerData) markerBuilder,
  }) {
    final cacheKey = _generateCacheKey(markers);

    // Check if we have cached options
    if (_optionsCache.containsKey(cacheKey)) {
      return _optionsCache[cacheKey]!;
    }

    // Build markers list (cache this too for marker identity)
    final builtMarkers = _buildMarkersList(
      markers,
      onMarkerTap,
      markerBuilder,
    );

    // Create new options
    final options = MarkerClusterLayerOptions(
      maxClusterRadius: 45,
      size: const Size(36, 36),
      markers: builtMarkers,
      builder: clusterBuilder,
    );

    // Cache it
    _optionsCache[cacheKey] = options;
    _markersCache[cacheKey] = builtMarkers;

    // Limit cache size
    if (_optionsCache.length > _maxCacheSize) {
      final oldestKey = _optionsCache.keys.first;
      _optionsCache.remove(oldestKey);
      _markersCache.remove(oldestKey);
    }

    return options;
  }

  /// Get cached markers list (for identity checks)
  List<Marker>? getCachedMarkers(List<MapMarkerData> markers) {
    final cacheKey = _generateCacheKey(markers);
    return _markersCache[cacheKey];
  }

  /// Build markers list
  List<Marker> _buildMarkersList(
    List<MapMarkerData> markers,
    void Function(String)? onMarkerTap,
    Widget Function(MapMarkerData) markerBuilder,
  ) {
    return markers.map((m) {
      return Marker(
        key: ValueKey('marker_${m.id}_${m.isSelected}'),
        point: m.position,
        width: 32,
        height: 32,
        child: GestureDetector(
          key: ValueKey('tap_${m.id}'),
          onTap: () => onMarkerTap?.call(m.id),
          child: markerBuilder(m),
        ),
      );
    }).toList();
  }

  /// Generate cache key from markers
  ///
  /// Includes id, selection state, and rounded coordinates to ensure
  /// cached marker widgets are reused only when their positions haven't
  /// changed materially. Rounding to 5 decimals (~1.1m) avoids excessive
  /// churn due to tiny animation deltas while still updating when markers
  /// move noticeably.
  String _generateCacheKey(List<MapMarkerData> markers) {
    if (markers.isEmpty) return 'empty';

    // Create a hash based on marker IDs and selection state
    // and their (rounded) coordinates. This ensures we get a new cache
    // entry when markers change identity, selection, or move sufficiently.
    final buffer = StringBuffer();
    for (final m in markers) {
      final lat = m.position.latitude.isFinite ? m.position.latitude.toStringAsFixed(5) : 'nan';
      final lon = m.position.longitude.isFinite ? m.position.longitude.toStringAsFixed(5) : 'nan';
      buffer.write('${m.id}_${m.isSelected ? '1' : '0'}_${lat}_${lon}_');
    }

    return buffer.toString().hashCode.toString();
  }

  /// Clear cache
  void clear() {
    _optionsCache.clear();
    _markersCache.clear();
  }

  /// Get cache statistics
  Map<String, int> get stats => {
        'cachedOptions': _optionsCache.length,
        'cachedMarkers': _markersCache.length,
      };
}
