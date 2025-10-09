class TripEntity {
  final String id;
  final int deviceId;
  final DateTime startTime;
  final DateTime endTime;
  final double distanceKm;
  const TripEntity({
    required this.id,
    required this.deviceId,
    required this.startTime,
    required this.endTime,
    required this.distanceKm,
  });
}
