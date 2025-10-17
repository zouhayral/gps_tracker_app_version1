import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:my_app_gps/core/database/dao/telemetry_dao.dart';
import 'package:my_app_gps/core/database/entities/telemetry_record.dart';
import 'package:my_app_gps/objectbox.g.dart';
import 'package:objectbox/objectbox.dart' as ob;

/// Real ObjectBox-backed implementation of [TelemetryDaoBase].
class TelemetryDaoObjectBox implements TelemetryDaoBase {
  TelemetryDaoObjectBox(ob.Store store) : _box = store.box<TelemetryRecord>();

  final ob.Box<TelemetryRecord> _box;

  @override
  Future<void> put(TelemetryRecord record) async {
    _box.put(record);
  }

  @override
  Future<void> putMany(List<TelemetryRecord> records) async {
    _box.putMany(records);
  }

  @override
  Future<List<TelemetryRecord>> byDeviceInRange(
    int deviceId,
    DateTime start,
    DateTime end,
  ) async {
    final startMs = start.toUtc().millisecondsSinceEpoch;
    final endMs = end.toUtc().millisecondsSinceEpoch;
    final q = _box
        .query(
          TelemetryRecord_.deviceId.equals(deviceId) &
              TelemetryRecord_.timestampMs.between(startMs, endMs),
        )
        .order(TelemetryRecord_.timestampMs)
        .build();
    try {
      return q.find();
    } finally {
      q.close();
    }
  }

  @override
  Future<int> countForDevice(int deviceId) async {
    final q = _box.query(TelemetryRecord_.deviceId.equals(deviceId)).build();
    try {
      return q.count();
    } finally {
      q.close();
    }
  }

  @override
  Future<void> deleteOlderThan(DateTime cutoff) async {
    final cutoffMs = cutoff.toUtc().millisecondsSinceEpoch;
    final q =
        _box.query(TelemetryRecord_.timestampMs.lessThan(cutoffMs)).build();
    try {
      final ids = q.findIds();
      if (ids.isNotEmpty) {
        _box.removeMany(ids);
      }
    } finally {
      q.close();
    }
  }
}

/// Provider exposing an ObjectBox-backed telemetry DAO (async, opens the store).
final telemetryDaoObjectBoxProvider =
    FutureProvider<TelemetryDaoBase>((ref) async {
  final store = await openStore();
  return TelemetryDaoObjectBox(store);
});
