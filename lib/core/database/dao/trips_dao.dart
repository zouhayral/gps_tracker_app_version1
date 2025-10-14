import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:my_app_gps/core/database/entities/trip_entity.dart';
import 'package:my_app_gps/objectbox.g.dart';
import 'package:objectbox/objectbox.dart' as ob;

/// Abstraction for trip persistence to enable test fakes.
abstract class TripsDaoBase {
  Future<void> upsert(TripEntity trip);
  Future<void> upsertMany(List<TripEntity> trips);
  Future<TripEntity?> getById(String tripId);
  Future<List<TripEntity>> getByDevice(int deviceId);
  Future<List<TripEntity>> getByDeviceInRange(
    int deviceId,
    DateTime startTime,
    DateTime endTime,
  );
  Future<List<TripEntity>> getAll();
  Future<void> delete(String tripId);
  Future<void> deleteAll();
}

/// ObjectBox-backed DAO for managing trip persistence.
class TripsDaoObjectBox implements TripsDaoBase {
  TripsDaoObjectBox(this._store) : _box = _store.box<TripEntity>();

  // Store reference kept to keep the database open for the lifetime of the DAO.
  // ignore: unused_field
  final ob.Store _store;
  final ob.Box<TripEntity> _box;

  @override
  Future<void> upsert(TripEntity trip) async {
    // Upsert by unique tripId
    final query = _box.query(TripEntity_.tripId.equals(trip.tripId)).build();
    try {
      final existing = query.findFirst();
      if (existing != null) {
        trip.id = existing.id;
      }
      _box.put(trip);
    } finally {
      query.close();
    }
  }

  @override
  Future<void> upsertMany(List<TripEntity> trips) async {
    for (final trip in trips) {
      await upsert(trip);
    }
  }

  @override
  Future<TripEntity?> getById(String tripId) async {
    final query = _box.query(TripEntity_.tripId.equals(tripId)).build();
    try {
      return query.findFirst();
    } finally {
      query.close();
    }
  }

  @override
  Future<List<TripEntity>> getByDevice(int deviceId) async {
    final query = _box
        .query(TripEntity_.deviceId.equals(deviceId))
        .order(TripEntity_.startTimeMs, flags: ob.Order.descending)
        .build();
    try {
      return query.find();
    } finally {
      query.close();
    }
  }

  @override
  Future<List<TripEntity>> getByDeviceInRange(
    int deviceId,
    DateTime startTime,
    DateTime endTime,
  ) async {
    final startMs = startTime.toUtc().millisecondsSinceEpoch;
    final endMs = endTime.toUtc().millisecondsSinceEpoch;

    final query = _box
        .query(
          TripEntity_.deviceId.equals(deviceId) &
              TripEntity_.startTimeMs.greaterOrEqual(startMs) &
              TripEntity_.endTimeMs.lessOrEqual(endMs),
        )
        .order(TripEntity_.startTimeMs, flags: ob.Order.descending)
        .build();
    try {
      return query.find();
    } finally {
      query.close();
    }
  }

  @override
  Future<List<TripEntity>> getAll() async {
    return _box.getAll();
  }

  @override
  Future<void> delete(String tripId) async {
    final query = _box.query(TripEntity_.tripId.equals(tripId)).build();
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

/// Provider exposing ObjectBox-backed trips DAO.
final tripsDaoProvider = FutureProvider<TripsDaoBase>((ref) async {
  // Keep alive with a 10-minute cache.
  final link = ref.keepAlive();
  Timer? timer;
  ref
    ..onCancel(() {
      timer?.cancel();
      timer = Timer(const Duration(minutes: 10), link.close);
    })
    ..onDispose(() => timer?.cancel());

  final store = await openStore();
  return TripsDaoObjectBox(store);
});
