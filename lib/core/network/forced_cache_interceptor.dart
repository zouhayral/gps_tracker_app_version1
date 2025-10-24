import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';

/// ForcedLocalCacheInterceptor
///
/// Purpose
/// - Provide fast, offline-friendly caching for static GET endpoints regardless
///   of server validators (ETag/Last-Modified).
/// - Avoid repeated REST hits to Traccar endpoints that rarely change per
///   session: /api/devices, /api/geofences, /api/users.
///
/// Behavior
/// - On GET to whitelisted paths:
///   - If a non-expired cache entry exists → return it immediately (short-circuit
///     network). Logs FORCED-CACHE HIT.
///   - If expired or missing → pass-through; on 200, store response with TTL.
///   - On network error and a stale entry exists → serve stale as fallback if
///     serveStaleOnError is true. Logs FORCED-CACHE STALE-FALLBACK.
///
/// Notes
/// - Works on Android, iOS, Web (pure Dart, in-memory only).
/// - Pairs well with a conditional caching interceptor (ETag/If-Modified-Since)
///   for revalidation when TTL has elapsed.
class ForcedLocalCacheInterceptor extends Interceptor {
  ForcedLocalCacheInterceptor({
    Map<String, Duration>? ttlOverrides,
    this.serveStaleOnError = true,
  }) : _ttlMap = {
          // Sensible defaults; tune as needed
          '/api/devices': const Duration(minutes: 5),
          '/api/geofences': const Duration(minutes: 10),
          '/api/users': const Duration(minutes: 10),
          if (ttlOverrides != null) ...ttlOverrides,
        };

  final Map<String, Duration> _ttlMap;
  final bool serveStaleOnError;

  static const _allowedPaths = <String>{
    '/api/devices',
    '/api/geofences',
    '/api/users',
  };

  // Shared in-memory cache across all instances
  static final Map<String, _ForcedCacheEntry> _cache = {};

  bool _shouldHandle(RequestOptions options) {
    if (options.method.toUpperCase() != 'GET') return false;
    final path = options.uri.path;
    return _allowedPaths.contains(path);
  }

  Duration _ttlForPath(String path) =>
      _ttlMap[path] ?? const Duration(minutes: 5);

  String _key(RequestOptions options) => options.uri.toString();

  @override
  void onRequest(RequestOptions options, RequestInterceptorHandler handler) {
    if (_shouldHandle(options)) {
      final key = _key(options);
      final entry = _cache[key];
      if (entry != null) {
        final now = DateTime.now();
        final ttl = _ttlForPath(options.uri.path);
        final expired = now.difference(entry.storedAt) > ttl;
        if (!expired) {
          if (kDebugMode) {
            // ignore: avoid_print
            print(
              '[FORCED-CACHE][HIT] ${options.uri} (age: ${now.difference(entry.storedAt).inSeconds}s)',
            );
          }
          handler.resolve(
            Response<dynamic>(
              requestOptions: options,
              statusCode: 200,
              data: _deepClone(entry.data),
              headers: entry.headers,
            ),
          );
          return;
        } else {
          if (kDebugMode) {
            // ignore: avoid_print
            print(
              '[FORCED-CACHE][EXPIRED] ${options.uri} (age: ${now.difference(entry.storedAt).inSeconds}s)',
            );
          }
        }
      } else {
        if (kDebugMode) {
          // ignore: avoid_print
          print('[FORCED-CACHE][MISS] ${options.uri}');
        }
      }
    }
    handler.next(options);
  }

  @override
  void onResponse(
    Response<dynamic> response,
    ResponseInterceptorHandler handler,
  ) {
    final options = response.requestOptions;
    if (_shouldHandle(options) && (response.statusCode ?? 0) == 200) {
      final key = _key(options);
      _cache[key] = _ForcedCacheEntry(
        data: _deepClone(response.data),
        headers: response.headers,
        storedAt: DateTime.now(),
        path: options.uri.path,
      );
      if (kDebugMode) {
        // ignore: avoid_print
        print('[FORCED-CACHE][STORE] ${options.uri}');
      }
    }
    handler.next(response);
  }

  @override
  void onError(DioException err, ErrorInterceptorHandler handler) {
    final options = err.requestOptions;
    if (_shouldHandle(options)) {
      final key = _key(options);
      final entry = _cache[key];
      if (entry != null && serveStaleOnError) {
        if (kDebugMode) {
          // ignore: avoid_print
          print(
            '[FORCED-CACHE][STALE-FALLBACK] ${options.uri} due to ${err.type.name}',
          );
        }
        handler.resolve(
          Response<dynamic>(
            requestOptions: options,
            statusCode: 200,
            data: _deepClone(entry.data),
            headers: entry.headers,
          ),
        );
        return;
      }
    }
    handler.next(err);
  }

  static dynamic _deepClone(dynamic data) {
    try {
      if (data is Map || data is List) {
        final text = jsonEncode(data);
        return jsonDecode(text);
      }
    } catch (e) {
      debugPrint('[ForcedCacheInterceptor] ⚠️ Failed to deep clone data: $e');
    }
    return data;
  }

  // ---------- Debug utilities ----------

  /// Clears all cached entries or those matching [pathStartsWith].
  static void clear({String? pathStartsWith}) {
    if (pathStartsWith == null) {
      _cache.clear();
    } else {
      _cache.removeWhere((key, value) => value.path.startsWith(pathStartsWith));
    }
    if (kDebugMode) {
      // ignore: avoid_print
      print('[FORCED-CACHE][CLEAR] pathPrefix=${pathStartsWith ?? '*'}');
    }
  }

  /// Returns a snapshot of the cache for introspection in debug tools.
  static List<Map<String, dynamic>> snapshot() {
    final now = DateTime.now();
    return _cache.entries
        .map(
          (e) => {
            'url': e.key,
            'path': e.value.path,
            'ageSec': now.difference(e.value.storedAt).inSeconds,
            'storedAt': e.value.storedAt.toIso8601String(),
            'size': _estimateSize(e.value.data),
          },
        )
        .toList();
  }

  static int _estimateSize(dynamic data) {
    try {
      return utf8.encode(jsonEncode(data)).length;
    } catch (_) {
      return 0;
    }
  }
}

class _ForcedCacheEntry {
  _ForcedCacheEntry({
    required this.data,
    required this.headers,
    required this.storedAt,
    required this.path,
  });
  final dynamic data;
  final Headers headers;
  final DateTime storedAt;
  final String path;
}
