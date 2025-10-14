import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:my_app_gps/core/database/entities/device_entity.dart';
import 'package:my_app_gps/objectbox.g.dart';
import 'package:objectbox/objectbox.dart' as ob;

/// Abstraction for device persistence to enable test fakes.
abstract class DevicesDaoBase {
  Future<void> upsert(DeviceEntity device);
  Future<void> upsertMany(List<DeviceEntity> devices);
  Future<DeviceEntity?> getById(int deviceId);
  Future<List<DeviceEntity>> getAll();
  Future<List<DeviceEntity>> getByStatus(String status);
  Future<void> delete(int deviceId);
  Future<void> deleteAll();
}

/// ObjectBox-backed DAO for managing device persistence.
class DevicesDaoObjectBox implements DevicesDaoBase {
  DevicesDaoObjectBox(this._store) : _box = _store.box<DeviceEntity>();

  // Store reference kept to keep the database open for the lifetime of the DAO.
  // ignore: unused_field
  final ob.Store _store;
  final ob.Box<DeviceEntity> _box;

  @override
  Future<void> upsert(DeviceEntity device) async {
    // Upsert by unique deviceId
    final query =
        _box.query(DeviceEntity_.deviceId.equals(device.deviceId)).build();
    try {
      final existing = query.findFirst();
      if (existing != null) {
        device.id = existing.id;
      }
      _box.put(device);
    } finally {
      query.close();
    }
  }

  @override
  Future<void> upsertMany(List<DeviceEntity> devices) async {
    for (final device in devices) {
      await upsert(device);
    }
  }

  @override
  Future<DeviceEntity?> getById(int deviceId) async {
    final query = _box.query(DeviceEntity_.deviceId.equals(deviceId)).build();
    try {
      return query.findFirst();
    } finally {
      query.close();
    }
  }

  @override
  Future<List<DeviceEntity>> getAll() async {
    return _box.getAll();
  }

  @override
  Future<List<DeviceEntity>> getByStatus(String status) async {
    final query = _box.query(DeviceEntity_.status.equals(status)).build();
    try {
      return query.find();
    } finally {
      query.close();
    }
  }

  @override
  Future<void> delete(int deviceId) async {
    final query = _box.query(DeviceEntity_.deviceId.equals(deviceId)).build();
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
}

/// Provider exposing ObjectBox-backed devices DAO.
final devicesDaoProvider = FutureProvider<DevicesDaoBase>((ref) async {
  // Keep alive with a 10-minute cache.
  final link = ref.keepAlive();
  Timer? timer;
  ref.onCancel(() {
    timer?.cancel();
    timer = Timer(const Duration(minutes: 10), link.close);
  });
  ref.onDispose(() => timer?.cancel());

  final store = await openStore();
  return DevicesDaoObjectBox(store);
});
