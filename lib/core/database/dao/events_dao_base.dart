import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:my_app_gps/data/models/event.dart';

/// Domain-oriented Events DAO interface to enable platform-specific backends.
abstract class EventsDaoBase {
  Future<void> upsert(Event event);
  Future<void> upsertMany(List<Event> events);
  Future<Event?> getById(String eventId);
  Future<List<Event>> getByDevice(int deviceId);
  Future<List<Event>> getByDeviceAndType(int deviceId, String eventType);
  Future<List<Event>> getByDeviceInRange(
    int deviceId,
    DateTime startTime,
    DateTime endTime,
  );
  Future<List<Event>> getByType(String eventType);
  Future<List<Event>> getAll();
  Future<void> delete(String eventId);
  Future<void> deleteAll();
}

// Forward-declared provider, bound in platform impls
late final FutureProvider<EventsDaoBase> eventsDaoProvider;
