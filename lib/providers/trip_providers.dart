import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:my_app_gps/core/database/dao/trip_snapshots_dao.dart';
import 'package:my_app_gps/core/diagnostics/dev_diagnostics.dart';
import 'package:my_app_gps/data/models/position.dart';
import 'package:my_app_gps/data/models/trip.dart';
import 'package:my_app_gps/data/models/trip_aggregate.dart';
import 'package:my_app_gps/data/models/trip_snapshot.dart';
import 'package:my_app_gps/features/trips/analytics/widgets/trip_trends_chart.dart'
    show MetricType;
import 'package:my_app_gps/repositories/trip_repository.dart';

/// Simple query struct for requesting trips for a device and date range.
@immutable
class TripQuery {
  const TripQuery(
      {required this.deviceId, required this.from, required this.to,});
  final int deviceId;
  final DateTime from;
  final DateTime to;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is TripQuery &&
          runtimeType == other.runtimeType &&
          deviceId == other.deviceId &&
          from == other.from &&
          to == other.to;

  @override
  int get hashCode => deviceId.hashCode ^ from.hashCode ^ to.hashCode;
}

/// AsyncNotifier for trips by device and date range with proper loading state management.
class TripsByDeviceNotifier extends AutoDisposeFamilyAsyncNotifier<List<Trip>, TripQuery> {
  bool _isLoading = false;
  bool _hasLoaded = false;
  TripQuery? _lastQuery;

  @override
  Future<List<Trip>> build(TripQuery arg) async {
    // Prevent multiple simultaneous fetches for the same query
    if (_isLoading && _lastQuery == arg) {
      debugPrint('[TripProviders] ⏸️ Already loading this query, returning current state');
      return state.valueOrNull ?? const <Trip>[];
    }

    // If we've already loaded this exact query, return cached data without refetching
    if (_hasLoaded && _lastQuery == arg && state.hasValue) {
      debugPrint('[TripProviders] ✅ Data already loaded for this query, skipping fetch');
      return state.valueOrNull ?? const <Trip>[];
    }

    _isLoading = true;
    _lastQuery = arg;

    try {
      final repo = ref.read(tripRepositoryProvider);

      // 1) Load from cache immediately if available
      final cached = await repo.getCachedTrips(arg.deviceId, arg.from, arg.to);
      if (cached.isNotEmpty) {
        debugPrint('[TripProviders] 🗄️ Loaded ${cached.length} trips from cache');
        _hasLoaded = true;
        _isLoading = false;
        return cached;
      }

      // 2) No cache: fetch from network
      final fetched = await repo.fetchTrips(
        deviceId: arg.deviceId,
        from: arg.from,
        to: arg.to,
      );
      debugPrint('[TripProviders] 🌐 Loaded ${fetched.length} trips from network');
      _hasLoaded = true;
      return fetched;
    } catch (e) {
      debugPrint('[TripProviders] ⚠️ Network fetch failed: $e');
      // Return empty list instead of throwing to prevent infinite error states
      return const <Trip>[];
    } finally {
      _isLoading = false;
    }
  }

  /// Manual refresh method for pull-to-refresh
  Future<void> refresh() async {
    if (_isLoading) {
      debugPrint('[TripProviders] ⏸️ Refresh skipped, already loading');
      return;
    }

    _isLoading = true;
    final repo = ref.read(tripRepositoryProvider);
    state = const AsyncLoading();
    
    try {
      final fetched = await repo.fetchTrips(
        deviceId: arg.deviceId,
        from: arg.from,
        to: arg.to,
      );
      debugPrint('[TripProviders] 🔄 Manual refresh: ${fetched.length} trips');
      state = AsyncData(fetched);
      _hasLoaded = true;
    } catch (e, st) {
      debugPrint('[TripProviders] ⚠️ Manual refresh failed: $e');
      state = AsyncError(e, st);
    } finally {
      _isLoading = false;
    }
  }
}

/// Family provider to fetch trips by device and date range.
final tripsByDeviceProvider =
    AutoDisposeAsyncNotifierProviderFamily<TripsByDeviceNotifier, List<Trip>, TripQuery>(
  TripsByDeviceNotifier.new,
);

/// Playback state for trip replay.
class TripPlaybackState {
  const TripPlaybackState(
      {this.tripId, this.isPlaying = false, this.progress = 0.0,});
  final String? tripId;
  final bool isPlaying;
  final double progress; // 0.0 - 1.0 timeline position

  TripPlaybackState copyWith(
          {String? tripId, bool? isPlaying, double? progress,}) =>
      TripPlaybackState(
        tripId: tripId ?? this.tripId,
        isPlaying: isPlaying ?? this.isPlaying,
        progress: progress ?? this.progress,
      );
}

class TripPlaybackNotifier extends StateNotifier<TripPlaybackState> {
  TripPlaybackNotifier() : super(const TripPlaybackState());

  void selectTrip(String id) => state = state.copyWith(tripId: id, progress: 0);
  void play() => state = state.copyWith(isPlaying: true);
  void pause() => state = state.copyWith(isPlaying: false);
  void seek(double p) => state = state.copyWith(progress: p.clamp(0.0, 1.0));
}

final tripPlaybackProvider =
    StateNotifierProvider.autoDispose<TripPlaybackNotifier, TripPlaybackState>(
        (ref) {
  return TripPlaybackNotifier();
});

/// Load positions for a trip (deviceId + time range), with diagnostics timing.
final tripPositionsProvider =
    FutureProvider.autoDispose.family<List<Position>, Trip>((ref, trip) async {
  final repo = ref.watch(tripRepositoryProvider);
  final sw = Stopwatch()..start();
  final positions = await repo.fetchTripPositions(
      deviceId: trip.deviceId, from: trip.startTime, to: trip.endTime,);
  sw.stop();
  // Record fetch+parse time to diagnostics for visibility
  DevDiagnostics.instance.recordClusterCompute(sw.elapsedMilliseconds);
  return positions;
});

/// Analytics provider (aggregates by day) for a given date range.
final tripAnalyticsProvider =
    FutureProvider.family<Map<String, TripAggregate>, DateTimeRange>(
        (ref, range) async {
  final repo = ref.watch(tripRepositoryProvider);
  final sw = Stopwatch()..start();
  final data = await repo.fetchAggregates(from: range.start, to: range.end);
  sw.stop();
  DevDiagnostics.instance.recordFilterCompute(sw.elapsedMilliseconds);
  return data;
});

/// Provider for persisted monthly snapshots
final tripSnapshotsProvider = FutureProvider<List<TripSnapshot>>((ref) async {
  final dao = await ref.watch(tripSnapshotsDaoProvider.future);
  final sw = Stopwatch()..start();
  final list = await dao.getAllSnapshots();
  sw.stop();
  DevDiagnostics.instance.recordFilterCompute(sw.elapsedMilliseconds);
  return list;
});

/// Derived provider: sorted snapshots for trends chart
final tripTrendsProvider = Provider<List<TripSnapshot>>((ref) {
  final sw = Stopwatch()..start();
  final snapshots = ref.watch(tripSnapshotsProvider).maybeWhen(
        data: List<TripSnapshot>.from,
        orElse: () => <TripSnapshot>[],
      );
  snapshots.sort((a, b) => a.monthKey.compareTo(b.monthKey));
  sw.stop();
  DevDiagnostics.instance.recordFilterCompute(sw.elapsedMilliseconds);
  return snapshots;
});

/// UI state: selected metric for trends chart
final tripTrendsMetricProvider =
    StateProvider<MetricType>((_) => MetricType.distance);

/// Debounced, cache-first trips list for the last 24h per device.
final tripListProvider =
    AutoDisposeAsyncNotifierProviderFamily<TripListNotifier, List<Trip>, int>(
  TripListNotifier.new,
);

class TripListNotifier extends AutoDisposeFamilyAsyncNotifier<List<Trip>, int> {
  Timer? _debounce;
  bool _isRefreshing = false;
  int get _deviceId => arg;

  @override
  Future<List<Trip>> build(int deviceId) async {
    ref.onDispose(() => _debounce?.cancel());

    final repo = ref.read(tripRepositoryProvider);
    final now = DateTime.now();
    final from = now.subtract(const Duration(hours: 24));
    final to = now;

    final cached = await repo.getCachedTrips(deviceId, from, to);
    if (cached.isNotEmpty) {
      debugPrint(
          '[TripProviders] 🗄️ Loaded ${cached.length} trips from cache',);
      state = AsyncData(_sortedUnique(cached));
    }

    // Debounced initial refresh after mount
    _debounce = Timer(const Duration(seconds: 3), () {
      _safeRefresh(silent: cached.isNotEmpty);
    });

    return _sortedUnique(cached);
  }

  Future<void> refresh({bool silent = true}) async =>
      _safeRefresh(silent: silent);

  Future<void> _safeRefresh({required bool silent}) async {
    if (_isRefreshing) {
      debugPrint('[TripProviders] ⏸️ Refresh skipped (already running)');
      return;
    }
    _isRefreshing = true;
    try {
      await _fetchNetworkAndMerge(silent: silent);
    } finally {
      _isRefreshing = false;
    }
  }

  Future<void> _fetchNetworkAndMerge({required bool silent}) async {
    final repo = ref.read(tripRepositoryProvider);
    final previous = state.valueOrNull ?? const <Trip>[];

    if (!silent) state = const AsyncLoading();

    final now = DateTime.now();
    final from = now.subtract(const Duration(hours: 24));
    final to = now;
    try {
      final fetched =
          await repo.fetchTrips(deviceId: _deviceId, from: from, to: to);
      debugPrint(
          '[TripProviders] 🌐 Refreshed ${fetched.length} trips from network',);
      final merged = _mergeById(previous, fetched);
      state = AsyncData(_sortedUnique(merged));
    } catch (e, st) {
      if (!silent) state = AsyncError(e, st);
      debugPrint('[TripProviders] ⚠️ Refresh failed: $e');
    }
  }

  List<Trip> _mergeById(List<Trip> a, List<Trip> b) {
    final map = {for (final t in a) t.id: t};
    for (final t in b) {
      map[t.id] = t;
    }
    return map.values.toList();
  }

  List<Trip> _sortedUnique(List<Trip> list) {
    final merged = _mergeById(const [], list);
    merged.sort((x, y) => y.endTime.compareTo(x.endTime));
    return merged;
  }
}
