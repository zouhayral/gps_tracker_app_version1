import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import 'package:my_app_gps/core/database/entities/event_entity.dart';

/// Domain model representing a Traccar event or alert.
/// Converts between:
///   • REST/WebSocket JSON
///   • ObjectBox EventEntity
///   • UI-friendly data (icon, color, formatted message)
class Event {
  final String id;
  final int deviceId;
  final String type; // e.g. 'deviceOnline', 'alarm', 'geofenceEnter'
  final DateTime timestamp;
  final String? message;
  final String? severity; // 'info', 'warning', 'critical'
  final int? positionId;
  final int? geofenceId;
  final Map<String, dynamic> attributes;
  final bool isRead;

  const Event({
    required this.id,
    required this.deviceId,
    required this.type,
    required this.timestamp,
    this.message,
    this.severity,
    this.positionId,
    this.geofenceId,
    this.attributes = const {},
    this.isRead = false,
  });

  // -----------------------------
  // JSON serialization
  // -----------------------------
  factory Event.fromJson(Map<String, dynamic> json) {
    return Event(
      id: json['id'].toString(),
      deviceId: (json['deviceId'] as num?)?.toInt() ?? 0,
      type: json['type'] as String? ?? 'unknown',
      timestamp: DateTime.tryParse(
            (json['serverTime'] ?? json['eventTime'] ?? '') as String,
          ) ??
          DateTime.now(),
      message: json['message'] as String?,
      severity: json['severity'] as String?,
      positionId: (json['positionId'] as num?)?.toInt(),
      geofenceId: (json['geofenceId'] as num?)?.toInt(),
      attributes: json['attributes'] is Map
          ? Map<String, dynamic>.from(json['attributes'] as Map)
          : {},
      isRead: json['isRead'] as bool? ?? false,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'deviceId': deviceId,
        'type': type,
        'serverTime': timestamp.toUtc().toIso8601String(),
        'message': message,
        'severity': severity,
        'positionId': positionId,
        'geofenceId': geofenceId,
        'attributes': attributes,
        'isRead': isRead,
      };

  // -----------------------------
  // ObjectBox conversion
  // -----------------------------
  EventEntity toEntity() => EventEntity(
        eventId: id,
        deviceId: deviceId,
        eventType: type,
        eventTimeMs: timestamp.millisecondsSinceEpoch,
        positionId: positionId,
        geofenceId: geofenceId,
        priority: severity,
        message: message ?? '',
        attributesJson: attributes.isNotEmpty ? attributes.toString() : '{}',
        isRead: isRead,
      );

  factory Event.fromEntity(EventEntity e) => Event(
        id: e.eventId,
        deviceId: e.deviceId,
        type: e.eventType,
        timestamp: DateTime.fromMillisecondsSinceEpoch(e.eventTimeMs),
        message: e.message,
        severity: e.priority,
        positionId: e.positionId,
        geofenceId: e.geofenceId,
        attributes: {},
        isRead: e.isRead,
      );

  // -----------------------------
  // UI Helpers
  // -----------------------------
  IconData get icon {
    switch (type) {
      case 'deviceOnline':
        return Icons.check_circle;
      case 'deviceOffline':
        return Icons.offline_bolt;
      case 'alarm':
        return Icons.warning;
      case 'geofenceEnter':
        return Icons.location_on;
      case 'geofenceExit':
        return Icons.location_off;
      case 'ignitionOn':
        return Icons.power;
      case 'ignitionOff':
        return Icons.power_off;
      case 'sos':
        return Icons.emergency;
      default:
        return Icons.info_outline;
    }
  }

  Color get color {
    switch (type) {
      case 'deviceOnline':
      case 'ignitionOn':
        return Colors.green;
      case 'deviceOffline':
      case 'sos':
        return Colors.red;
      case 'alarm':
        return Colors.orange;
      case 'geofenceEnter':
        return Colors.blue;
      case 'geofenceExit':
        return Colors.purple;
      default:
        return Colors.grey;
    }
  }

  String get formattedMessage {
    if (message != null && message!.isNotEmpty) return message!;
    switch (type) {
      case 'deviceOnline':
        return 'Device connected';
      case 'deviceOffline':
        return 'Device disconnected';
      case 'alarm':
        return 'Alarm triggered';
      case 'geofenceEnter':
        return 'Entered geofence';
      case 'geofenceExit':
        return 'Exited geofence';
      case 'ignitionOn':
        return 'Ignition turned on';
      case 'ignitionOff':
        return 'Ignition turned off';
      case 'sos':
        return 'SOS alert';
      default:
        return 'Event: $type';
    }
  }

  String get formattedTime =>
      DateFormat('yyyy-MM-dd HH:mm:ss').format(timestamp);

  // -----------------------------
  // Copy helper
  // -----------------------------
  Event copyWith({
    bool? isRead,
  }) =>
      Event(
        id: id,
        deviceId: deviceId,
        type: type,
        timestamp: timestamp,
        message: message,
        severity: severity,
        positionId: positionId,
        geofenceId: geofenceId,
        attributes: attributes,
        isRead: isRead ?? this.isRead,
      );
}


