import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:my_app_gps/core/database/entities/telemetry_record.dart';
import 'package:my_app_gps/core/database/dao/telemetry_dao_objectbox.dart';

/// Abstraction for telemetry persistence to enable test fakes.
abstract class TelemetryDaoBase {
  Future<void> put(TelemetryRecord record);
  Future<void> putMany(List<TelemetryRecord> records);
  Future<List<TelemetryRecord>> byDeviceInRange(
    int deviceId,
    DateTime start,
    DateTime end,
  );
  Future<int> countForDevice(int deviceId);
  Future<void> deleteOlderThan(DateTime cutoff);
}

/// No-op implementation used until ObjectBox codegen is updated.
class TelemetryDaoNoop implements TelemetryDaoBase {
  @override
  Future<void> put(TelemetryRecord record) async {}

  @override
  Future<void> putMany(List<TelemetryRecord> records) async {}

  @override
  Future<List<TelemetryRecord>> byDeviceInRange(
    int deviceId,
    DateTime start,
    DateTime end,
  ) async =>
      <TelemetryRecord>[];

  @override
  Future<int> countForDevice(int deviceId) async => 0;

  @override
  Future<void> deleteOlderThan(DateTime cutoff) async {}
}

/// Provider exposing a telemetry DAO. Defaults to a no-op.
/// Replace/override this provider with an ObjectBox-backed implementation
/// after running ObjectBox code generation to include TelemetryRecord in the model.
final telemetryDaoProvider = Provider<TelemetryDaoBase>((ref) {
  // Prefer real ObjectBox DAO when the Store is ready; fall back to no-op.
  final asyncObj = ref.watch(telemetryDaoObjectBoxProvider);
  return asyncObj.maybeWhen(
    data: (dao) => dao,
    orElse: () => TelemetryDaoNoop(),
  );
});
