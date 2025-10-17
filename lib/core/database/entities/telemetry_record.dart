import 'package:objectbox/objectbox.dart';

/// ObjectBox entity representing a single telemetry snapshot for a device.
///
/// Note: Adding a new @Entity requires running ObjectBox code generation.
/// Until codegen is run, DAO will gracefully no-op to avoid runtime errors.
@Entity()
class TelemetryRecord {
  TelemetryRecord({
    required this.deviceId, required this.timestampMs, this.id = 0,
    this.speed,
    this.battery,
    this.signal,
    this.engine,
    this.odometer,
    this.motion,
  });

  @Id()
  int id;

  @Index()
  int deviceId;

  /// UTC milliseconds since epoch
  @Index()
  int timestampMs;

  double? speed; // km/h
  double? battery; // %
  double? signal; // 0-100 (when available)
  String? engine; // on/off/unknown
  double? odometer; // km
  bool? motion; // motion sensor
}
