import 'dart:math';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:my_app_gps/core/network/traccar_api.dart';
import 'package:my_app_gps/core/utils/app_logger.dart';
import 'package:my_app_gps/features/analytics/models/analytics_report.dart';

/// Provider for AnalyticsRepository.
final analyticsRepositoryProvider = Provider<AnalyticsRepository>((ref) {
  final api = ref.watch(traccarApiProvider);
  return AnalyticsRepository(api);
});

/// Repository for aggregating tracking data into analytics reports.
///
/// Fetches raw data from Traccar API endpoints (summary, trips, positions)
/// and processes them into unified [AnalyticsReport] objects for different
/// time periods (daily, weekly, monthly).
class AnalyticsRepository {
  static final _log = 'AnalyticsRepository'.logger;

  const AnalyticsRepository(this._api);

  final TraccarApi _api;

  /// Fetches a daily analytics report for a specific date and device.
  ///
  /// The report covers the entire day from midnight (00:00:00) to
  /// just before midnight the next day (23:59:59).
  ///
  /// Parameters:
  /// - [date]: The date to generate the report for
  /// - [deviceId]: The ID of the device to analyze
  ///
  /// Returns an [AnalyticsReport] with aggregated statistics.
  /// Returns a zeroed report if any error occurs.
  Future<AnalyticsReport> fetchDailyReport(DateTime date, int deviceId) async {
    try {
      final from = DateTime(date.year, date.month, date.day);
      final to = DateTime(date.year, date.month, date.day, 23, 59, 59);

      _log.debug(
        'Fetching daily report: deviceId=$deviceId, '
        'from=$from, to=$to',
      );

      return await _fetchAndAggregateReport(deviceId, from, to);
    } catch (e, st) {
      _log.error(
        'fetchDailyReport failed for deviceId=$deviceId, date=$date',
        error: e,
        stackTrace: st,
      );
      return _createZeroedReport(date, date);
    }
  }

  /// Fetches a weekly analytics report starting from a specific date.
  ///
  /// The report covers 7 days starting from the given start date.
  ///
  /// Parameters:
  /// - [start]: The start date of the week
  /// - [deviceId]: The ID of the device to analyze
  ///
  /// Returns an [AnalyticsReport] with aggregated statistics.
  /// Returns a zeroed report if any error occurs.
  Future<AnalyticsReport> fetchWeeklyReport(
    DateTime start,
    int deviceId,
  ) async {
    try {
      final from = DateTime(start.year, start.month, start.day);
      final to = from.add(const Duration(days: 7));

      _log.debug(
        'Fetching weekly report: deviceId=$deviceId, '
        'from=$from, to=$to',
      );

      return await _fetchAndAggregateReport(deviceId, from, to);
    } catch (e, st) {
      _log.error(
        'fetchWeeklyReport failed for deviceId=$deviceId, start=$start',
        error: e,
        stackTrace: st,
      );
      return _createZeroedReport(start, start.add(const Duration(days: 7)));
    }
  }

  /// Fetches a monthly analytics report starting from a specific date.
  ///
  /// The report covers 30 days starting from the given start date.
  ///
  /// Parameters:
  /// - [start]: The start date of the month
  /// - [deviceId]: The ID of the device to analyze
  ///
  /// Returns an [AnalyticsReport] with aggregated statistics.
  /// Returns a zeroed report if any error occurs.
  Future<AnalyticsReport> fetchMonthlyReport(
    DateTime start,
    int deviceId,
  ) async {
    try {
      final from = DateTime(start.year, start.month, start.day);
      final to = from.add(const Duration(days: 30));

      _log.debug(
        'Fetching monthly report: deviceId=$deviceId, '
        'from=$from, to=$to',
      );

      return await _fetchAndAggregateReport(deviceId, from, to);
    } catch (e, st) {
      _log.error(
        'fetchMonthlyReport failed for deviceId=$deviceId, start=$start',
        error: e,
        stackTrace: st,
      );
      return _createZeroedReport(start, start.add(const Duration(days: 30)));
    }
  }

  /// Internal helper that fetches all data sources in parallel and aggregates them.
  Future<AnalyticsReport> _fetchAndAggregateReport(
    int deviceId,
    DateTime from,
    DateTime to,
  ) async {
    // Fetch all data sources in parallel for efficiency
    final results = await Future.wait([
      _api.getSummaryReport(deviceId, from, to),
      _api.getTripsReport(deviceId, from, to),
      _api.getPositions(deviceId, from, to),
    ]);

    final summaryData = results[0];
    final tripsData = results[1];
    final positionsData = results[2];

    _log.debug(
      'Data fetched: ${summaryData.length} summaries, '
      '${tripsData.length} trips, ${positionsData.length} positions',
    );

    // Aggregate distance from summary or trips
    var totalDistanceKm = _computeTotalDistance(summaryData, tripsData);

    // Fallback: Calculate distance from positions if summary/trips returned 0
    if (totalDistanceKm == 0 && positionsData.isNotEmpty) {
      totalDistanceKm = _calculateDistanceFromPositions(positionsData);
      _log.debug(
        '[AnalyticsRepository] Calculated distance from positions: $totalDistanceKm km',
      );
    }

    // Compute speed statistics from positions
    final speedStats = _computeSpeedStats(positionsData);

    // Count trips
    var tripCount = tripsData.length;

    // Fallback: Estimate trip count from positions if trips returned 0
    if (tripCount == 0 && positionsData.isNotEmpty) {
      tripCount = _estimateTripCount(positionsData);
      _log.debug(
        '[AnalyticsRepository] Estimated trip count: $tripCount',
      );
    }

    // Extract fuel usage if available
    final fuelUsed = _extractFuelUsed(summaryData);

    final report = AnalyticsReport(
      startTime: from,
      endTime: to,
      totalDistanceKm: totalDistanceKm,
      avgSpeed: speedStats.avgSpeed,
      maxSpeed: speedStats.maxSpeed,
      tripCount: tripCount,
      fuelUsed: fuelUsed,
    );

    _log.debug('Report generated: $report');

    return report;
  }

  /// Computes total distance from summary or trips data.
  double _computeTotalDistance(
    List<Map<String, dynamic>> summaryData,
    List<Map<String, dynamic>> tripsData,
  ) {
    // Try to get distance from summary data first (more accurate)
    if (summaryData.isNotEmpty) {
      final distance = summaryData.fold<double>(
        0,
        (sum, item) {
          final dist = item['distance'];
          if (dist != null) {
            // Distance is usually in meters, convert to km
            return sum + (dist is num ? dist.toDouble() / 1000.0 : 0.0);
          }
          return sum;
        },
      );
      if (distance > 0) return distance;
    }

    // Fallback: Sum distances from trips data
    if (tripsData.isNotEmpty) {
      return tripsData.fold<double>(
        0,
        (sum, trip) {
          final dist = trip['distance'];
          if (dist != null) {
            // Distance is usually in meters, convert to km
            return sum + (dist is num ? dist.toDouble() / 1000.0 : 0.0);
          }
          return sum;
        },
      );
    }

    return 0;
  }

  /// Computes speed statistics (average and max) from positions data.
  ({double avgSpeed, double maxSpeed}) _computeSpeedStats(
    List<Map<String, dynamic>> positionsData,
  ) {
    if (positionsData.isEmpty) {
      return (avgSpeed: 0.0, maxSpeed: 0.0);
    }

    var maxSpeed = 0.0;
    var totalSpeed = 0.0;
    var speedCount = 0;

    for (final position in positionsData) {
      final speed = position['speed'];
      if (speed != null && speed is num) {
        final speedValue = speed.toDouble();
        
        // Speed from Traccar is typically in knots, convert to km/h
        // 1 knot = 1.852 km/h
        final speedKmh = speedValue * 1.852;

        totalSpeed += speedKmh;
        speedCount++;

        if (speedKmh > maxSpeed) {
          maxSpeed = speedKmh;
        }
      }
    }

    final avgSpeed = speedCount > 0 ? totalSpeed / speedCount : 0.0;

    return (avgSpeed: avgSpeed, maxSpeed: maxSpeed);
  }

  /// Extracts fuel usage from summary data if available.
  double? _extractFuelUsed(List<Map<String, dynamic>> summaryData) {
    if (summaryData.isEmpty) return null;

    // Look for fuel-related fields in summary data
    for (final summary in summaryData) {
      // Check common fuel field names
      final fuel = summary['fuelUsed'] ?? 
                   summary['fuel'] ?? 
                   summary['spentFuel'];
      
      if (fuel != null && fuel is num) {
        return fuel.toDouble();
      }
    }

    return null;
  }

  /// Creates a zeroed report for error cases.
  AnalyticsReport _createZeroedReport(DateTime from, DateTime to) {
    return AnalyticsReport(
      startTime: from,
      endTime: to,
      totalDistanceKm: 0,
      avgSpeed: 0,
      maxSpeed: 0,
      tripCount: 0,
    );
  }

  /// Calculates total distance from position coordinates using Haversine formula.
  ///
  /// This is a fallback method when Traccar's summary/trips reports don't
  /// provide distance data. It computes the distance between consecutive
  /// GPS positions.
  double _calculateDistanceFromPositions(List<dynamic> positions) {
    var total = 0.0;
    
    for (var i = 1; i < positions.length; i++) {
      final prev = positions[i - 1];
      final curr = positions[i];
      
      final lat1 = prev['latitude'];
      final lon1 = prev['longitude'];
      final lat2 = curr['latitude'];
      final lon2 = curr['longitude'];
      
      if (lat1 != null && lon1 != null && lat2 != null && lon2 != null) {
        total += _haversine(
          lat1 is num ? lat1.toDouble() : 0.0,
          lon1 is num ? lon1.toDouble() : 0.0,
          lat2 is num ? lat2.toDouble() : 0.0,
          lon2 is num ? lon2.toDouble() : 0.0,
        );
      }
    }
    
    return total;
  }

  /// Calculates distance between two GPS coordinates using Haversine formula.
  ///
  /// Returns distance in kilometers.
  double _haversine(double lat1, double lon1, double lat2, double lon2) {
    const R = 6371.0; // Earth radius in km
    
    final dLat = _deg2rad(lat2 - lat1);
    final dLon = _deg2rad(lon2 - lon1);
    
    final a = sin(dLat / 2) * sin(dLat / 2) +
        cos(_deg2rad(lat1)) * cos(_deg2rad(lat2)) *
        sin(dLon / 2) * sin(dLon / 2);
    
    final c = 2 * atan2(sqrt(a), sqrt(1 - a));
    
    return R * c;
  }

  /// Converts degrees to radians.
  double _deg2rad(double deg) => deg * pi / 180;

  /// Estimates trip count from position data based on speed thresholds.
  ///
  /// This is a fallback method when Traccar's trips report is empty.
  /// It counts trips by detecting when speed crosses above 5 km/h (moving)
  /// and drops below 2 km/h (stopped).
  int _estimateTripCount(List<dynamic> positions) {
    var trips = 0;
    var inTrip = false;
    
    for (final pos in positions) {
      final speed = pos['speed'];
      
      if (speed != null && speed is num) {
        // Convert knots to km/h
        final speedKmh = speed.toDouble() * 1.852;
        
        if (!inTrip && speedKmh > 5) {
          // Started moving - new trip
          inTrip = true;
          trips++;
        } else if (inTrip && speedKmh < 2) {
          // Stopped moving - trip ended
          inTrip = false;
        }
      }
    }
    
    return trips;
  }
}
