import 'dart:convert';

import 'package:objectbox/objectbox.dart';

// TODO(OBX5): When migrating to ObjectBox 5.x re-run generator and confirm
// entity fields and indices are still valid. Update factories to named ctors
// if necessary.

/// ObjectBox entity for Geofence persistence
/// 
/// Enhanced to support full geofencing features:
/// - Circle and polygon geofences
/// - Device monitoring
/// - Entry/exit/dwell triggers
/// - Notification configuration
@Entity()
class GeofenceEntity {
  GeofenceEntity({
    required this.geofenceId,
    required this.name,
    this.id = 0,
    this.description,
    this.area,
    this.calendarId,
    this.attributesJson = '{}',
  });

  /// Local ObjectBox ID (auto-increment)
  @Id()
  int id;

  /// Backend geofence ID - indexed for fast lookups
  /// Note: Changed to String for UUID support in new implementation
  /// For backward compatibility, this remains int
  @Unique()
  @Index()
  int geofenceId;

  /// Geofence name - indexed for searching
  @Index()
  String name;

  /// Optional description
  String? description;

  /// Geofence area definition (WKT format: POLYGON, CIRCLE, etc.)
  /// Example: "CIRCLE (lat lon, radius)" or "POLYGON((x1 y1, x2 y2, ...))"
  @Index()
  String? area;

  /// Optional calendar ID for time-based geofences
  int? calendarId;

  /// JSON string for additional attributes
  /// Now stores: userId, enabled, monitoredDevices, triggers, notifications, etc.
  String attributesJson;

  /// Factory constructor from domain entity
  factory GeofenceEntity.fromDomain({
    required int geofenceId,
    required String name,
    String? description,
    String? area,
    int? calendarId,
    Map<String, dynamic>? attributes,
  }) {
    return GeofenceEntity(
      geofenceId: geofenceId,
      name: name,
      description: description,
      area: area,
      calendarId: calendarId,
      attributesJson: attributes != null ? _encodeAttributes(attributes) : '{}',
    );
  }

  /// Convert to domain entity
  Map<String, dynamic> toDomain() {
    return {
      'id': geofenceId,
      'name': name,
      'description': description,
      'area': area,
      'calendarId': calendarId,
      'attributes': _decodeAttributes(attributesJson),
    };
  }

  static String _encodeAttributes(Map<String, dynamic> attributes) {
    try {
      return jsonEncode(attributes);
    } catch (_) {
      return '{}';
    }
  }

  static Map<String, dynamic> _decodeAttributes(String json) {
    try {
      if (json.isEmpty || json == '{}') return {};
      final decoded = jsonDecode(json);
      return decoded is Map<String, dynamic> ? decoded : {};
    } catch (_) {
      return {};
    }
  }
}
