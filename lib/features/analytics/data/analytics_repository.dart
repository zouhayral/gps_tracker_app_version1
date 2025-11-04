import 'dart:math';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:my_app_gps/core/network/traccar_api.dart';
import 'package:my_app_gps/core/utils/app_logger.dart';
import 'package:my_app_gps/features/analytics/models/analytics_report.dart';
import 'package:my_app_gps/repositories/trip_repository.dart';

/// Provider for AnalyticsRepository.
final analyticsRepositoryProvider = Provider<AnalyticsRepository>((ref) {
  final api = ref.watch(traccarApiProvider);
  return AnalyticsRepository(api, ref);
});

/// Repository for aggregating tracking data into analytics reports.
///
/// Fetches raw data from Traccar API endpoints (summary, trips, positions)
/// and processes them into unified [AnalyticsReport] objects for different
/// time periods (daily, weekly, monthly).
class AnalyticsRepository {
  static final _log = 'AnalyticsRepository'.logger;

  const AnalyticsRepository(this._api, this._ref);

  final TraccarApi _api;
  final Ref _ref;

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
      // Use exclusive end bound at next midnight to match Traccar expectations
      final to = from.add(const Duration(days: 1));

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
    // Fetch trips using TripRepository to ensure parity with Trips page
    final tripRepo = _ref.read(tripRepositoryProvider);
    final trips = await tripRepo.fetchTrips(deviceId: deviceId, from: from, to: to);

    // In parallel, fetch summary and positions for speed/fuel when available
    final results = await Future.wait([
      _api.getSummaryReport(deviceId, from, to),
      _api.getPositions(deviceId, from, to),
    ]);
    final summaryData = results[0];
    final positionsData = results[1];

    _log.debug(
      'Data fetched: ${summaryData.length} summaries, '
      '${trips.length} trips, ${positionsData.length} positions',
    );

    // Aggregate distance from summary or trips
    // Primary distance/trips from TripRepository (matches Trips page)
    var totalDistanceKm = trips.fold<double>(0.0, (s, t) => s + t.distanceKm);
    var tripCount = trips.length;

    // Fallback: Calculate distance from positions if summary/trips returned 0
    if (totalDistanceKm == 0 && positionsData.isNotEmpty) {
      totalDistanceKm = _calculateDistanceFromPositions(positionsData);
      _log.debug(
        '[AnalyticsRepository] Calculated distance from positions: $totalDistanceKm km',
      );
    }

    // Compute speed statistics from positions
    final speedStats = _computeSpeedStats(positionsData);

    // No position-based fallback for trips; keep parity with Trips page

    // Extract fuel usage if available
    final fuelUsed = _extractFuelUsed(summaryData);

    // Determine display end time: if 'to' is an exclusive midnight bound,
    // show 23:59:59 of the previous day for readability.
    DateTime displayEnd = to;
    if (to.hour == 0 && to.minute == 0 && to.second == 0 && to.millisecond == 0 && to.microsecond == 0) {
      displayEnd = to.subtract(const Duration(seconds: 1));
    }

    final report = AnalyticsReport(
      startTime: from,
      endTime: displayEnd,
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
  // Removed legacy distance aggregation from raw summary/trips maps.

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
    double total = 0.0;
    
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

  // Removed legacy trip-count estimation from raw positions; we rely on TripRepository for parity.

  /// Fetches analytics report for an explicit range, inclusive of the 'to' day.
  ///
  /// From is normalized to start of day; To is treated as inclusive and expanded
  /// to the start of the next day for API queries (exclusive upper bound).
  Future<AnalyticsReport> fetchRangeReport(
    DateTime from,
    DateTime to,
    int deviceId,
  ) async {
    try {
      final fromNorm = DateTime(from.year, from.month, from.day);
      final toExclusive = DateTime(to.year, to.month, to.day).add(const Duration(days: 1));

      _log.debug(
        'Fetching range report: deviceId=$deviceId, from=$fromNorm, toExclusive=$toExclusive',
      );

      return await _fetchAndAggregateReport(deviceId, fromNorm, toExclusive);
    } catch (e, st) {
      _log.error('fetchRangeReport failed', error: e, stackTrace: st);
      final fromNorm = DateTime(from.year, from.month, from.day);
      final toNorm = DateTime(to.year, to.month, to.day, 23, 59, 59);
      return _createZeroedReport(fromNorm, toNorm);
    }
  }
}
