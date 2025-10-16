import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_map_tile_caching/flutter_map_tile_caching.dart';

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
      debugPrint('[FMTC][WARMUP] Completed in ${stopwatch.elapsedMilliseconds}ms (attempted)');
    }
  }
}
