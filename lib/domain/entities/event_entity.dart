class EventEntity {
  final String id;
  final int deviceId;
  final String type;
  final DateTime eventTime;
  const EventEntity({
    required this.id,
    required this.deviceId,
    required this.type,
    required this.eventTime,
  });
}
