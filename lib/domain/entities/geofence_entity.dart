class GeofenceEntity {
  final int id;
  final String name;
  final String? description;
  const GeofenceEntity({
    required this.id,
    required this.name,
    this.description,
  });
}
