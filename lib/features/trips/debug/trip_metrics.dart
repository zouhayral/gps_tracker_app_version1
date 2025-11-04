import 'package:flutter_riverpod/flutter_riverpod.dart';

class TripPerfSample {
  final DateTime timestamp;
  final double parseDurationMs;
  final int cacheHits;
  final int cacheMisses;
  final int reuse;
  const TripPerfSample({
    required this.timestamp,
    required this.parseDurationMs,
    required this.cacheHits,
    required this.cacheMisses,
    required this.reuse,
  });
}

/// Riverpod state provider holding the last N (<=60) performance samples.
final tripPerfTimelineProvider = StateProvider<List<TripPerfSample>>(
  (ref) => const <TripPerfSample>[],
);
