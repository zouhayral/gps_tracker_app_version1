import 'dart:async';
import 'dart:convert';
import 'dart:io' show Cookie;

import 'package:cookie_jar/cookie_jar.dart';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:my_app_gps/core/utils/app_logger.dart';
import 'package:my_app_gps/data/models/position.dart' as model;
import 'package:my_app_gps/data/models/trip.dart';

/// Top-level function for isolate-based trip parsing with JSON decoding
/// This function must be top-level (not a method) to work with compute()
List<Trip> _parseTripsIsolate(dynamic jsonData) {
  List<dynamic> jsonList;
  
  if (jsonData is String) {
    try {
      final decoded = jsonDecode(jsonData);
      if (decoded is List) {
        jsonList = decoded;
      } else {
        return [];
      }
    } catch (_) {
      return [];
    }
  } else if (jsonData is List) {
    jsonList = jsonData;
  } else {
    return [];
  }
  
  final trips = <Trip>[];
  for (final item in jsonList) {
    if (item is Map<String, dynamic>) {
      try {
        trips.add(Trip.fromJson(item));
      } catch (_) {
        // Skip malformed items silently
      }
    }
  }
  return trips;
}

/// Handles all network operations for trip data fetching.
/// 
/// Responsibilities:
/// - Execute HTTP requests with Dio
/// - Retry logic with exponential backoff
/// - Cookie session management
/// - Background isolate parsing
/// - Fallback endpoint handling
/// - Position fetching
class TripNetworkService {
  static final _log = 'TripNetworkService'.logger;

  TripNetworkService({
    required Dio dio,
    required this.cookieJar,
    required this.rehydrateCookie,
  }) : _dio = dio;

  final Dio _dio;
  final CookieJar cookieJar;
  final Future<void> Function() rehydrateCookie;

  // Feature flag for legacy /generate fallback
  static const bool _useGenerateFallback = bool.fromEnvironment(
    'USE_TRIPS_GENERATE',
    defaultValue: true,
  );

  /// Fetch trips with exponential backoff retry
  Future<List<Trip>> fetchTripsWithRetry({
    required int deviceId,
    required DateTime from,
    required DateTime to,
    required int attempts,
    CancelToken? cancelToken,
  }) async {
    var attempt = 0;
    var delay = const Duration(seconds: 1);

    while (attempt < attempts) {
      attempt++;
      
      try {
        _log.debug('🔄 Attempt $attempt/$attempts');
        return await fetchTrips(
          deviceId: deviceId,
          from: from,
          to: to,
          cancelToken: cancelToken,
        );
      } catch (e) {
        if (attempt >= attempts) {
          _log.warning('❌ All $attempts attempts failed');
          rethrow;
        }
        
        _log.debug('⏳ Attempt $attempt failed, retrying in ${delay.inSeconds}s: $e');
        await Future<void>.delayed(delay);
        delay *= 2; // Exponential backoff
      }
    }

    return <Trip>[];
  }

  /// Core network fetch logic
  Future<List<Trip>> fetchTrips({
    required int deviceId,
    required DateTime from,
    required DateTime to,
    CancelToken? cancelToken,
  }) async {
    // Ensure cookie is present
    try {
      await rehydrateCookie();
    } catch (e) {
      _log.warning('Failed to rehydrate session cookie', error: e);
    }

    const url = '/api/reports/trips';
    final params = <String, String>{
      'deviceId': deviceId.toString(),
      'from': _toUtcIso(from),
      'to': _toUtcIso(to),
    };

    try {
      final base = _dio.options.baseUrl;
      final resolved = Uri.parse(base)
          .resolve(Uri(path: url, queryParameters: params).toString());
      _log.debug('🔍 fetchTrips GET deviceId=${params['deviceId']} from=${params['from']} to=${params['to']}');
      _log.debug('🔧 Query=$params');
      _log.debug('🌐 BaseURL=$base');
      
      // Log cookie presence
      try {
        final cookieUri = Uri(
          scheme: resolved.scheme,
          host: resolved.host,
          port: resolved.hasPort ? resolved.port : null,
          path: '/',
        );
        final cookies = await cookieJar.loadForRequest(cookieUri);
        final js = cookies.firstWhere(
          (Cookie c) => c.name.toUpperCase() == 'JSESSIONID',
          orElse: () => Cookie('NONE', ''),
        );
        final hasJs = js.name.toUpperCase() == 'JSESSIONID';
        final preview = hasJs
            ? (js.value.isNotEmpty ? '${js.value.substring(0, js.value.length.clamp(0, 8))}…' : '<empty>')
            : '<none>';
        _log.debug('🍪 Cookie JSESSIONID: ${hasJs ? 'present' : 'missing'} ($preview)');
      } catch (e) {
        _log.warning('Failed to peek cookie jar', error: e);
      }

      _log.debug('⇢ URL=$resolved');
      final response = await _dio.get<dynamic>(
        url,
        queryParameters: params,
        cancelToken: cancelToken,
        options: Options(
          responseType: ResponseType.json,
          headers: const {'Accept': 'application/json'},
          validateStatus: (code) => code != null && code < 500,
        ),
      );

      _log.debug('⇢ Status=${response.statusCode}, Type=${response.data.runtimeType}');

      if (response.statusCode == 200) {
        final contentType = response.headers.value('content-type') ?? '';
        final data = response.data;
        
        if (data is String) {
          final t = data.trimLeft();
          if (t.startsWith('[') || t.startsWith('{')) {
            final trips = await _parseTripsInBackground(data);
            if (trips.isEmpty) {
              _log.debug('Text payload not JSON-decodable or empty');
            } else {
              _log.debug('✅ Parsed ${trips.length} trips from JSON string');
            }
            return trips;
          } else {
            _log.debug('Text payload (likely HTML), returning empty');
            return const <Trip>[];
          }
        }
        
        if (data is List) {
          final trips = await _parseTripsInBackground(data);
          _log.debug('✅ Parsed ${trips.length} trips');
          return trips;
        } else {
          final hint = contentType.contains('html') ? ' (content-type suggests HTML)' : '';
          _log.debug('200 but non-list payload: type=${data.runtimeType}$hint');
          return const <Trip>[];
        }
      }

      _log.debug('Unexpected response: status=${response.statusCode}, type=${response.data.runtimeType}');
      if (_useGenerateFallback) {
        return await _fetchTripsGenerateFallback(
          deviceId: deviceId,
          from: from,
          to: to,
          cancelToken: cancelToken,
        );
      }
      return <Trip>[];
    } on DioException catch (e, st) {
      _log.error('DioException (trips)', error: e, stackTrace: st);
      if (_useGenerateFallback) {
        try {
          return await _fetchTripsGenerateFallback(
            deviceId: deviceId,
            from: from,
            to: to,
            cancelToken: cancelToken,
          );
        } catch (e) {
          _log.warning('Fallback failed', error: e);
        }
      }
      rethrow;
    } catch (e, st) {
      _log.error('Unexpected error', error: e, stackTrace: st);
      rethrow;
    }
  }

  /// Fallback to legacy POST /generate endpoint
  Future<List<Trip>> _fetchTripsGenerateFallback({
    required int deviceId,
    required DateTime from,
    required DateTime to,
    CancelToken? cancelToken,
  }) async {
    const path = '/api/reports/trips/generate';
    final body = {
      'deviceIds': [deviceId],
      'from': _toUtcIso(from),
      'to': _toUtcIso(to),
    };
    _log.debug('🧪 Fallback POST $path body=$body');
    
    final r = await _dio.post<dynamic>(
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
    
    _log.debug('🧪 Fallback status=${r.statusCode} type=${r.data.runtimeType}');
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
              _log.debug('Skipped malformed trip item (fallback)');
            }
          }
        }
        _log.debug('✅ Fallback parsed ${trips.length} trips');
        return trips;
      } else {
        final hint = contentType.contains('html') ? ' (content-type suggests HTML)' : '';
        _log.debug('Fallback 200 but non-list payload: type=${data.runtimeType}$hint');
        return const <Trip>[];
      }
    }
    _log.debug('Fallback failed or non-JSON, returning empty');
    return const <Trip>[];
  }

  /// Parse trips in background isolate
  Future<List<Trip>> _parseTripsInBackground(dynamic data) async {
    final shouldUseIsolate = data is String
        ? data.length > 500
        : (data is List && data.length > 10);
    
    if (!shouldUseIsolate) {
      return _parseTripsIsolate(data);
    }
    
    final itemCount = data is String ? 'unknown' : (data as List).length;
    _log.debug('🔄 Parsing $itemCount trips in background isolate (JSON decoding: ${data is String})');
    final stopwatch = Stopwatch()..start();
    
    final trips = await compute(_parseTripsIsolate, data);
    
    stopwatch.stop();
    _log.debug('✅ Background parsing completed in ${stopwatch.elapsedMilliseconds}ms');
    
    return trips;
  }

  /// Fetch raw positions for a given device and time range
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
      final positions = data
          .whereType<Map<String, dynamic>>()
          .map(model.Position.fromJson)
          .toList(growable: false);
      return positions;
    } on DioException catch (e) {
      _log.error('DioException (positions)', error: e);
      rethrow;
    } catch (e, st) {
      _log.error('Error (positions)', error: e, stackTrace: st);
      rethrow;
    }
  }

  // Format to second precision per Traccar expectations
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
}
