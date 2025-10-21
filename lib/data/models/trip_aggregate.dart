class TripAggregate {
  final double totalDistanceKm;
  final double totalDurationHrs;
  final double avgSpeedKph;
  final int tripCount;

  const TripAggregate({
    required this.totalDistanceKm,
    required this.totalDurationHrs,
    required this.avgSpeedKph,
    required this.tripCount,
  });

  TripAggregate copyWith({
    double? totalDistanceKm,
    double? totalDurationHrs,
    double? avgSpeedKph,
    int? tripCount,
  }) => TripAggregate(
        totalDistanceKm: totalDistanceKm ?? this.totalDistanceKm,
        totalDurationHrs: totalDurationHrs ?? this.totalDurationHrs,
        avgSpeedKph: avgSpeedKph ?? this.avgSpeedKph,
        tripCount: tripCount ?? this.tripCount,
      );

  static TripAggregate empty() => const TripAggregate(
        totalDistanceKm: 0,
        totalDurationHrs: 0,
        avgSpeedKph: 0,
        tripCount: 0,
      );
}
