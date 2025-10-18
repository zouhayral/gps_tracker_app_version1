import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_map_tile_caching/flutter_map_tile_caching.dart';
import 'package:my_app_gps/map/map_tile_providers.dart';

class FMTCInitializer {
  static Future<void> warmup({String store = 'main'}) async {
    WidgetsFlutterBinding.ensureInitialized();
    final stopwatch = Stopwatch()..start();
    try {
      // Use FMTCStore which is the project's canonical store wrapper.
      final storeObj = FMTCStore(store);
      await storeObj.manage.create();
      if (kDebugMode) debugPrint('[FMTC][WARMUP] Store "$store" created');
    } catch (e) {
      // Non-fatal: log and continue.
      debugPrint('[FMTC][WARMUP] failed: $e');
    } finally {
      stopwatch.stop();
      debugPrint(
          '[FMTC][WARMUP] Completed in ${stopwatch.elapsedMilliseconds}ms (attempted)',);
    }
  }

  /// Create/warm up FMTC stores for all provided tile sources.
  /// For each source with id=X, creates:
  /// - tiles_X (base tiles)
  /// - overlay_X (only if overlayUrlTemplate is not null)
  static Future<void> warmupStoresForSources(List<MapTileSource> sources) async {
    WidgetsFlutterBinding.ensureInitialized();
    for (final src in sources) {
      final baseStore = 'tiles_${src.id}';
      try {
        await FMTCStore(baseStore).manage.create();
        if (kDebugMode) {
          debugPrint('[FMTC][WARMUP] Store "$baseStore" created');
        }
      } catch (e) {
        debugPrint('[FMTC][WARMUP] "$baseStore" failed: $e');
      }

      if (src.overlayUrlTemplate != null) {
        final overlayStore = 'overlay_${src.id}';
        try {
          await FMTCStore(overlayStore).manage.create();
          if (kDebugMode) {
            debugPrint('[FMTC][WARMUP] Store "$overlayStore" created');
          }
        } catch (e) {
          debugPrint('[FMTC][WARMUP] "$overlayStore" failed: $e');
        }
      }
    }
  }
}
