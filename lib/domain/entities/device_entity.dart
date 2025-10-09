class DeviceEntity {
  final int id;
  final String name;
  final String uniqueId;
  final String status; // online/offline/unknown
  const DeviceEntity({
    required this.id,
    required this.name,
    required this.uniqueId,
    required this.status,
  });
}
