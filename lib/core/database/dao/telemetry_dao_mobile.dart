import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:my_app_gps/core/database/dao/telemetry_dao_base.dart';
import 'package:my_app_gps/core/database/entities/telemetry_record.dart' as ent;
import 'package:my_app_gps/core/database/objectbox_singleton.dart';
import 'package:my_app_gps/objectbox.g.dart';
import 'package:objectbox/objectbox.dart' as ob;

class TelemetryDaoMobile implements TelemetryDaoBase {
  TelemetryDaoMobile(ob.Store store) : _box = store.box<ent.TelemetryRecord>();

  final ob.Box<ent.TelemetryRecord> _box;

  ent.TelemetryRecord _toEntity(TelemetrySample s) => ent.TelemetryRecord(
        deviceId: s.deviceId,
        timestampMs: s.timestampMs,
        speed: s.speed,
        battery: s.battery,
        signal: s.signal,
        engine: s.engine,
        odometer: s.odometer,
        motion: s.motion,
      );

  TelemetrySample _fromEntity(ent.TelemetryRecord e) => TelemetrySample(
        deviceId: e.deviceId,
        timestampMs: e.timestampMs,
        speed: e.speed,
        battery: e.battery,
        signal: e.signal,
        engine: e.engine,
        odometer: e.odometer,
        motion: e.motion,
      );

  @override
  Future<void> put(TelemetrySample record) async {
    _box.put(_toEntity(record));
  }

  @override
  Future<void> putMany(List<TelemetrySample> records) async {
    _box.putMany(records.map(_toEntity).toList());
  }

  @override
  Future<List<TelemetrySample>> byDeviceInRange(
    int deviceId,
    DateTime start,
    DateTime end,
  ) async {
    final startMs = start.toUtc().millisecondsSinceEpoch;
    final endMs = end.toUtc().millisecondsSinceEpoch;
    final q = _box
        .query(TelemetryRecord_.deviceId.equals(deviceId) &
            TelemetryRecord_.timestampMs.between(startMs, endMs))
        .order(TelemetryRecord_.timestampMs)
        .build();
    try {
      return q.find().map(_fromEntity).toList();
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

/// Provider exposing a mobile (ObjectBox) telemetry DAO (async)
final telemetryDaoMobileProvider = FutureProvider<TelemetryDaoBase>((ref) async {
  final link = ref.keepAlive();
  Timer? timer;
  ref.onCancel(() {
    timer?.cancel();
    timer = Timer(const Duration(minutes: 10), link.close);
  });
  ref.onDispose(() => timer?.cancel());
  final store = await ObjectBoxSingleton.getStore();
  return TelemetryDaoMobile(store);
});

/// Factory used by the conditional shim to produce a unified Provider<TelemetryDaoBase>
TelemetryDaoBase createTelemetryDao(Ref ref) {
  final asyncDao = ref.watch(telemetryDaoMobileProvider);
  return asyncDao.maybeWhen(
    data: (d) => d,
    orElse: () => ref.read(telemetryDaoFallbackProvider),
  );
}
