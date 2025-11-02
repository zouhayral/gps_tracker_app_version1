import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:latlong2/latlong.dart';

/// Domain model representing a geofence event (entry, exit, or dwell).
/// Converts between:
///   • REST/WebSocket JSON
///   • SQLite Map storage
///   • UI-friendly data (icon, color, formatted message)
class GeofenceEvent {
  final String id;
  final String geofenceId;
  final String geofenceName; // For UI display
  final String deviceId;
  final String deviceName; // For UI display
  final String eventType; // 'enter' | 'exit' | 'dwell'
  final DateTime timestamp;
  final double latitude;
  final double longitude;
  final String status; // 'pending' | 'acknowledged' | 'archived'
  final String syncStatus; // 'synced' | 'pending'
  final DateTime createdAt;
  final int? dwellDurationMs; // For dwell events
  final Map<String, dynamic> attributes; // Additional metadata

  const GeofenceEvent({
    required this.id,
    required this.geofenceId,
    required this.geofenceName,
    required this.deviceId,
    required this.deviceName,
    required this.eventType,
    required this.timestamp,
    required this.latitude,
    required this.longitude,
    required this.createdAt, this.status = 'pending',
    this.syncStatus = 'synced',
    this.dwellDurationMs,
    this.attributes = const {},
  });

  // -----------------------------
  // Factory Constructors
  // -----------------------------

  /// Create an entry event
  factory GeofenceEvent.entry({
    required String id,
    required String geofenceId,
    required String geofenceName,
    required String deviceId,
    required String deviceName,
    required LatLng location,
    DateTime? timestamp,
  }) {
    final now = DateTime.now().toUtc();
    return GeofenceEvent(
      id: id,
      geofenceId: geofenceId,
      geofenceName: geofenceName,
      deviceId: deviceId,
      deviceName: deviceName,
      eventType: 'enter',
      timestamp: timestamp ?? now,
      latitude: location.latitude,
      longitude: location.longitude,
      syncStatus: 'pending',
      createdAt: now,
      attributes: {'priority': 'high'},
    );
  }

  /// Create an exit event
  factory GeofenceEvent.exit({
    required String id,
    required String geofenceId,
    required String geofenceName,
    required String deviceId,
    required String deviceName,
    required LatLng location,
    DateTime? timestamp,
  }) {
    final now = DateTime.now().toUtc();
    return GeofenceEvent(
      id: id,
      geofenceId: geofenceId,
      geofenceName: geofenceName,
      deviceId: deviceId,
      deviceName: deviceName,
      eventType: 'exit',
      timestamp: timestamp ?? now,
      latitude: location.latitude,
      longitude: location.longitude,
      syncStatus: 'pending',
      createdAt: now,
      attributes: {'priority': 'high'},
    );
  }

  /// Create a dwell event
  factory GeofenceEvent.dwell({
    required String id,
    required String geofenceId,
    required String geofenceName,
    required String deviceId,
    required String deviceName,
    required LatLng location,
    required int dwellDurationMs,
    DateTime? timestamp,
  }) {
    final now = DateTime.now().toUtc();
    return GeofenceEvent(
      id: id,
      geofenceId: geofenceId,
      geofenceName: geofenceName,
      deviceId: deviceId,
      deviceName: deviceName,
      eventType: 'dwell',
      timestamp: timestamp ?? now,
      latitude: location.latitude,
      longitude: location.longitude,
      syncStatus: 'pending',
      createdAt: now,
      dwellDurationMs: dwellDurationMs,
      attributes: {'priority': 'default'},
    );
  }

  /// Create event from location data (generic constructor)
  factory GeofenceEvent.fromLocation({
    required String id,
    required String geofenceId,
    required String geofenceName,
    required String deviceId,
    required String deviceName,
    required String eventType,
    required double latitude,
    required double longitude,
    DateTime? timestamp,
    int? dwellDurationMs,
    Map<String, dynamic>? attributes,
  }) {
    final now = DateTime.now().toUtc();
    return GeofenceEvent(
      id: id,
      geofenceId: geofenceId,
      geofenceName: geofenceName,
      deviceId: deviceId,
      deviceName: deviceName,
      eventType: eventType,
      timestamp: timestamp ?? now,
      latitude: latitude,
      longitude: longitude,
      syncStatus: 'pending',
      createdAt: now,
      dwellDurationMs: dwellDurationMs,
      attributes: attributes ?? {},
    );
  }

  // -----------------------------
  // JSON Serialization
  // -----------------------------

  factory GeofenceEvent.fromJson(Map<String, dynamic> json) {
    final rawTimestamp =
        (json['timestamp'] ?? json['eventTime'] ?? '') as String?;
    final rawCreatedAt = (json['createdAt'] ?? json['created_at'] ?? '') as String?;

    final parsedTimestamp = rawTimestamp != null && rawTimestamp.isNotEmpty
        ? DateTime.tryParse(rawTimestamp)
        : null;
    final parsedCreatedAt = rawCreatedAt != null && rawCreatedAt.isNotEmpty
        ? DateTime.tryParse(rawCreatedAt)
        : null;

    final timestampUtc = (parsedTimestamp ?? DateTime.now()).toUtc();
    final createdAtUtc = (parsedCreatedAt ?? DateTime.now()).toUtc();

    // Parse attributes
    var attributes = <String, dynamic>{};
    if (json['attributes'] != null) {
      try {
        if (json['attributes'] is Map) {
          attributes = Map<String, dynamic>.from(json['attributes'] as Map);
        }
      } catch (_) {
        attributes = {};
      }
    }

    return GeofenceEvent(
      id: json['id']?.toString() ?? '',
      geofenceId: json['geofenceId']?.toString() ?? 
                  json['geofence_id']?.toString() ?? '',
      geofenceName: json['geofenceName'] as String? ?? 
                    json['geofence_name'] as String? ?? 
                    'Unknown',
      deviceId: json['deviceId']?.toString() ?? 
                json['device_id']?.toString() ?? '',
      deviceName: json['deviceName'] as String? ?? 
                  json['device_name'] as String? ?? 
                  'Unknown Device',
      eventType: (json['eventType'] ?? json['event_type'] ?? json['type']) as String? ?? 'enter',
      timestamp: timestampUtc,
      latitude: (json['latitude'] ?? json['lat']) as double? ?? 0.0,
      longitude: (json['longitude'] ?? json['lng'] ?? json['lon']) as double? ?? 0.0,
      status: json['status'] as String? ?? 'pending',
      syncStatus: (json['syncStatus'] ?? json['sync_status']) as String? ?? 'synced',
      createdAt: createdAtUtc,
      dwellDurationMs: (json['dwellDurationMs'] ?? 
                       json['dwell_duration_ms'] ?? 
                       json['dwellMs']) as int?,
      attributes: attributes,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'geofenceId': geofenceId,
        'geofenceName': geofenceName,
        'deviceId': deviceId,
        'deviceName': deviceName,
        'eventType': eventType,
        'timestamp': timestamp.toUtc().toIso8601String(),
        'latitude': latitude,
        'longitude': longitude,
        'status': status,
        'syncStatus': syncStatus,
        'createdAt': createdAt.toUtc().toIso8601String(),
        if (dwellDurationMs != null) 'dwellDurationMs': dwellDurationMs,
        if (attributes.isNotEmpty) 'attributes': attributes,
      };

  // -----------------------------
  // SQLite / Map Conversion
  // -----------------------------

  /// Convert to Map for SQLite storage
  Map<String, dynamic> toMap() => {
        'id': id,
        'geofence_id': geofenceId,
        'geofence_name': geofenceName,
        'device_id': deviceId,
        'device_name': deviceName,
        'event_type': eventType,
        'timestamp': timestamp.toUtc().millisecondsSinceEpoch,
        'latitude': latitude,
        'longitude': longitude,
        'status': status,
        'sync_status': syncStatus,
        'created_at': createdAt.toUtc().millisecondsSinceEpoch,
        'dwell_duration_ms': dwellDurationMs,
        'attributes_json': attributes.isNotEmpty ? attributes.toString() : '{}',
      };

  /// Convert from Map (SQLite result)
  factory GeofenceEvent.fromMap(Map<String, dynamic> map) {
    // Parse attributes from JSON string
    var attributes = <String, dynamic>{};
    if (map['attributes_json'] != null) {
      try {
        // Simple parsing - in production you might want to use jsonDecode
        attributes = {};
      } catch (_) {
        attributes = {};
      }
    }

    return GeofenceEvent(
      id: map['id'] as String,
      geofenceId: map['geofence_id'] as String,
      geofenceName: map['geofence_name'] as String? ?? 'Unknown',
      deviceId: map['device_id'] as String,
      deviceName: map['device_name'] as String? ?? 'Unknown Device',
      eventType: map['event_type'] as String,
      timestamp: DateTime.fromMillisecondsSinceEpoch(
        map['timestamp'] as int,
        isUtc: true,
      ),
      latitude: map['latitude'] as double,
      longitude: map['longitude'] as double,
      status: map['status'] as String? ?? 'pending',
      syncStatus: map['sync_status'] as String? ?? 'synced',
      createdAt: DateTime.fromMillisecondsSinceEpoch(
        map['created_at'] as int,
        isUtc: true,
      ),
      dwellDurationMs: map['dwell_duration_ms'] as int?,
      attributes: attributes,
    );
  }

  // -----------------------------
  // Utility Methods
  // -----------------------------

  /// Get location as LatLng
  LatLng get location => LatLng(latitude, longitude);

  /// Get human-readable event type
  String get eventTypeLabel {
    switch (eventType.toLowerCase()) {
      case 'enter':
      case 'entry':
        return 'Entry';
      case 'exit':
        return 'Exit';
      case 'dwell':
        return 'Dwell';
      default:
        return eventType;
    }
  }

  /// Get formatted timestamp
  String get formattedTime => DateFormat('yyyy-MM-dd HH:mm:ss').format(timestamp.toLocal());

  /// Get formatted date only
  String get formattedDate => DateFormat('yyyy-MM-dd').format(timestamp.toLocal());

  /// Get formatted time only
  String get formattedTimeOnly => DateFormat('HH:mm:ss').format(timestamp.toLocal());

  /// Get relative time (e.g., "2 hours ago")
  String get relativeTime {
    final now = DateTime.now();
    final difference = now.difference(timestamp.toLocal());

    if (difference.inSeconds < 60) {
      return 'Just now';
    } else if (difference.inMinutes < 60) {
      return '${difference.inMinutes}m ago';
    } else if (difference.inHours < 24) {
      return '${difference.inHours}h ago';
    } else if (difference.inDays < 7) {
      return '${difference.inDays}d ago';
    } else {
      return formattedDate;
    }
  }

  /// Get formatted dwell duration
  String get formattedDwellDuration {
    if (dwellDurationMs == null) return 'N/A';
    
    final duration = Duration(milliseconds: dwellDurationMs!);
    final hours = duration.inHours;
    final minutes = duration.inMinutes % 60;
    final seconds = duration.inSeconds % 60;

    if (hours > 0) {
      return '${hours}h ${minutes}m';
    } else if (minutes > 0) {
      return '${minutes}m ${seconds}s';
    } else {
      return '${seconds}s';
    }
  }

  /// Get full event message
  String get message {
    switch (eventType.toLowerCase()) {
      case 'enter':
      case 'entry':
        return '$deviceName entered $geofenceName';
      case 'exit':
        return '$deviceName exited $geofenceName';
      case 'dwell':
        return '$deviceName stayed in $geofenceName for $formattedDwellDuration';
      default:
        return '$deviceName triggered $eventType in $geofenceName';
    }
  }

  /// Get short message
  String get shortMessage {
    switch (eventType.toLowerCase()) {
      case 'enter':
      case 'entry':
        return 'Entered $geofenceName';
      case 'exit':
        return 'Exited $geofenceName';
      case 'dwell':
        return 'Dwelling in $geofenceName';
      default:
        return eventType;
    }
  }

  /// Check if event is recent (within last hour)
  bool get isRecent {
    final now = DateTime.now().toUtc();
    return now.difference(timestamp).inHours < 1;
  }

  /// Check if event is unread (pending status)
  bool get isUnread => status == 'pending';

  /// Check if event is acknowledged
  bool get isAcknowledged => status == 'acknowledged';

  /// Check if event is archived
  bool get isArchived => status == 'archived';

  /// Check if event needs sync
  bool get needsSync => syncStatus == 'pending';

  // -----------------------------
  // UI Helpers
  // -----------------------------

  /// Get icon for event type
  IconData get icon {
    switch (eventType.toLowerCase()) {
      case 'enter':
      case 'entry':
        return Icons.login;
      case 'exit':
        return Icons.logout;
      case 'dwell':
        return Icons.access_time;
      default:
        return Icons.location_on;
    }
  }

  /// Get color for event type
  Color get color {
    switch (eventType.toLowerCase()) {
      case 'enter':
      case 'entry':
        return Colors.green;
      case 'exit':
        return Colors.orange;
      case 'dwell':
        return Colors.blue;
      default:
        return Colors.grey;
    }
  }

  /// Get status color
  Color get statusColor {
    switch (status) {
      case 'pending':
        return Colors.amber;
      case 'acknowledged':
        return Colors.green;
      case 'archived':
        return Colors.grey;
      default:
        return Colors.grey;
    }
  }

  // -----------------------------
  // Copy Method
  // -----------------------------

  GeofenceEvent copyWith({
    String? id,
    String? geofenceId,
    String? geofenceName,
    String? deviceId,
    String? deviceName,
    String? eventType,
    DateTime? timestamp,
    double? latitude,
    double? longitude,
    String? status,
    String? syncStatus,
    DateTime? createdAt,
    int? dwellDurationMs,
    Map<String, dynamic>? attributes,
  }) =>
      GeofenceEvent(
        id: id ?? this.id,
        geofenceId: geofenceId ?? this.geofenceId,
        geofenceName: geofenceName ?? this.geofenceName,
        deviceId: deviceId ?? this.deviceId,
        deviceName: deviceName ?? this.deviceName,
        eventType: eventType ?? this.eventType,
        timestamp: timestamp ?? this.timestamp,
        latitude: latitude ?? this.latitude,
        longitude: longitude ?? this.longitude,
        status: status ?? this.status,
        syncStatus: syncStatus ?? this.syncStatus,
        createdAt: createdAt ?? this.createdAt,
        dwellDurationMs: dwellDurationMs ?? this.dwellDurationMs,
        attributes: attributes ?? this.attributes,
      );

  // -----------------------------
  // Equality & HashCode
  // -----------------------------

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is GeofenceEvent &&
          runtimeType == other.runtimeType &&
          id == other.id &&
          geofenceId == other.geofenceId &&
          geofenceName == other.geofenceName &&
          deviceId == other.deviceId &&
          deviceName == other.deviceName &&
          eventType == other.eventType &&
          timestamp == other.timestamp &&
          latitude == other.latitude &&
          longitude == other.longitude &&
          status == other.status &&
          syncStatus == other.syncStatus &&
          createdAt == other.createdAt &&
          dwellDurationMs == other.dwellDurationMs;

  @override
  int get hashCode =>
      id.hashCode ^
      geofenceId.hashCode ^
      geofenceName.hashCode ^
      deviceId.hashCode ^
      deviceName.hashCode ^
      eventType.hashCode ^
      timestamp.hashCode ^
      latitude.hashCode ^
      longitude.hashCode ^
      status.hashCode ^
      syncStatus.hashCode ^
      createdAt.hashCode ^
      (dwellDurationMs?.hashCode ?? 0);

  @override
  String toString() => 'GeofenceEvent('
      'id: $id, '
      'device: $deviceName, '
      'geofence: $geofenceName, '
      'type: $eventType, '
      'status: $status, '
      'time: $formattedTime'
      ')';
}
