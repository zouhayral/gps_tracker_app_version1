import 'dart:convert';

import 'package:objectbox/objectbox.dart';

// TODO(OBX5): When upgrading to ObjectBox 5.x, re-run generator and verify

/// ObjectBox entity for GeofenceEvent persistence
/// 
/// Tracks device entry/exit/dwell events for geofences
@Entity()
class GeofenceEventEntity {
  GeofenceEventEntity({
    required this.eventId,
    required this.geofenceId,
    required this.geofenceName,
    required this.deviceId,
    required this.deviceName,
    required this.eventType,
    required this.eventTimeMs,
    required this.latitude,
    required this.longitude,
    this.id = 0,
    this.status = 'pending',
    this.syncStatus = 'synced',
    this.dwellDurationMs,
    this.attributesJson = '{}',
  });

  /// Local ObjectBox ID (auto-increment)
  @Id()
  int id;

  /// Unique event ID - indexed for fast lookups
  @Unique()
  @Index()
  String eventId;

  /// Geofence ID this event belongs to - indexed for queries
  @Index()
  String geofenceId;

  /// Geofence name for UI display (cached)
  String geofenceName;

  /// Device ID that triggered the event - indexed for queries
  @Index()
  String deviceId;

  /// Device name for UI display (cached)
  String deviceName;

  /// Event type: 'enter', 'exit', or 'dwell'
  @Index()
  String eventType;

  /// Event timestamp in milliseconds since epoch (UTC)
  @Index()
  int eventTimeMs;

  /// Event location - latitude
  double latitude;

  /// Event location - longitude
  double longitude;

  /// Dwell duration in milliseconds (nullable for enter/exit events)
  int? dwellDurationMs;

  /// Event status: 'pending', 'acknowledged', 'archived'
  @Index()
  String status;

  /// Sync status: 'synced', 'pending'
  @Index()
  String syncStatus;

  /// Additional metadata as JSON string
  String attributesJson;

  /// Factory constructor from domain model
  factory GeofenceEventEntity.fromDomain({
    required String eventId,
    required String geofenceId,
    required String geofenceName,
    required String deviceId,
    required String deviceName,
    required String eventType,
    required DateTime eventTime,
    required double latitude,
    required double longitude,
    int? dwellDurationMs,
    String status = 'pending',
    String syncStatus = 'synced',
    Map<String, dynamic>? attributes,
  }) {
    return GeofenceEventEntity(
      eventId: eventId,
      geofenceId: geofenceId,
      geofenceName: geofenceName,
      deviceId: deviceId,
      deviceName: deviceName,
      eventType: eventType,
      eventTimeMs: eventTime.toUtc().millisecondsSinceEpoch,
      latitude: latitude,
      longitude: longitude,
      dwellDurationMs: dwellDurationMs,
      status: status,
      syncStatus: syncStatus,
      attributesJson: attributes != null ? _encodeAttributes(attributes) : '{}',
    );
  }

  /// Convert to domain model
  Map<String, dynamic> toDomain() {
    return {
      'id': eventId,
      'geofenceId': geofenceId,
      'geofenceName': geofenceName,
      'deviceId': deviceId,
      'deviceName': deviceName,
      'eventType': eventType,
      'timestamp': DateTime.fromMillisecondsSinceEpoch(
        eventTimeMs,
        isUtc: true,
      ),
      'latitude': latitude,
      'longitude': longitude,
      'dwellDurationMs': dwellDurationMs,
      'status': status,
      'syncStatus': syncStatus,
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
