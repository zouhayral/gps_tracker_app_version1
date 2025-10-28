import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:my_app_gps/core/database/dao/telemetry_dao.dart';
import 'package:my_app_gps/features/telemetry/telemetry_history_provider.dart';

class _FakeDao implements TelemetryDaoBase {
  List<TelemetrySample> data = [];
  @override
  Future<List<TelemetrySample>> byDeviceInRange(
      int deviceId, DateTime start, DateTime end,) async {
    return data
        .where((r) =>
            r.deviceId == deviceId &&
            r.timestampMs >= start.toUtc().millisecondsSinceEpoch &&
            r.timestampMs <= end.toUtc().millisecondsSinceEpoch,)
        .toList()
      ..sort((a, b) => a.timestampMs.compareTo(b.timestampMs));
  }

  @override
  Future<int> countForDevice(int deviceId) async =>
      data.where((r) => r.deviceId == deviceId).length;
  @override
  Future<void> deleteOlderThan(DateTime cutoff) async {
    final cutoffMs = cutoff.toUtc().millisecondsSinceEpoch;
    data.removeWhere((r) => r.timestampMs < cutoffMs);
  }

  @override
  Future<void> put(TelemetrySample record) async => data.add(record);
  @override
  Future<void> putMany(List<TelemetrySample> records) async =>
      data.addAll(records);
}

void main() {
  test('telemetryHistoryProvider returns last 24h ordered', () async {
    final dao = _FakeDao();
    final now = DateTime.now().toUtc();
    const deviceId = 1;
    // 25h ago (should be filtered out)
  dao.data.add(TelemetrySample(
        deviceId: deviceId,
        timestampMs:
            now.subtract(const Duration(hours: 25)).millisecondsSinceEpoch,
        battery: 50,),);
    // 23h ago
  dao.data.add(TelemetrySample(
        deviceId: deviceId,
        timestampMs:
            now.subtract(const Duration(hours: 23)).millisecondsSinceEpoch,
        battery: 70,),);
    // now
  dao.data.add(TelemetrySample(
        deviceId: deviceId,
        timestampMs: now.millisecondsSinceEpoch,
        battery: 80,),);

    final container = ProviderContainer(overrides: [
      telemetryDaoProvider.overrideWithValue(dao),
    ],);

    final result =
        await container.read(telemetryHistoryProvider(deviceId).future);
    expect(result.length, 2);
    expect(result.first.timestampMs, lessThan(result.last.timestampMs));

    container.dispose();
  });
}
