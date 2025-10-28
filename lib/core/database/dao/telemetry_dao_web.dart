import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive/hive.dart' as hive;
import 'package:hive_flutter/hive_flutter.dart';
import 'package:my_app_gps/core/database/dao/telemetry_dao_base.dart';

class TelemetryDaoWeb implements TelemetryDaoBase {
  static const _boxName = 'telemetry';

  Future<hive.Box<Map<String, dynamic>>> _box() async {
    if (!Hive.isAdapterRegistered(0)) {
      // No adapters; using raw Map so nothing to register
    }
    return hive.Hive.openBox<Map<String, dynamic>>(_boxName);
  }

  String _key(int deviceId, int ts) => '$deviceId:$ts';

  Map<String, dynamic> _toJson(TelemetrySample s) => {
        'deviceId': s.deviceId,
        'timestampMs': s.timestampMs,
        if (s.speed != null) 'speed': s.speed,
        if (s.battery != null) 'battery': s.battery,
        if (s.signal != null) 'signal': s.signal,
        if (s.engine != null) 'engine': s.engine,
        if (s.odometer != null) 'odometer': s.odometer,
        if (s.motion != null) 'motion': s.motion,
      };

  TelemetrySample _fromJson(Map<String, dynamic> json) => TelemetrySample(
        deviceId: (json['deviceId'] as num).toInt(),
        timestampMs: (json['timestampMs'] as num).toInt(),
        speed: (json['speed'] as num?)?.toDouble(),
        battery: (json['battery'] as num?)?.toDouble(),
        signal: (json['signal'] as num?)?.toDouble(),
        engine: json['engine'] as String?,
        odometer: (json['odometer'] as num?)?.toDouble(),
        motion: json['motion'] as bool?,
      );

  @override
  Future<void> put(TelemetrySample record) async {
    final b = await _box();
    await b.put(_key(record.deviceId, record.timestampMs), _toJson(record));
  }

  @override
  Future<void> putMany(List<TelemetrySample> records) async {
    if (records.isEmpty) return;
    final b = await _box();
    final entries = <String, Map<String, dynamic>>{};
    for (final r in records) {
      entries[_key(r.deviceId, r.timestampMs)] = _toJson(r);
    }
    await b.putAll(entries);
  }

  @override
  Future<List<TelemetrySample>> byDeviceInRange(
    int deviceId,
    DateTime start,
    DateTime end,
  ) async {
    final b = await _box();
    final startMs = start.toUtc().millisecondsSinceEpoch;
    final endMs = end.toUtc().millisecondsSinceEpoch;
    final result = <TelemetrySample>[];
    for (final key in b.keys) {
      if (key is String && key.startsWith('$deviceId:')) {
        final json = b.get(key);
        if (json != null) {
          final ts = (json['timestampMs'] as num).toInt();
          if (ts >= startMs && ts <= endMs) {
            result.add(_fromJson(json));
          }
        }
      }
    }
    result.sort((a, b2) => a.timestampMs.compareTo(b2.timestampMs));
    return result;
  }

  @override
  Future<int> countForDevice(int deviceId) async {
    final b = await _box();
    var count = 0;
    for (final key in b.keys) {
      if (key is String && key.startsWith('$deviceId:')) count++;
    }
    return count;
  }

  @override
  Future<void> deleteOlderThan(DateTime cutoff) async {
    final b = await _box();
    final cutoffMs = cutoff.toUtc().millisecondsSinceEpoch;
    final toDelete = <dynamic>[];
    for (final entry in b.toMap().entries) {
      final k = entry.key;
      final v = entry.value;
      if (k is String) {
        final ts = (v['timestampMs'] as num).toInt();
        if (ts < cutoffMs) toDelete.add(k);
      }
    }
    if (toDelete.isNotEmpty) await b.deleteAll(toDelete);
  }
}

final telemetryDaoWebProvider = Provider<TelemetryDaoBase>((ref) {
  // Simple sync provider; Hive box opens lazily on operations
  return TelemetryDaoWeb();
});

/// Factory used by the conditional shim to produce a unified Provider<TelemetryDaoBase>
TelemetryDaoBase createTelemetryDao(Ref ref) {
  return ref.watch(telemetryDaoWebProvider);
}
