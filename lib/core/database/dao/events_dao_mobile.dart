import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:my_app_gps/core/database/dao/events_dao_base.dart';
import 'package:my_app_gps/core/database/entities/event_entity.dart' as ent;
import 'package:my_app_gps/core/database/objectbox_singleton.dart';
import 'package:my_app_gps/data/models/event.dart';
import 'package:my_app_gps/objectbox.g.dart';
import 'package:objectbox/objectbox.dart' as ob;

class EventsDaoObjectBox implements EventsDaoBase {
  EventsDaoObjectBox(ob.Store store) : _box = store.box<ent.EventEntity>();

  final ob.Box<ent.EventEntity> _box;

  ent.EventEntity _toEntity(Event e) => ent.EventEntity(
        eventId: e.id,
        deviceId: e.deviceId,
        deviceName: e.deviceName,
        eventType: e.type,
        eventTimeMs: e.timestamp.toLocal().millisecondsSinceEpoch,
        positionId: e.positionId,
        geofenceId: e.geofenceId,
        severity: e.severity,
        priority: _priorityForSeverity(e.severity),
        message: e.message,
        attributesJson: e.attributes.isNotEmpty ? e.attributes.toString() : '{}',
        isRead: e.isRead,
      );

  Event _fromEntity(ent.EventEntity e) => Event(
        id: e.eventId,
        deviceId: e.deviceId,
        deviceName: e.deviceName,
        type: e.eventType,
        timestamp: DateTime.fromMillisecondsSinceEpoch(e.eventTimeMs),
        message: e.message,
        severity: e.severity,
        positionId: e.positionId,
        geofenceId: e.geofenceId,
        attributes: {if (e.priority != null) 'priority': e.priority},
        isRead: e.isRead,
      );

  String _priorityForSeverity(String? severity) {
    switch ((severity ?? '').toLowerCase()) {
      case 'critical':
        return 'high';
      case 'warning':
        return 'medium';
      default:
        return 'low';
    }
  }

  @override
  Future<void> upsert(Event event) async {
    final q = _box.query(EventEntity_.eventId.equals(event.id)).build();
    try {
      final existing = q.findFirst();
      final entity = _toEntity(event);
      if (existing != null) entity.id = existing.id;
      _box.put(entity);
    } finally {
      q.close();
    }
  }

  @override
  Future<void> upsertMany(List<Event> events) async {
    for (final e in events) {
      await upsert(e);
    }
  }

  @override
  Future<Event?> getById(String eventId) async {
    final q = _box.query(EventEntity_.eventId.equals(eventId)).build();
    try {
      final e = q.findFirst();
      return e != null ? _fromEntity(e) : null;
    } finally {
      q.close();
    }
  }

  @override
  Future<List<Event>> getByDevice(int deviceId) async {
  final q = _box
    .query(EventEntity_.deviceId.equals(deviceId))
    .order(EventEntity_.eventTimeMs, flags: ob.Order.descending)
        .build();
    try {
      return q.find().map(_fromEntity).toList();
    } finally {
      q.close();
    }
  }

  @override
  Future<List<Event>> getByDeviceAndType(int deviceId, String eventType) async {
  final q = _box
    .query(EventEntity_.deviceId.equals(deviceId) &
      EventEntity_.eventType.equals(eventType))
    .order(EventEntity_.eventTimeMs, flags: ob.Order.descending)
        .build();
    try {
      return q.find().map(_fromEntity).toList();
    } finally {
      q.close();
    }
  }

  @override
  Future<List<Event>> getByDeviceInRange(
      int deviceId, DateTime startTime, DateTime endTime) async {
    final startMs = startTime.toUtc().millisecondsSinceEpoch;
    final endMs = endTime.toUtc().millisecondsSinceEpoch;
  final q = _box
    .query(EventEntity_.deviceId.equals(deviceId) &
      EventEntity_.eventTimeMs.greaterOrEqual(startMs) &
      EventEntity_.eventTimeMs.lessOrEqual(endMs))
    .order(EventEntity_.eventTimeMs, flags: ob.Order.descending)
        .build();
    try {
      return q.find().map(_fromEntity).toList();
    } finally {
      q.close();
    }
  }

  @override
  Future<List<Event>> getByType(String eventType) async {
  final q = _box
    .query(EventEntity_.eventType.equals(eventType))
    .order(EventEntity_.eventTimeMs, flags: ob.Order.descending)
        .build();
    try {
      return q.find().map(_fromEntity).toList();
    } finally {
      q.close();
    }
  }

  @override
  Future<List<Event>> getAll() async {
    return _box.getAll().map(_fromEntity).toList();
  }

  @override
  Future<void> delete(String eventId) async {
  final q = _box.query(EventEntity_.eventId.equals(eventId)).build();
    try {
      final existing = q.findFirst();
      if (existing != null) _box.remove(existing.id);
    } finally {
      q.close();
    }
  }

  @override
  Future<void> deleteAll() async {
    _box.removeAll();
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
  final store = await ObjectBoxSingleton.getStore();
  return EventsDaoObjectBox(store);
});
