import 'package:latlong2/latlong.dart';
import 'package:my_app_gps/features/map/core/map_adapter.dart';
import 'package:my_app_gps/features/map/data/position_model.dart';

/// Enhanced marker cache with intelligent diffing and memoization
/// Prevents unnecessary marker object creation and reduces memory churn
class EnhancedMarkerCache {
  final Map<String, MapMarkerData> _cache = {};
  final Map<String, _MarkerSnapshot> _snapshots = {};

  /// Get markers with intelligent diffing - only updates changed markers
  MarkerDiffResult getMarkersWithDiff(
    Map<int, Position> positions,
    List<Map<String, dynamic>> devices,
    Set<int> selectedIds,
    String query,
  ) {
    final updated = <MapMarkerData>[];
    final created = <String>[];
    final reused = <String>[];
    final removed = <String>[];
    final processedIds = <String>{};
    final q = query.trim().toLowerCase();

    // Process devices with positions
    for (final p in positions.values) {
      final deviceId = p.deviceId;
      final markerId = '$deviceId';
      final name = devices
              .firstWhere(
                (d) => d['id'] == deviceId,
                orElse: () => <String, Object>{'name': ''},
              )['name']
              ?.toString() ??
          '';

      // Filter by query if not selected
      if (q.isNotEmpty &&
          !name.toLowerCase().contains(q) &&
          !selectedIds.contains(deviceId)) {
        continue;
      }

      if (_valid(p.latitude, p.longitude)) {
        final snapshot = _MarkerSnapshot(
          lat: p.latitude,
          lon: p.longitude,
          isSelected: selectedIds.contains(deviceId),
          speed: p.speed,
          course: p.course,
        );

        final existingSnapshot = _snapshots[markerId];
        final existingMarker = _cache[markerId];

        // Check if marker needs update
        if (existingSnapshot == null ||
            existingMarker == null ||
            existingSnapshot != snapshot) {
          // Create or update marker
          final marker = MapMarkerData(
            id: markerId,
            position: LatLng(p.latitude, p.longitude),
            heading: p.course,
            isSelected: selectedIds.contains(deviceId),
            meta: {
              'name': name,
              'speed': p.speed,
              'course': p.course,
            },
          );

          _cache[markerId] = marker;
          _snapshots[markerId] = snapshot;
          updated.add(marker);

          if (existingSnapshot == null) {
            created.add(markerId);
          }
        } else {
          // Reuse existing marker
          updated.add(existingMarker);
          reused.add(markerId);
        }

        processedIds.add(markerId);
      }
    }

    // Process devices without positions (last known location)
    for (final d in devices) {
      final deviceId = d['id'] as int?;
      if (deviceId == null) continue;

      final markerId = '$deviceId';
      if (processedIds.contains(markerId)) continue;

      final name = d['name']?.toString() ?? '';

      // Filter by query if not selected
      if (q.isNotEmpty &&
          !name.toLowerCase().contains(q) &&
          !selectedIds.contains(deviceId)) {
        continue;
      }

      final lat = _asDouble(d['latitude']);
      final lon = _asDouble(d['longitude']);

      if (_valid(lat, lon)) {
        final snapshot = _MarkerSnapshot(
          lat: lat!,
          lon: lon!,
          isSelected: selectedIds.contains(deviceId),
          speed: 0,
          course: 0,
        );

        final existingSnapshot = _snapshots[markerId];
        final existingMarker = _cache[markerId];

        // Check if marker needs update
        if (existingSnapshot == null ||
            existingMarker == null ||
            existingSnapshot != snapshot) {
          // Create or update marker
          final marker = MapMarkerData(
            id: markerId,
            position: LatLng(lat, lon),
            isSelected: selectedIds.contains(deviceId),
            meta: {'name': name},
          );

          _cache[markerId] = marker;
          _snapshots[markerId] = snapshot;
          updated.add(marker);

          if (existingSnapshot == null) {
            created.add(markerId);
          }
        } else {
          // Reuse existing marker
          updated.add(existingMarker);
          reused.add(markerId);
        }

        processedIds.add(markerId);
      }
    }

    // Remove markers for devices that no longer exist
    final toRemove =
        _cache.keys.where((id) => !processedIds.contains(id)).toList();
    for (final id in toRemove) {
      _cache.remove(id);
      _snapshots.remove(id);
      removed.add(id);
    }

    return MarkerDiffResult(
      markers: updated,
      created: created.length,
      reused: reused.length,
      removed: removed.length,
      totalCached: _cache.length,
    );
  }

  /// Clear all cached markers
  void clear() {
    _cache.clear();
    _snapshots.clear();
  }

  /// Get cache statistics
  Map<String, dynamic> getStats() {
    return {
      'cached_markers': _cache.length,
      'snapshots': _snapshots.length,
    };
  }

  bool _valid(double? lat, double? lon) =>
      lat != null &&
      lon != null &&
      lat >= -90 &&
      lat <= 90 &&
      lon >= -180 &&
      lon <= 180;

  double? _asDouble(dynamic v) {
    if (v == null) return null;
    if (v is double) return v;
    if (v is int) return v.toDouble();
    if (v is String) return double.tryParse(v);
    return null;
  }
}

/// Result of marker diff operation
class MarkerDiffResult {
  const MarkerDiffResult({
    required this.markers,
    required this.created,
    required this.reused,
    required this.removed,
    required this.totalCached,
  });

  final List<MapMarkerData> markers;
  final int created;
  final int reused;
  final int removed;
  final int totalCached;

  /// Efficiency ratio: reused / (created + reused)
  double get efficiency {
    final total = created + reused;
    if (total == 0) return 0;
    return reused / total;
  }

  @override
  String toString() =>
      'MarkerDiff(total=${markers.length}, created=$created, reused=$reused, removed=$removed, cached=$totalCached, efficiency=${(efficiency * 100).toStringAsFixed(1)}%)';
}

/// Lightweight snapshot of marker state for diffing
class _MarkerSnapshot {
  const _MarkerSnapshot({
    required this.lat,
    required this.lon,
    required this.isSelected,
    required this.speed,
    required this.course,
  });

  final double lat;
  final double lon;
  final bool isSelected;
  final double speed;
  final double course;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is _MarkerSnapshot &&
          runtimeType == other.runtimeType &&
          lat == other.lat &&
          lon == other.lon &&
          isSelected == other.isSelected &&
          speed == other.speed &&
          course == other.course;

  @override
  int get hashCode =>
      lat.hashCode ^
      lon.hashCode ^
      isSelected.hashCode ^
      speed.hashCode ^
      course.hashCode;
}
