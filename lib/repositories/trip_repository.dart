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
      // Traccar reports API expects POST with JSON body
      final response = await _dio.post<List<dynamic>>(
        '/api/reports/trips',
        data: {
          'deviceIds': [deviceId],
          'from': from.toUtc().toIso8601String(),
          'to': to.toUtc().toIso8601String(),
        },
        options: Options(headers: const {'Accept': 'application/json'}),
      );
      final data = response.data ?? const <dynamic>[];
      final trips = data
          .whereType<Map<String, dynamic>>()
          .map(Trip.fromJson)
          .toList(growable: false);
      sw.stop();

      // Record parsing/processing time into diagnostics for visibility
      if (kDebugMode) {
        DevDiagnostics.instance.recordFilterCompute(sw.elapsedMilliseconds);
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
      rethrow;
    } catch (e, st) {
      if (kDebugMode) {
        debugPrint('[TripRepository] ❌ Error: $e');
        debugPrint(st.toString());
      }
      rethrow;
    }
  }

  /// Placeholder for retention policy: delete trips older than 30 days from local cache.
  Future<void> cleanupOldTrips() async {
    try {
      final dao = await _ref.read(tripsDaoProvider.future);
      final cutoff = DateTime.now().toUtc().subtract(const Duration(days: 30));
      // Snapshot basic analytics before deletion
      final old = await dao.getOlderThan(cutoff);
      if (old.isNotEmpty && kDebugMode) {
        final totalKm = old.fold<double>(0.0, (s, t) => s + t.distanceKm);
        debugPrint('[TripRepository] 🧹 Retention: deleting ${old.length} trips (< ${cutoff.toIso8601String()}) totaling ${totalKm.toStringAsFixed(1)} km');
      }
      await dao.deleteOlderThan(cutoff);
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
}

/// Provider for TripRepository (singleton per container)
final tripRepositoryProvider = Provider<TripRepository>((ref) {
  final dio = ref.watch(dioProvider);
  return TripRepository(dio: dio, ref: ref);
});
