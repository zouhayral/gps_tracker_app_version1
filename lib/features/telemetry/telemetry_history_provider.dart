import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:my_app_gps/core/database/dao/telemetry_dao.dart';
import 'package:my_app_gps/core/database/entities/telemetry_record.dart';

/// Provides telemetry history for a device over the last 24 hours.
///
/// Usage:
///   ref.watch(telemetryHistoryProvider(deviceId))
final telemetryHistoryProvider =
    FutureProvider.family<List<TelemetryRecord>, int>((ref, deviceId) async {
  final dao = ref.watch(telemetryDaoProvider);
  final now = DateTime.now().toUtc();
  final start = now.subtract(const Duration(hours: 24));
  final records = await dao.byDeviceInRange(deviceId, start, now);
  return records;
});
