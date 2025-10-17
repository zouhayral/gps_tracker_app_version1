import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:my_app_gps/core/database/entities/event_entity.dart';
import 'package:my_app_gps/objectbox.g.dart';
import 'package:objectbox/objectbox.dart' as ob;

/// Abstraction for event persistence to enable test fakes.
abstract class EventsDaoBase {
  Future<void> upsert(EventEntity event);
  Future<void> upsertMany(List<EventEntity> events);
  Future<EventEntity?> getById(String eventId);
  Future<List<EventEntity>> getByDevice(int deviceId);
  Future<List<EventEntity>> getByDeviceAndType(int deviceId, String eventType);
  Future<List<EventEntity>> getByDeviceInRange(
    int deviceId,
    DateTime startTime,
    DateTime endTime,
  );
  Future<List<EventEntity>> getByType(String eventType);
  Future<List<EventEntity>> getAll();
  Future<void> delete(String eventId);
  Future<void> deleteAll();
}

/// ObjectBox-backed DAO for managing event persistence.
class EventsDaoObjectBox implements EventsDaoBase {
  EventsDaoObjectBox(this._store) : _box = _store.box<EventEntity>();

  // Store reference kept to keep the database open for the lifetime of the DAO.
  // ignore: unused_field
  final ob.Store _store;
  final ob.Box<EventEntity> _box;

  @override
  Future<void> upsert(EventEntity event) async {
    // Upsert by unique eventId
    final query =
        _box.query(EventEntity_.eventId.equals(event.eventId)).build();
    try {
      final existing = query.findFirst();
      if (existing != null) {
        event.id = existing.id;
      }
      _box.put(event);
    } finally {
      query.close();
    }
  }

  @override
  Future<void> upsertMany(List<EventEntity> events) async {
    for (final event in events) {
      await upsert(event);
    }
  }

  @override
  Future<EventEntity?> getById(String eventId) async {
    final query = _box.query(EventEntity_.eventId.equals(eventId)).build();
    try {
      return query.findFirst();
    } finally {
      query.close();
    }
  }

  @override
  Future<List<EventEntity>> getByDevice(int deviceId) async {
    final query = _box
        .query(EventEntity_.deviceId.equals(deviceId))
        .order(EventEntity_.eventTimeMs, flags: ob.Order.descending)
        .build();
    try {
      return query.find();
    } finally {
      query.close();
    }
  }

  @override
  Future<List<EventEntity>> getByDeviceAndType(
    int deviceId,
    String eventType,
  ) async {
    final query = _box
        .query(
          EventEntity_.deviceId.equals(deviceId) &
              EventEntity_.eventType.equals(eventType),
        )
        .order(EventEntity_.eventTimeMs, flags: ob.Order.descending)
        .build();
    try {
      return query.find();
    } finally {
      query.close();
    }
  }

  @override
  Future<List<EventEntity>> getByDeviceInRange(
    int deviceId,
    DateTime startTime,
    DateTime endTime,
  ) async {
    final startMs = startTime.toUtc().millisecondsSinceEpoch;
    final endMs = endTime.toUtc().millisecondsSinceEpoch;

    final query = _box
        .query(
          EventEntity_.deviceId.equals(deviceId) &
              EventEntity_.eventTimeMs.greaterOrEqual(startMs) &
              EventEntity_.eventTimeMs.lessOrEqual(endMs),
        )
        .order(EventEntity_.eventTimeMs, flags: ob.Order.descending)
        .build();
    try {
      return query.find();
    } finally {
      query.close();
    }
  }

  @override
  Future<List<EventEntity>> getByType(String eventType) async {
    final query = _box
        .query(EventEntity_.eventType.equals(eventType))
        .order(EventEntity_.eventTimeMs, flags: ob.Order.descending)
        .build();
    try {
      return query.find();
    } finally {
      query.close();
    }
  }

  @override
  Future<List<EventEntity>> getAll() async {
    return _box.getAll();
  }

  @override
  Future<void> delete(String eventId) async {
    final query = _box.query(EventEntity_.eventId.equals(eventId)).build();
    try {
      final existing = query.findFirst();
      if (existing != null) {
        _box.remove(existing.id);
      }
    } finally {
      query.close();
    }
  }

  @override
  Future<void> deleteAll() async {
    _box.removeAll();
  }
}

/// Provider exposing ObjectBox-backed events DAO.
final eventsDaoProvider = FutureProvider<EventsDaoBase>((ref) async {
  // Keep alive with a 10-minute cache.
  final link = ref.keepAlive();
  Timer? timer;
  ref.onCancel(() {
    timer?.cancel();
    timer = Timer(const Duration(minutes: 10), link.close);
  });
  ref.onDispose(() => timer?.cancel());

  final store = await openStore();
  return EventsDaoObjectBox(store);
});
