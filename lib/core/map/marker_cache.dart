import 'package:flutter/foundation.dart';
import 'package:latlong2/latlong.dart';
import 'package:my_app_gps/features/map/core/map_adapter.dart';
import 'package:my_app_gps/features/map/data/position_model.dart';
import 'package:my_app_gps/perf/marker_widget_pool.dart';

class MarkerCache {
  final Map<int, MapMarkerData> _cache = {};
  final Set<String> _activeMarkerIds = {};
  final Map<int, _Snapshot> _snapshots = {};

  /// Toggle verbose visual logging to reduce spam in production.
  bool verboseLogs = false;

  List<MapMarkerData> getMarkers(
    Map<int, Position> positions,
    List<Map<String, dynamic>> devices,
    Set<int> selectedIds,
    String query, {
    MarkerTier tier = MarkerTier.high,
  }) {
    final markers = <MapMarkerData>[];
    final processedIds = <int>{};
    final currentActiveIds = <String>{};
    final q = query.trim().toLowerCase();
    final pool = MarkerPoolManager.instance;

    var created = 0;
    var reused = 0;

    // Devices with positions
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
      if (q.isNotEmpty &&
          !name.toLowerCase().contains(q) &&
          !selectedIds.contains(deviceId)) {
        continue;
      }
      if (_valid(p.latitude, p.longitude)) {
        // Try to acquire from pool (will reuse if available)
        pool.acquire(
          tier: tier,
          deviceId: deviceId,
          position: LatLng(p.latitude, p.longitude),
          name: name,
          speed: p.speed,
          course: p.course,
          isSelected: selectedIds.contains(deviceId),
        );
        
        currentActiveIds.add(markerId);
        // Diffing: only rebuild when meaningful change detected
        final snap = _Snapshot(
          lat: p.latitude,
          lon: p.longitude,
          selected: selectedIds.contains(deviceId),
          speed: p.speed,
          course: p.course,
          // coarse time check (0 if null)
          tsMicros: p.deviceTime.microsecondsSinceEpoch,
        );
        final prev = _snapshots[deviceId];
        final needsUpdate = _shouldRebuild(prev, snap);

        if (needsUpdate) {
          final marker = MapMarkerData(
            id: markerId,
            position: LatLng(p.latitude, p.longitude),
            isSelected: snap.selected,
            meta: {
              'name': name,
              'speed': p.speed,
              'course': p.course,
            },
          );
          _cache[deviceId] = marker;
          _snapshots[deviceId] = snap;
          markers.add(marker);
          if (prev == null) {
            created++;
            if (verboseLogs && kDebugMode) {
              debugPrint('[MarkerCache] [MISS] Marker(deviceId=$deviceId) - First time creation');
            }
          }
        } else {
          final existing = _cache[deviceId];
          if (existing != null) {
            markers.add(existing);
            reused++;
            if (verboseLogs && kDebugMode) {
              debugPrint('[MarkerCache] [HIT] Marker(deviceId=$deviceId) - Reused (no changes)');
            }
          }
        }
        processedIds.add(deviceId);
      }
    }

    // Devices without positions
    for (final d in devices) {
      final deviceId = d['id'] as int?;
      if (deviceId == null || processedIds.contains(deviceId)) continue;
      final markerId = '$deviceId';
      final name = d['name']?.toString() ?? '';
      if (q.isNotEmpty &&
          !name.toLowerCase().contains(q) &&
          !selectedIds.contains(deviceId)) {
        continue;
      }
      final lat = _asDouble(d['latitude']);
      final lon = _asDouble(d['longitude']);
      if (_valid(lat, lon)) {
        // Try to acquire from pool
        pool.acquire(
          tier: tier,
          deviceId: deviceId,
          position: LatLng(lat!, lon!),
          name: name,
          isSelected: selectedIds.contains(deviceId),
        );
        
        currentActiveIds.add(markerId);
        final snap = _Snapshot(
          lat: lat,
          lon: lon,
          selected: selectedIds.contains(deviceId),
          speed: 0,
          course: 0,
          tsMicros: 0,
        );
        final prev = _snapshots[deviceId];
        final needsUpdate = _shouldRebuild(prev, snap);
        if (needsUpdate) {
          final marker = MapMarkerData(
            id: markerId,
            position: LatLng(lat, lon),
            isSelected: snap.selected,
            meta: {'name': name},
          );
          _cache[deviceId] = marker;
          _snapshots[deviceId] = snap;
          markers.add(marker);
          if (prev == null) created++;
        } else {
          final existing = _cache[deviceId];
          if (existing != null) {
            markers.add(existing);
            reused++;
          }
        }
      }
    }
    
    // Release markers that are no longer visible
    final idsToRelease = _activeMarkerIds.difference(currentActiveIds);
    for (final id in idsToRelease) {
      pool.releaseById(id, tier);
    }
    _activeMarkerIds
      ..clear()
      ..addAll(currentActiveIds);
    
    // Defensive: filter out any markers with invalid positions just in case
    markers
        .removeWhere((m) => !_valid(m.position.latitude, m.position.longitude));
    if (verboseLogs && kDebugMode) {
      final total = created + reused;
      final reuseRate = total == 0 ? 1.0 : reused / total;
      debugPrint('[MarkerCache] ✅ Rebuilt $created/${markers.length} markers '
          '(${(reuseRate * 100).toStringAsFixed(1)}% reuse)');
    }
    return markers;
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

class _Snapshot {
  const _Snapshot({
    required this.lat,
    required this.lon,
    required this.selected,
    required this.speed,
    required this.course,
    required this.tsMicros,
  });
  final double lat;
  final double lon;
  final bool selected;
  final double speed;
  final double course;
  final int tsMicros; // 0 when unknown
}

bool _shouldRebuild(_Snapshot? oldSnap, _Snapshot newSnap) {
  if (oldSnap == null) return true;
  if (oldSnap.selected != newSnap.selected) return true; // visual change
  if (oldSnap.tsMicros != 0 && newSnap.tsMicros != 0 && oldSnap.tsMicros == newSnap.tsMicros) {
    return false; // identical timestamp
  }
  final samePos = (oldSnap.lat - newSnap.lat).abs() < 0.000001 &&
      (oldSnap.lon - newSnap.lon).abs() < 0.000001;
  final sameState = oldSnap.speed == newSnap.speed && oldSnap.course == newSnap.course;
  if (samePos && sameState) return false;
  return true;
}
