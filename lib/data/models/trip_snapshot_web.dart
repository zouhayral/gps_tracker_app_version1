import 'package:my_app_gps/data/models/trip_aggregate.dart';

class TripSnapshot {
  TripSnapshot({
    required this.monthKey,
    required this.tripCount,
    required this.totalDistanceKm,
    required this.totalDurationHrs,
    required this.avgSpeedKph,
    this.id = 0,
    DateTime? createdAt,
  }) : createdAt = createdAt ?? DateTime.now();

  int id;
  String monthKey; // e.g. "2025-10"
  int tripCount;
  double totalDistanceKm;
  double totalDurationHrs;
  double avgSpeedKph;
  DateTime createdAt;

  factory TripSnapshot.fromAggregate(String monthKey, TripAggregate agg) =>
      TripSnapshot(
        monthKey: monthKey,
        tripCount: agg.tripCount,
        totalDistanceKm: agg.totalDistanceKm,
        totalDurationHrs: agg.totalDurationHrs,
        avgSpeedKph: agg.avgSpeedKph,
      );
}
