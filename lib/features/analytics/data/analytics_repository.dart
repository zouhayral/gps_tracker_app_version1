import 'dart:math';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:my_app_gps/core/network/traccar_api.dart';
import 'package:my_app_gps/core/utils/app_logger.dart';
import 'package:my_app_gps/features/analytics/models/analytics_report.dart';
import 'package:my_app_gps/repositories/trip_repository.dart';

/// Provider for AnalyticsRepository.
final analyticsRepositoryProvider = Provider<AnalyticsRepository>((ref) {
  final api = ref.watch(traccarApiProvider);
  final tripRepo = ref.watch(tripRepositoryProvider);
  return AnalyticsRepository(api, tripRepo);
});

/// Repository for aggregating tracking data into analytics reports.
///
/// Fetches raw data from Traccar API endpoints (summary, trips, positions)
/// and processes them into unified [AnalyticsReport] objects for different
/// time periods (daily, weekly, monthly).
class AnalyticsRepository {
  static final _log = 'AnalyticsRepository'.logger;

  const AnalyticsRepository(this._api, this._tripRepo);

  final TraccarApi _api;
  final TripRepository _tripRepo;

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
      // Create UTC dates to ensure consistent timezone handling
      // The user's selected date should cover the full 24 hours in UTC
      final from = DateTime.utc(date.year, date.month, date.day, 0, 0, 0);
      final to = DateTime.utc(date.year, date.month, date.day, 23, 59, 59);

      _log.debug(
        'Fetching daily report: deviceId=$deviceId, '
        'date=${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}, '
        'from=$from, to=$to (UTC)',
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
      // Use UTC to avoid timezone conversion issues
      final from = DateTime.utc(start.year, start.month, start.day, 0, 0, 0);
      final to = from.add(const Duration(days: 7));

      _log.debug(
        'Fetching weekly report: deviceId=$deviceId, '
        'from=$from, to=$to (UTC)',
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
      // Use UTC to avoid timezone conversion issues
      final from = DateTime.utc(start.year, start.month, start.day, 0, 0, 0);
      final to = from.add(const Duration(days: 30));

      _log.debug(
        'Fetching monthly report: deviceId=$deviceId, '
        'from=$from, to=$to (UTC)',
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

  /// Fetches an analytics report for a custom date range.
  ///
  /// Parameters:
  /// - [from]: Start date and time of the report period
  /// - [to]: End date and time of the report period
  /// - [deviceId]: The ID of the device to analyze
  ///
  /// Returns an [AnalyticsReport] with aggregated statistics for the specified range.
  /// Returns a zeroed report if any error occurs.
  Future<AnalyticsReport> fetchCustomReport(
    DateTime from,
    DateTime to,
    int deviceId,
  ) async {
    try {
      _log.debug(
        'Fetching custom report: deviceId=$deviceId, '
        'from=$from, to=$to',
      );

      return await _fetchAndAggregateReport(deviceId, from, to);
    } catch (e, st) {
      _log.error(
        'fetchCustomReport failed for deviceId=$deviceId, from=$from, to=$to',
        error: e,
        stackTrace: st,
      );
      return _createZeroedReport(from, to);
    }
  }

  /// Internal helper that fetches all data sources in parallel and aggregates them.
  Future<AnalyticsReport> _fetchAndAggregateReport(
    int deviceId,
    DateTime from,
    DateTime to,
  ) async {
    // Fetch data sources separately to maintain proper types
    final summaryData = await _api.getSummaryReport(deviceId, from, to);
    final trips = await _tripRepo.fetchTrips(deviceId: deviceId, from: from, to: to);
    final positionsData = await _api.getPositions(deviceId, from, to);

    _log.debug(
      'Data fetched: ${summaryData.length} summaries, '
      '${trips.length} trips, ${positionsData.length} positions',
    );

    // Calculate total distance from trips (most accurate)
    var totalDistanceKm = 0.0;
    if (trips.isNotEmpty) {
      totalDistanceKm = trips.fold<double>(
        0,
        (sum, trip) => sum + trip.distanceKm, // Already in km
      );
      _log.debug('Distance from trips: $totalDistanceKm km');
    }

    // Fallback: Get distance from summary if no trips
    if (totalDistanceKm == 0 && summaryData.isNotEmpty) {
      totalDistanceKm = summaryData.fold<double>(
        0,
        (sum, item) {
          final dist = item['distance'];
          if (dist != null) {
            return sum + (dist is num ? dist.toDouble() / 1000.0 : 0.0);
          }
          return sum;
        },
      );
      _log.debug('Distance from summary: $totalDistanceKm km');
    }

    // Fallback: Calculate distance from positions if still 0
    if (totalDistanceKm == 0 && positionsData.isNotEmpty) {
      totalDistanceKm = _calculateDistanceFromPositions(positionsData);
      _log.debug('Distance from positions: $totalDistanceKm km');
    }

    // Compute speed statistics from positions
    final speedStats = _computeSpeedStats(positionsData);

    // Trip count from TripRepository (accurate, handles API errors)
    final tripCount = trips.length;

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
      final prev = positions[i - 1] as Map<String, dynamic>;
      final curr = positions[i] as Map<String, dynamic>;
      
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
}
