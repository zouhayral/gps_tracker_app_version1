import 'package:latlong2/latlong.dart';
import 'package:my_app_gps/features/map/core/map_adapter.dart';
import 'package:my_app_gps/features/map/data/position_model.dart';

class MarkerCache {
  final Map<int, MapMarkerData> _cache = {};

  List<MapMarkerData> getMarkers(
    Map<int, Position> positions,
    List<Map<String, dynamic>> devices,
    Set<int> selectedIds,
    String query,
  ) {
    final markers = <MapMarkerData>[];
    final processedIds = <int>{};
    final q = query.trim().toLowerCase();

    // Devices with positions
    for (final p in positions.values) {
      final deviceId = p.deviceId;
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
        markers.add(_cache.putIfAbsent(
          deviceId,
          () => MapMarkerData(
            id: '$deviceId',
            position: LatLng(p.latitude, p.longitude),
            isSelected: selectedIds.contains(deviceId),
            meta: {
              'name': name,
              'speed': p.speed,
              'course': p.course,
            },
          ),
        ));
        processedIds.add(deviceId);
      }
    }

    // Devices without positions
    for (final d in devices) {
      final deviceId = d['id'] as int?;
      if (deviceId == null || processedIds.contains(deviceId)) continue;
      final name = d['name']?.toString() ?? '';
      if (q.isNotEmpty &&
          !name.toLowerCase().contains(q) &&
          !selectedIds.contains(deviceId)) {
        continue;
      }
      final lat = _asDouble(d['latitude']);
      final lon = _asDouble(d['longitude']);
      if (_valid(lat, lon)) {
        markers.add(_cache.putIfAbsent(
          deviceId,
          () => MapMarkerData(
            id: '$deviceId',
            position: LatLng(lat!, lon!),
            isSelected: selectedIds.contains(deviceId),
            meta: {'name': name},
          ),
        ));
      }
    }
    // Defensive: filter out any markers with invalid positions just in case
    markers
        .removeWhere((m) => !_valid(m.position.latitude, m.position.longitude));
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
