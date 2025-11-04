import 'dart:async';
import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:my_app_gps/core/utils/app_logger.dart';
import 'package:my_app_gps/features/map/data/position_model.dart';
import 'package:my_app_gps/services/auth_service.dart';

// ============================================================================
// 🎯 ASYNC JSON PARSING (STEP 2.2)
// ============================================================================

/// Top-level function for isolate-based position parsing
/// This must be top-level to work with compute()
/// 
/// Accepts either:
/// - String: Raw JSON that needs decoding + parsing
/// - List<dynamic>: Already decoded JSON that needs parsing
List<Position> _parsePositions(dynamic jsonData) {
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
  
  // Step 2: Parse Position objects from JSON list
  final positions = <Position>[];
  for (final item in jsonList) {
    if (item is Map<String, dynamic>) {
      try {
        positions.add(Position.fromJson(item));
      } catch (_) {
        // Skip malformed items silently in isolate
      }
    }
  }
  return positions;
}

/// Provider for positions service (raw access + probing utilities).
final positionsServiceProvider = Provider<PositionsService>((ref) {
  final dio = ref.watch(dioProvider);
  return PositionsService(dio);
});

class PositionsService {
  static final _log = 'PositionsService'.logger;
  
  PositionsService(this._dio);
  final Dio _dio;
  
  // ----------------------------------------------------------------------------
  // 🔁 Lightweight transient-error retry wrapper for Dio GET requests
  // ----------------------------------------------------------------------------
  // - Retries only on transient network conditions and 5xx like 502/503/504
  // - Uses small exponential backoff with jitter (300ms, 600ms, 1200ms)
  // - Preserves gzip + connection pooling defaults by NOT overriding adapters
  Future<Response<T>> _getWithRetry<T>(
    String path, {
    Map<String, dynamic>? queryParameters,
    Options? options,
    int maxAttempts = 3,
    CancelToken? cancelToken,
  }) async {
    int attempt = 0;
    Duration delay = const Duration(milliseconds: 300);
    DioException? lastError;

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
        lastError = e;
        final status = e.response?.statusCode;
        final isTimeout = e.type == DioExceptionType.connectionTimeout ||
            e.type == DioExceptionType.receiveTimeout ||
            e.type == DioExceptionType.sendTimeout;
        final isConn = e.type == DioExceptionType.connectionError;
        final isRetryableStatus = status == 502 || status == 503 || status == 504;

        // Only retry on transient errors
        if (attempt < maxAttempts && (isTimeout || isConn || isRetryableStatus)) {
          final jitter = Duration(milliseconds: 50 * attempt);
          if (kDebugMode) {
            debugPrint('[HTTP][RETRY] GET $path attempt#$attempt failed (status=$status type=${e.type.name}) → retrying in ${delay.inMilliseconds + jitter.inMilliseconds}ms');
          }
          await Future<void>.delayed(delay + jitter);
          delay *= 2; // exponential backoff
          continue;
        }
        // Non-retryable or attempts exhausted
        rethrow;
      }
    }
    throw lastError ?? StateError('Unknown Dio error without exception');
  }
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

  /// Fetch history positions for a device in a time range and parse into Position objects.
  /// Uses an isolate for large payloads to avoid blocking the UI thread.
  Future<List<Position>> fetchHistoryPositions({
    required int deviceId,
    required DateTime from,
    required DateTime to,
  }) async {
    final raw = await fetchHistoryRaw(deviceId: deviceId, from: from, to: to);
    if (raw.isEmpty) return const <Position>[];

    // Estimate payload size to decide whether to use isolate
    int payloadBytes = 0;
    try {
      payloadBytes = utf8.encode(jsonEncode(raw)).length;
    } catch (_) {
      // ignore sizing errors
    }

    if (payloadBytes > 1024) {
      if (kDebugMode) {
        debugPrint('[ASYNC_PARSE] History Payload Size: $payloadBytes bytes (compute)');
      }
      return compute(_parsePositions, raw);
    }

    if (kDebugMode) {
      debugPrint('[ASYNC_PARSE] History Payload Size: $payloadBytes bytes (sync)');
    }
    return raw
        .whereType<Map<String, dynamic>>()
        .map(Position.fromJson)
        .toList();
  }

  /// Convenience: fetch positions since a given timestamp (to now).
  Future<List<Position>> fetchPositionsSince({
    required int deviceId,
    required DateTime since,
    DateTime? to,
  }) async {
    final end = to ?? DateTime.now().toUtc();
    // Guard: ensure sane window (non-negative, max 12h)
    var start = since.toUtc();
    if (!start.isBefore(end)) {
      start = end.subtract(const Duration(minutes: 5));
    }
    const maxWindow = Duration(hours: 12);
    if (end.difference(start) > maxWindow) {
      start = end.subtract(maxWindow);
    }
    final list = await fetchHistoryPositions(deviceId: deviceId, from: start, to: end);
    // Return early if empty (no need to sort)
    if (list.isEmpty) return list;
    // Clone to ensure mutability before sorting (list might be const or unmodifiable)
    final mutable = List<Position>.of(list);
    // Sort ascending by time for deterministic processing
    mutable.sort((a, b) => a.deviceTime.compareTo(b.deviceTime));
    return mutable;
  }

  /// Fetch raw history positions list for a device and time range.
  Future<List<dynamic>> fetchHistoryRaw({
    required int deviceId,
    required DateTime from,
    required DateTime to,
  }) async {
    // Note: Keep gzip + pooling defaults (Dart HttpClient enables gzip + keep-alive by default)
    final resp = await _getWithRetry<List<dynamic>>(
      '/api/positions',
      queryParameters: {
        'deviceId': deviceId,
        'from': from.toUtc().toIso8601String(),
        'to': to.toUtc().toIso8601String(),
      },
      options: Options(headers: const {'Accept': 'application/json'}),
    );
    final data = resp.data;
    if (data is List) {
      // 🎯 ASYNC PARSING: Calculate payload size
      final payloadBytes = utf8.encode(jsonEncode(data)).length;
      
      if (payloadBytes > 1024 && kDebugMode) {
        debugPrint('[ASYNC_PARSE] History Payload Size: $payloadBytes bytes (device: $deviceId)');
      }
      
      return data;
    }
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
          _log.warning('Failed to calculate payload bytes', error: e);
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
      final resp = await _getWithRetry<List<dynamic>>(
        '/api/positions',
        queryParameters: const {'latest': 'true'},
        options: Options(headers: const {'Accept': 'application/json'}),
      );
      final data = resp.data;
      if (data is List) {
        // 🎯 ASYNC PARSING: Calculate payload size
        final payloadBytes = utf8.encode(jsonEncode(data)).length;
        
        List<Position> list;
        if (payloadBytes > 1024) {
          // Large payload: use isolate-based parsing
          if (kDebugMode) {
            debugPrint('[ASYNC_PARSE] Payload Size: $payloadBytes bytes (using compute)');
          }
          list = await compute(_parsePositions, data);
        } else {
          // Small payload: synchronous parsing is faster
          if (kDebugMode) {
            debugPrint('[ASYNC_PARSE] Payload Size: $payloadBytes bytes (synchronous)');
          }
          list = data
              .whereType<Map<String, dynamic>>()
              .map(Position.fromJson)
              .toList();
        }
        
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
  /// 
  /// **Note:** Traccar API doesn't support GET /api/positions/:id (returns 405).
  /// Instead, we use GET /api/positions?id=:id which is the correct endpoint.
  Future<Position?> latestByPositionId(int id) async {
    try {
      final resp = await _getWithRetry<List<dynamic>>(
        '/api/positions',
        queryParameters: {'id': id},
      );
      final data = resp.data;
      if (data == null || data.isEmpty) {
        if (kDebugMode) {
          // ignore: avoid_print
          print('[positionsService] Position $id returned empty');
        }
        return null;
      }
      // API returns array with single item
      final posData = data.first;
      if (posData is Map<String, dynamic>) {
        return Position.fromJson(posData);
      }
      return null;
    } on DioException catch (e) {
      // Log detailed error for debugging
      _log.error(
        'Failed to fetch position $id: ${e.type.name} '
        'status=${e.response?.statusCode} '
        'message=${e.message}',
      );
      return null;
    } catch (e) {
      _log.error('Unexpected error fetching position $id', error: e);
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
          _log.debug(
            '✋ Using cached positions '
            '(age: ${timeSinceLastBulkFetch.inSeconds}s, TTL: ${_bulkFetchTTL.inMinutes}m, '
            'throttled: $_bulkFetchThrottled, devices: ${cached.length})',
          );
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
      // Guard: some backends report positionId=0 or negative when unavailable
      if (devId is int && posId is int && posId > 0) {
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
    
    _log.debug('Bulk fetch complete: ${out.length} positions');

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
    _log.debug('Cache cleared');
  }

  /// Adaptive REST fallback polling stream used when WebSocket is offline.
  ///
  /// Behavior:
  /// - Polls `fetchLatestPositions` for the provided [deviceIds]
  /// - Starts at [baseInterval] (default 10s) and doubles on consecutive empty/failed polls
  ///   up to [maxInterval] (default 120s)
  /// - Resets back to [baseInterval] immediately when any data arrives
  /// - Stops automatically when [isWebSocketOnline] returns true
  ///
  /// This is optional; the repository already includes a similar fallback.
  /// Exposed here for targeted consumers and testing.
  Stream<List<Position>> fallbackPollLatestAdaptive({
    required List<int> deviceIds,
    bool Function()? isWebSocketOnline,
    Duration baseInterval = const Duration(seconds: 10),
    Duration maxInterval = const Duration(seconds: 120),
    bool emitEmptyOnStop = false,
  }) {
    final controller = StreamController<List<Position>>.broadcast();
    Timer? timer;
    var interval = baseInterval;
    var closed = false;

    void scheduleNext() {
      if (closed) return;
      timer?.cancel();
      timer = Timer(interval, () async {
        if (closed) return;
        // Stop if WebSocket is back
        if (isWebSocketOnline?.call() == true) {
          if (emitEmptyOnStop && !controller.isClosed) {
            controller.add(const <Position>[]);
          }
          await controller.close();
          return;
        }
        try {
          final list = await fetchLatestPositions(deviceIds: deviceIds);
          if (list.isNotEmpty) {
            // Emit and reset backoff
            if (!controller.isClosed) controller.add(list);
            interval = baseInterval;
          } else {
            // Backoff (double up to max)
            final nextMs = (interval.inMilliseconds * 2)
                .clamp(baseInterval.inMilliseconds, maxInterval.inMilliseconds);
            // Add small jitter (±10%) to avoid thundering herd
            final jitter = (nextMs * 0.1).toInt();
            final adjusted = (nextMs - jitter) + (jitter ~/ 2);
            interval = Duration(milliseconds: adjusted);
          }
        } catch (e) {
          // Treat as empty result: backoff
          final nextMs = (interval.inMilliseconds * 2)
              .clamp(baseInterval.inMilliseconds, maxInterval.inMilliseconds);
          final jitter = (nextMs * 0.1).toInt();
          final adjusted = (nextMs - jitter) + (jitter ~/ 2);
          interval = Duration(milliseconds: adjusted);
        } finally {
          scheduleNext();
        }
      });
    }

    controller.onListen = scheduleNext;
    controller.onCancel = () {
      closed = true;
      timer?.cancel();
      timer = null;
    };

    return controller.stream;
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
