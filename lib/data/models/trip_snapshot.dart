import 'package:objectbox/objectbox.dart';
import 'package:my_app_gps/data/models/trip_aggregate.dart';

@Entity()
class TripSnapshot {
  TripSnapshot({
    this.id = 0,
    required this.monthKey,
    required this.tripCount,
    required this.totalDistanceKm,
    required this.totalDurationHrs,
    required this.avgSpeedKph,
    DateTime? createdAt,
  }) : createdAt = createdAt ?? DateTime.now();

  @Id()
  int id;

  // e.g. "2025-10"
  @Unique()
  @Index()
  String monthKey;

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
