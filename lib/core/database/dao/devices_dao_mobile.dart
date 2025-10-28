import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:my_app_gps/core/database/dao/devices_dao_base.dart';
import 'package:my_app_gps/core/database/entities/device_entity.dart' as ent;
import 'package:my_app_gps/core/database/objectbox_singleton.dart';
import 'package:my_app_gps/objectbox.g.dart';
import 'package:objectbox/objectbox.dart' as ob;

class DevicesDaoObjectBox implements DevicesDaoBase {
  DevicesDaoObjectBox(this._store) : _box = _store.box<ent.DeviceEntity>();

  // Keep store reference alive for the lifetime of the DAO
  // ignore: unused_field
  final ob.Store _store;
  final ob.Box<ent.DeviceEntity> _box;

  DeviceRecord _fromEntity(ent.DeviceEntity e) => DeviceRecord(
        deviceId: e.deviceId,
        name: e.name,
        uniqueId: e.uniqueId,
        status: e.status,
      );

  ent.DeviceEntity _toEntity(DeviceRecord d) => ent.DeviceEntity(
        deviceId: d.deviceId,
        name: d.name,
        uniqueId: d.uniqueId ?? '',
        status: d.status,
      );

  @override
  Future<void> upsert(DeviceRecord device) async {
  final query = _box.query(DeviceEntity_.deviceId.equals(device.deviceId)).build();
    try {
      final existing = query.findFirst();
      final entity = _toEntity(device);
      if (existing != null) entity.id = existing.id;
      _box.put(entity);
    } finally {
      query.close();
    }
  }

  @override
  Future<void> upsertMany(List<DeviceRecord> devices) async {
    for (final d in devices) {
      await upsert(d);
    }
  }

  @override
  Future<DeviceRecord?> getById(int deviceId) async {
  final q = _box.query(DeviceEntity_.deviceId.equals(deviceId)).build();
    try {
      final e = q.findFirst();
      return e != null ? _fromEntity(e) : null;
    } finally {
      q.close();
    }
  }

  @override
  Future<List<DeviceRecord>> getAll() async {
    return _box.getAll().map(_fromEntity).toList(growable: false);
  }

  @override
  Future<List<DeviceRecord>> getByStatus(String status) async {
  final q = _box.query(DeviceEntity_.status.equals(status)).build();
    try {
      return q.find().map(_fromEntity).toList(growable: false);
    } finally {
      q.close();
    }
  }

  @override
  Future<void> delete(int deviceId) async {
  final q = _box.query(DeviceEntity_.deviceId.equals(deviceId)).build();
    try {
      final e = q.findFirst();
      if (e != null) _box.remove(e.id);
    } finally {
      q.close();
    }
  }

  @override
  Future<void> deleteAll() async {
    _box.removeAll();
  }
}

final devicesDaoProvider = FutureProvider<DevicesDaoBase>((ref) async {
  // Keep alive with a 10-minute cache.
  final link = ref.keepAlive();
  Timer? timer;
  ref.onCancel(() {
    timer?.cancel();
    timer = Timer(const Duration(minutes: 10), link.close);
  });
  ref.onDispose(() => timer?.cancel());

  final store = await ObjectBoxSingleton.getStore();
  return DevicesDaoObjectBox(store);
});
