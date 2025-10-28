import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive/hive.dart' as hive;
import 'package:my_app_gps/core/database/dao/geofences_dao_base.dart';
import 'package:my_app_gps/data/models/geofence.dart';
import 'package:my_app_gps/data/models/geofence_event.dart';

class GeofencesDaoHive implements GeofencesDaoBase {
  static const String _boxGeofences = 'geofences';
  static const String _boxEvents = 'geofence_events';

  Future<hive.Box<dynamic>> _openBox(String name) async {
    if (!hive.Hive.isBoxOpen(name)) {
      return hive.Hive.openBox<dynamic>(name);
    }
    return hive.Hive.box<dynamic>(name);
  }

  @override
  Future<void> upsertGeofence(Geofence geofence) async {
    final box = await _openBox(_boxGeofences);
    await box.put(geofence.id, geofence.toJson());
  }

  @override
  Future<void> deleteGeofence(String geofenceId) async {
    final box = await _openBox(_boxGeofences);
    await box.delete(geofenceId);
    // Cascade delete events for this geofence
    final evBox = await _openBox(_boxEvents);
    final keysToDelete = <dynamic>[];
    for (final key in evBox.keys) {
      try {
        final data = evBox.get(key);
        if (data is Map && data['geofenceId']?.toString() == geofenceId) {
          keysToDelete.add(key);
        }
      } catch (_) {}
    }
    if (keysToDelete.isNotEmpty) {
      await evBox.deleteAll(keysToDelete);
    }
  }

  @override
  Future<Geofence?> getGeofence(String geofenceId) async {
    final box = await _openBox(_boxGeofences);
    final data = box.get(geofenceId);
    if (data is Map) {
      try {
        return Geofence.fromJson(Map<String, dynamic>.from(data));
      } catch (e) {
        if (kDebugMode) {
          print('[GeofencesDaoHive] parse error: $e');
        }
      }
    }
    return null;
  }

  @override
  Future<List<Geofence>> getAllGeofences() async {
    final box = await _openBox(_boxGeofences);
    final out = <Geofence>[];
    for (final key in box.keys) {
      final data = box.get(key);
      if (data is Map) {
        try {
          out.add(Geofence.fromJson(Map<String, dynamic>.from(data)));
        } catch (_) {}
      }
    }
    return out;
  }

  @override
  Future<List<Geofence>> getEnabledGeofences() async {
    final all = await getAllGeofences();
    return all.where((g) => g.enabled).toList();
  }

  @override
  Future<void> insertEvent(GeofenceEvent event) async {
    final box = await _openBox(_boxEvents);
    await box.put(event.id, event.toJson());
  }

  Future<List<GeofenceEvent>> _queryEvents(bool Function(GeofenceEvent e) test,
      {int limit = 100}) async {
    final box = await _openBox(_boxEvents);
    final out = <GeofenceEvent>[];
    for (final key in box.keys) {
      final data = box.get(key);
      if (data is Map) {
        try {
          final e = GeofenceEvent.fromJson(Map<String, dynamic>.from(data));
          if (test(e)) out.add(e);
        } catch (_) {}
      }
    }
    out.sort((a, b) => b.timestamp.compareTo(a.timestamp));
    return out.take(limit).toList();
  }

  @override
  Future<List<GeofenceEvent>> getEventsForGeofence(String geofenceId,
      {int limit = 100}) async {
    return _queryEvents((e) => e.geofenceId == geofenceId, limit: limit);
  }

  @override
  Future<List<GeofenceEvent>> getEventsForDevice(String deviceId,
      {int limit = 100}) async {
    return _queryEvents((e) => e.deviceId == deviceId, limit: limit);
  }

  @override
  Future<List<GeofenceEvent>> getPendingEvents({int limit = 100}) async {
    return _queryEvents((e) => e.status == 'pending', limit: limit);
  }

  @override
  Future<void> updateEventStatus(String eventId, String status) async {
    final box = await _openBox(_boxEvents);
    final data = box.get(eventId);
    if (data is Map) {
      final map = Map<String, dynamic>.from(data);
      map['status'] = status;
      await box.put(eventId, map);
    }
  }
}

final geofencesDaoProvider = FutureProvider<GeofencesDaoBase>((ref) async {
  final link = ref.keepAlive();
  Timer? timer;
  ref.onCancel(() {
    timer?.cancel();
    timer = Timer(const Duration(minutes: 10), link.close);
  });
  ref.onDispose(() => timer?.cancel());
  return GeofencesDaoHive();
});
