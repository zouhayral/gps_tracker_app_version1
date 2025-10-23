import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:my_app_gps/core/database/dao/trip_snapshots_dao.dart';
import 'package:my_app_gps/core/database/dao/trips_dao.dart';
import 'package:my_app_gps/core/diagnostics/dev_diagnostics.dart';
import 'package:my_app_gps/data/models/position.dart' as model;
import 'package:my_app_gps/data/models/trip.dart';
import 'package:my_app_gps/data/models/trip_aggregate.dart';
import 'package:my_app_gps/data/models/trip_snapshot.dart';
import 'package:my_app_gps/services/auth_service.dart';

/// Repository responsible for fetching Trips from Traccar and caching results.
///
/// Endpoint: /api/reports/trips
/// Query params: deviceId, from, to (ISO8601)
class TripRepository {
  TripRepository({required Dio dio, required Ref ref})
      : _dio = dio,
        _ref = ref;

  final Dio _dio;
  // Keeping Ref for DAO and future integrations (e.g., device lookups, prefs)
  final Ref _ref;

  // Note: In-memory cache removed from active code path for simpler, safer networking.

  Future<List<Trip>> fetchTrips({
    required int deviceId,
    required DateTime from,
    required DateTime to,
  }) async {
    final params = {
      'deviceId': deviceId,
      'from': _toUtcIso(from),
      'to': _toUtcIso(to),
    };

    debugPrint('[TripRepository] 🔍 fetchTrips deviceId=$deviceId from=${params['from']} to=${params['to']}');
    debugPrint('[TripRepository] 🌐 BaseURL=${_dio.options.baseUrl}');
    debugPrint('[TripRepository] ↩️  Headers=${_dio.options.headers}');

    try {
      final res = await _dio.post<dynamic>('/api/reports/trips', data: params);
      debugPrint('[TripRepository] ⇢ Status=${res.statusCode} Type=${res.data.runtimeType}');

      // Defensive check for non-200
      if (res.statusCode != 200) {
        debugPrint('[TripRepository] ⚠️ Non-200: ${res.statusCode}, body=${res.data}');
        return <Trip>[];
      }

      // Ensure we got JSON List
      if (res.data is! List) {
        debugPrint('[TripRepository] ⚠️ Unexpected data type: ${res.data.runtimeType}, content=${res.data}');
        return <Trip>[];
      }

      final trips = (res.data as List)
          .whereType<Map<String, dynamic>>()
          .map((e) => Trip.fromJson(e))
          .toList(growable: false);

      debugPrint('[TripRepository] ✅ Parsed ${trips.length} trips');
      return trips;
    } on DioException catch (e) {
      debugPrint('[TripRepository] ❌ DioException (trips): ${e.type}, ${e.message}');
      debugPrint('[TripRepository] ❌ Body: ${e.response?.data}');
      return <Trip>[];
    } catch (e, st) {
      debugPrint('[TripRepository] 💥 Fatal error: $e\n$st');
      return <Trip>[];
    }
  }

  /// Safe cached trips lookup from DAO; returns empty list on error.
  Future<List<Trip>> getCachedTrips(
      int deviceId, DateTime from, DateTime to,) async {
    try {
      final dao = await _ref.read(tripsDaoProvider.future);
      final cached = await dao.getByDeviceInRange(deviceId, from, to);
      if (cached.isEmpty) return const <Trip>[];
      return cached
          .map((e) => Trip.fromJson(e.toDomain()))
          .toList(growable: false);
    } catch (e) {
      if (kDebugMode) {
        debugPrint('[TripRepository] ⚠️ Cache lookup failed: $e');
      }
      return const <Trip>[];
    }
  }

  /// Placeholder for retention policy: delete trips older than 30 days from local cache.
  Future<void> cleanupOldTrips() async {
    try {
      final tripsDao = await _ref.read(tripsDaoProvider.future);
      final snapshotsDao = await _ref.read(tripSnapshotsDaoProvider.future);
      final now = DateTime.now().toUtc();
      final cutoff = now.subtract(const Duration(days: 30));

      // Persist monthly snapshot for the month identified by cutoff
      await _persistMonthlySnapshot(
          cutoff: cutoff, tripsDao: tripsDao, snapshotsDao: snapshotsDao,);

      // Proceed with deletion
      final old = await tripsDao.getOlderThan(cutoff);
      if (old.isNotEmpty && kDebugMode) {
        final totalKm = old.fold<double>(0, (s, t) => s + t.distanceKm);
        debugPrint(
            '[TripRepository] 🧹 Retention: deleting ${old.length} trips (< ${cutoff.toIso8601String()}) totaling ${totalKm.toStringAsFixed(1)} km',);
      }
      await tripsDao.deleteOlderThan(cutoff);
    } catch (e) {
      // Best-effort cleanup; ignore DAO issues
      if (kDebugMode) {
        debugPrint('[TripRepository] ⚠️ cleanupOldTrips error: $e');
      }
    }
  }

  // Removed persistTripsAndCleanup to simplify network path.

  String _toUtcIso(DateTime d) => d.toUtc().toIso8601String();

  // Removed POST/GET fallback helpers; server should return JSON list for POST.

  // Removed transient retry helper; simplified flow.

  // Removed GET fallback; diagnostic logs will catch unexpected responses.

  // Cache key helper removed with cache usage.

  /// Fetch raw positions for a given device and time range.
  Future<List<model.Position>> fetchTripPositions({
    required int deviceId,
    required DateTime from,
    required DateTime to,
  }) async {
    try {
      final response = await _dio.get<List<dynamic>>(
        '/api/positions',
        queryParameters: {
          'deviceId': deviceId,
          'from': from.toUtc().toIso8601String(),
          'to': to.toUtc().toIso8601String(),
        },
      );
      final data = response.data ?? const <dynamic>[];
      final sw = Stopwatch()..start();
      final positions = data
          .whereType<Map<String, dynamic>>()
          .map(model.Position.fromJson)
          .toList(growable: false);
      sw.stop();
      if (kDebugMode) {
        // Use cluster compute metric to capture mapping/polyline prep time
        DevDiagnostics.instance.recordClusterCompute(sw.elapsedMilliseconds);
      }
      return positions;
    } on DioException catch (e) {
      if (kDebugMode) {
        debugPrint('[TripRepository] ❌ DioException (positions): ${e.message}');
      }
      rethrow;
    } catch (e, st) {
      if (kDebugMode) {
        debugPrint('[TripRepository] ❌ Error (positions): $e');
        debugPrint(st.toString());
      }
      rethrow;
    }
  }

  /// Aggregated analytics by day over a period, sourced from local cache (DAO).
  Future<Map<String, TripAggregate>> fetchAggregates({
    required DateTime from,
    required DateTime to,
  }) async {
    final sw = Stopwatch()..start();
    try {
      final dao = await _ref.read(tripsDaoProvider.future);
      final result = await dao.getAggregatesByDay(from, to);
      return result;
    } catch (e) {
      if (kDebugMode) {
        debugPrint('[TripRepository] ⚠️ fetchAggregates error: $e');
      }
      return <String, TripAggregate>{};
    } finally {
      sw.stop();
      if (kDebugMode) {
        DevDiagnostics.instance.recordFilterCompute(sw.elapsedMilliseconds);
      }
    }
  }

  Future<void> _persistMonthlySnapshot({
    required DateTime cutoff,
    required TripsDaoBase tripsDao,
    required TripSnapshotsDaoBase snapshotsDao,
  }) async {
    // Compute the month range for the cutoff's month: [first day 00:00, last day 23:59:59]
    final monthStart = DateTime(cutoff.year, cutoff.month).toUtc();
    // To get month end, advance to next month and subtract 1 day
    final nextMonth = (cutoff.month == 12)
        ? DateTime(cutoff.year + 1).toUtc()
        : DateTime(cutoff.year, cutoff.month + 1).toUtc();
    final monthEnd = nextMonth.subtract(const Duration(seconds: 1));

    final monthKey = _fmtYearMonth(cutoff);

    final sw = Stopwatch()..start();
    try {
      final daily = await tripsDao.getAggregatesByDay(monthStart, monthEnd);
      if (daily.isEmpty) return;
      final totals = TripAggregate(
        totalDistanceKm: daily.values.fold(0.0, (double a, b) => a + b.totalDistanceKm),
        totalDurationHrs:
            daily.values.fold(0.0, (double a, b) => a + b.totalDurationHrs),
        avgSpeedKph: daily.values.isEmpty
            ? 0.0
            : daily.values.fold(0.0, (double a, b) => a + b.avgSpeedKph) /
                daily.length,
        tripCount: daily.values.fold(0, (int a, b) => a + b.tripCount),
      );
      await snapshotsDao
          .putSnapshot(TripSnapshot.fromAggregate(monthKey, totals));
      // Optionally prune very old snapshots (keep last 24 months)
      const keepBackMonths = 24;
      final olderCutoff = _fmtYearMonth(DateTime.now()
          .toUtc()
          .subtract(const Duration(days: keepBackMonths * 30)),);
      await snapshotsDao.deleteOlderThan(olderCutoff);
      if (kDebugMode) {
        debugPrint(
            '[TripSnapshots] ✅ Saved monthly snapshot for $monthKey: ${totals.tripCount} trips, ${totals.totalDistanceKm.toStringAsFixed(1)} km',);
      }
    } catch (e) {
      if (kDebugMode) {
        debugPrint('[TripSnapshots] ⚠️ Snapshot persist failed: $e');
      }
    } finally {
      sw.stop();
      if (kDebugMode) {
        DevDiagnostics.instance.recordFilterCompute(sw.elapsedMilliseconds);
      }
    }
  }

  String _fmtYearMonth(DateTime d) {
    final y = d.year.toString().padLeft(4, '0');
    final m = d.month.toString().padLeft(2, '0');
    return '$y-$m';
  }
}

/// Provider for TripRepository (singleton per container)
final tripRepositoryProvider = Provider<TripRepository>((ref) {
  final dio = ref.watch(dioProvider);
  return TripRepository(dio: dio, ref: ref);
});
