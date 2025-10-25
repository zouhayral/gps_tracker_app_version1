import 'dart:convert';


import 'package:latlong2/latlong.dart';

import 'package:my_app_gps/core/database/entities/geofence_entity.dart';

/// Domain model representing a geofence for location-based monitoring.
/// Converts between:
///   • REST/WebSocket JSON
///   • ObjectBox GeofenceEntity
///   • UI-friendly data (validation, formatted display)
class Geofence {
  final String id;
  final String userId;
  final String name;
  final String type; // 'circle' or 'polygon'
  final bool enabled;
  final double? centerLat; // For circles
  final double? centerLng; // For circles
  final double? radius; // Meters, for circles
  final List<LatLng>? vertices; // For polygons
  final List<String> monitoredDevices; // Device IDs
  final bool onEnter; // Trigger on entry
  final bool onExit; // Trigger on exit
  final int? dwellMs; // Optional dwell time in milliseconds
  final String notificationType; // 'local' | 'push' | 'both'
  final DateTime createdAt;
  final DateTime updatedAt;
  final String syncStatus; // 'synced' | 'pending' | 'conflict'
  final int version; // For conflict resolution

  const Geofence({
    required this.id,
    required this.userId,
    required this.name,
    required this.type,
    required this.enabled,
    this.centerLat,
    this.centerLng,
    this.radius,
    this.vertices,
    this.monitoredDevices = const [],
    this.onEnter = true,
    this.onExit = true,
    this.dwellMs,
    this.notificationType = 'local',
    required this.createdAt,
    required this.updatedAt,
    this.syncStatus = 'synced',
    this.version = 1,
  });

  // -----------------------------
  // Factory Constructors
  // -----------------------------

  /// Create a new circular geofence with default values
  factory Geofence.circle({
    required String id,
    required String userId,
    required String name,
    required LatLng center,
    required double radius,
    List<String> monitoredDevices = const [],
    bool enabled = true,
    bool onEnter = true,
    bool onExit = true,
    int? dwellMs,
    String notificationType = 'local',
  }) {
    final now = DateTime.now().toUtc();
    return Geofence(
      id: id,
      userId: userId,
      name: name,
      type: 'circle',
      enabled: enabled,
      centerLat: center.latitude,
      centerLng: center.longitude,
      radius: radius,
      vertices: null,
      monitoredDevices: monitoredDevices,
      onEnter: onEnter,
      onExit: onExit,
      dwellMs: dwellMs,
      notificationType: notificationType,
      createdAt: now,
      updatedAt: now,
      syncStatus: 'pending',
      version: 1,
    );
  }

  /// Create a new polygon geofence with default values
  factory Geofence.polygon({
    required String id,
    required String userId,
    required String name,
    required List<LatLng> vertices,
    List<String> monitoredDevices = const [],
    bool enabled = true,
    bool onEnter = true,
    bool onExit = true,
    int? dwellMs,
    String notificationType = 'local',
  }) {
    final now = DateTime.now().toUtc();
    return Geofence(
      id: id,
      userId: userId,
      name: name,
      type: 'polygon',
      enabled: enabled,
      centerLat: null,
      centerLng: null,
      radius: null,
      vertices: vertices,
      monitoredDevices: monitoredDevices,
      onEnter: onEnter,
      onExit: onExit,
      dwellMs: dwellMs,
      notificationType: notificationType,
      createdAt: now,
      updatedAt: now,
      syncStatus: 'pending',
      version: 1,
    );
  }

  /// Create an empty geofence template
  factory Geofence.empty({
    required String id,
    required String userId,
  }) {
    final now = DateTime.now().toUtc();
    return Geofence(
      id: id,
      userId: userId,
      name: '',
      type: 'circle',
      enabled: false,
      centerLat: 0.0,
      centerLng: 0.0,
      radius: 100.0,
      vertices: null,
      monitoredDevices: const [],
      onEnter: true,
      onExit: true,
      dwellMs: null,
      notificationType: 'local',
      createdAt: now,
      updatedAt: now,
      syncStatus: 'pending',
      version: 1,
    );
  }

  // -----------------------------
  // JSON Serialization
  // -----------------------------

  factory Geofence.fromJson(Map<String, dynamic> json) {
    final rawCreatedAt =
        (json['createdAt'] ?? json['created_at'] ?? '') as String?;
    final rawUpdatedAt =
        (json['updatedAt'] ?? json['updated_at'] ?? '') as String?;

    final parsedCreatedAt = rawCreatedAt != null && rawCreatedAt.isNotEmpty
        ? DateTime.tryParse(rawCreatedAt)
        : null;
    final parsedUpdatedAt = rawUpdatedAt != null && rawUpdatedAt.isNotEmpty
        ? DateTime.tryParse(rawUpdatedAt)
        : null;

    final createdAtUtc = (parsedCreatedAt ?? DateTime.now()).toUtc();
    final updatedAtUtc = (parsedUpdatedAt ?? DateTime.now()).toUtc();

    // Parse vertices from JSON array
    List<LatLng>? vertices;
    if (json['vertices'] != null) {
      try {
        final verticesData = json['vertices'] is String
            ? jsonDecode(json['vertices'] as String) as List
            : json['vertices'] as List;
        vertices = verticesData
            .map((v) => LatLng(
                  (v['lat'] ?? v['latitude']) as double,
                  (v['lng'] ?? v['longitude'] ?? v['lon']) as double,
                ))
            .toList();
      } catch (_) {
        vertices = null;
      }
    }

    // Parse monitored devices from JSON array
    List<String> monitoredDevices = [];
    if (json['monitoredDevices'] != null ||
        json['monitored_devices'] != null) {
      try {
        final devicesData =
            json['monitoredDevices'] ?? json['monitored_devices'];
        if (devicesData is String) {
          final decoded = jsonDecode(devicesData) as List;
          monitoredDevices = decoded.map((e) => e.toString()).toList();
        } else if (devicesData is List) {
          monitoredDevices = devicesData.map((e) => e.toString()).toList();
        }
      } catch (_) {
        monitoredDevices = [];
      }
    }

    return Geofence(
      id: json['id']?.toString() ?? '',
      userId: json['userId']?.toString() ?? json['user_id']?.toString() ?? '',
      name: json['name'] as String? ?? '',
      type: json['type'] as String? ?? 'circle',
      enabled: json['enabled'] as bool? ?? true,
      centerLat: (json['centerLat'] ?? json['center_lat']) as double?,
      centerLng: (json['centerLng'] ?? json['center_lng']) as double?,
      radius: (json['radius'] ?? json['radiusMeters']) as double?,
      vertices: vertices,
      monitoredDevices: monitoredDevices,
      onEnter: (json['onEnter'] ?? json['on_enter']) as bool? ?? true,
      onExit: (json['onExit'] ?? json['on_exit']) as bool? ?? true,
      dwellMs: (json['dwellMs'] ?? json['dwell_ms']) as int?,
      notificationType: (json['notificationType'] ?? 
          json['notification_type']) as String? ?? 'local',
      createdAt: createdAtUtc,
      updatedAt: updatedAtUtc,
      syncStatus: (json['syncStatus'] ?? json['sync_status']) as String? ?? 'synced',
      version: (json['version'] as num?)?.toInt() ?? 1,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'userId': userId,
        'name': name,
        'type': type,
        'enabled': enabled,
        'centerLat': centerLat,
        'centerLng': centerLng,
        'radius': radius,
        'vertices': vertices
            ?.map((v) => {'lat': v.latitude, 'lng': v.longitude})
            .toList(),
        'monitoredDevices': monitoredDevices,
        'onEnter': onEnter,
        'onExit': onExit,
        'dwellMs': dwellMs,
        'notificationType': notificationType,
        'createdAt': createdAt.toUtc().toIso8601String(),
        'updatedAt': updatedAt.toUtc().toIso8601String(),
        'syncStatus': syncStatus,
        'version': version,
      };

  // -----------------------------
  // SQLite / Map Conversion
  // -----------------------------

  /// Convert to Map for SQLite storage
  Map<String, dynamic> toMap() => {
        'id': id,
        'user_id': userId,
        'name': name,
        'type': type,
        'enabled': enabled ? 1 : 0,
        'center_lat': centerLat,
        'center_lng': centerLng,
        'radius': radius,
        'vertices': vertices != null
            ? jsonEncode(
                vertices!
                    .map((v) => {'lat': v.latitude, 'lng': v.longitude})
                    .toList(),
              )
            : null,
        'monitored_devices': jsonEncode(monitoredDevices),
        'on_enter': onEnter ? 1 : 0,
        'on_exit': onExit ? 1 : 0,
        'dwell_ms': dwellMs,
        'notification_type': notificationType,
        'created_at': createdAt.toUtc().millisecondsSinceEpoch,
        'updated_at': updatedAt.toUtc().millisecondsSinceEpoch,
        'sync_status': syncStatus,
        'version': version,
      };

  /// Convert from Map (SQLite result)
  factory Geofence.fromMap(Map<String, dynamic> map) {
    // Parse vertices from JSON string
    List<LatLng>? vertices;
    if (map['vertices'] != null) {
      try {
        final verticesData = jsonDecode(map['vertices'] as String) as List;
        vertices = verticesData
            .map((v) => LatLng(v['lat'] as double, v['lng'] as double))
            .toList();
      } catch (_) {
        vertices = null;
      }
    }

    // Parse monitored devices from JSON string
    List<String> monitoredDevices = [];
    if (map['monitored_devices'] != null) {
      try {
        final decoded = jsonDecode(map['monitored_devices'] as String) as List;
        monitoredDevices = decoded.map((e) => e.toString()).toList();
      } catch (_) {
        monitoredDevices = [];
      }
    }

    return Geofence(
      id: map['id'] as String,
      userId: map['user_id'] as String,
      name: map['name'] as String,
      type: map['type'] as String,
      enabled: (map['enabled'] as int) == 1,
      centerLat: map['center_lat'] as double?,
      centerLng: map['center_lng'] as double?,
      radius: map['radius'] as double?,
      vertices: vertices,
      monitoredDevices: monitoredDevices,
      onEnter: (map['on_enter'] as int?) == 1,
      onExit: (map['on_exit'] as int?) == 1,
      dwellMs: map['dwell_ms'] as int?,
      notificationType: map['notification_type'] as String? ?? 'local',
      createdAt: DateTime.fromMillisecondsSinceEpoch(
        map['created_at'] as int,
        isUtc: true,
      ),
      updatedAt: DateTime.fromMillisecondsSinceEpoch(
        map['updated_at'] as int,
        isUtc: true,
      ),
      syncStatus: map['sync_status'] as String? ?? 'synced',
      version: map['version'] as int? ?? 1,
    );
  }

  // -----------------------------
  // ObjectBox Conversion
  // -----------------------------

  /// Convert to ObjectBox GeofenceEntity
  GeofenceEntity toEntity() {
    // Convert to WKT (Well-Known Text) format for area field
    String? area;
    if (type == 'circle' && centerLat != null && centerLng != null && radius != null) {
      area = 'CIRCLE ($centerLat $centerLng, $radius)';
    } else if (type == 'polygon' && vertices != null && vertices!.isNotEmpty) {
      final coords = vertices!
          .map((v) => '${v.longitude} ${v.latitude}')
          .join(', ');
      // Close the polygon by repeating first vertex
      final firstVertex = vertices!.first;
      area = 'POLYGON(($coords, ${firstVertex.longitude} ${firstVertex.latitude}))';
    }

    // Build attributes JSON with all custom fields
    final attributes = {
      'userId': userId,
      'enabled': enabled,
      'monitoredDevices': monitoredDevices,
      'onEnter': onEnter,
      'onExit': onExit,
      if (dwellMs != null) 'dwellMs': dwellMs,
      'notificationType': notificationType,
      'createdAt': createdAt.toUtc().toIso8601String(),
      'updatedAt': updatedAt.toUtc().toIso8601String(),
      'syncStatus': syncStatus,
      'version': version,
    };

    return GeofenceEntity.fromDomain(
      geofenceId: int.tryParse(id) ?? 0, // Parse numeric ID or default to 0
      name: name,
      description: 'Type: $type',
      area: area,
      attributes: attributes,
    );
  }

  /// Convert from ObjectBox GeofenceEntity
  factory Geofence.fromEntity(GeofenceEntity entity) {
    final attributes = entity.toDomain()['attributes'] as Map<String, dynamic>? ?? {};
    
    // Parse area WKT format
    String type = 'circle';
    double? centerLat;
    double? centerLng;
    double? radius;
    List<LatLng>? vertices;

    if (entity.area != null) {
      final area = entity.area!;
      if (area.startsWith('CIRCLE')) {
        type = 'circle';
        // Parse: CIRCLE (lat lng, radius)
        final match = RegExp(r'CIRCLE \(([^ ]+) ([^ ]+), ([^\)]+)\)').firstMatch(area);
        if (match != null) {
          centerLat = double.tryParse(match.group(1)!);
          centerLng = double.tryParse(match.group(2)!);
          radius = double.tryParse(match.group(3)!);
        }
      } else if (area.startsWith('POLYGON')) {
        type = 'polygon';
        // Parse: POLYGON((lng1 lat1, lng2 lat2, ...))
        final coordsMatch = RegExp(r'POLYGON\(\((.*?)\)\)').firstMatch(area);
        if (coordsMatch != null) {
          final coordsStr = coordsMatch.group(1)!;
          final coordPairs = coordsStr.split(', ');
          vertices = coordPairs.map((pair) {
            final parts = pair.trim().split(' ');
            if (parts.length == 2) {
              final lng = double.tryParse(parts[0]);
              final lat = double.tryParse(parts[1]);
              if (lng != null && lat != null) {
                return LatLng(lat, lng);
              }
            }
            return null;
          }).whereType<LatLng>().toList();
          
          // Remove duplicate closing vertex
          if (vertices.length > 1 && 
              vertices.first.latitude == vertices.last.latitude &&
              vertices.first.longitude == vertices.last.longitude) {
            vertices.removeLast();
          }
        }
      }
    }

    // Parse monitored devices
    List<String> monitoredDevices = [];
    if (attributes['monitoredDevices'] != null) {
      final devicesData = attributes['monitoredDevices'];
      if (devicesData is List) {
        monitoredDevices = devicesData.map((e) => e.toString()).toList();
      }
    }

    // Parse timestamps
    final createdAtStr = attributes['createdAt'] as String?;
    final updatedAtStr = attributes['updatedAt'] as String?;
    final createdAt = createdAtStr != null 
        ? DateTime.tryParse(createdAtStr)?.toUtc() ?? DateTime.now().toUtc()
        : DateTime.now().toUtc();
    final updatedAt = updatedAtStr != null
        ? DateTime.tryParse(updatedAtStr)?.toUtc() ?? DateTime.now().toUtc()
        : DateTime.now().toUtc();

    return Geofence(
      id: entity.geofenceId.toString(),
      userId: attributes['userId'] as String? ?? '',
      name: entity.name,
      type: type,
      enabled: attributes['enabled'] as bool? ?? true,
      centerLat: centerLat,
      centerLng: centerLng,
      radius: radius,
      vertices: vertices,
      monitoredDevices: monitoredDevices,
      onEnter: attributes['onEnter'] as bool? ?? true,
      onExit: attributes['onExit'] as bool? ?? true,
      dwellMs: attributes['dwellMs'] as int?,
      notificationType: attributes['notificationType'] as String? ?? 'local',
      createdAt: createdAt,
      updatedAt: updatedAt,
      syncStatus: attributes['syncStatus'] as String? ?? 'synced',
      version: attributes['version'] as int? ?? 1,
    );
  }

  // -----------------------------
  // Validation Methods
  // -----------------------------

  /// Validate that this is a valid circle geofence
  bool isValidCircle() {
    if (type != 'circle') return false;
    if (centerLat == null || centerLng == null || radius == null) return false;
    if (centerLat! < -90 || centerLat! > 90) return false;
    if (centerLng! < -180 || centerLng! > 180) return false;
    if (radius! <= 0 || radius! > 10000) return false; // Max 10km
    return true;
  }

  /// Validate that this is a valid polygon geofence
  bool isValidPolygon() {
    if (type != 'polygon') return false;
    if (vertices == null || vertices!.length < 3) return false;
    
    // Validate each vertex
    for (final vertex in vertices!) {
      if (vertex.latitude < -90 || vertex.latitude > 90) return false;
      if (vertex.longitude < -180 || vertex.longitude > 180) return false;
    }
    
    return true;
  }

  /// Validate that this geofence is valid (either valid circle or polygon)
  bool isValid() {
    if (name.isEmpty) return false;
    if (userId.isEmpty) return false;
    if (type == 'circle') return isValidCircle();
    if (type == 'polygon') return isValidPolygon();
    return false;
  }

  /// Validate notification type
  bool hasValidNotificationType() {
    return ['local', 'push', 'both'].contains(notificationType);
  }

  /// Validate that at least one trigger is enabled
  bool hasValidTriggers() {
    return onEnter || onExit || dwellMs != null;
  }

  // -----------------------------
  // Utility Methods
  // -----------------------------

  /// Get center point for the geofence (for display on map)
  LatLng? get center {
    if (type == 'circle' && centerLat != null && centerLng != null) {
      return LatLng(centerLat!, centerLng!);
    } else if (type == 'polygon' && vertices != null && vertices!.isNotEmpty) {
      // Calculate centroid of polygon
      double sumLat = 0;
      double sumLng = 0;
      for (final vertex in vertices!) {
        sumLat += vertex.latitude;
        sumLng += vertex.longitude;
      }
      return LatLng(sumLat / vertices!.length, sumLng / vertices!.length);
    }
    return null;
  }

  /// Get human-readable description of geofence area
  String get areaDescription {
    if (type == 'circle' && radius != null) {
      if (radius! < 1000) {
        return '${radius!.toStringAsFixed(0)}m radius';
      } else {
        return '${(radius! / 1000).toStringAsFixed(1)}km radius';
      }
    } else if (type == 'polygon' && vertices != null) {
      return '${vertices!.length} vertices';
    }
    return 'Unknown';
  }

  /// Get list of active triggers as human-readable strings
  List<String> get activeTriggers {
    final triggers = <String>[];
    if (onEnter) triggers.add('Entry');
    if (onExit) triggers.add('Exit');
    if (dwellMs != null && dwellMs! > 0) {
      final minutes = dwellMs! ~/ 60000;
      triggers.add('Dwell ${minutes}m');
    }
    return triggers;
  }

  // -----------------------------
  // Copy Method
  // -----------------------------

  Geofence copyWith({
    String? id,
    String? userId,
    String? name,
    String? type,
    bool? enabled,
    double? centerLat,
    double? centerLng,
    double? radius,
    List<LatLng>? vertices,
    List<String>? monitoredDevices,
    bool? onEnter,
    bool? onExit,
    int? dwellMs,
    String? notificationType,
    DateTime? createdAt,
    DateTime? updatedAt,
    String? syncStatus,
    int? version,
  }) =>
      Geofence(
        id: id ?? this.id,
        userId: userId ?? this.userId,
        name: name ?? this.name,
        type: type ?? this.type,
        enabled: enabled ?? this.enabled,
        centerLat: centerLat ?? this.centerLat,
        centerLng: centerLng ?? this.centerLng,
        radius: radius ?? this.radius,
        vertices: vertices ?? this.vertices,
        monitoredDevices: monitoredDevices ?? this.monitoredDevices,
        onEnter: onEnter ?? this.onEnter,
        onExit: onExit ?? this.onExit,
        dwellMs: dwellMs ?? this.dwellMs,
        notificationType: notificationType ?? this.notificationType,
        createdAt: createdAt ?? this.createdAt,
        updatedAt: updatedAt ?? this.updatedAt,
        syncStatus: syncStatus ?? this.syncStatus,
        version: version ?? this.version,
      );

  // -----------------------------
  // Equality & HashCode
  // -----------------------------

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is Geofence &&
          runtimeType == other.runtimeType &&
          id == other.id &&
          userId == other.userId &&
          name == other.name &&
          type == other.type &&
          enabled == other.enabled &&
          centerLat == other.centerLat &&
          centerLng == other.centerLng &&
          radius == other.radius &&
          _listEquals(vertices, other.vertices) &&
          _listEquals(monitoredDevices, other.monitoredDevices) &&
          onEnter == other.onEnter &&
          onExit == other.onExit &&
          dwellMs == other.dwellMs &&
          notificationType == other.notificationType &&
          createdAt == other.createdAt &&
          updatedAt == other.updatedAt &&
          syncStatus == other.syncStatus &&
          version == other.version;

  @override
  int get hashCode =>
      id.hashCode ^
      userId.hashCode ^
      name.hashCode ^
      type.hashCode ^
      enabled.hashCode ^
      (centerLat?.hashCode ?? 0) ^
      (centerLng?.hashCode ?? 0) ^
      (radius?.hashCode ?? 0) ^
      (vertices?.length.hashCode ?? 0) ^
      monitoredDevices.length.hashCode ^
      onEnter.hashCode ^
      onExit.hashCode ^
      (dwellMs?.hashCode ?? 0) ^
      notificationType.hashCode ^
      createdAt.hashCode ^
      updatedAt.hashCode ^
      syncStatus.hashCode ^
      version.hashCode;

  /// Helper to compare nullable lists
  static bool _listEquals<T>(List<T>? a, List<T>? b) {
    if (identical(a, b)) return true;
    if (a == null || b == null) return false;
    if (a.length != b.length) return false;
    for (int i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }

  @override
  String toString() => 'Geofence('
      'id: $id, '
      'name: $name, '
      'type: $type, '
      'enabled: $enabled, '
      'devices: ${monitoredDevices.length}, '
      'syncStatus: $syncStatus, '
      'version: $version'
      ')';
}
