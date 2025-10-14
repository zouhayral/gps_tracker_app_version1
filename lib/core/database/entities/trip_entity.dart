import 'package:objectbox/objectbox.dart';

// TODO(OBX5): After upgrading to ObjectBox 5.x, re-run generator and verify
// indices and named constructors. Update DAO query code if APIs change.

/// ObjectBox entity for Trip persistence
@Entity()
class TripEntity {
  TripEntity({
    required this.tripId,
    required this.deviceId,
    required this.startTimeMs,
    required this.endTimeMs,
    required this.distanceKm,
    this.id = 0,
    this.driverName,
    this.driverUniqueId,
    this.maxSpeed = 0.0,
    this.averageSpeed = 0.0,
    this.startOdometer = 0.0,
    this.endOdometer = 0.0,
    this.startPositionId,
    this.endPositionId,
    this.spentFuel = 0.0,
    this.attributesJson = '{}',
  });

  /// Local ObjectBox ID (auto-increment)
  @Id()
  int id;

  /// Backend trip ID - indexed for fast lookups
  @Unique()
  @Index()
  String tripId;

  /// Device ID this trip belongs to - indexed for querying trips by device
  @Index()
  int deviceId;

  /// Trip start time in milliseconds since epoch
  @Index()
  int startTimeMs;

  /// Trip end time in milliseconds since epoch
  @Index()
  int endTimeMs;

  /// Total distance traveled in kilometers
  double distanceKm;

  /// Optional driver information
  String? driverName;
  String? driverUniqueId;

  /// Speed statistics
  double maxSpeed;
  double averageSpeed;

  /// Odometer readings
  double startOdometer;
  double endOdometer;

  /// Position references
  int? startPositionId;
  int? endPositionId;

  /// Fuel consumption
  double spentFuel;

  /// JSON string for additional attributes
  String attributesJson;

  /// Factory constructor from domain entity
  factory TripEntity.fromDomain({
    required String tripId,
    required int deviceId,
    required DateTime startTime,
    required DateTime endTime,
    required double distanceKm,
    String? driverName,
    String? driverUniqueId,
    double maxSpeed = 0.0,
    double averageSpeed = 0.0,
    double startOdometer = 0.0,
    double endOdometer = 0.0,
    int? startPositionId,
    int? endPositionId,
    double spentFuel = 0.0,
    Map<String, dynamic>? attributes,
  }) {
    return TripEntity(
      tripId: tripId,
      deviceId: deviceId,
      startTimeMs: startTime.toUtc().millisecondsSinceEpoch,
      endTimeMs: endTime.toUtc().millisecondsSinceEpoch,
      distanceKm: distanceKm,
      driverName: driverName,
      driverUniqueId: driverUniqueId,
      maxSpeed: maxSpeed,
      averageSpeed: averageSpeed,
      startOdometer: startOdometer,
      endOdometer: endOdometer,
      startPositionId: startPositionId,
      endPositionId: endPositionId,
      spentFuel: spentFuel,
      attributesJson:
          attributes != null ? _encodeAttributes(attributes) : '{}',
    );
  }

  /// Convert to domain entity
  Map<String, dynamic> toDomain() {
    return {
      'id': tripId,
      'deviceId': deviceId,
      'startTime': DateTime.fromMillisecondsSinceEpoch(startTimeMs, isUtc: true)
          .toLocal(),
      'endTime':
          DateTime.fromMillisecondsSinceEpoch(endTimeMs, isUtc: true).toLocal(),
      'distanceKm': distanceKm,
      'driverName': driverName,
      'driverUniqueId': driverUniqueId,
      'maxSpeed': maxSpeed,
      'averageSpeed': averageSpeed,
      'startOdometer': startOdometer,
      'endOdometer': endOdometer,
      'startPositionId': startPositionId,
      'endPositionId': endPositionId,
      'spentFuel': spentFuel,
      'attributes': _decodeAttributes(attributesJson),
    };
  }

  /// Get trip duration in seconds
  int get durationSeconds => (endTimeMs - startTimeMs) ~/ 1000;

  static String _encodeAttributes(Map<String, dynamic> attributes) {
    try {
      return attributes.toString();
    } catch (_) {
      return '{}';
    }
  }

  static Map<String, dynamic> _decodeAttributes(String json) {
    try {
      return {};
    } catch (_) {
      return {};
    }
  }
}
