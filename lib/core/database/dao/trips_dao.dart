import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:my_app_gps/core/database/entities/trip_entity.dart';
import 'package:my_app_gps/core/database/objectbox_singleton.dart';
import 'package:my_app_gps/data/models/trip.dart';
import 'package:my_app_gps/data/models/trip_aggregate.dart';
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
  /// Return trips that ended before the cutoff time (UTC).
  Future<List<TripEntity>> getOlderThan(DateTime cutoff);
  /// Delete trips that ended before the cutoff time (UTC). Returns number deleted.
  Future<int> deleteOlderThan(DateTime cutoff);
  /// Domain-level helpers for analytics
  Future<List<Trip>> getTripsForPeriod(DateTime from, DateTime to);
  Future<Map<String, TripAggregate>> getAggregatesByDay(DateTime from, DateTime to);
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

  @override
  Future<List<TripEntity>> getOlderThan(DateTime cutoff) async {
    final cutoffMs = cutoff.toUtc().millisecondsSinceEpoch;
  final query = _box
    .query(TripEntity_.endTimeMs.lessThan(cutoffMs))
    .order(TripEntity_.endTimeMs)
    .build();
    try {
      return query.find();
    } finally {
      query.close();
    }
  }

  @override
  Future<int> deleteOlderThan(DateTime cutoff) async {
    final cutoffMs = cutoff.toUtc().millisecondsSinceEpoch;
    final query = _box.query(TripEntity_.endTimeMs.lessThan(cutoffMs)).build();
    try {
      final ids = query.findIds();
      if (ids.isEmpty) return 0;
      // removeMany is available but for safety fall back if not.
      final removed = _box.removeMany(ids);
      return removed;
    } finally {
      query.close();
    }
  }

  @override
  Future<List<Trip>> getTripsForPeriod(DateTime from, DateTime to) async {
    final fromMs = from.toUtc().millisecondsSinceEpoch;
    final toMs = to.toUtc().millisecondsSinceEpoch;
    final query = _box
        .query(
          TripEntity_.startTimeMs.greaterOrEqual(fromMs) &
              TripEntity_.endTimeMs.lessOrEqual(toMs),
        )
        .order(TripEntity_.startTimeMs, flags: 0)
        .build();
    try {
      final rows = query.find();
      // Map through domain adapter; fine for analytics
      return rows
          .map((e) => Trip.fromJson(e.toDomain()))
          .toList(growable: false);
    } finally {
      query.close();
    }
  }

  @override
  Future<Map<String, TripAggregate>> getAggregatesByDay(
      DateTime from, DateTime to) async {
    final fromMs = from.toUtc().millisecondsSinceEpoch;
    final toMs = to.toUtc().millisecondsSinceEpoch;
    final query = _box
        .query(
          TripEntity_.startTimeMs.greaterOrEqual(fromMs) &
              TripEntity_.endTimeMs.lessOrEqual(toMs),
        )
        .build();
    try {
      final rows = query.find();
      final Map<String, _AggAcc> acc = {};
      for (final t in rows) {
        final startLocal = DateTime.fromMillisecondsSinceEpoch(
                t.startTimeMs,
                isUtc: true)
            .toLocal();
        final key = _fmtYmd(startLocal);
        final entry = acc.putIfAbsent(key, () => _AggAcc());
        final durHrs = (t.endTimeMs - t.startTimeMs) / 1000.0 / 3600.0;
        entry.totalDistanceKm += t.distanceKm;
        entry.totalDurationHrs += durHrs;
        entry.sumAvgSpeedKph += t.averageSpeed;
        entry.tripCount += 1;
      }
      return acc.map((k, v) => MapEntry(
            k,
            TripAggregate(
              totalDistanceKm: v.totalDistanceKm,
              totalDurationHrs: v.totalDurationHrs,
              avgSpeedKph: v.tripCount == 0 ? 0 : v.sumAvgSpeedKph / v.tripCount,
              tripCount: v.tripCount,
            ),
          ));
    } finally {
      query.close();
    }
  }
}

class _AggAcc {
  double totalDistanceKm = 0;
  double totalDurationHrs = 0;
  double sumAvgSpeedKph = 0;
  int tripCount = 0;
}

String _fmtYmd(DateTime d) {
  final y = d.year.toString().padLeft(4, '0');
  final m = d.month.toString().padLeft(2, '0');
  final day = d.day.toString().padLeft(2, '0');
  return '$y-$m-$day';
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

  final store = await ObjectBoxSingleton.getStore();
  return TripsDaoObjectBox(store);
});
