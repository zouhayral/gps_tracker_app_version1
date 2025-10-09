class PositionEntity {
  final int id;
  final int deviceId;
  final double latitude;
  final double longitude;
  final double speed;
  final double course;
  final DateTime deviceTime;
  const PositionEntity({
    required this.id,
    required this.deviceId,
    required this.latitude,
    required this.longitude,
    required this.speed,
    required this.course,
    required this.deviceTime,
  });
}
