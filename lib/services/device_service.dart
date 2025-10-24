import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:my_app_gps/services/auth_service.dart';

final deviceServiceProvider = Provider<DeviceService>((ref) {
  final dio = ref.watch(dioProvider); // reuse dio with cookie manager
  return DeviceService(dio);
});

class DeviceService {
  DeviceService(this._dio);
  final Dio _dio;
  
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
    
    final resp = await _dio.get<List<dynamic>>('/api/devices');
    final data = resp.data;
    if (data is List) {
      final devices = data.whereType<Map<String, dynamic>>().map((e) {
        final m = Map<String, dynamic>.from(e);
        final lu = m['lastUpdate'];
        if (lu is String) {
          final dt = DateTime.tryParse(lu);
          if (dt != null) m['lastUpdateDt'] = dt.toUtc();
        }
        return m;
      }).toList();
      
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
