import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:my_app_gps/core/database/dao/trip_snapshots_dao.dart';
import 'package:my_app_gps/core/database/dao/trips_dao.dart';
import 'package:my_app_gps/core/diagnostics/dev_diagnostics.dart';
import 'package:my_app_gps/core/utils/app_logger.dart';
import 'package:my_app_gps/data/models/position.dart' as model;
import 'package:my_app_gps/data/models/trip.dart';
import 'package:my_app_gps/data/models/trip_aggregate.dart';
import 'package:my_app_gps/data/models/trip_snapshot.dart';
import 'package:my_app_gps/features/dashboard/controller/devices_notifier.dart';
import 'package:my_app_gps/features/trips/models/trip_filter.dart';
import 'package:my_app_gps/repositories/services/trip_cache_manager.dart';
import 'package:my_app_gps/repositories/services/trip_network_service.dart';
import 'package:my_app_gps/services/auth_service.dart';

/// Provider for TripCacheManager
final tripCacheManagerProvider = Provider<TripCacheManager>((ref) {
  return TripCacheManager();
});

/// Provider for TripNetworkService
final tripNetworkServiceProvider = Provider<TripNetworkService>((ref) {
  final dio = ref.watch(dioProvider);
  final cookieJar = ref.watch(authCookieJarProvider);
  final authService = ref.watch(authServiceProvider);
  
  return TripNetworkService(
    dio: dio,
    cookieJar: cookieJar,
    rehydrateCookie: authService.rehydrateSessionCookie,
  );
});

/// Refactored repository - thin coordinator between cache and network layers.
///
/// Responsibilities:
/// - Coordinate between cache and network services
/// - Implement business logic (online check, prefetch, smart retry)
/// - Handle DAO operations for persistence
/// - Manage last used filter for prefetch
/// 
/// Architecture:
/// - TripCacheManager: In-memory caching with TTL
/// - TripNetworkService: All HTTP operations
/// - TripRepository: Orchestration and business logic
class TripRepository {
  static final _log = 'TripRepository'.logger;
  
  TripRepository({
    required this.cacheManager,
    required this.networkService,
    required Ref ref,
  }) : _ref = ref;

  final TripCacheManager cacheManager;
  final TripNetworkService networkService;
  final Ref _ref;

  // Last used filter for prefetch on resume
  TripFilter? _lastUsedFilter;

  /// Fetch trips with caching, deduplication, and smart retry
  Future<List<Trip>> fetchTrips({
    required int deviceId,
    required DateTime from,
    required DateTime to,
    CancelToken? cancelToken,
    TripFilter? filter,
  }) async {
    // Store last used filter for prefetch
    if (filter != null) {
      _lastUsedFilter = filter;
    }

    final cacheKey = cacheManager.buildCacheKey(deviceId, from, to);
    final sw = Stopwatch()..start();

    // 1. Check cache first
    final cached = cacheManager.getCached(cacheKey);
    if (cached != null) {
      return cached;
    }

    // 2. Check for ongoing request (deduplication)
    if (cacheManager.isRequestOngoing(cacheKey)) {
      _log.debug('⏸️ Skipping duplicate fetch for $cacheKey');
      return cacheManager.getOngoingRequest(cacheKey)!;
    }

    // 3. Create new request with retry logic
    final requestFuture = networkService.fetchTripsWithRetry(
      deviceId: deviceId,
      from: from,
      to: to,
      attempts: 3,
      cancelToken: cancelToken,
    ).then((trips) async {
      // Smart retry for empty responses on active devices
      if (trips.isEmpty && await _isDeviceOnline(deviceId)) {
        _log.debug('Empty response for online device $deviceId — retrying in 2s');
        await Future<void>.delayed(const Duration(seconds: 2));
        
        try {
          final retryTrips = await networkService.fetchTrips(
            deviceId: deviceId,
            from: from,
            to: to,
            cancelToken: cancelToken,
          );
          
          if (retryTrips.isNotEmpty) {
            _log.debug('✅ Retry successful: ${retryTrips.length} trips');
            trips = retryTrips;
          } else {
            _log.debug('Still empty after retry');
          }
        } catch (e) {
          _log.warning('Retry failed', error: e);
        }
      }
      
      sw.stop();
      _log.debug('⏱️ Fetch completed in ${sw.elapsedMilliseconds}ms');
      
      // Cache the result
      cacheManager.store(cacheKey, trips);
      
      return trips;
    }).catchError((Object error, StackTrace stackTrace) {
      _log.warning('Network error, checking cache', error: error);
      
      // Graceful fallback: return stale cache if available
      final stale = cacheManager.getStaleCached(cacheKey);
      if (stale != null) {
        return stale;
      }
      
      _log.debug('❌ No cache available, returning empty');
      return <Trip>[];
    }).whenComplete(() {
      cacheManager.removeRequest(cacheKey);
    });

    // Track ongoing request
    cacheManager.trackRequest(cacheKey, requestFuture);
    return requestFuture;
  }

  /// Check if device is online
  Future<bool> _isDeviceOnline(int deviceId) async {
    try {
      final devicesAsync = _ref.read(devicesNotifierProvider);
      final devices = devicesAsync.asData?.value ?? <Map<String, dynamic>>[];
      
      final device = devices.firstWhere(
        (Map<String, dynamic> d) => d['id'] == deviceId,
        orElse: () => <String, dynamic>{},
      );
      
      if (device.keys.isEmpty) return false;
      
      final status = (device['status']?.toString() ?? '').toLowerCase();
      if (status != 'online') return false;
      
      final lastUpdate = device['lastUpdate'];
      if (lastUpdate is String) {
        final lastUpdateTime = DateTime.tryParse(lastUpdate);
        if (lastUpdateTime != null) {
          final age = DateTime.now().toUtc().difference(lastUpdateTime.toUtc());
          return age < const Duration(minutes: 5);
        }
      }
      
      return true;
    } catch (e) {
      _log.warning('Error checking device status', error: e);
      return false;
    }
  }

  /// Prefetch trips for last used filter (app resume optimization)
  Future<void> prefetchLastUsedFilter() async {
    if (_lastUsedFilter == null) {
      _log.debug('No last filter stored, skipping prefetch');
      return;
    }
    
    final filter = _lastUsedFilter!;
    _log.debug('Background prefetch for last filter: ${filter.deviceIds.length} devices');
    
    try {
      final deviceIds = filter.deviceIds.isEmpty 
          ? await _getAllDeviceIds() 
          : filter.deviceIds;
      
      for (final deviceId in deviceIds) {
        unawaited(
          fetchTrips(
            deviceId: deviceId,
            from: filter.from,
            to: filter.to,
            filter: filter,
          ).catchError((Object e) {
            _log.warning('Prefetch failed for device $deviceId', error: e);
            return <Trip>[];
          }),
        );
      }
      
      _log.debug('✅ Started background prefetch for ${deviceIds.length} devices');
    } catch (e) {
      _log.error('Prefetch error', error: e);
    }
  }

  /// Get all device IDs for prefetch
  Future<List<int>> _getAllDeviceIds() async {
    try {
      final devicesAsync = _ref.read(devicesNotifierProvider);
      final devices = devicesAsync.asData?.value ?? <Map<String, dynamic>>[];
      return devices
          .where((Map<String, dynamic> d) => d['id'] != null)
          .map((Map<String, dynamic> d) => d['id'] as int)
          .toList();
    } catch (e) {
      _log.warning('Error getting device IDs', error: e);
      return [];
    }
  }

  /// Fetch raw positions for a given device and time range
  Future<List<model.Position>> fetchTripPositions({
    required int deviceId,
    required DateTime from,
    required DateTime to,
  }) async {
    return networkService.fetchTripPositions(
      deviceId: deviceId,
      from: from,
      to: to,
    );
  }

  /// Safe cached trips lookup from DAO
  Future<List<Trip>> getCachedTrips(
    int deviceId,
    DateTime from,
    DateTime to,
  ) async {
    try {
      final dao = await _ref.read(tripsDaoProvider.future);
      final cached = await dao.getByDeviceInRange(deviceId, from, to);
      if (cached.isEmpty) return const <Trip>[];
      // DAO returns domain Trip models directly
      return List<Trip>.unmodifiable(cached);
    } catch (e) {
      _log.warning('Cache lookup failed', error: e);
      return const <Trip>[];
    }
  }

  /// Remove expired entries from memory cache
  void cleanupExpiredCache() {
    cacheManager.cleanupExpiredCache();
  }

  /// Remove all trips older than 30 days from DAO
  Future<void> cleanupOldTrips() async {
    try {
      final tripsDao = await _ref.read(tripsDaoProvider.future);
      final snapshotsDao = await _ref.read(tripSnapshotsDaoProvider.future);
      final now = DateTime.now().toUtc();
      final cutoff = now.subtract(const Duration(days: 30));

      // Persist monthly snapshot before deletion
      await _persistMonthlySnapshot(
        cutoff: cutoff,
        tripsDao: tripsDao,
        snapshotsDao: snapshotsDao,
      );

      // Proceed with deletion
      final old = await tripsDao.getOlderThan(cutoff);
      if (old.isNotEmpty) {
        final totalKm = old.fold<double>(0, (s, t) => s + t.distanceKm);
        _log.debug(
          '🧹 Retention: deleting ${old.length} trips (< ${cutoff.toIso8601String()}) totaling ${totalKm.toStringAsFixed(1)} km',
        );
      }
      await tripsDao.deleteOlderThan(cutoff);
    } catch (e) {
      _log.warning('cleanupOldTrips error', error: e);
    }
  }

  /// Aggregated analytics by day over a period
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
      _log.warning('fetchAggregates error', error: e);
      return <String, TripAggregate>{};
    } finally {
      sw.stop();
      if (kDebugMode) {
        DevDiagnostics.instance.recordFilterCompute(sw.elapsedMilliseconds);
      }
    }
  }

  /// Persist monthly snapshot for historical reference
  Future<void> _persistMonthlySnapshot({
    required DateTime cutoff,
    required TripsDaoBase tripsDao,
    required TripSnapshotsDaoBase snapshotsDao,
  }) async {
    final monthStart = DateTime(cutoff.year, cutoff.month).toUtc();
    final nextMonth = (cutoff.month == 12)
        ? DateTime(cutoff.year + 1).toUtc()
        : DateTime(cutoff.year, cutoff.month + 1).toUtc();
    final monthEnd = nextMonth.subtract(const Duration(seconds: 1));

    final monthKey = _fmtYearMonth(cutoff);

    try {
      final daily = await tripsDao.getAggregatesByDay(monthStart, monthEnd);
      if (daily.isEmpty) return;
      
      final totals = TripAggregate(
        totalDistanceKm: daily.values.fold<double>(0, (a, b) => a + b.totalDistanceKm),
        totalDurationHrs: daily.values.fold<double>(0, (a, b) => a + b.totalDurationHrs),
        avgSpeedKph: daily.values.isEmpty
            ? 0.0
            : daily.values.fold<double>(0, (a, b) => a + b.avgSpeedKph) / daily.length,
        tripCount: daily.values.fold<int>(0, (a, b) => a + b.tripCount),
      );
      
      await snapshotsDao.putSnapshot(TripSnapshot.fromAggregate(monthKey, totals));
      
      // Prune old snapshots (keep last 24 months)
      const keepBackMonths = 24;
      final olderCutoff = _fmtYearMonth(
        DateTime.now().toUtc().subtract(const Duration(days: keepBackMonths * 30)),
      );
      await snapshotsDao.deleteOlderThan(olderCutoff);
      
      _log.debug(
        'Saved monthly snapshot for $monthKey: ${totals.tripCount} trips, ${totals.totalDistanceKm.toStringAsFixed(1)} km',
      );
    } catch (e) {
      _log.warning('Snapshot persist failed', error: e);
    }
  }

  String _fmtYearMonth(DateTime d) {
    final y = d.year.toString().padLeft(4, '0');
    final m = d.month.toString().padLeft(2, '0');
    return '$y-$m';
  }

  /// Get cache statistics
  Map<String, dynamic> getCacheStats() {
    return cacheManager.getStats();
  }
}

/// Provider for TripRepository (refactored version)
final tripRepositoryProvider = Provider<TripRepository>((ref) {
  final cacheManager = ref.watch(tripCacheManagerProvider);
  final networkService = ref.watch(tripNetworkServiceProvider);
  
  return TripRepository(
    cacheManager: cacheManager,
    networkService: networkService,
    ref: ref,
  );
});
