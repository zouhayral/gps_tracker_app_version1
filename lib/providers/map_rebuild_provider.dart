import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Riverpod provider for map rebuild epoch
///
/// Manages a simple integer counter that increments whenever the map
/// needs a full rebuild (e.g., tile source switch, major config change).
///
/// This provider is watched by FlutterMapAdapter to construct a stable
/// ValueKey that changes ONLY when necessary, avoiding unnecessary
/// widget reconstructions.
///
/// Usage:
/// ```dart
/// // Watch the current epoch
/// final epoch = ref.watch(mapRebuildProvider);
/// 
/// // Trigger a rebuild
/// ref.read(mapRebuildProvider.notifier).trigger();
/// 
/// // Reset to baseline
/// ref.read(mapRebuildProvider.notifier).reset();
/// ```
final mapRebuildProvider =
    StateNotifierProvider<MapRebuildNotifier, int>((ref) {
  return MapRebuildNotifier();
});

/// StateNotifier managing map rebuild epoch
///
/// Starts at epoch 0 and increments on each trigger() call.
/// This provides a clean, testable way to control map lifecycle
/// through Riverpod's state management.
class MapRebuildNotifier extends StateNotifier<int> {
  MapRebuildNotifier() : super(0);

  /// Trigger a full map rebuild
  ///
  /// Increments the epoch, which will cause FlutterMap's ValueKey
  /// to change and force widget reconstruction.
  ///
  /// Call ONLY when necessary:
  /// - Tile source switching (OSM ↔ Satellite)
  /// - Major configuration changes
  /// - Error recovery scenarios
  void trigger() {
    state++;
  }

  /// Reset epoch to 0
  ///
  /// Useful for:
  /// - Testing scenarios
  /// - App lifecycle events
  /// - Complete map state reset
  void reset() {
    state = 0;
  }

  /// Get current epoch (for diagnostics)
  int get epoch => state;
}
