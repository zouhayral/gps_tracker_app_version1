import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive/hive.dart' as hive;
import 'package:my_app_gps/core/database/dao/trips_dao_base.dart';
import 'package:my_app_gps/data/models/trip.dart';
import 'package:my_app_gps/data/models/trip_aggregate.dart';

class TripsDaoWeb implements TripsDaoBase {
  static const _boxName = 'trips';

  Future<hive.Box<Map<String, dynamic>>> _box() async {
    // Storing raw Map<String, dynamic>, no adapters required
    return hive.Hive.openBox<Map<String, dynamic>>(_boxName);
  }

  Map<String, dynamic> _toJson(Trip t) => {
        'id': t.id,
        'deviceId': t.deviceId,
        'startTimeMs': t.startTime.toUtc().millisecondsSinceEpoch,
        'endTimeMs': t.endTime.toUtc().millisecondsSinceEpoch,
        'distanceKm': t.distanceKm,
        'avgSpeedKph': t.avgSpeedKph,
        'maxSpeedKph': t.maxSpeedKph,
        'startLat': t.start.latitude,
        'startLon': t.start.longitude,
        'endLat': t.end.latitude,
        'endLon': t.end.longitude,
      };

  Trip _fromJson(Map<String, dynamic> j) => Trip.fromJson({
        'id': j['id']?.toString(),
        'deviceId': j['deviceId'],
        'startTime': j['startTimeMs'],
        'endTime': j['endTimeMs'],
        'distanceKm': j['distanceKm'],
        'avgSpeedKph': j['avgSpeedKph'],
        'maxSpeedKph': j['maxSpeedKph'],
        'startLat': j['startLat'],
        'startLon': j['startLon'],
        'endLat': j['endLat'],
        'endLon': j['endLon'],
      });

  @override
  Future<void> upsert(Trip trip) async {
    final b = await _box();
    await b.put(trip.id, _toJson(trip));
  }

  @override
  Future<void> upsertMany(List<Trip> trips) async {
    if (trips.isEmpty) return;
    final b = await _box();
    final data = <String, Map<String, dynamic>>{};
    for (final t in trips) {
      data[t.id] = _toJson(t);
    }
    await b.putAll(data);
  }

  @override
  Future<Trip?> getById(String tripId) async {
    final b = await _box();
    final j = b.get(tripId);
    if (j == null) return null;
    return _fromJson(j);
  }

  @override
  Future<List<Trip>> getByDevice(int deviceId) async {
    final b = await _box();
    final res = <Trip>[];
    for (final e in b.toMap().entries) {
      final j = e.value;
      if (j['deviceId'] == deviceId) {
        res.add(_fromJson(j));
      }
    }
    res.sort((a, b) => b.startTime.compareTo(a.startTime));
    return res;
  }

  @override
  Future<List<Trip>> getByDeviceInRange(
    int deviceId,
    DateTime startTime,
    DateTime endTime, {
    int? limit,
    int? offset,
  }) async {
    final b = await _box();
    final startMs = startTime.toUtc().millisecondsSinceEpoch;
    final endMs = endTime.toUtc().millisecondsSinceEpoch;
    final res = <Trip>[];
    for (final j in b.values) {
      if (j['deviceId'] == deviceId) {
        final s = (j['startTimeMs'] as num).toInt();
        final e = (j['endTimeMs'] as num).toInt();
        if (s >= startMs && e <= endMs) res.add(_fromJson(j));
      }
    }
    res.sort((a, b) => b.startTime.compareTo(a.startTime));
    
    // Apply pagination if specified
    if (limit != null) {
      final start = offset ?? 0;
      final end = (start + limit).clamp(0, res.length);
      return res.sublist(start.clamp(0, res.length), end);
    }
    
    return res;
  }

  @override
  Future<int> countByDeviceInRange(
    int deviceId,
    DateTime startTime,
    DateTime endTime,
  ) async {
    final b = await _box();
    final startMs = startTime.toUtc().millisecondsSinceEpoch;
    final endMs = endTime.toUtc().millisecondsSinceEpoch;
    
    var count = 0;
    for (final j in b.values) {
      if (j['deviceId'] == deviceId) {
        final s = (j['startTimeMs'] as num).toInt();
        final e = (j['endTimeMs'] as num).toInt();
        if (s >= startMs && e <= endMs) count++;
      }
    }
    
    return count;
  }

  @override
  Future<List<Trip>> getAll() async {
    final b = await _box();
    final res = b.values.map(_fromJson).toList(growable: false);
    res.sort((a, b) => a.startTime.compareTo(b.startTime));
    return res;
  }

  @override
  Future<void> delete(String tripId) async {
    final b = await _box();
    await b.delete(tripId);
  }

  @override
  Future<void> deleteAll() async {
    final b = await _box();
    await b.clear();
  }

  @override
  Future<List<Trip>> getOlderThan(DateTime cutoff) async {
    final b = await _box();
    final cutoffMs = cutoff.toUtc().millisecondsSinceEpoch;
    final res = <Trip>[];
    for (final j in b.values) {
      final endMs = (j['endTimeMs'] as num).toInt();
      if (endMs < cutoffMs) res.add(_fromJson(j));
    }
    res.sort((a, b) => a.endTime.compareTo(b.endTime));
    return res;
  }

  @override
  Future<int> deleteOlderThan(DateTime cutoff) async {
    final b = await _box();
    final cutoffMs = cutoff.toUtc().millisecondsSinceEpoch;
    final keys = <dynamic>[];
    for (final e in b.toMap().entries) {
      final endMs = (e.value['endTimeMs'] as num).toInt();
      if (endMs < cutoffMs) keys.add(e.key);
    }
    if (keys.isEmpty) return 0;
    await b.deleteAll(keys);
    return keys.length;
  }

  @override
  Future<List<Trip>> getTripsForPeriod(DateTime from, DateTime to) async {
    final b = await _box();
    final fromMs = from.toUtc().millisecondsSinceEpoch;
    final toMs = to.toUtc().millisecondsSinceEpoch;
    final res = <Trip>[];
    for (final j in b.values) {
      final s = (j['startTimeMs'] as num).toInt();
      final e = (j['endTimeMs'] as num).toInt();
      if (s >= fromMs && e <= toMs) res.add(_fromJson(j));
    }
    res.sort((a, b) => a.startTime.compareTo(b.startTime));
    return res;
  }

  @override
  Future<Map<String, TripAggregate>> getAggregatesByDay(
    DateTime from,
    DateTime to,
  ) async {
    final b = await _box();
    final fromMs = from.toUtc().millisecondsSinceEpoch;
    final toMs = to.toUtc().millisecondsSinceEpoch;
    final acc = <String, _AggAcc>{};
    for (final j in b.values) {
      final s = (j['startTimeMs'] as num).toInt();
      final e = (j['endTimeMs'] as num).toInt();
      if (s >= fromMs && e <= toMs) {
        final startLocal = DateTime.fromMillisecondsSinceEpoch(s, isUtc: true).toLocal();
        final key = _fmtYmd(startLocal);
        final entry = acc.putIfAbsent(key, _AggAcc.new);
        final durHrs = (e - s) / 1000.0 / 3600.0;
        entry.totalDistanceKm += (j['distanceKm'] as num).toDouble();
        entry.totalDurationHrs += durHrs;
        entry.sumAvgSpeedKph += (j['avgSpeedKph'] as num).toDouble();
        entry.tripCount += 1;
      }
    }
    return acc.map((k, v) => MapEntry(
          k,
          TripAggregate(
            totalDistanceKm: v.totalDistanceKm,
            totalDurationHrs: v.totalDurationHrs,
            avgSpeedKph: v.tripCount == 0 ? 0.0 : v.sumAvgSpeedKph / v.tripCount,
            tripCount: v.tripCount,
          ),
        ));
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

final tripsDaoWebProvider = Provider<TripsDaoBase>((ref) {
  // Box is opened lazily on first use
  return TripsDaoWeb();
});

TripsDaoBase createTripsDao(Ref ref) {
  return ref.watch(tripsDaoWebProvider);
}
