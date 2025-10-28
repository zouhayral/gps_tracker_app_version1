import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:my_app_gps/core/database/dao/trips_dao_base.dart';
import 'package:my_app_gps/core/database/entities/trip_entity.dart' as ent;
import 'package:my_app_gps/core/database/objectbox_singleton.dart';
import 'package:my_app_gps/data/models/trip.dart';
import 'package:my_app_gps/data/models/trip_aggregate.dart';
import 'package:my_app_gps/objectbox.g.dart';
import 'package:objectbox/objectbox.dart' as ob;

class TripsDaoMobile implements TripsDaoBase {
  TripsDaoMobile(this._store) : _box = _store.box<ent.TripEntity>();

  // ignore: unused_field
  final ob.Store _store;
  final ob.Box<ent.TripEntity> _box;

  ent.TripEntity _toEntity(Trip t) => ent.TripEntity.fromDomain(
        tripId: t.id,
        deviceId: t.deviceId,
        startTime: t.startTime,
        endTime: t.endTime,
        distanceKm: t.distanceKm,
        maxSpeed: t.maxSpeedKph,
        averageSpeed: t.avgSpeedKph,
      );

  Trip _fromEntity(ent.TripEntity e) => Trip.fromJson(e.toDomain());

  @override
  Future<void> upsert(Trip trip) async {
    final q = _box.query(TripEntity_.tripId.equals(trip.id)).build();
    try {
      final existing = q.findFirst();
      final entity = _toEntity(trip);
      if (existing != null) entity.id = existing.id;
      _box.put(entity);
    } finally {
      q.close();
    }
  }

  @override
  Future<void> upsertMany(List<Trip> trips) async {
    for (final t in trips) {
      await upsert(t);
    }
  }

  @override
  Future<Trip?> getById(String tripId) async {
    final q = _box.query(TripEntity_.tripId.equals(tripId)).build();
    try {
      final e = q.findFirst();
      return e != null ? _fromEntity(e) : null;
    } finally {
      q.close();
    }
  }

  @override
  Future<List<Trip>> getByDevice(int deviceId) async {
    final q = _box
        .query(TripEntity_.deviceId.equals(deviceId))
        .order(TripEntity_.startTimeMs, flags: ob.Order.descending)
        .build();
    try {
      return q.find().map(_fromEntity).toList();
    } finally {
      q.close();
    }
  }

  @override
  Future<List<Trip>> getByDeviceInRange(
    int deviceId,
    DateTime startTime,
    DateTime endTime,
  ) async {
    final startMs = startTime.toUtc().millisecondsSinceEpoch;
    final endMs = endTime.toUtc().millisecondsSinceEpoch;
    final q = _box
        .query(
          TripEntity_.deviceId.equals(deviceId) &
              TripEntity_.startTimeMs.greaterOrEqual(startMs) &
              TripEntity_.endTimeMs.lessOrEqual(endMs),
        )
        .order(TripEntity_.startTimeMs, flags: ob.Order.descending)
        .build();
    try {
      return q.find().map(_fromEntity).toList();
    } finally {
      q.close();
    }
  }

  @override
  Future<List<Trip>> getAll() async => _box.getAll().map(_fromEntity).toList();

  @override
  Future<void> delete(String tripId) async {
    final q = _box.query(TripEntity_.tripId.equals(tripId)).build();
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

  @override
  Future<List<Trip>> getOlderThan(DateTime cutoff) async {
    final cutoffMs = cutoff.toUtc().millisecondsSinceEpoch;
    final q = _box
        .query(TripEntity_.endTimeMs.lessThan(cutoffMs))
        .order(TripEntity_.endTimeMs)
        .build();
    try {
      return q.find().map(_fromEntity).toList();
    } finally {
      q.close();
    }
  }

  @override
  Future<int> deleteOlderThan(DateTime cutoff) async {
    final cutoffMs = cutoff.toUtc().millisecondsSinceEpoch;
    final q = _box.query(TripEntity_.endTimeMs.lessThan(cutoffMs)).build();
    try {
      final ids = q.findIds();
      if (ids.isEmpty) return 0;
      return _box.removeMany(ids);
    } finally {
      q.close();
    }
  }

  @override
  Future<List<Trip>> getTripsForPeriod(DateTime from, DateTime to) async {
    final fromMs = from.toUtc().millisecondsSinceEpoch;
    final toMs = to.toUtc().millisecondsSinceEpoch;
    final q = _box
        .query(
          TripEntity_.startTimeMs.greaterOrEqual(fromMs) &
              TripEntity_.endTimeMs.lessOrEqual(toMs),
        )
        .order(TripEntity_.startTimeMs)
        .build();
    try {
      return q.find().map(_fromEntity).toList();
    } finally {
      q.close();
    }
  }

  @override
  Future<Map<String, TripAggregate>> getAggregatesByDay(
      DateTime from, DateTime to) async {
    final fromMs = from.toUtc().millisecondsSinceEpoch;
    final toMs = to.toUtc().millisecondsSinceEpoch;
    final q = _box
        .query(
          TripEntity_.startTimeMs.greaterOrEqual(fromMs) &
              TripEntity_.endTimeMs.lessOrEqual(toMs),
        )
        .build();
    try {
      final rows = q.find();
      final acc = <String, _AggAcc>{};
      for (final t in rows) {
        final startLocal = DateTime.fromMillisecondsSinceEpoch(
          t.startTimeMs,
          isUtc: true,
        ).toLocal();
        final key = _fmtYmd(startLocal);
        final entry = acc.putIfAbsent(key, _AggAcc.new);
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
      q.close();
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

final tripsDaoMobileProvider = FutureProvider<TripsDaoBase>((ref) async {
  final link = ref.keepAlive();
  Timer? timer;
  ref
    ..onCancel(() {
      timer?.cancel();
      timer = Timer(const Duration(minutes: 10), link.close);
    })
    ..onDispose(() => timer?.cancel());

  final store = await ObjectBoxSingleton.getStore();
  return TripsDaoMobile(store);
});

TripsDaoBase createTripsDao(Ref ref) {
  final asyncDao = ref.watch(tripsDaoMobileProvider);
  return asyncDao.maybeWhen(
    data: (d) => d,
    orElse: _TripsNoop.new,
  );
}

class _TripsNoop implements TripsDaoBase {
  @override
  Future<int> deleteOlderThan(DateTime cutoff) async => 0;

  @override
  Future<void> delete(String tripId) async {}

  @override
  Future<void> deleteAll() async {}

  @override
  Future<List<Trip>> getAll() async => <Trip>[];

  @override
  Future<Map<String, TripAggregate>> getAggregatesByDay(DateTime from, DateTime to) async => <String, TripAggregate>{};

  @override
  Future<List<Trip>> getByDevice(int deviceId) async => <Trip>[];

  @override
  Future<List<Trip>> getByDeviceInRange(int deviceId, DateTime startTime, DateTime endTime) async => <Trip>[];

  @override
  Future<Trip?> getById(String tripId) async => null;

  @override
  Future<List<Trip>> getOlderThan(DateTime cutoff) async => <Trip>[];

  @override
  Future<List<Trip>> getTripsForPeriod(DateTime from, DateTime to) async => <Trip>[];

  @override
  Future<void> upsert(Trip trip) async {}

  @override
  Future<void> upsertMany(List<Trip> trips) async {}
}
