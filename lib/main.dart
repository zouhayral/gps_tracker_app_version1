import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_map_tile_caching/flutter_map_tile_caching.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:my_app_gps/app/app_root.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // Limit global image cache to reduce memory pressure on low-end devices.
  try {
    PaintingBinding.instance.imageCache.maximumSizeBytes = 50 << 20; // ~50MB
    PaintingBinding.instance.imageCache.maximumSize = 200; // optional object count limit
    // ignore: avoid_print
    print('[IMAGES] ImageCache limits set: maxBytes=50MB, maxCount=200');
  } catch (e) {
    // ignore: avoid_print
    print('[IMAGES][WARN] Failed to set ImageCache limits: $e');
  }
  // Init Hive (for DAO persistence)
  try {
    await Hive.initFlutter();
  } catch (e) {
    // ignore: avoid_print
    print('Hive init failed or already initialized: $e');
  }
  // Initialize tile caching (FMTC) with platform-appropriate backend
  try {
    // [FMTC][INIT] Begin
    // ignore: avoid_print
    print(
      '[FMTC][INIT] Starting initialisation... (platform: ${kIsWeb ? 'web' : 'io'})',
    );
    if (!kIsWeb) {
      await FMTCObjectBoxBackend().initialise();
      // ignore: avoid_print
      print('[FMTC][INIT] ObjectBox backend initialised');
    } else {
      // On web, rely on FMTC default web backend (e.g., IndexedDB) if available.
      // ignore: avoid_print
      print(
        "[FMTC][INIT] Web platform detected; using FMTC's default web backend",
      );
    }
    await const FMTCStore('main').manage.create();
  // ignore: avoid_print
  print("[FMTC][INIT] Store 'main' created and ready");
  // Confirm global init for diagnostic clarity
  debugPrint('[FMTC][INIT] Initialized globally in main.dart');
  } catch (e) {
    // ignore: avoid_print
    print('[FMTC][ERROR] FMTC init failed (${e.runtimeType}): $e');
    // Continue without tile caching (map will still work without disk cache)
  }
  // Capture framework errors and avoid giant solid red rectangles.
  FlutterError.onError = (FlutterErrorDetails details) {
    FlutterError.presentError(details);
    // ignore: avoid_print
    print('FlutterError: ${details.exceptionAsString()}');
  };
  ErrorWidget.builder = (FlutterErrorDetails d) {
    // Compact inline error widget instead of full red screen.
    return Center(
      child: Card(
        color: Colors.red.shade700,
        margin: const EdgeInsets.all(16),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Text(
            'UI error: ${d.exception}\nTap back or continue.',
            style: const TextStyle(color: Colors.white, fontSize: 12),
            textAlign: TextAlign.center,
          ),
        ),
      ),
    );
  };
  runApp(
    const ProviderScope(
      child: MaterialApp(home: AppRoot(), debugShowCheckedModeBanner: false),
    ),
  );
}

// MyApp is no longer used since we mount AppRoot via MaterialApp(home: ...)
