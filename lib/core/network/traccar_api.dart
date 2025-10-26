import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:my_app_gps/core/utils/app_logger.dart';
import 'package:my_app_gps/services/auth_service.dart';

/// Provider for TraccarApi service for analytics and reports.
final traccarApiProvider = Provider<TraccarApi>((ref) {
  final dio = ref.watch(dioProvider);
  return TraccarApi(dio);
});

/// API client for Traccar analytics and report endpoints.
/// 
/// Provides access to summary reports, trip data, and position history
/// from the Traccar server for generating analytics and statistics.
class TraccarApi {
  static final _log = 'TraccarApi'.logger;

  TraccarApi(this._dio);

  final Dio _dio;

  /// Fetches summary report data for a device within a time range.
  /// 
  /// Returns aggregated statistics including distance, duration, and other
  /// summary metrics from the Traccar `/api/reports/summary` endpoint.
  /// 
  /// Parameters:
  /// - [deviceId]: The ID of the device to fetch the report for
  /// - [from]: Start date/time of the report period (converted to UTC)
  /// - [to]: End date/time of the report period (converted to UTC)
  /// 
  /// Returns a list of summary report entries as JSON maps.
  /// Returns an empty list if the request fails.
  Future<List<Map<String, dynamic>>> getSummaryReport(
    int deviceId,
    DateTime from,
    DateTime to,
  ) async {
    try {
      _log.debug(
        'Fetching summary report: deviceId=$deviceId, '
        'from=${from.toUtc().toIso8601String()}, '
        'to=${to.toUtc().toIso8601String()}',
      );

      final response = await _dio.get<dynamic>(
        '/api/reports/summary',
        queryParameters: {
          'deviceId': deviceId,
          'from': from.toUtc().toIso8601String(),
          'to': to.toUtc().toIso8601String(),
        },
      );

      if (response.data is List) {
        final result = List<Map<String, dynamic>>.from(
          (response.data as List).map((item) => 
            item is Map ? Map<String, dynamic>.from(item) : <String, dynamic>{}
          ),
        );
        
        _log.debug('Summary report fetched: ${result.length} entries');
        return result;
      }

      _log.warning('Unexpected summary report response type: ${response.data.runtimeType}');
      return [];
    } catch (e, st) {
      _log.error('getSummaryReport failed for deviceId=$deviceId', error: e, stackTrace: st);
      return [];
    }
  }

  /// Fetches trip report data for a device within a time range.
  /// 
  /// Returns detailed trip information including start/end times, distances,
  /// and durations from the Traccar `/api/reports/trips` endpoint.
  /// 
  /// Parameters:
  /// - [deviceId]: The ID of the device to fetch trips for
  /// - [from]: Start date/time of the report period (converted to UTC)
  /// - [to]: End date/time of the report period (converted to UTC)
  /// 
  /// Returns a list of trip entries as JSON maps.
  /// Returns an empty list if the request fails.
  Future<List<Map<String, dynamic>>> getTripsReport(
    int deviceId,
    DateTime from,
    DateTime to,
  ) async {
    try {
      _log.debug(
        'Fetching trips report: deviceId=$deviceId, '
        'from=${from.toUtc().toIso8601String()}, '
        'to=${to.toUtc().toIso8601String()}',
      );

      final response = await _dio.get<dynamic>(
        '/api/reports/trips',
        queryParameters: {
          'deviceId': deviceId,
          'from': from.toUtc().toIso8601String(),
          'to': to.toUtc().toIso8601String(),
        },
      );

      if (response.data is List) {
        final result = List<Map<String, dynamic>>.from(
          (response.data as List).map((item) => 
            item is Map ? Map<String, dynamic>.from(item) : <String, dynamic>{}
          ),
        );
        
        _log.debug('Trips report fetched: ${result.length} trips');
        return result;
      }

      _log.warning('Unexpected trips report response type: ${response.data.runtimeType}');
      return [];
    } catch (e, st) {
      _log.error('getTripsReport failed for deviceId=$deviceId', error: e, stackTrace: st);
      return [];
    }
  }

  /// Fetches position history for a device within a time range.
  /// 
  /// Returns a chronological list of GPS positions from the Traccar
  /// `/api/positions` endpoint for detailed speed and location analysis.
  /// 
  /// Parameters:
  /// - [deviceId]: The ID of the device to fetch positions for
  /// - [from]: Start date/time of the query period (converted to UTC)
  /// - [to]: End date/time of the query period (converted to UTC)
  /// 
  /// Returns a list of position entries as JSON maps.
  /// Returns an empty list if the request fails.
  Future<List<Map<String, dynamic>>> getPositions(
    int deviceId,
    DateTime from,
    DateTime to,
  ) async {
    try {
      _log.debug(
        'Fetching positions: deviceId=$deviceId, '
        'from=${from.toUtc().toIso8601String()}, '
        'to=${to.toUtc().toIso8601String()}',
      );

      final response = await _dio.get<dynamic>(
        '/api/positions',
        queryParameters: {
          'deviceId': deviceId,
          'from': from.toUtc().toIso8601String(),
          'to': to.toUtc().toIso8601String(),
        },
      );

      if (response.data is List) {
        final result = List<Map<String, dynamic>>.from(
          (response.data as List).map((item) => 
            item is Map ? Map<String, dynamic>.from(item) : <String, dynamic>{}
          ),
        );
        
        _log.debug('Positions fetched: ${result.length} positions');
        return result;
      }

      _log.warning('Unexpected positions response type: ${response.data.runtimeType}');
      return [];
    } catch (e, st) {
      _log.error('getPositions failed for deviceId=$deviceId', error: e, stackTrace: st);
      return [];
    }
  }
}
