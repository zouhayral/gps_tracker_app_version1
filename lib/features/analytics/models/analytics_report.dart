/// Data model representing analytics and statistics for a GPS tracker device
/// over a specific time period.
class AnalyticsReport {
  /// Creates an immutable [AnalyticsReport] instance.
  const AnalyticsReport({
    required this.startTime,
    required this.endTime,
    required this.totalDistanceKm,
    required this.avgSpeed,
    required this.maxSpeed,
    required this.tripCount,
    this.fuelUsed,
  });

  /// Creates an [AnalyticsReport] from a JSON map.
  factory AnalyticsReport.fromJson(Map<String, dynamic> json) {
    return AnalyticsReport(
      startTime: DateTime.parse(json['startTime'] as String),
      endTime: DateTime.parse(json['endTime'] as String),
      totalDistanceKm: (json['totalDistanceKm'] as num).toDouble(),
      avgSpeed: (json['avgSpeed'] as num).toDouble(),
      maxSpeed: (json['maxSpeed'] as num).toDouble(),
      tripCount: json['tripCount'] as int,
      fuelUsed: json['fuelUsed'] != null 
          ? (json['fuelUsed'] as num).toDouble() 
          : null,
    );
  }

  /// The start date and time of the analytics period.
  final DateTime startTime;

  /// The end date and time of the analytics period.
  final DateTime endTime;

  /// Total distance traveled in kilometers during the period.
  final double totalDistanceKm;

  /// Average speed in km/h during the period.
  final double avgSpeed;

  /// Maximum speed reached in km/h during the period.
  final double maxSpeed;

  /// Total fuel consumed in liters (nullable, depends on device support).
  final double? fuelUsed;

  /// Number of trips completed during the period.
  final int tripCount;

  /// Converts this [AnalyticsReport] to a JSON map.
  Map<String, dynamic> toJson() {
    return {
      'startTime': startTime.toIso8601String(),
      'endTime': endTime.toIso8601String(),
      'totalDistanceKm': totalDistanceKm,
      'avgSpeed': avgSpeed,
      'maxSpeed': maxSpeed,
      'fuelUsed': fuelUsed,
      'tripCount': tripCount,
    };
  }

  /// Creates a copy of this [AnalyticsReport] with the given fields replaced
  /// with new values.
  AnalyticsReport copyWith({
    DateTime? startTime,
    DateTime? endTime,
    double? totalDistanceKm,
    double? avgSpeed,
    double? maxSpeed,
    double? fuelUsed,
    int? tripCount,
  }) {
    return AnalyticsReport(
      startTime: startTime ?? this.startTime,
      endTime: endTime ?? this.endTime,
      totalDistanceKm: totalDistanceKm ?? this.totalDistanceKm,
      avgSpeed: avgSpeed ?? this.avgSpeed,
      maxSpeed: maxSpeed ?? this.maxSpeed,
      fuelUsed: fuelUsed ?? this.fuelUsed,
      tripCount: tripCount ?? this.tripCount,
    );
  }

  @override
  String toString() {
    return 'AnalyticsReport('
        'startTime: $startTime, '
        'endTime: $endTime, '
        'totalDistanceKm: $totalDistanceKm, '
        'avgSpeed: $avgSpeed, '
        'maxSpeed: $maxSpeed, '
        'fuelUsed: $fuelUsed, '
        'tripCount: $tripCount'
        ')';
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;

    return other is AnalyticsReport &&
        other.startTime == startTime &&
        other.endTime == endTime &&
        other.totalDistanceKm == totalDistanceKm &&
        other.avgSpeed == avgSpeed &&
        other.maxSpeed == maxSpeed &&
        other.fuelUsed == fuelUsed &&
        other.tripCount == tripCount;
  }

  @override
  int get hashCode {
    return startTime.hashCode ^
        endTime.hashCode ^
        totalDistanceKm.hashCode ^
        avgSpeed.hashCode ^
        maxSpeed.hashCode ^
        fuelUsed.hashCode ^
        tripCount.hashCode;
  }
}
