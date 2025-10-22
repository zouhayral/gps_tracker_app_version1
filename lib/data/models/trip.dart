import 'package:intl/intl.dart';
import 'package:latlong2/latlong.dart';

/// Domain model representing a Traccar Trip (from /api/reports/trips).
///
/// Traccar reports often include fields such as deviceId, startTime, endTime,
/// distance (meters), averageSpeed, maxSpeed, and coordinates for start/end.
class Trip {
  const Trip({
    required this.id,
    required this.deviceId,
    required this.startTime,
    required this.endTime,
    required this.distanceKm,
    required this.avgSpeedKph,
    required this.maxSpeedKph,
    required this.start,
    required this.end,
  });

  final String id;
  final int deviceId;
  final DateTime startTime;
  final DateTime endTime;
  final double distanceKm;
  final double avgSpeedKph;
  final double maxSpeedKph;
  final LatLng start;
  final LatLng end;

  Duration get duration => endTime.difference(startTime);

  String get formattedDateRange {
    final df = DateFormat('MMM d, y HH:mm');
    return '${df.format(startTime)} → ${df.format(endTime)}';
  }

  String get formattedDistanceKm => '${distanceKm.toStringAsFixed(2)} km';
  String get formattedAvgSpeed => '${avgSpeedKph.toStringAsFixed(1)} km/h';
  String get formattedMaxSpeed => '${maxSpeedKph.toStringAsFixed(1)} km/h';

  /// Create a Trip from Traccar reports JSON. Falls back gracefully if some
  /// fields are missing; computes a synthetic id if not present.
  factory Trip.fromJson(Map<String, dynamic> json) {
    // Prefer explicit id when provided; otherwise generate a stable synthetic id
  final deviceId = _asInt(json['deviceId']) ?? 0;
  final startRaw = json.containsKey('startTime') ? json['startTime'] : json['start'];
  final endRaw = json.containsKey('endTime') ? json['endTime'] : json['end'];
  final start = _parseAnyDate(startRaw) ?? DateTime.now().toLocal();
  final end = _parseAnyDate(endRaw) ?? start.add(const Duration(minutes: 1));
    final syntheticId = '${deviceId}_${start.millisecondsSinceEpoch}';

    // Distance from meters to km if provided in meters; accept km directly when given
    final meters = _asDouble(json['distance']) ?? (_asDouble(json['distanceMeters']) ?? 0.0);
    final kilometers = meters > 0 ? (meters / 1000.0) : (_asDouble(json['distanceKm']) ?? 0.0);

    // Speeds: support km/h directly; if provided in m/s convert to km/h
    double speedToKph(dynamic v) {
      final s = _asDouble(v) ?? 0.0;
      // Heuristic: if value looks like m/s (usually < 50), convert to km/h
      return s <= 60 ? s * 3.6 : s;
    }

    final avgKph = speedToKph(json['averageSpeed'] ?? json['avgSpeed'] ?? json['avgSpeedKph']);
    final maxKph = speedToKph(json['maxSpeed'] ?? json['maxSpeedKph']);

    // Coordinates may be provided as startLat/startLon and endLat/endLon
    final startLat = _asDouble(json['startLat']) ?? _asDouble(json['startLatitude']) ?? 0.0;
    final startLon = _asDouble(json['startLon']) ?? _asDouble(json['startLongitude']) ?? 0.0;
    final endLat = _asDouble(json['endLat']) ?? _asDouble(json['endLatitude']) ?? 0.0;
    final endLon = _asDouble(json['endLon']) ?? _asDouble(json['endLongitude']) ?? 0.0;

    return Trip(
      id: json['id']?.toString() ?? syntheticId,
      deviceId: deviceId,
      startTime: start,
      endTime: end,
      distanceKm: kilometers,
      avgSpeedKph: avgKph,
      maxSpeedKph: maxKph,
      start: LatLng(startLat, startLon),
      end: LatLng(endLat, endLon),
    );
  }
}

int? _asInt(dynamic v) {
  if (v == null) return null;
  if (v is int) return v;
  if (v is double) return v.toInt();
  return int.tryParse(v.toString());
}

double? _asDouble(dynamic v) {
  if (v == null) return null;
  if (v is double) return v;
  if (v is int) return v.toDouble();
  return double.tryParse(v.toString());
}

DateTime? _parseTime(String? s) {
  if (s == null || s.isEmpty) return null;
  try {
    return DateTime.parse(s).toLocal();
  } catch (_) {
    return null;
  }
}

DateTime? _parseAnyDate(dynamic v) {
  if (v == null) return null;
  if (v is DateTime) return v.toLocal();
  if (v is int) {
    try {
      // Assume milliseconds since epoch
      return DateTime.fromMillisecondsSinceEpoch(v, isUtc: true).toLocal();
    } catch (_) {
      return null;
    }
  }
  if (v is String) {
    return _parseTime(v);
  }
  // Unknown type
  return null;
}

