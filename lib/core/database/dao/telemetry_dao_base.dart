import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Domain telemetry sample used across platforms (no ObjectBox annotations).
class TelemetrySample {
  TelemetrySample({
    required this.deviceId,
    required this.timestampMs,
    this.speed,
    this.battery,
    this.signal,
    this.engine,
    this.odometer,
    this.motion,
  });

  final int deviceId;
  final int timestampMs; // UTC ms since epoch
  final double? speed; // km/h
  final double? battery; // %
  final double? signal; // 0-100
  final String? engine; // on/off/unknown
  final double? odometer; // km
  final bool? motion; // motion sensor
}

/// Abstraction for telemetry persistence to enable test fakes.
abstract class TelemetryDaoBase {
  Future<void> put(TelemetrySample record);
  Future<void> putMany(List<TelemetrySample> records);
  Future<List<TelemetrySample>> byDeviceInRange(
    int deviceId,
    DateTime start,
    DateTime end,
  );
  Future<int> countForDevice(int deviceId);
  Future<void> deleteOlderThan(DateTime cutoff);
}

/// Fallback no-op provider implementation (used only if platform providers fail)
final telemetryDaoFallbackProvider = Provider<TelemetryDaoBase>((ref) {
  return _TelemetryDaoNoop();
});

class _TelemetryDaoNoop implements TelemetryDaoBase {
  @override
  Future<void> put(TelemetrySample record) async {}

  @override
  Future<void> putMany(List<TelemetrySample> records) async {}

  @override
  Future<List<TelemetrySample>> byDeviceInRange(
    int deviceId,
    DateTime start,
    DateTime end,
  ) async => <TelemetrySample>[];

  @override
  Future<int> countForDevice(int deviceId) async => 0;

  @override
  Future<void> deleteOlderThan(DateTime cutoff) async {}
}
