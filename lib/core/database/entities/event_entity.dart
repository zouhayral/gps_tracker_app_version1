import 'package:objectbox/objectbox.dart';

// TODO(OBX5): On upgrade to ObjectBox 5.x, re-run codegen and verify that
// factory constructors and query/watch usages remain compatible.

/// ObjectBox entity for Event persistence
@Entity()
class EventEntity {
  EventEntity({
    required this.eventId,
    required this.deviceId,
    required this.eventType,
    required this.eventTimeMs,
    this.id = 0,
    this.positionId,
    this.geofenceId,
    this.maintenanceId,
    this.priority,
    this.severity,
    this.message,
    this.attributesJson = '{}',
  });

  /// Local ObjectBox ID (auto-increment)
  @Id()
  int id;

  /// Backend event ID - indexed for fast lookups
  @Unique()
  @Index()
  String eventId;

  /// Device ID this event belongs to - indexed for querying events by device
  @Index()
  int deviceId;

  /// Event type (e.g., "deviceOnline", "deviceOffline", "geofenceEnter", "geofenceExit", "alarm", etc.)
  @Index()
  String eventType;

  /// Event timestamp in milliseconds since epoch
  @Index()
  int eventTimeMs;

  /// Related position ID
  int? positionId;

  /// Related geofence ID (if applicable)
  @Index()
  int? geofenceId;

  /// Related maintenance ID (if applicable)
  int? maintenanceId;

  /// Event priority (for sorting/filtering)
  String? priority;

  /// Event severity level
  String? severity;

  /// Human-readable message
  String? message;

  /// JSON string for additional attributes
  String attributesJson;

  /// Factory constructor from domain entity
  factory EventEntity.fromDomain({
    required String eventId,
    required int deviceId,
    required String eventType,
    required DateTime eventTime,
    int? positionId,
    int? geofenceId,
    int? maintenanceId,
    String? priority,
    String? severity,
    String? message,
    Map<String, dynamic>? attributes,
  }) {
    return EventEntity(
      eventId: eventId,
      deviceId: deviceId,
      eventType: eventType,
      eventTimeMs: eventTime.toUtc().millisecondsSinceEpoch,
      positionId: positionId,
      geofenceId: geofenceId,
      maintenanceId: maintenanceId,
      priority: priority,
      severity: severity,
      message: message,
      attributesJson:
          attributes != null ? _encodeAttributes(attributes) : '{}',
    );
  }

  /// Convert to domain entity
  Map<String, dynamic> toDomain() {
    return {
      'id': eventId,
      'deviceId': deviceId,
      'type': eventType,
      'eventTime':
          DateTime.fromMillisecondsSinceEpoch(eventTimeMs, isUtc: true)
              .toLocal(),
      'positionId': positionId,
      'geofenceId': geofenceId,
      'maintenanceId': maintenanceId,
      'priority': priority,
      'severity': severity,
      'message': message,
      'attributes': _decodeAttributes(attributesJson),
    };
  }

  static String _encodeAttributes(Map<String, dynamic> attributes) {
    try {
      return attributes.toString();
    } catch (_) {
      return '{}';
    }
  }

  static Map<String, dynamic> _decodeAttributes(String json) {
    try {
      return {};
    } catch (_) {
      return {};
    }
  }
}
