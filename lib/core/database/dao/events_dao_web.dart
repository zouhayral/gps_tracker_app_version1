import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive/hive.dart' as hive;
import 'package:my_app_gps/core/database/dao/events_dao_base.dart';
import 'package:my_app_gps/data/models/event.dart';

class EventsDaoHive implements EventsDaoBase {
  static const String _boxName = 'events';

  Future<hive.Box<dynamic>> _box() async {
    if (!hive.Hive.isBoxOpen(_boxName)) {
      return hive.Hive.openBox<dynamic>(_boxName);
    }
    return hive.Hive.box<dynamic>(_boxName);
  }

  @override
  Future<void> upsert(Event event) async {
    final box = await _box();
    await box.put(event.id, event.toJson());
  }

  @override
  Future<void> upsertMany(List<Event> events) async {
    final box = await _box();
    final map = <dynamic, dynamic>{};
    for (final e in events) {
      map[e.id] = e.toJson();
    }
    await box.putAll(map);
  }

  @override
  Future<Event?> getById(String eventId) async {
    final box = await _box();
    final data = box.get(eventId);
    if (data is Map) {
      try {
        return Event.fromJson(Map<String, dynamic>.from(data));
      } catch (e) {
        if (kDebugMode) {
          print('[EventsDaoHive] parse error: $e');
        }
      }
    }
    return null;
  }

  Future<List<Event>> _filter(bool Function(Event e) test) async {
    final box = await _box();
    final out = <Event>[];
    for (final key in box.keys) {
      final data = box.get(key);
      if (data is Map) {
        try {
          final e = Event.fromJson(Map<String, dynamic>.from(data));
          if (test(e)) out.add(e);
        } catch (_) {}
      }
    }
    out.sort((a, b) => b.timestamp.compareTo(a.timestamp));
    return out;
  }

  @override
  Future<List<Event>> getByDevice(int deviceId) async {
    return _filter((e) => e.deviceId == deviceId);
  }

  @override
  Future<List<Event>> getByDeviceAndType(int deviceId, String eventType) async {
    final t = eventType.toLowerCase();
    return _filter((e) => e.deviceId == deviceId && e.type.toLowerCase() == t);
  }

  @override
  Future<List<Event>> getByDeviceInRange(int deviceId, DateTime startTime, DateTime endTime) async {
    final start = startTime.toUtc();
    final end = endTime.toUtc();
    return _filter((e) => e.deviceId == deviceId && e.timestamp.isAfter(start) && e.timestamp.isBefore(end));
  }

  @override
  Future<List<Event>> getByType(String eventType) async {
    final t = eventType.toLowerCase();
    return _filter((e) => e.type.toLowerCase() == t);
  }

  @override
  Future<List<Event>> getAll() async {
    return _filter((_) => true);
  }

  @override
  Future<void> delete(String eventId) async {
    final box = await _box();
    await box.delete(eventId);
  }

  @override
  Future<void> deleteAll() async {
    final box = await _box();
    await box.clear();
  }
}

final eventsDaoProvider = FutureProvider<EventsDaoBase>((ref) async {
  final link = ref.keepAlive();
  Timer? timer;
  ref.onCancel(() {
    timer?.cancel();
    timer = Timer(const Duration(minutes: 10), link.close);
  });
  ref.onDispose(() => timer?.cancel());
  return EventsDaoHive();
});
