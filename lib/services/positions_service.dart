import 'dart:async';
import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:my_app_gps/features/map/data/position_model.dart';
import 'package:my_app_gps/services/auth_service.dart';

/// Provider for positions service (raw access + probing utilities).
final positionsServiceProvider = Provider<PositionsService>((ref) {
  final dio = ref.watch(dioProvider);
  return PositionsService(dio);
});

class PositionsService {
  PositionsService(this._dio);
  final Dio _dio;
  // In-memory latest position cache
  final Map<int, Position> _latestCache = {};
  final Map<int, DateTime> _latestCacheTime = {};
  DateTime _lastPrune = DateTime.fromMillisecondsSinceEpoch(0, isUtc: true);
  int _cacheHits = 0;
  int _cacheMisses = 0;
  
  // 🎯 PHASE 2 TASK 2: Bulk fetch throttling
  DateTime? _lastBulkFetchTime;
  static const _bulkFetchTTL = Duration(minutes: 3);
  int _bulkFetchThrottled = 0;

  void _pruneCache({Duration maxAge = const Duration(hours: 24)}) {
    final now = DateTime.now().toUtc();
    if (now.difference(_lastPrune) < const Duration(minutes: 10)) {
      return; // throttle pruning
    }
    _lastPrune = now;
    final toRemove = <int>[];
    _latestCacheTime.forEach((id, ts) {
      if (now.difference(ts) > maxAge) {
        toRemove.add(id);
      }
    });
    for (final id in toRemove) {
      _latestCache.remove(id);
      _latestCacheTime.remove(id);
    }
    if (kDebugMode && toRemove.isNotEmpty) {
      // ignore: avoid_print
      print('[positionsCache] pruned ${toRemove.length} stale entries');
    }
  }

  /// Fetch raw history positions list for a device and time range.
  Future<List<dynamic>> fetchHistoryRaw({
    required int deviceId,
    required DateTime from,
    required DateTime to,
  }) async {
    final resp = await _dio.get<List<dynamic>>(
      '/api/positions',
      queryParameters: {
        'deviceId': deviceId,
        'from': from.toUtc().toIso8601String(),
        'to': to.toUtc().toIso8601String(),
      },
      options: Options(headers: const {'Accept': 'application/json'}),
    );
    final data = resp.data;
    if (data is List) return data;
    throw StateError('Unexpected positions response type: ${data.runtimeType}');
  }

  /// Probe to estimate safe maximum history window size before needing chunking.
  /// Doubles window length until count threshold reached, error thrown, or max iterations.
  Future<List<HistoryProbeStep>> probeHistoryMax({
    required int deviceId,
    int initialHours = 6,
    int targetCount = 5000,
    int maxIterations = 8,
  }) async {
    final now = DateTime.now().toUtc();
    final steps = <HistoryProbeStep>[];
    var hours = initialHours;
    for (var i = 0; i < maxIterations; i++) {
      final from = now.subtract(Duration(hours: hours));
      try {
        final list = await fetchHistoryRaw(
          deviceId: deviceId,
          from: from,
          to: now,
        );
        var bytes = 0;
        try {
          bytes = utf8.encode(jsonEncode(list)).length;
        } catch (e) {
          debugPrint('[PositionsService] ⚠️ Failed to calculate payload bytes: $e');
        }
        final step = HistoryProbeStep(
          windowHours: hours,
          from: from,
          to: now,
          count: list.length,
          payloadBytes: bytes,
        );
        steps.add(step);
        if (kDebugMode) {
          // ignore: avoid_print
          print(
            '[historyProbe] hours=$hours count=${step.count} bytes=${step.payloadBytes}',
          );
        }
        if (list.length >= targetCount) {
          break;
        }
        hours *= 2;
      } on DioException catch (e) {
        steps.add(
          HistoryProbeStep(
            windowHours: hours,
            from: from,
            to: now,
            count: -1,
            payloadBytes: 0,
            error: '${e.response?.statusCode}:${e.type.name}',
          ),
        );
        break;
      } catch (e) {
        steps.add(
          HistoryProbeStep(
            windowHours: hours,
            from: from,
            to: now,
            count: -1,
            payloadBytes: 0,
            error: e.toString(),
          ),
        );
        break;
      }
    }
    return steps;
  }

  /// Attempt to fetch latest positions for all devices in one call (using `latest=true` if supported).
  /// On backends that don't support this flag, falls back to per-device recent history (last [fallbackMinutes] minutes).
  Future<List<Position>> fetchLatestPositions({
    required List<int> deviceIds,
    int fallbackMinutes = 30,
    int maxConcurrent = 4,
    Duration minFresh = const Duration(seconds: 10),
  }) async {
    // First try aggregated latest endpoint variant
    try {
      final resp = await _dio.get<List<dynamic>>(
        '/api/positions',
        queryParameters: const {'latest': 'true'},
        options: Options(headers: const {'Accept': 'application/json'}),
      );
      final data = resp.data;
      if (data is List) {
        final list = data
            .whereType<Map<String, dynamic>>()
            .map(Position.fromJson)
            .toList();
        final nowTs = DateTime.now().toUtc();
        for (final p in list) {
          _latestCache[p.deviceId] = p;
          _latestCacheTime[p.deviceId] = nowTs;
        }
        _pruneCache();
        if (kDebugMode) {
          // ignore: avoid_print
          print(
            '[positionsLatest] aggregated latest=true path size=${list.length}',
          );
        }
        return list;
      }
    } catch (_) {
      // ignore and fallback
    }
    // Fallback: fetch a recent window per device with limited concurrency
    final now = DateTime.now().toUtc();
    final from = now.subtract(Duration(minutes: fallbackMinutes));
    final results = <Position>[];

    // Helper to fetch single device latest
    Future<void> fetchOne(int id) async {
      final nowTs = DateTime.now().toUtc();
      final lastTs = _latestCacheTime[id];
      if (lastTs != null && nowTs.difference(lastTs) < minFresh) {
        final cached = _latestCache[id];
        if (cached != null) {
          results.add(cached);
          _cacheHits++;
          if (kDebugMode) {
            // ignore: avoid_print
            print(
              '[positionsCache] hit device=$id (hits=$_cacheHits misses=$_cacheMisses)',
            );
          }
          return; // skip network fetch
        }
      }
      _cacheMisses++;
      try {
        final raw = await fetchHistoryRaw(deviceId: id, from: from, to: now);
        if (raw.isEmpty) return;
        Map<String, dynamic>? newest;
        var newestT = DateTime.fromMillisecondsSinceEpoch(0, isUtc: true);
        for (final item in raw) {
          if (item is Map<String, dynamic>) {
            final m = Map<String, dynamic>.from(item);
            final dtDevice = DateTime.tryParse(
              m['deviceTime']?.toString() ?? '',
            )?.toUtc();
            final dtServer = DateTime.tryParse(
              m['serverTime']?.toString() ?? '',
            )?.toUtc();
            final t = dtDevice ?? dtServer ?? newestT;
            if (t.isAfter(newestT)) {
              newestT = t;
              newest = m;
            }
          }
        }
        if (newest != null) {
          final pos = Position.fromJson(newest);
          results.add(pos);
          _latestCache[id] = pos;
          _latestCacheTime[id] = DateTime.now().toUtc();
        }
      } catch (_) {
        /* ignore individual errors */
      }
    }

    // Chunk device IDs to limit concurrent requests
    for (var i = 0; i < deviceIds.length; i += maxConcurrent) {
      final slice = deviceIds.sublist(
        i,
        (i + maxConcurrent).clamp(0, deviceIds.length),
      );
      await Future.wait(slice.map(fetchOne));
    }

    _pruneCache();
    if (kDebugMode) {
      // ignore: avoid_print
      print(
        '[positionsLatest] fallback path fetched=${results.length} hits=$_cacheHits misses=$_cacheMisses cacheSize=${_latestCache.length}',
      );
    }

    return results;
  }

  /// Fetch a single Position by Traccar position id.
  Future<Position?> latestByPositionId(int id) async {
    try {
      final resp = await _dio.get<Map<String, dynamic>>('/api/positions/$id');
      final data = resp.data;
      if (data == null) return null;
      return Position.fromJson(data);
    } catch (_) {
      return null;
    }
  }

  /// Resolve deviceId -> Position using device.positionId for a set of devices.
  /// Fallback: For devices without positionId, fetch last 30min history.
  Future<Map<int, Position>> latestForDevices(
      List<Map<String, dynamic>> devices, {bool forceRefresh = false,}) async {
    // 🎯 PHASE 2 TASK 2: Throttle bulk position fetches
    if (!forceRefresh && _lastBulkFetchTime != null) {
      final timeSinceLastBulkFetch = DateTime.now().difference(_lastBulkFetchTime!);
      
      if (timeSinceLastBulkFetch < _bulkFetchTTL) {
        // Return cached positions for all requested devices
        final cached = <int, Position>{};
        var allCached = true;
        
        for (final d in devices) {
          final devId = d['id'];
          if (devId is int && _latestCache.containsKey(devId)) {
            cached[devId] = _latestCache[devId]!;
          } else {
            allCached = false;
          }
        }
        
        if (allCached && cached.isNotEmpty) {
          _bulkFetchThrottled++;
          if (kDebugMode) {
            debugPrint(
              '[PositionsService][CACHE][THROTTLED] ✋ Using cached positions '
              '(age: ${timeSinceLastBulkFetch.inSeconds}s, TTL: ${_bulkFetchTTL.inMinutes}m, '
              'throttled: $_bulkFetchThrottled, devices: ${cached.length})',
            );
          }
          return cached;
        }
      }
    }
    
    final out = <int, Position>{};
    final tasks = <Future<void>>[];
    final devicesWithoutPosId = <int>[];

    for (final d in devices) {
      final devId = d['id'];
      final posId = d['positionId'];
      if (devId is int && posId is int) {
        tasks.add(() async {
          final p = await latestByPositionId(posId);
          if (p != null) out[devId] = p;
        }());
      } else if (devId is int) {
        // Track devices without positionId for fallback fetch
        devicesWithoutPosId.add(devId);
      }
    }
    await Future.wait(tasks);

    if (kDebugMode) {
      // ignore: avoid_print
      print(
        '[positionsService] ✅ Fetched ${out.length} via positionId, ${devicesWithoutPosId.length} without positionId',
      );
    }

    // Fallback: Fetch last positions for devices without positionId
    if (devicesWithoutPosId.isNotEmpty) {
      final fallbackPositions = await fetchLatestPositions(
        deviceIds: devicesWithoutPosId,
      );
      for (final p in fallbackPositions) {
        out[p.deviceId] = p;
      }
      if (kDebugMode) {
        // ignore: avoid_print
        print(
          '[positionsService] 🔄 Fallback fetch: ${fallbackPositions.length} positions for devices without positionId',
        );
      }
    }

    // 🎯 PHASE 2: Update bulk fetch timestamp
    _lastBulkFetchTime = DateTime.now();
    
    if (kDebugMode) {
      debugPrint(
        '[PositionsService][FETCH] Bulk fetch complete: ${out.length} positions',
      );
    }

    return out;
  }
  
  /// 🎯 PHASE 2: Get cache statistics
  Map<String, dynamic> getCacheStats() {
    return {
      'cacheSize': _latestCache.length,
      'cacheHits': _cacheHits,
      'cacheMisses': _cacheMisses,
      'bulkFetchThrottled': _bulkFetchThrottled,
      'lastBulkFetchTime': _lastBulkFetchTime?.toIso8601String(),
      'bulkFetchAge': _lastBulkFetchTime != null
          ? DateTime.now().difference(_lastBulkFetchTime!).inSeconds
          : null,
      'hitRate': (_cacheHits + _cacheMisses) > 0
          ? (_cacheHits / (_cacheHits + _cacheMisses) * 100).toStringAsFixed(1)
          : '0.0',
    };
  }
  
  /// 🎯 PHASE 2: Clear cache (useful for testing or manual refresh)
  void clearCache() {
    _latestCache.clear();
    _latestCacheTime.clear();
    _lastBulkFetchTime = null;
    _cacheHits = 0;
    _cacheMisses = 0;
    _bulkFetchThrottled = 0;
    if (kDebugMode) {
      debugPrint('[PositionsService][CACHE][CLEAR] Cache cleared');
    }
  }
}

class HistoryProbeStep {
  HistoryProbeStep({
    required this.windowHours,
    required this.from,
    required this.to,
    required this.count,
    required this.payloadBytes,
    this.error,
  });
  final int windowHours;
  final DateTime from;
  final DateTime to;
  final int count; // -1 if error
  final int payloadBytes; // 0 if unknown
  final String? error;

  Map<String, dynamic> toJson() => {
        'hours': windowHours,
        'from': from.toIso8601String(),
        'to': to.toIso8601String(),
        'count': count,
        'bytes': payloadBytes,
        if (error != null) 'error': error,
      };

  @override
  String toString() => jsonEncode(toJson());
}
