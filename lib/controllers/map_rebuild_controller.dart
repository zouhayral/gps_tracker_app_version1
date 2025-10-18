import 'package:flutter/foundation.dart';

/// Controller for managing FlutterMap rebuild lifecycle
///
/// Purpose: Track when the map widget should rebuild vs when it should reuse
/// existing instances. This prevents unnecessary full rebuilds that cause jank.
///
/// Key concepts:
/// - Rebuild epoch: Monotonically increasing counter that changes only when
///   a full map rebuild is truly needed (e.g., base layer switch, major config change)
/// - Isolation: Marker updates, camera moves, and minor state changes do NOT
///   trigger epoch increments, keeping the map stable
///
/// Usage:
/// ```dart
/// final controller = MapRebuildController();
/// 
/// // Force full rebuild (e.g., on tile source switch)
/// controller.triggerRebuild();
/// 
/// // Reset to baseline (e.g., on map reset or app resume)
/// controller.reset();
/// 
/// // Listen for changes
/// controller.addListener(() {
///   print('Rebuild epoch: ${controller.epoch}');
/// });
/// ```
class MapRebuildController extends ChangeNotifier {
  int _epoch = 0;

  /// Current rebuild epoch
  /// 
  /// Increments each time triggerRebuild() is called.
  /// Used as part of FlutterMap's ValueKey to force widget reconstruction.
  int get epoch => _epoch;

  /// Trigger a full map rebuild
  /// 
  /// Call this ONLY when absolutely necessary:
  /// - Switching between tile sources (OSM ↔ Satellite)
  /// - Major configuration changes (max zoom, bounds, etc.)
  /// - Recovery from critical errors
  /// 
  /// DO NOT call for:
  /// - Marker updates (use MarkerLayer caching)
  /// - Camera movements (use MapController.move)
  /// - Tile refresh (handled by FMTC internally)
  void triggerRebuild() {
    _epoch++;
    if (kDebugMode) {
      debugPrint('[MapRebuildController] 🔄 Rebuild triggered, epoch: $_epoch');
    }
    notifyListeners();
  }

  /// Reset to baseline epoch
  /// 
  /// Useful when:
  /// - Resetting map state completely
  /// - App lifecycle events (resume from background)
  /// - Testing scenarios
  void reset() {
    if (_epoch != 0) {
      if (kDebugMode) {
        debugPrint('[MapRebuildController] 🔃 Reset from epoch $_epoch → 0');
      }
      _epoch = 0;
      notifyListeners();
    }
  }

  @override
  void dispose() {
    if (kDebugMode) {
      debugPrint('[MapRebuildController] 🗑️ Disposed at epoch $_epoch');
    }
    super.dispose();
  }
}
