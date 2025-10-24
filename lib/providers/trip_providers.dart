import 'dart:async';

import 'package:dio/dio.dart' show CancelToken;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:my_app_gps/core/database/dao/trip_snapshots_dao.dart';
import 'package:my_app_gps/core/diagnostics/dev_diagnostics.dart';
import 'package:my_app_gps/data/models/position.dart';
import 'package:my_app_gps/data/models/trip.dart';
import 'package:my_app_gps/data/models/trip_snapshot.dart';
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

// ============================================================================
// LIFECYCLE-AWARE OPTIMIZED TRIPS PROVIDER
// ============================================================================

/// State model for lifecycle-aware trips provider
@immutable
class TripsState {
  const TripsState({
    this.trips = const [],
    this.isLoading = false,
    this.hasError = false,
    this.lastUpdated,
    this.errorMessage,
  });

  final List<Trip> trips;
  final bool isLoading;
  final bool hasError;
  final DateTime? lastUpdated;
  final String? errorMessage;

  /// Check if cached data is still fresh (< 2 minutes old)
  bool get isFresh {
    if (lastUpdated == null) return false;
    return DateTime.now().difference(lastUpdated!) < const Duration(minutes: 2);
  }

  TripsState copyWith({
    List<Trip>? trips,
    bool? isLoading,
    bool? hasError,
    DateTime? lastUpdated,
    String? errorMessage,
  }) {
    return TripsState(
      trips: trips ?? this.trips,
      isLoading: isLoading ?? this.isLoading,
      hasError: hasError ?? this.hasError,
      lastUpdated: lastUpdated ?? this.lastUpdated,
      errorMessage: errorMessage ?? this.errorMessage,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is TripsState &&
          runtimeType == other.runtimeType &&
          trips.length == other.trips.length &&
          isLoading == other.isLoading &&
          hasError == other.hasError &&
          lastUpdated == other.lastUpdated;

  @override
  int get hashCode =>
      trips.length.hashCode ^
      isLoading.hashCode ^
      hasError.hashCode ^
      lastUpdated.hashCode;
}

/// Lifecycle-aware trips provider with caching, throttling, and resilient fetch logic
class LifecycleAwareTripsNotifier
    extends AutoDisposeFamilyAsyncNotifier<TripsState, TripQuery> {
  bool _isFetching = false;
  Future<void>? _ongoingFetch;
  CancelToken? _cancelToken;
  AppLifecycleListener? _lifecycleListener;
  bool _isDisposed = false;
  bool _isPaused = false;

  @override
  Future<TripsState> build(TripQuery query) async {
    // Setup lifecycle listener
    _setupLifecycleListener();

    // Setup disposal cleanup
    ref.onDispose(() {
      debugPrint('[TripsProvider] 🗑️ Disposing provider for device ${query.deviceId}');
      _isDisposed = true;
      _cancelToken?.cancel('Provider disposed');
      _lifecycleListener?.dispose();
    });

    // Initial load: cache-first, then background refresh
    return _initialLoad(query);
  }

  void _setupLifecycleListener() {
    _lifecycleListener = AppLifecycleListener(
      onResume: () {
        if (!_isDisposed) {
          debugPrint('[TripsProvider] 📱 App resumed, refreshing if stale');
          _isPaused = false;
          refreshIfStale();
        }
      },
      onInactive: () {
        if (!_isDisposed) {
          debugPrint('[TripsProvider] 📱 App inactive, pausing fetches');
          _isPaused = true;
        }
      },
      onPause: () {
        if (!_isDisposed) {
          debugPrint('[TripsProvider] 📱 App paused, cancelling ongoing fetch');
          _isPaused = true;
          _cancelToken?.cancel('App paused');
        }
      },
    );
  }

  Future<TripsState> _initialLoad(TripQuery query) async {
    final repo = ref.read(tripRepositoryProvider);
    final sw = Stopwatch()..start();

    try {
      // 1. Try to load from cache first (instant return)
      final cached = await repo.getCachedTrips(
        query.deviceId,
        query.from,
        query.to,
      );

      if (cached.isNotEmpty) {
        sw.stop();
        debugPrint(
          '[TripsProvider] 🗄️ Loaded ${cached.length} trips from cache in ${sw.elapsedMilliseconds}ms',
        );

        final initialState = TripsState(
          trips: cached,
          lastUpdated: DateTime.now(),
        );

        // Schedule background refresh
        Future.microtask(() => _backgroundRefresh(query));

        return initialState;
      }

      // 2. No cache: fetch from network
      debugPrint('[TripsProvider] 🌐 No cache, fetching from network...');
      final trips = await _fetchFromNetwork(query, repo);
      sw.stop();

      debugPrint(
        '[TripsProvider] ✅ Loaded ${trips.length} trips from network in ${sw.elapsedMilliseconds}ms',
      );

      return TripsState(
        trips: trips,
        lastUpdated: DateTime.now(),
      );
    } catch (e, st) {
      sw.stop();
      debugPrint('[TripsProvider] ⚠️ Initial load failed: $e');
      debugPrint(st.toString());

      return TripsState(
        isLoading: false,
        hasError: true,
        errorMessage: e.toString(),
      );
    }
  }

  Future<void> _backgroundRefresh(TripQuery query) async {
    if (_isDisposed || _isPaused) return;

    final currentState = state.valueOrNull;
    if (currentState?.isFresh ?? false) {
      debugPrint('[TripsProvider] ✨ Cache still fresh, skipping background refresh');
      return;
    }

    await refreshIfStale();
  }

  /// Fetch trips from network with lifecycle checks
  Future<List<Trip>> _fetchFromNetwork(TripQuery query, TripRepository repo) async {
    if (_isDisposed) {
      debugPrint('[TripsProvider] ⏸️ Fetch aborted: provider disposed');
      return const [];
    }

    if (_isPaused) {
      debugPrint('[TripsProvider] ⏸️ Fetch aborted: app paused');
      return const [];
    }

    _cancelToken = CancelToken();

    try {
      final trips = await repo.fetchTrips(
        deviceId: query.deviceId,
        from: query.from,
        to: query.to,
        cancelToken: _cancelToken,
      );
      return trips;
    } finally {
      _cancelToken = null;
    }
  }

  /// Refresh trips if cache is stale (> 2 minutes old)
  Future<void> refreshIfStale() async {
    if (_isDisposed || _isPaused) {
      debugPrint('[TripsProvider] ⏸️ Refresh skipped: ${_isDisposed ? "disposed" : "paused"}');
      return;
    }

    final currentState = state.valueOrNull;
    if (currentState?.isFresh ?? false) {
      debugPrint('[TripsProvider] ✨ Cache still fresh (age: ${DateTime.now().difference(currentState!.lastUpdated!).inSeconds}s), skipping refresh');
      return;
    }

    await refresh(silent: currentState?.trips.isNotEmpty ?? false);
  }

  /// Force refresh trips from network
  Future<void> refresh({bool silent = false}) async {
    // Prevent concurrent fetches
    if (_isFetching) {
      debugPrint('[TripsProvider] ⏸️ Refresh skipped: already fetching');
      return _ongoingFetch ?? Future.value();
    }

    if (_isDisposed) {
      debugPrint('[TripsProvider] ⏸️ Refresh skipped: provider disposed');
      return;
    }

    if (_isPaused) {
      debugPrint('[TripsProvider] ⏸️ Refresh skipped: app paused');
      return;
    }

    _isFetching = true;
    final query = arg;
    final repo = ref.read(tripRepositoryProvider);
    final sw = Stopwatch()..start();

    // Store current state as fallback
    final previousState = state.valueOrNull;

    _ongoingFetch = Future(() async {
      try {
        // Update state to loading (unless silent)
        if (!silent) {
          final loadingState = previousState?.copyWith(isLoading: true) ??
              const TripsState(isLoading: true);
          state = AsyncData(loadingState);
        }

        debugPrint('[TripsProvider] ⏳ Fetching trips for device ${query.deviceId}...');

        final trips = await _fetchFromNetwork(query, repo);
        sw.stop();

        if (_isDisposed) {
          debugPrint('[TripsProvider] ⏸️ Fetch completed but provider disposed, discarding result');
          return;
        }

        // Check if data actually changed
        final dataChanged = previousState == null ||
            previousState.trips.length != trips.length ||
            !_areTripsEqual(previousState.trips, trips);

        if (dataChanged) {
          debugPrint(
            '[TripsProvider] ✅ Loaded ${trips.length} trips from network in ${sw.elapsedMilliseconds}ms',
          );
          DevDiagnostics.instance.recordFilterCompute(sw.elapsedMilliseconds);

          state = AsyncData(
            TripsState(
              trips: trips,
              lastUpdated: DateTime.now(),
            ),
          );
        } else {
          debugPrint('[TripsProvider] ✨ Data unchanged, skipping notification');
          // Update lastUpdated but don't trigger rebuild
          state = AsyncData(previousState.copyWith(
            isLoading: false,
            lastUpdated: DateTime.now(),
          ),);
        }
      } catch (e) {
        sw.stop();
        debugPrint('[TripsProvider] ⚠️ Fetch failed after ${sw.elapsedMilliseconds}ms: $e');

        if (_isDisposed) return;

        // Resilient fallback: keep previous data if available
        if (previousState != null && previousState.trips.isNotEmpty) {
          debugPrint('[TripsProvider] 🔄 Reverting to cached data (${previousState.trips.length} trips)');
          state = AsyncData(
            previousState.copyWith(
              isLoading: false,
              hasError: true,
              errorMessage: e.toString(),
            ),
          );
        } else {
          state = AsyncData(
            TripsState(
              isLoading: false,
              hasError: true,
              errorMessage: e.toString(),
            ),
          );
        }
      } finally {
        _isFetching = false;
        _ongoingFetch = null;
      }
    });

    return _ongoingFetch;
  }

  /// Compare trips lists for equality (by id and basic properties)
  bool _areTripsEqual(List<Trip> a, List<Trip> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i].id != b[i].id ||
          a[i].startTime != b[i].startTime ||
          a[i].endTime != b[i].endTime) {
        return false;
      }
    }
    return true;
  }

  /// Retry last failed fetch
  Future<void> retry() async {
    debugPrint('[TripsProvider] 🔄 Retrying failed fetch...');
    await refresh();
  }
}

/// Lifecycle-aware trips provider - optimized with caching, throttling, and resilience
final lifecycleAwareTripsProvider = AutoDisposeAsyncNotifierProviderFamily<
    LifecycleAwareTripsNotifier, TripsState, TripQuery>(
  LifecycleAwareTripsNotifier.new,
);
