import 'dart:async';
import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:my_app_gps/core/database/dao/trip_snapshots_dao.dart';
import 'package:my_app_gps/core/database/dao/trips_dao.dart';
import 'package:my_app_gps/core/diagnostics/dev_diagnostics.dart';
import 'dart:io' show Cookie;
import 'package:cookie_jar/cookie_jar.dart';
import 'package:my_app_gps/data/models/position.dart' as model;
import 'package:my_app_gps/data/models/trip.dart';
import 'package:my_app_gps/data/models/trip_aggregate.dart';
import 'package:my_app_gps/data/models/trip_snapshot.dart';
import 'package:my_app_gps/services/auth_service.dart';

/// Top-level function for isolate-based trip parsing with JSON decoding
/// This function must be top-level (not a method) to work with compute()
/// 
/// Accepts either:
/// - String: Raw JSON that needs decoding + parsing
/// - List<dynamic>: Already decoded JSON that needs parsing
List<Trip> _parseTripsIsolate(dynamic jsonData) {
  List<dynamic> jsonList;
  
  // Step 1: Decode JSON if needed (offloading json.decode from main thread)
  if (jsonData is String) {
    try {
      final decoded = jsonDecode(jsonData);
      if (decoded is List) {
        jsonList = decoded;
      } else {
        return []; // Not a list, return empty
      }
    } catch (_) {
      return []; // JSON decode failed, return empty
    }
  } else if (jsonData is List) {
    jsonList = jsonData;
  } else {
    return []; // Unexpected type, return empty
  }
  
  // Step 2: Parse Trip objects from JSON list
  final trips = <Trip>[];
  for (final item in jsonList) {
    if (item is Map<String, dynamic>) {
      try {
        trips.add(Trip.fromJson(item));
      } catch (_) {
        // Skip malformed items silently in isolate
      }
    }
  }
  return trips;
}

/// Cached response for trip requests
class _CachedTripResponse {
  _CachedTripResponse({
    required this.trips,
    required this.timestamp,
  });

  final List<Trip> trips;
  final DateTime timestamp;

  bool isExpired(Duration ttl) {
    return DateTime.now().difference(timestamp) > ttl;
  }
}

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

  // In-memory cache for network responses
  final Map<String, _CachedTripResponse> _cache = {};
  
  // Track ongoing requests to prevent duplicates
  final Map<String, Future<List<Trip>>> _ongoingRequests = {};
  
  // Cache TTL: 2 minutes
  static const Duration _cacheTTL = Duration(minutes: 2);

  Future<List<Trip>> fetchTrips({
    required int deviceId,
    required DateTime from,
    required DateTime to,
    CancelToken? cancelToken,
  }) async {
    final cacheKey = _buildCacheKey(deviceId, from, to);
    final sw = Stopwatch()..start();

    // 1. Check cache first
    final cached = _cache[cacheKey];
    if (cached != null && !cached.isExpired(_cacheTTL)) {
      final age = DateTime.now().difference(cached.timestamp).inSeconds;
      debugPrint('[TripRepository][CACHE HIT] 🎯 Returning ${cached.trips.length} trips (age: ${age}s, TTL: ${_cacheTTL.inSeconds}s)');
      return cached.trips;
    }

    // 2. Check for ongoing request (throttling)
    final ongoing = _ongoingRequests[cacheKey];
    if (ongoing != null) {
      debugPrint('[TripRepository][THROTTLED] ⏸️ Skipping duplicate fetch for $cacheKey');
      return ongoing;
    }

    // 3. Create new request with retry logic
    final requestFuture = _fetchTripsWithRetry(
      deviceId: deviceId,
      from: from,
      to: to,
      cancelToken: cancelToken,
      attempts: 3,
    ).then((trips) {
      sw.stop();
      debugPrint('[TripRepository][TIMING] ⏱️ Fetch completed in ${sw.elapsedMilliseconds}ms');
      
      // Cache the result
      _cache[cacheKey] = _CachedTripResponse(
        trips: trips,
        timestamp: DateTime.now(),
      );
      debugPrint('[TripRepository][CACHE STORE] 💾 Stored ${trips.length} trips (key: $cacheKey)');
      
      return trips;
    }).catchError((Object error, StackTrace stackTrace) {
      debugPrint('[TripRepository][FALLBACK] ⚠️ Network error, checking cache: $error');
      
      // Graceful fallback: return stale cache if available
      final stale = _cache[cacheKey];
      if (stale != null) {
        final age = DateTime.now().difference(stale.timestamp).inSeconds;
        debugPrint('[TripRepository][FALLBACK] 🔄 Returning stale cache (${stale.trips.length} trips, age: ${age}s)');
        return stale.trips;
      }
      
      debugPrint('[TripRepository][FALLBACK] ❌ No cache available, returning empty');
      return <Trip>[];
    }).whenComplete(() {
      // Remove from ongoing requests
      _ongoingRequests.remove(cacheKey);
    });

    // Track ongoing request
    _ongoingRequests[cacheKey] = requestFuture;
    return requestFuture;
  }

  /// Build cache key from request parameters
  String _buildCacheKey(int deviceId, DateTime from, DateTime to) {
    return '$deviceId|${_toUtcIso(from)}|${_toUtcIso(to)}';
  }

  /// Fetch trips with exponential backoff retry
  Future<List<Trip>> _fetchTripsWithRetry({
    required int deviceId,
    required DateTime from,
    required DateTime to,
    CancelToken? cancelToken,
    required int attempts,
  }) async {
    var attempt = 0;
    var delay = const Duration(seconds: 1);

    while (attempt < attempts) {
      attempt++;
      
      try {
        debugPrint('[TripRepository][ATTEMPT] 🔄 Attempt $attempt/$attempts');
        return await _fetchTripsNetwork(
          deviceId: deviceId,
          from: from,
          to: to,
          cancelToken: cancelToken,
        );
      } catch (e) {
        if (attempt >= attempts) {
          debugPrint('[TripRepository][RETRY EXHAUSTED] ❌ All $attempts attempts failed');
          rethrow;
        }
        
        debugPrint('[TripRepository][RETRY] ⏳ Attempt $attempt failed, retrying in ${delay.inSeconds}s: $e');
        await Future<void>.delayed(delay);
        delay *= 2; // Exponential backoff: 1s, 2s, 4s
      }
    }

    return <Trip>[];
  }

  /// Core network fetch logic
  Future<List<Trip>> _fetchTripsNetwork({
    required int deviceId,
    required DateTime from,
    required DateTime to,
    CancelToken? cancelToken,
  }) async {
    // Ensure cookie is present in jar (silent restore)
    try {
      await _ref.read(authServiceProvider).rehydrateSessionCookie();
    } catch (_) {}

    final dio = _ref.read(dioProvider);
    final url = '/api/reports/trips';
    // Normalize all query parameters to strings to prevent Uri/encoder issues
    final params = <String, String>{
      'deviceId': deviceId.toString(),
      'from': _toUtcIso(from),
      'to': _toUtcIso(to),
    };

    try {
      // Log resolved URL and cookie presence
    final base = dio.options.baseUrl;
    final resolved = Uri.parse(base)
      .resolve(Uri(path: url, queryParameters: params).toString());
    debugPrint('[TripRepository] 🔍 fetchTrips GET deviceId=${params['deviceId']} from=${params['from']} to=${params['to']}');
    debugPrint('[TripRepository] 🔧 Query=${params.toString()}');
      debugPrint('[TripRepository] 🌐 BaseURL=$base');
      // Peek cookie jar for Cookie header presence
      try {
        final jar = _ref.read(authCookieJarProvider);
        final cookieUri = Uri(scheme: resolved.scheme, host: resolved.host, port: resolved.hasPort ? resolved.port : null, path: '/');
  final List<Cookie> cookies = await jar.loadForRequest(cookieUri);
  final js = cookies.firstWhere((Cookie c) => c.name.toUpperCase() == 'JSESSIONID', orElse: () => Cookie('NONE', ''));
        final hasJs = js.name.toUpperCase() == 'JSESSIONID';
        final preview = hasJs ? (js.value.isNotEmpty ? '${js.value.substring(0, (js.value.length).clamp(0, 8))}…' : '<empty>') : '<none>';
        debugPrint('[TripRepository] 🍪 Cookie JSESSIONID: ${hasJs ? 'present' : 'missing'} (${preview})');
      } catch (_) {}

      debugPrint('[TripRepository] ⇢ URL=${resolved.toString()}');
      final response = await dio.get<dynamic>(
        url,
        queryParameters: params,
        cancelToken: cancelToken,
        options: Options(
          responseType: ResponseType.json,
          headers: const {'Accept': 'application/json'},
          // Let us handle 4xx gracefully without throwing in Dio
          validateStatus: (code) => code != null && code < 500,
        ),
      );

      debugPrint('[TripRepository] ⇢ Status=${response.statusCode}, Type=${response.data.runtimeType}');

      if (response.statusCode == 200) {
        final contentType = response.headers.value('content-type') ?? '';
        var data = response.data;
        
        // If server returned text, parse it in background if it looks like JSON
        if (data is String) {
          final t = data.trimLeft();
          if (t.startsWith('[') || t.startsWith('{')) {
            // Offload JSON decoding + parsing to isolate
            final trips = await _parseTripsInBackground(data);
            if (trips.isEmpty && kDebugMode) {
              debugPrint('[TripRepository] ⚠️ Text payload not JSON-decodable or empty');
            } else {
              debugPrint('[TripRepository] ✅ Parsed ${trips.length} trips from JSON string');
            }
            return trips;
          } else {
            if (kDebugMode) {
              debugPrint('[TripRepository] ⚠️ Text payload (likely HTML), returning empty');
            }
            return const <Trip>[];
          }
        }
        
        // Data already decoded (Dio handled it)
        if (data is List) {
          final trips = await _parseTripsInBackground(data);
          debugPrint('[TripRepository] ✅ Parsed ${trips.length} trips');
          return trips;
        } else {
          // Defensive: non-list response
          if (kDebugMode) {
            final hint = contentType.contains('html') ? ' (content-type suggests HTML)' : '';
            debugPrint('[TripRepository] ⚠️ 200 but non-list payload: type=${data.runtimeType}$hint');
          }
          return const <Trip>[];
        }
      }

      // Non-200 or invalid type → optional fallback to legacy /generate POST
      debugPrint('[TripRepository] ⚠️ Unexpected response: status=${response.statusCode}, type=${response.data.runtimeType}');
      if (_useGenerateFallback) {
        return await _fetchTripsGenerateFallback(
          dio: dio,
          deviceId: deviceId,
          from: from,
          to: to,
          cancelToken: cancelToken,
        );
      }
      return <Trip>[];
    } on DioException catch (e, st) {
      debugPrint('[TripRepository] ❌ DioException (trips): $e');
      debugPrint(st.toString());
      if (_useGenerateFallback) {
        try {
          return await _fetchTripsGenerateFallback(
            dio: dio,
            deviceId: deviceId,
            from: from,
            to: to,
            cancelToken: cancelToken,
          );
        } catch (_) {}
      }
      rethrow;
    } catch (e, st) {
      debugPrint('[TripRepository] ❌ Unexpected error: $e');
      debugPrint(st.toString());
      rethrow;
    }
  }

  /// Parse trips in background isolate for heavy computation
  /// 
  /// Accepts either:
  /// - String: Raw JSON response (will decode + parse in isolate)
  /// - List<dynamic>: Already decoded JSON (will parse in isolate)
  /// 
  /// Uses compute() to avoid blocking the UI thread for:
  /// - JSON decoding (when String input)
  /// - Trip.fromJson() parsing (always)
  Future<List<Trip>> _parseTripsInBackground(dynamic data) async {
    // Determine if we should use isolate based on data size
    final shouldUseIsolate = data is String 
        ? data.length > 500  // Use isolate for large JSON strings
        : (data is List && data.length > 10); // Use isolate for large lists
    
    if (!shouldUseIsolate) {
      // Small data: parse synchronously (isolate overhead not worth it)
      return _parseTripsIsolate(data);
    }
    
    // Large data: offload to isolate
    final itemCount = data is String ? 'unknown' : (data as List).length;
    debugPrint('[TripRepository] 🔄 Parsing $itemCount trips in background isolate (with JSON decoding: ${data is String})');
    final stopwatch = Stopwatch()..start();
    
    final trips = await compute(_parseTripsIsolate, data);
    
    stopwatch.stop();
    debugPrint('[TripRepository] ✅ Background parsing completed in ${stopwatch.elapsedMilliseconds}ms');
    
    return trips;
  }

  // Feature flag to toggle legacy /generate fallback for older Traccar servers
  static const bool _useGenerateFallback = bool.fromEnvironment(
    'USE_TRIPS_GENERATE',
    defaultValue: true,
  );

  Future<List<Trip>> _fetchTripsGenerateFallback({
    required Dio dio,
    required int deviceId,
    required DateTime from,
    required DateTime to,
    CancelToken? cancelToken,
  }) async {
    final path = '/api/reports/trips/generate';
    final body = {
      'deviceIds': [deviceId],
      'from': _toUtcIso(from),
      'to': _toUtcIso(to),
    };
    debugPrint('[TripRepository] 🧪 Fallback POST $path body=$body');
    final r = await dio.post<dynamic>(
      path,
      data: body,
      cancelToken: cancelToken,
      options: Options(
        headers: const {'Accept': 'application/json'},
        contentType: 'application/json',
        responseType: ResponseType.json,
        validateStatus: (code) => code != null && code < 500,
      ),
    );
    debugPrint('[TripRepository] 🧪 Fallback status=${r.statusCode} type=${r.data.runtimeType}');
    if (r.statusCode == 200) {
      final contentType = r.headers.value('content-type') ?? '';
      final data = r.data;
      if (data is List) {
        final trips = <Trip>[];
        for (final item in data) {
          if (item is Map<String, dynamic>) {
            try {
              trips.add(Trip.fromJson(item));
            } catch (_) {
              if (kDebugMode) {
                debugPrint('[TripRepository] ⚠️ Skipped malformed trip item (fallback)');
              }
            }
          }
        }
        debugPrint('[TripRepository] ✅ Fallback parsed ${trips.length} trips');
        return trips;
      } else {
        if (kDebugMode) {
          final hint = contentType.contains('html') ? ' (content-type suggests HTML)' : '';
          debugPrint('[TripRepository] ⚠️ Fallback 200 but non-list payload: type=${data.runtimeType}$hint');
        }
        return const <Trip>[];
      }
    }
    debugPrint('[TripRepository] ⚠️ Fallback failed or non-JSON, returning empty');
    return const <Trip>[];
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
  /// Remove expired entries from memory cache
  void cleanupExpiredCache() {
    final before = _cache.length;
    _cache.removeWhere((key, cached) => cached.isExpired(_cacheTTL));
    final after = _cache.length;
    if (before != after) {
      debugPrint('[TripRepository][CACHE CLEANUP] 🧹 Removed ${before - after} expired entries (${after} remain)');
    }
  }

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

  // Format to second precision (no fractional seconds) per Traccar expectations
  String _toUtcIso(DateTime d) {
    final dt = d.toUtc();
    String pad2(int n) => n.toString().padLeft(2, '0');
    final y = dt.year.toString().padLeft(4, '0');
    final m = pad2(dt.month);
    final day = pad2(dt.day);
    final h = pad2(dt.hour);
    final min = pad2(dt.minute);
    final s = pad2(dt.second);
    return '$y-$m-$day' 'T' '$h:$min:$s' 'Z';
  }

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
