import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:my_app_gps/core/diagnostics/dev_diagnostics.dart';
import 'package:my_app_gps/data/models/position.dart';
import 'package:my_app_gps/data/models/trip.dart';
import 'package:my_app_gps/data/models/trip_aggregate.dart';
import 'package:my_app_gps/data/models/trip_snapshot.dart';
import 'package:my_app_gps/core/database/dao/trip_snapshots_dao.dart';
import 'package:my_app_gps/repositories/trip_repository.dart';
import 'package:my_app_gps/features/trips/analytics/widgets/trip_trends_chart.dart' show MetricType;

/// Simple query struct for requesting trips for a device and date range.
class TripQuery {
  const TripQuery({required this.deviceId, required this.from, required this.to});
  final int deviceId;
  final DateTime from;
  final DateTime to;
}

/// Family provider to fetch trips by device and date range.
final tripsByDeviceProvider = FutureProvider.autoDispose.family<List<Trip>, TripQuery>((ref, q) async {
  final repo = ref.watch(tripRepositoryProvider);

  // 1) Load from cache immediately if available
  final cached = await repo.getCachedTrips(q.deviceId, q.from, q.to);
  if (cached.isNotEmpty) {
    debugPrint('[TripProviders] 🗄️ Loaded ${cached.length} trips from cache');
    // Kick a background refresh; when done, invalidate this provider to update UI
    // ignore: discarded_futures
    Future(() async {
      try {
        final fetched = await repo.fetchTrips(deviceId: q.deviceId, from: q.from, to: q.to);
        if (fetched.isNotEmpty) {
          debugPrint('[TripProviders] 🌐 Refreshed ${fetched.length} trips from network');
          // Recompute this provider to surface fresh network data
          ref.invalidateSelf();
        }
      } catch (e) {
        debugPrint('[TripProviders] ⚠️ Network fetch failed: $e');
      }
    });
    return cached;
  }

  // 2) No cache: do network fetch and return
  try {
    final fetched = await repo.fetchTrips(deviceId: q.deviceId, from: q.from, to: q.to);
    if (fetched.isNotEmpty) {
      debugPrint('[TripProviders] 🌐 Loaded ${fetched.length} trips from network');
      return fetched;
    }
  } catch (e) {
    debugPrint('[TripProviders] ⚠️ Network fetch failed: $e');
  }

  // 3) Nothing found
  debugPrint('[TripProviders] ❌ No trips found (cache or network)');
  return const <Trip>[];
});

/// Playback state for trip replay.
class TripPlaybackState {
  const TripPlaybackState({this.tripId, this.isPlaying = false, this.progress = 0.0});
  final String? tripId;
  final bool isPlaying;
  final double progress; // 0.0 - 1.0 timeline position

  TripPlaybackState copyWith({String? tripId, bool? isPlaying, double? progress}) => TripPlaybackState(
        tripId: tripId ?? this.tripId,
        isPlaying: isPlaying ?? this.isPlaying,
        progress: progress ?? this.progress,
      );
}

class TripPlaybackNotifier extends StateNotifier<TripPlaybackState> {
  TripPlaybackNotifier() : super(const TripPlaybackState());

  void selectTrip(String id) => state = state.copyWith(tripId: id, progress: 0.0);
  void play() => state = state.copyWith(isPlaying: true);
  void pause() => state = state.copyWith(isPlaying: false);
  void seek(double p) => state = state.copyWith(progress: p.clamp(0.0, 1.0));
}

final tripPlaybackProvider = StateNotifierProvider.autoDispose<TripPlaybackNotifier, TripPlaybackState>((ref) {
  return TripPlaybackNotifier();
});

/// Load positions for a trip (deviceId + time range), with diagnostics timing.
final tripPositionsProvider = FutureProvider.autoDispose.family<List<Position>, Trip>((ref, trip) async {
  final repo = ref.watch(tripRepositoryProvider);
  final sw = Stopwatch()..start();
  final positions = await repo.fetchTripPositions(deviceId: trip.deviceId, from: trip.startTime, to: trip.endTime);
  sw.stop();
  // Record fetch+parse time to diagnostics for visibility
  DevDiagnostics.instance.recordClusterCompute(sw.elapsedMilliseconds);
  return positions;
});

/// Analytics provider (aggregates by day) for a given date range.
final tripAnalyticsProvider = FutureProvider.family<Map<String, TripAggregate>, DateTimeRange>((ref, range) async {
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
        data: (list) => List<TripSnapshot>.from(list),
        orElse: () => <TripSnapshot>[],
      );
  snapshots.sort((a, b) => a.monthKey.compareTo(b.monthKey));
  sw.stop();
  DevDiagnostics.instance.recordFilterCompute(sw.elapsedMilliseconds);
  return snapshots;
});

/// UI state: selected metric for trends chart
final tripTrendsMetricProvider = StateProvider<MetricType>((_) => MetricType.distance);
