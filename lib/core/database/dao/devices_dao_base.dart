import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Lightweight device record used by repositories across platforms.
class DeviceRecord {
  final int deviceId;
  final String name;
  final String? uniqueId;
  final String status; // online/offline/unknown

  const DeviceRecord({
    required this.deviceId,
    required this.name,
    this.uniqueId,
    this.status = 'unknown',
  });

  Map<String, dynamic> toJson() => {
        'deviceId': deviceId,
        'name': name,
        'uniqueId': uniqueId,
        'status': status,
      };

  factory DeviceRecord.fromJson(Map<String, dynamic> json) => DeviceRecord(
        deviceId: (json['deviceId'] as num).toInt(),
        name: json['name'] as String? ?? 'Unknown',
        uniqueId: json['uniqueId'] as String?,
        status: json['status'] as String? ?? 'unknown',
      );
}

/// Abstraction for device persistence to enable platform-specific backends.
abstract class DevicesDaoBase {
  Future<void> upsert(DeviceRecord device);
  Future<void> upsertMany(List<DeviceRecord> devices);
  Future<DeviceRecord?> getById(int deviceId);
  Future<List<DeviceRecord>> getAll();
  Future<List<DeviceRecord>> getByStatus(String status);
  Future<void> delete(int deviceId);
  Future<void> deleteAll();
}

// Forward-declared provider, bound in platform impls
late final FutureProvider<DevicesDaoBase> devicesDaoProvider;
