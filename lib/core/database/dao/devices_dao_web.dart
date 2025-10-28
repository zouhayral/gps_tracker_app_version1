import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive/hive.dart' as hive;
import 'package:my_app_gps/core/database/dao/devices_dao_base.dart';

class DevicesDaoHive implements DevicesDaoBase {
  static const String _boxName = 'devices';

  Future<hive.Box<dynamic>> _box() async {
    if (!hive.Hive.isBoxOpen(_boxName)) {
      return hive.Hive.openBox<dynamic>(_boxName);
    }
    return hive.Hive.box<dynamic>(_boxName);
  }

  @override
  Future<void> upsert(DeviceRecord device) async {
    final box = await _box();
    await box.put(device.deviceId, device.toJson());
  }

  @override
  Future<void> upsertMany(List<DeviceRecord> devices) async {
    final box = await _box();
    final entries = <dynamic, dynamic>{
      for (final d in devices) d.deviceId: d.toJson(),
    };
    await box.putAll(entries);
  }

  @override
  Future<DeviceRecord?> getById(int deviceId) async {
    final box = await _box();
    final data = box.get(deviceId);
    if (data is Map) {
      return DeviceRecord.fromJson(Map<String, dynamic>.from(data));
    }
    return null;
  }

  @override
  Future<List<DeviceRecord>> getAll() async {
    final box = await _box();
    final out = <DeviceRecord>[];
    for (final key in box.keys) {
      final data = box.get(key);
      if (data is Map) {
        try {
          out.add(DeviceRecord.fromJson(Map<String, dynamic>.from(data)));
        } catch (_) {}
      }
    }
    return out;
  }

  @override
  Future<List<DeviceRecord>> getByStatus(String status) async {
    final all = await getAll();
    return all.where((d) => d.status.toLowerCase() == status.toLowerCase()).toList();
  }

  @override
  Future<void> delete(int deviceId) async {
    final box = await _box();
    await box.delete(deviceId);
  }

  @override
  Future<void> deleteAll() async {
    final box = await _box();
    await box.clear();
  }
}

final devicesDaoProvider = FutureProvider<DevicesDaoBase>((ref) async {
  final link = ref.keepAlive();
  Timer? timer;
  ref.onCancel(() {
    timer?.cancel();
    timer = Timer(const Duration(minutes: 10), link.close);
  });
  ref.onDispose(() => timer?.cancel());
  return DevicesDaoHive();
});
