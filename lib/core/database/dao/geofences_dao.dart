import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:latlong2/latlong.dart';
import 'package:my_app_gps/core/database/entities/geofence_entity.dart';
import 'package:my_app_gps/core/database/entities/geofence_event_entity.dart';
import 'package:my_app_gps/core/database/objectbox_singleton.dart';
import 'package:my_app_gps/data/models/geofence.dart';
import 'package:my_app_gps/data/models/geofence_event.dart';
import 'package:my_app_gps/objectbox.g.dart';
import 'package:objectbox/objectbox.dart' as ob;

/// Abstraction for geofence persistence to enable test fakes.
abstract class GeofencesDaoBase {
  // Geofence operations
  Future<void> upsertGeofence(Geofence geofence);
  Future<void> deleteGeofence(String geofenceId);
  Future<Geofence?> getGeofence(String geofenceId);
  Future<List<Geofence>> getAllGeofences();
  Future<List<Geofence>> getEnabledGeofences();
  
  // Geofence event operations
  Future<void> insertEvent(GeofenceEvent event);
  Future<List<GeofenceEvent>> getEventsForGeofence(String geofenceId, {int limit = 100});
  Future<List<GeofenceEvent>> getEventsForDevice(String deviceId, {int limit = 100});
  Future<List<GeofenceEvent>> getPendingEvents({int limit = 100});
  Future<void> updateEventStatus(String eventId, String status);
}

/// ObjectBox-backed DAO for geofences and geofence events.
class GeofencesDaoObjectBox implements GeofencesDaoBase {
  GeofencesDaoObjectBox(this._store)
      : _geofenceBox = _store.box<GeofenceEntity>(),
        _eventBox = _store.box<GeofenceEventEntity>();

  // Store reference kept to keep the database open for the lifetime of the DAO.
  // ignore: unused_field
  final ob.Store _store;
  final ob.Box<GeofenceEntity> _geofenceBox;
  final ob.Box<GeofenceEventEntity> _eventBox;

  // =============================
  // Geofence Operations
  // =============================

  @override
  Future<void> upsertGeofence(Geofence geofence) async {
    try {
      // Convert String UUID to numeric hash for ObjectBox entity
      final numericId = _hashStringToInt(geofence.id);
      
      // Find existing by geofenceId (unique index)
      final query = _geofenceBox
          .query(GeofenceEntity_.geofenceId.equals(numericId))
          .build();
      
      try {
        final existing = query.findFirst();
        
        // Create entity with proper attributes JSON
        final attributes = <String, dynamic>{
          'originalId': geofence.id, // Preserve original String ID
          'userId': geofence.userId,
          'enabled': geofence.enabled,
          'type': geofence.type,
          'centerLat': geofence.centerLat,
          'centerLng': geofence.centerLng,
          'radius': geofence.radius,
          'vertices': geofence.vertices?.map((v) => [v.latitude, v.longitude]).toList(),
          'monitoredDevices': geofence.monitoredDevices,
          'onEnter': geofence.onEnter,
          'onExit': geofence.onExit,
          'dwellMs': geofence.dwellMs,
          'notificationType': geofence.notificationType,
          'createdAt': geofence.createdAt.toIso8601String(),
          'updatedAt': geofence.updatedAt.toIso8601String(),
          'syncStatus': geofence.syncStatus,
          'version': geofence.version,
        };
        
        final entity = GeofenceEntity(
          geofenceId: numericId,
          name: geofence.name,
          area: _encodeArea(geofence),
          attributesJson: jsonEncode(attributes),
        );
        
        // Preserve ObjectBox internal ID if updating
        if (existing != null) {
          entity.id = existing.id;
        }
        
        _geofenceBox.put(entity);
        
        if (kDebugMode) {
          print('[GeofencesDAO] Upserted geofence: ${geofence.name} (${geofence.id})');
        }
      } finally {
        query.close();
      }
    } catch (e, stackTrace) {
      if (kDebugMode) {
        print('[GeofencesDAO] ❌ Error upserting geofence: $e');
        print(stackTrace);
      }
      rethrow;
    }
  }

  @override
  Future<void> deleteGeofence(String geofenceId) async {
    try {
      final numericId = _hashStringToInt(geofenceId);
      final query = _geofenceBox
          .query(GeofenceEntity_.geofenceId.equals(numericId))
          .build();
      
      try {
        final existing = query.findFirst();
        if (existing != null) {
          _geofenceBox.remove(existing.id);
          
          // Also delete associated events (cascade delete)
          await _deleteEventsForGeofence(geofenceId);
          
          if (kDebugMode) {
            print('[GeofencesDAO] Deleted geofence: $geofenceId');
          }
        }
      } finally {
        query.close();
      }
    } catch (e) {
      if (kDebugMode) {
        print('[GeofencesDAO] ❌ Error deleting geofence: $e');
      }
      rethrow;
    }
  }

  @override
  Future<Geofence?> getGeofence(String geofenceId) async {
    try {
      final numericId = _hashStringToInt(geofenceId);
      final query = _geofenceBox
          .query(GeofenceEntity_.geofenceId.equals(numericId))
          .build();
      
      try {
        final entity = query.findFirst();
        if (entity == null) return null;
        
        return _entityToGeofence(entity);
      } finally {
        query.close();
      }
    } catch (e) {
      if (kDebugMode) {
        print('[GeofencesDAO] ❌ Error getting geofence: $e');
      }
      return null;
    }
  }

  @override
  Future<List<Geofence>> getAllGeofences() async {
    try {
      final entities = _geofenceBox.getAll();
      return entities
          .map(_entityToGeofence)
          .where((g) => g != null)
          .cast<Geofence>()
          .toList();
    } catch (e) {
      if (kDebugMode) {
        print('[GeofencesDAO] ❌ Error getting all geofences: $e');
      }
      return [];
    }
  }

  @override
  Future<List<Geofence>> getEnabledGeofences() async {
    try {
      final all = await getAllGeofences();
      return all.where((g) => g.enabled).toList();
    } catch (e) {
      if (kDebugMode) {
        print('[GeofencesDAO] ❌ Error getting enabled geofences: $e');
      }
      return [];
    }
  }

  // =============================
  // Geofence Event Operations
  // =============================

  @override
  Future<void> insertEvent(GeofenceEvent event) async {
    try {
      final entity = GeofenceEventEntity(
        eventId: event.id,
        geofenceId: event.geofenceId,
        geofenceName: event.geofenceName,
        deviceId: event.deviceId,
        deviceName: event.deviceName,
        eventType: event.eventType,
        eventTimeMs: event.timestamp.millisecondsSinceEpoch,
        latitude: event.latitude,
        longitude: event.longitude,
        dwellDurationMs: event.dwellDurationMs,
        status: event.status,
        syncStatus: event.syncStatus,
      );
      
      _eventBox.put(entity);
      
      if (kDebugMode) {
        print('[GeofencesDAO] Inserted event: ${event.eventType} for ${event.geofenceName}');
      }
    } catch (e) {
      if (kDebugMode) {
        print('[GeofencesDAO] ❌ Error inserting event: $e');
      }
      rethrow;
    }
  }

  @override
  Future<List<GeofenceEvent>> getEventsForGeofence(
    String geofenceId, {
    int limit = 100,
  }) async {
    try {
      final query = _eventBox
          .query(GeofenceEventEntity_.geofenceId.equals(geofenceId))
          .order(GeofenceEventEntity_.eventTimeMs, flags: ob.Order.descending)
          .build();
      
      try {
        final entities = query.find();
        final limited = entities.take(limit);
        return limited.map(_entityToEvent).where((e) => e != null).cast<GeofenceEvent>().toList();
      } finally {
        query.close();
      }
    } catch (e) {
      if (kDebugMode) {
        print('[GeofencesDAO] ❌ Error getting events for geofence: $e');
      }
      return [];
    }
  }

  @override
  Future<List<GeofenceEvent>> getEventsForDevice(
    String deviceId, {
    int limit = 100,
  }) async {
    try {
      final query = _eventBox
          .query(GeofenceEventEntity_.deviceId.equals(deviceId))
          .order(GeofenceEventEntity_.eventTimeMs, flags: ob.Order.descending)
          .build();
      
      try {
        final entities = query.find();
        final limited = entities.take(limit);
        return limited.map(_entityToEvent).where((e) => e != null).cast<GeofenceEvent>().toList();
      } finally {
        query.close();
      }
    } catch (e) {
      if (kDebugMode) {
        print('[GeofencesDAO] ❌ Error getting events for device: $e');
      }
      return [];
    }
  }

  @override
  Future<List<GeofenceEvent>> getPendingEvents({int limit = 100}) async {
    try {
      final query = _eventBox
          .query(GeofenceEventEntity_.status.equals('pending'))
          .order(GeofenceEventEntity_.eventTimeMs, flags: ob.Order.descending)
          .build();
      
      try {
        final entities = query.find();
        final limited = entities.take(limit);
        return limited.map(_entityToEvent).where((e) => e != null).cast<GeofenceEvent>().toList();
      } finally {
        query.close();
      }
    } catch (e) {
      if (kDebugMode) {
        print('[GeofencesDAO] ❌ Error getting pending events: $e');
      }
      return [];
    }
  }

  @override
  Future<void> updateEventStatus(String eventId, String status) async {
    try {
      final query = _eventBox
          .query(GeofenceEventEntity_.eventId.equals(eventId))
          .build();
      
      try {
        final existing = query.findFirst();
        if (existing != null) {
          existing.status = status;
          _eventBox.put(existing);
          
          if (kDebugMode) {
            print('[GeofencesDAO] Updated event status: $eventId -> $status');
          }
        }
      } finally {
        query.close();
      }
    } catch (e) {
      if (kDebugMode) {
        print('[GeofencesDAO] ❌ Error updating event status: $e');
      }
      rethrow;
    }
  }

  // =============================
  // Helper Methods
  // =============================

  /// Delete all events for a geofence (cascade delete)
  Future<void> _deleteEventsForGeofence(String geofenceId) async {
    try {
      final query = _eventBox
          .query(GeofenceEventEntity_.geofenceId.equals(geofenceId))
          .build();
      
      try {
        final events = query.find();
        final ids = events.map((e) => e.id).toList();
        _geofenceBox.removeMany(ids);
        
        if (kDebugMode) {
          print('[GeofencesDAO] Deleted ${ids.length} events for geofence: $geofenceId');
        }
      } finally {
        query.close();
      }
    } catch (e) {
      if (kDebugMode) {
        print('[GeofencesDAO] ❌ Error deleting events for geofence: $e');
      }
    }
  }

  /// Convert String UUID to int hash for ObjectBox
  int _hashStringToInt(String str) {
    var hash = 0;
    for (var i = 0; i < str.length; i++) {
      hash = ((hash << 5) - hash) + str.codeUnitAt(i);
      hash = hash & hash; // Convert to 32bit integer
    }
    return hash.abs();
  }

  /// Encode geofence area as WKT string
  String _encodeArea(Geofence geofence) {
    if (geofence.type == 'circle') {
      return 'CIRCLE(${geofence.centerLat} ${geofence.centerLng}, ${geofence.radius})';
    } else if (geofence.type == 'polygon' && geofence.vertices != null) {
      final coords = geofence.vertices!
          .map((v) => '${v.longitude} ${v.latitude}')
          .join(', ');
      return 'POLYGON(($coords))';
    }
    return '';
  }

  /// Convert GeofenceEntity to Geofence domain model
  Geofence? _entityToGeofence(GeofenceEntity entity) {
    try {
      final attributes = jsonDecode(entity.attributesJson) as Map<String, dynamic>;
      
      // Parse vertices if polygon
      List<LatLng>? vertices;
      if (attributes['vertices'] != null) {
        final vertList = attributes['vertices'] as List;
        vertices = vertList
            .map((v) => LatLng((v as List)[0] as double, v[1] as double))
            .toList();
      }
      
      return Geofence(
        id: attributes['originalId'] as String? ?? entity.geofenceId.toString(),
        userId: attributes['userId'] as String? ?? '',
        name: entity.name,
        type: attributes['type'] as String? ?? 'circle',
        enabled: attributes['enabled'] as bool? ?? true,
        centerLat: attributes['centerLat'] as double? ?? 0.0,
        centerLng: attributes['centerLng'] as double? ?? 0.0,
        radius: attributes['radius'] as double? ?? 100.0,
        vertices: vertices,
        monitoredDevices: (attributes['monitoredDevices'] as List?)?.cast<String>() ?? [],
        onEnter: attributes['onEnter'] as bool? ?? false,
        onExit: attributes['onExit'] as bool? ?? false,
        dwellMs: attributes['dwellMs'] as int? ?? 0,
        notificationType: attributes['notificationType'] as String? ?? 'push',
        createdAt: DateTime.parse(attributes['createdAt'] as String? ?? DateTime.now().toIso8601String()),
        updatedAt: DateTime.parse(attributes['updatedAt'] as String? ?? DateTime.now().toIso8601String()),
        syncStatus: attributes['syncStatus'] as String? ?? 'synced',
        version: attributes['version'] as int? ?? 1,
      );
    } catch (e) {
      if (kDebugMode) {
        print('[GeofencesDAO] ❌ Error converting entity to geofence: $e');
      }
      return null;
    }
  }

  /// Convert GeofenceEventEntity to GeofenceEvent domain model
  GeofenceEvent? _entityToEvent(GeofenceEventEntity entity) {
    try {
      final timestamp = DateTime.fromMillisecondsSinceEpoch(entity.eventTimeMs, isUtc: true);
      return GeofenceEvent(
        id: entity.eventId,
        geofenceId: entity.geofenceId,
        geofenceName: entity.geofenceName,
        deviceId: entity.deviceId,
        deviceName: entity.deviceName,
        eventType: entity.eventType,
        timestamp: timestamp,
        latitude: entity.latitude,
        longitude: entity.longitude,
        dwellDurationMs: entity.dwellDurationMs,
        status: entity.status,
        syncStatus: entity.syncStatus,
        createdAt: timestamp, // Use same timestamp for createdAt
      );
    } catch (e) {
      if (kDebugMode) {
        print('[GeofencesDAO] ❌ Error converting entity to event: $e');
      }
      return null;
    }
  }
}

/// Provider exposing ObjectBox-backed Geofences DAO.
final geofencesDaoProvider = FutureProvider<GeofencesDaoBase>((ref) async {
  // Keep alive with a 10-minute cache, like other providers.
  final link = ref.keepAlive();
  Timer? timer;
  ref.onCancel(() {
    timer?.cancel();
    timer = Timer(const Duration(minutes: 10), link.close);
  });
  ref.onDispose(() => timer?.cancel());

  // Reuse the same ObjectBox store singleton
  final store = await ObjectBoxSingleton.getStore();
  final dao = GeofencesDaoObjectBox(store);
  
  if (kDebugMode) {
    print('[GeofencesDAO] Provider initialized');
  }
  
  return dao;
});
