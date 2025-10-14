import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive/hive.dart' as hive;
import 'package:my_app_gps/core/database/entities/position_entity.dart';
import 'package:my_app_gps/features/map/data/position_model.dart';
import 'package:my_app_gps/objectbox.g.dart';
import 'package:objectbox/objectbox.dart' as ob;

/// Abstraction for persistence to enable test fakes.
abstract class PositionsDaoBase {
  Future<void> upsert(Position p);
  Future<Position?> latestByDevice(int deviceId);
  Future<Map<int, Position>> loadAll();
}
/// ObjectBox-backed DAO storing a single last-known Position per device.
class PositionsDaoObjectBox implements PositionsDaoBase {
  PositionsDaoObjectBox(this._store)
      : _box = _store.box<PositionEntity>();
  // Store reference kept to keep the database open for the lifetime of the DAO.
  // ignore: unused_field
  final ob.Store _store;
  final ob.Box<PositionEntity> _box;

  static const String hiveBoxName = 'positions_last_known';

  @override
  Future<void> upsert(Position p) async {
    // Upsert by unique deviceId
    final query = _box.query(PositionEntity_.deviceId.equals(p.deviceId)).build();
    try {
      final existing = query.findFirst();
      final entity = PositionEntity.fromPosition(p);
      if (existing != null) entity.id = existing.id;
      _box.put(entity);
    } finally {
      query.close();
    }
  }

  @override
  Future<Position?> latestByDevice(int deviceId) async {
    final query = _box.query(PositionEntity_.deviceId.equals(deviceId)).build();
    try {
      final e = query.findFirst();
      return e?.toPosition();
    } finally {
      query.close();
    }
  }

  @override
  Future<Map<int, Position>> loadAll() async {
    final list = _box.getAll();
    final out = <int, Position>{};
    for (final e in list) {
      out[e.deviceId] = e.toPosition();
    }
    return out;
  }

  /// One-time migration from Hive box to ObjectBox.
  Future<void> migrateFromHiveIfPresent() async {
    try {
      if (!hive.Hive.isBoxOpen(hiveBoxName)) {
        if (!await hive.Hive.boxExists(hiveBoxName)) return;
      }
      final box = await hive.Hive.openBox<String>(hiveBoxName);
      if (box.isEmpty) {
        await box.close();
        return;
      }
      for (final key in box.keys) {
        if (key is int) {
          final raw = box.get(key);
          if (raw is String) {
            try {
              final map = jsonDecode(raw) as Map<String, dynamic>;
              final p = Position.fromJson(map);
              await upsert(p);
            } catch (_) {/* ignore malformed */}
          }
        }
      }
      await box.deleteFromDisk();
    } catch (e) {
      if (kDebugMode) {
        // ignore: avoid_print
        print('[PositionsDaoObjectBox] migration skipped: $e');
      }
    }
  }
}

/// Provider exposing ObjectBox-backed DAO and running one-time migration.
final positionsDaoProvider = FutureProvider<PositionsDaoBase>((ref) async {
  // Keep alive with a 10-minute cache, like other providers.
  final link = ref.keepAlive();
  Timer? timer;
  ref.onCancel(() {
    timer?.cancel();
    timer = Timer(const Duration(minutes: 10), link.close);
  });
  ref.onDispose(() => timer?.cancel());

  // Reuse the same ObjectBox store as FMTC when available.
  // FMTCObjectBoxBackend initialises a default store directory; if you have your own
  // ObjectBox Store, you can share its directory. For simplicity, open default store.
  // Note: This requires objectbox.g.dart to be generated for PositionEntity.
  final store = await openStore();
  final dao = PositionsDaoObjectBox(store);
  await dao.migrateFromHiveIfPresent();
  return dao;
});
