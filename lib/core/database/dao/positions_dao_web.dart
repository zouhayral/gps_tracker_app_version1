import 'dart:async';
import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive/hive.dart' as hive;
import 'package:my_app_gps/core/database/dao/positions_dao_base.dart';
import 'package:my_app_gps/features/map/data/position_model.dart';

class PositionsDaoHive implements PositionsDaoBase {
  static const String hiveBoxName = 'positions_last_known';

  Future<hive.Box<String>> _box() async {
    if (!hive.Hive.isBoxOpen(hiveBoxName)) {
      return hive.Hive.openBox<String>(hiveBoxName);
    }
    return hive.Hive.box<String>(hiveBoxName);
  }

  @override
  Future<void> upsert(Position p) async {
    final box = await _box();
    await box.put(p.deviceId, jsonEncode(p.toJson()));
  }

  @override
  Future<Position?> latestByDevice(int deviceId) async {
    final box = await _box();
    final raw = box.get(deviceId);
    if (raw is String) {
      try {
        return Position.fromJson(jsonDecode(raw) as Map<String, dynamic>);
      } catch (_) {}
    }
    return null;
  }

  @override
  Future<Map<int, Position>> loadAll() async {
    final box = await _box();
    final out = <int, Position>{};
    for (final key in box.keys) {
      if (key is int) {
        final raw = box.get(key);
        if (raw is String) {
          try {
            final map = jsonDecode(raw) as Map<String, dynamic>;
            out[key] = Position.fromJson(map);
          } catch (_) {}
        }
      }
    }
    return out;
  }
}

final positionsDaoProvider = FutureProvider<PositionsDaoBase>((ref) async {
  final link = ref.keepAlive();
  Timer? timer;
  ref.onCancel(() {
    timer?.cancel();
    timer = Timer(const Duration(minutes: 10), link.close);
  });
  ref.onDispose(() => timer?.cancel());

  return PositionsDaoHive();
});
