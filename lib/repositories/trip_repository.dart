import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:my_app_gps/core/diagnostics/dev_diagnostics.dart';
import 'package:my_app_gps/data/models/position.dart' as model;
import 'package:my_app_gps/data/models/trip.dart';
import 'package:my_app_gps/core/database/dao/trips_dao.dart';
import 'package:my_app_gps/core/database/entities/trip_entity.dart';
import 'package:my_app_gps/data/models/trip_aggregate.dart';
import 'package:my_app_gps/core/database/dao/trip_snapshots_dao.dart';
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

  // Simple in-memory cache keyed by device+range to avoid repeat parsing in-session
  final Map<String, List<Trip>> _cache = <String, List<Trip>>{};

  Future<List<Trip>> fetchTrips({
    required int deviceId,
    required DateTime from,
    required DateTime to,
  }) async {
    final key = _cacheKey(deviceId, from, to);
    if (_cache.containsKey(key)) {
      return _cache[key]!;
    }

    try {
      final sw = Stopwatch()..start();
      // Try official POST body first (deviceId as single), then fallbacks
      List<dynamic> raw;
      try {
        final r = await _doTripsPost(
          deviceId: deviceId,
          from: from,
          to: to,
          useListBody: false,
          trailingSlash: false,
        );
        raw = r.data ?? const <dynamic>[];
      } on DioException catch (e) {
        if (e.response?.statusCode == 405) {
          // Try deviceIds array body
          try {
            final r = await _doTripsPost(
              deviceId: deviceId,
              from: from,
              to: to,
              useListBody: true,
              trailingSlash: false,
            );
            raw = r.data ?? const <dynamic>[];
          } on DioException catch (e2) {
            if (e2.response?.statusCode == 405) {
              // Try trailing-slash variants (some servers route only with /)
              try {
                final r = await _doTripsPost(
                  deviceId: deviceId,
                  from: from,
                  to: to,
                  useListBody: false,
                  trailingSlash: true,
                );
                raw = r.data ?? const <dynamic>[];
              } on DioException catch (e3) {
                if (e3.response?.statusCode == 405) {
                  try {
                    if (kDebugMode) {
                      debugPrint('[TripRepository] ⚠️ POST not supported; retrying with GET query');
                    }
                    final r = await _doTripsPost(
                      deviceId: deviceId,
                      from: from,
                      to: to,
                      useListBody: true,
                      trailingSlash: true,
                    );
                    raw = r.data ?? const <dynamic>[];
                  } on DioException catch (e4) {
                    if (e4.response?.statusCode == 405) {
                      // Final fallback: attempt GET (some non-standard configs)
                      final r = await _doTripsGet(deviceId: deviceId, from: from, to: to);
                      raw = r;
                    } else {
                      rethrow;
                    }
                  }
                } else {
                  rethrow;
                }
              }
            } else {
              rethrow;
            }
          }
        } else if (_isTransient(e.response?.statusCode)) {
          // Retry once after a short backoff
          await Future<void>.delayed(const Duration(milliseconds: 300));
          final r = await _doTripsPost(
            deviceId: deviceId,
            from: from,
            to: to,
            useListBody: false,
            trailingSlash: false,
          );
          raw = r.data ?? const <dynamic>[];
        } else {
          rethrow;
        }
      }

      final trips = raw
          .whereType<Map<String, dynamic>>()
          .map(Trip.fromJson)
          .toList(growable: false);
      sw.stop();

      // Record parsing/processing time into diagnostics for visibility
      if (kDebugMode) {
        DevDiagnostics.instance.recordFilterCompute(sw.elapsedMilliseconds);
        debugPrint('[TripRepository] ✅ Fetched ${trips.length} trips for device=$deviceId');
      }

      _cache[key] = trips;
      // Persist to ObjectBox for offline/retention support (best-effort)
      unawaited(_persistTripsAndCleanup(trips));
      return trips;
    } on DioException catch (e) {
      if (kDebugMode) {
        final code = e.response?.statusCode;
        final body = e.response?.data;
        debugPrint('[TripRepository] ❌ DioException (trips): code=$code type=${e.type.name} err=${e.message} body=${_safeBody(body)}');
      }
      // Network failed; try local cache as a fallback
      try {
        final dao = await _ref.read(tripsDaoProvider.future);
        final cached = await dao.getByDeviceInRange(deviceId, from, to);
        if (cached.isNotEmpty) {
          final trips = cached
              .map((e) => Trip.fromJson(e.toDomain()))
              .toList(growable: false);
          _cache[key] = trips;
          return trips;
        }
      } catch (_) {}
      // graceful fallback
      return <Trip>[];
    } catch (e, st) {
      if (kDebugMode) {
        debugPrint('[TripRepository] ❌ Error: $e');
        debugPrint(st.toString());
      }
      return <Trip>[];
    }
  }

  /// Safe cached trips lookup from DAO; returns empty list on error.
  Future<List<Trip>> getCachedTrips(int deviceId, DateTime from, DateTime to) async {
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
      await _persistMonthlySnapshot(cutoff: cutoff, tripsDao: tripsDao, snapshotsDao: snapshotsDao);

      // Proceed with deletion
      final old = await tripsDao.getOlderThan(cutoff);
      if (old.isNotEmpty && kDebugMode) {
        final totalKm = old.fold<double>(0.0, (s, t) => s + t.distanceKm);
        debugPrint('[TripRepository] 🧹 Retention: deleting ${old.length} trips (< ${cutoff.toIso8601String()}) totaling ${totalKm.toStringAsFixed(1)} km');
      }
      await tripsDao.deleteOlderThan(cutoff);
    } catch (e) {
      // Best-effort cleanup; ignore DAO issues
      if (kDebugMode) {
        debugPrint('[TripRepository] ⚠️ cleanupOldTrips error: $e');
      }
    }
  }

  Future<void> _persistTripsAndCleanup(List<Trip> trips) async {
    try {
      final dao = await _ref.read(tripsDaoProvider.future);
      if (trips.isNotEmpty) {
        final entities = trips
            .map(
              (t) => TripEntity.fromDomain(
                tripId: t.id,
                deviceId: t.deviceId,
                startTime: t.startTime,
                endTime: t.endTime,
                distanceKm: t.distanceKm,
                averageSpeed: t.avgSpeedKph,
                maxSpeed: t.maxSpeedKph,
                attributes: {
                  'startLat': t.start.latitude,
                  'startLon': t.start.longitude,
                  'endLat': t.end.latitude,
                  'endLon': t.end.longitude,
                },
              ),
            )
            .toList(growable: false);
        await dao.upsertMany(entities);
      }
      await cleanupOldTrips();
    } catch (e) {
      if (kDebugMode) {
        debugPrint('[TripRepository] ⚠️ persist/cleanup error: $e');
      }
    }
  }

  String _safeBody(dynamic body) {
    try {
      if (body == null) return 'null';
      final s = body.toString();
      // Truncate to avoid noisy logs
      return s.length > 300 ? '${s.substring(0, 300)}…' : s;
    } catch (_) {
      return '<unprintable>';
    }
  }

  // Helper to execute the POST request with alternate body shapes
  Future<Response<List<dynamic>>> _doTripsPost({
    required int deviceId,
    required DateTime from,
    required DateTime to,
    required bool useListBody,
    required bool trailingSlash,
  }) async {
    final body = useListBody
        ? {
            'deviceIds': [deviceId],
            'from': from.toUtc().toIso8601String(),
            'to': to.toUtc().toIso8601String(),
          }
        : {
            'deviceId': deviceId,
            'from': from.toUtc().toIso8601String(),
            'to': to.toUtc().toIso8601String(),
          };
    final path = trailingSlash ? '/api/reports/trips/' : '/api/reports/trips';
    return _dio.post<List<dynamic>>(
      path,
      data: body,
      options: Options(
        responseType: ResponseType.json,
        headers: const {'Accept': 'application/json'},
        contentType: 'application/json',
      ),
    );
  }

  // Retry wrapper (explicit helper, referenced in docs/spec)
  bool _isTransient(int? code) {
    return code == 500 || code == 502 || code == 503 || code == 504;
  }

  // Non-standard GET fallback (best-effort)
  Future<List<dynamic>> _doTripsGet({
    required int deviceId,
    required DateTime from,
    required DateTime to,
  }) async {
    final r = await _dio.get<List<dynamic>>(
      '/api/reports/trips',
      queryParameters: {
        'deviceId': deviceId,
        'from': from.toUtc().toIso8601String(),
        'to': to.toUtc().toIso8601String(),
      },
      options: Options(
        responseType: ResponseType.json,
        headers: const {'Accept': 'application/json'},
      ),
    );
    return r.data ?? const <dynamic>[];
  }

  String _cacheKey(int deviceId, DateTime from, DateTime to) =>
      '$deviceId:${from.toUtc().millisecondsSinceEpoch}-${to.toUtc().millisecondsSinceEpoch}';

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
    final monthStart = DateTime(cutoff.year, cutoff.month, 1).toUtc();
    // To get month end, advance to next month and subtract 1 day
    final nextMonth = (cutoff.month == 12)
        ? DateTime(cutoff.year + 1, 1, 1).toUtc()
        : DateTime(cutoff.year, cutoff.month + 1, 1).toUtc();
    final monthEnd = nextMonth.subtract(const Duration(seconds: 1));

    final monthKey = _fmtYearMonth(cutoff);

    final sw = Stopwatch()..start();
    try {
      final daily = await tripsDao.getAggregatesByDay(monthStart, monthEnd);
      if (daily.isEmpty) return;
      final totals = TripAggregate(
        totalDistanceKm: daily.values.fold(0.0, (a, b) => a + b.totalDistanceKm),
        totalDurationHrs: daily.values.fold(0.0, (a, b) => a + b.totalDurationHrs),
        avgSpeedKph: daily.values.isEmpty
            ? 0.0
            : daily.values.fold(0.0, (a, b) => a + b.avgSpeedKph) / daily.length,
        tripCount: daily.values.fold(0, (a, b) => a + b.tripCount),
      );
      await snapshotsDao.putSnapshot(TripSnapshot.fromAggregate(monthKey, totals));
      // Optionally prune very old snapshots (keep last 24 months)
      final keepBackMonths = 24;
      final olderCutoff = _fmtYearMonth(DateTime.now().toUtc().subtract(Duration(days: keepBackMonths * 30)));
      await snapshotsDao.deleteOlderThan(olderCutoff);
      if (kDebugMode) {
        debugPrint('[TripSnapshots] ✅ Saved monthly snapshot for $monthKey: ${totals.tripCount} trips, ${totals.totalDistanceKm.toStringAsFixed(1)} km');
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
