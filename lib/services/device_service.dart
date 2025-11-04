import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:my_app_gps/services/auth_service.dart';

// ============================================================================
// 🎯 ASYNC JSON PARSING (STEP 2.2)
// ============================================================================

/// Top-level function for isolate-based device parsing
/// This must be top-level to work with compute()
/// 
/// Accepts either:
/// - String: Raw JSON that needs decoding + parsing
/// - List<dynamic>: Already decoded JSON that needs parsing
List<Map<String, dynamic>> _parseDevices(dynamic jsonData) {
  List<dynamic> jsonList;
  
  // Step 1: Decode JSON if needed
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
  
  // Step 2: Parse device maps and add lastUpdateDt
  final devices = <Map<String, dynamic>>[];
  for (final item in jsonList) {
    if (item is Map<String, dynamic>) {
      try {
        final m = Map<String, dynamic>.from(item);
        final lu = m['lastUpdate'];
        if (lu is String) {
          final dt = DateTime.tryParse(lu);
          if (dt != null) m['lastUpdateDt'] = dt.toUtc();
        }
        devices.add(m);
      } catch (_) {
        // Skip malformed items silently in isolate
      }
    }
  }
  return devices;
}

final deviceServiceProvider = Provider<DeviceService>((ref) {
  final dio = ref.watch(dioProvider); // reuse dio with cookie manager
  return DeviceService(dio);
});

class DeviceService {
  DeviceService(this._dio);
  final Dio _dio;
  
  // ----------------------------------------------------------------------------
  // 🔁 Lightweight transient-error retry for GET /api/devices
  // ----------------------------------------------------------------------------
  // - Retries 2-3 times on timeouts/connection errors and 502/503/504
  // - Preserves gzip + keep-alive defaults by not changing HttpClient adapter
  Future<Response<T>> _getWithRetry<T>(
    String path, {
    Map<String, dynamic>? queryParameters,
    Options? options,
    int maxAttempts = 3,
    CancelToken? cancelToken,
  }) async {
    int attempt = 0;
    Duration delay = const Duration(milliseconds: 300);
    while (attempt < maxAttempts) {
      attempt++;
      try {
        return await _dio.get<T>(
          path,
          queryParameters: queryParameters,
          options: options,
          cancelToken: cancelToken,
        );
      } on DioException catch (e) {
        final status = e.response?.statusCode;
        final isTimeout = e.type == DioExceptionType.connectionTimeout ||
            e.type == DioExceptionType.receiveTimeout ||
            e.type == DioExceptionType.sendTimeout;
        final isConn = e.type == DioExceptionType.connectionError;
        final isRetryableStatus = status == 502 || status == 503 || status == 504;
        if (attempt < maxAttempts && (isTimeout || isConn || isRetryableStatus)) {
          final jitter = Duration(milliseconds: 50 * attempt);
          if (kDebugMode) {
            debugPrint('[HTTP][RETRY] GET $path attempt#$attempt failed (status=$status type=${e.type.name}) → retrying in ${delay.inMilliseconds + jitter.inMilliseconds}ms');
          }
          await Future<void>.delayed(delay + jitter);
          delay *= 2;
          continue;
        }
        rethrow;
      }
    }
    throw StateError('GET $path failed without DioException');
  }
  
  // 🎯 PHASE 2 TASK 2: Cache with TTL throttling
  static const _cacheTTL = Duration(minutes: 3);
  List<Map<String, dynamic>>? _cachedDevices;
  DateTime? _lastFetchTime;
  int _cacheHitCount = 0;
  int _cacheMissCount = 0;

  Future<List<Map<String, dynamic>>> fetchDevices({bool forceRefresh = false}) async {
    // 🎯 Check cache TTL (skip if force refresh requested)
    if (!forceRefresh && _cachedDevices != null && _lastFetchTime != null) {
      final timeSinceLastFetch = DateTime.now().difference(_lastFetchTime!);
      
      if (timeSinceLastFetch < _cacheTTL) {
        _cacheHitCount++;
        if (kDebugMode) {
          debugPrint(
            '[DeviceService][CACHE][THROTTLED] ✋ Using cached devices '
            '(age: ${timeSinceLastFetch.inSeconds}s, TTL: ${_cacheTTL.inMinutes}m, hits: $_cacheHitCount)',
          );
        }
        return _cachedDevices!;
      } else {
        if (kDebugMode) {
          debugPrint(
            '[DeviceService][CACHE][EXPIRED] Cache expired '
            '(age: ${timeSinceLastFetch.inSeconds}s, TTL: ${_cacheTTL.inMinutes}m)',
          );
        }
      }
    }
    
    // Cache miss or expired - fetch from API
    _cacheMissCount++;
    if (kDebugMode) {
      debugPrint(
        '[DeviceService][FETCH] Fetching devices from API '
        '(misses: $_cacheMissCount, force: $forceRefresh)',
      );
    }
    
  final resp = await _getWithRetry<List<dynamic>>('/api/devices');
    final data = resp.data;
    if (data is List) {
      // 🎯 ASYNC PARSING: Calculate payload size
      final payloadBytes = utf8.encode(jsonEncode(data)).length;
      
      List<Map<String, dynamic>> devices;
      if (payloadBytes > 1024) {
        // Large payload: use isolate-based parsing
        if (kDebugMode) {
          debugPrint('[ASYNC_PARSE] Payload Size: $payloadBytes bytes (using compute)');
        }
        devices = await compute(_parseDevices, data);
      } else {
        // Small payload: synchronous parsing is faster
        if (kDebugMode) {
          debugPrint('[ASYNC_PARSE] Payload Size: $payloadBytes bytes (synchronous)');
        }
        devices = data.whereType<Map<String, dynamic>>().map((e) {
          final m = Map<String, dynamic>.from(e);
          final lu = m['lastUpdate'];
          if (lu is String) {
            final dt = DateTime.tryParse(lu);
            if (dt != null) m['lastUpdateDt'] = dt.toUtc();
          }
          return m;
        }).toList();
      }
      
      // 🎯 Update cache
      _cachedDevices = devices;
      _lastFetchTime = DateTime.now();
      
      if (kDebugMode) {
        debugPrint(
          '[DeviceService][CACHE][UPDATE] Cached ${devices.length} devices',
        );
      }
      
      return devices;
    }
    return [];
  }
  
  /// 🎯 PHASE 2: Clear cache (useful for logout or when data becomes stale)
  void clearCache() {
    _cachedDevices = null;
    _lastFetchTime = null;
    _cacheHitCount = 0;
    _cacheMissCount = 0;
    if (kDebugMode) {
      debugPrint('[DeviceService][CACHE][CLEAR] Cache cleared');
    }
  }
  
  /// 🎯 PHASE 2: Get cache statistics for monitoring
  Map<String, dynamic> getCacheStats() {
    return {
      'isCached': _cachedDevices != null,
      'cacheSize': _cachedDevices?.length ?? 0,
      'lastFetchTime': _lastFetchTime?.toIso8601String(),
      'cacheAge': _lastFetchTime != null
          ? DateTime.now().difference(_lastFetchTime!).inSeconds
          : null,
      'cacheTTL': _cacheTTL.inSeconds,
      'cacheHits': _cacheHitCount,
      'cacheMisses': _cacheMissCount,
      'hitRate': (_cacheHitCount + _cacheMissCount) > 0
          ? (_cacheHitCount / (_cacheHitCount + _cacheMissCount) * 100).toStringAsFixed(1)
          : '0.0',
    };
  }
}
