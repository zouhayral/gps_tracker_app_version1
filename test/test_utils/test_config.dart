// Centralized test-only configuration for stable Flutter tests.
// Place this under `test/` so test-only APIs (e.g., SharedPreferences mock) are allowed.
//
// Provides helpers to:
// - Disable map tile loading in widget tests (avoid network I/O)
// - Detect ObjectBox native library availability for DAO tests
// - Initialize Hive and SharedPreferences in memory
//
// Usage in tests:
//   import 'test_utils/test_config.dart';
//
//   void main() {
//     setUpAll(() async {
//       await setupTestEnvironment();
//     });
//     ...
//   }

import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:hive/hive.dart' as hive;
// Adapter import for toggling tiles
import 'package:my_app_gps/features/map/view/flutter_map_adapter.dart';
// ObjectBox imports to check availability
import 'package:my_app_gps/objectbox.g.dart';
// Including this ensures native libs are bundled for Flutter tests when available.
// ignore: unused_import
import 'package:objectbox_flutter_libs/objectbox_flutter_libs.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:my_app_gps/core/utils/shared_prefs_holder.dart';
import 'package:my_app_gps/services/websocket_manager.dart';
import 'package:my_app_gps/services/websocket_manager_enhanced.dart'
    as ws_enhanced;
import 'package:my_app_gps/core/services/network_connectivity_monitor.dart'
    as netmon;
import 'package:my_app_gps/core/data/vehicle_data_repository.dart' as repo;

/// Disable map tiles/network in widget tests to prevent HTTP traffic and flakiness.
void disableMapTilesForTests() {
  WidgetsFlutterBinding.ensureInitialized();
  FlutterMapAdapterState.kDisableTilesForTests = true;
}

/// Attempt to open an ObjectBox store in a temp directory.
/// Returns true if native libs are available and store opened successfully.
Future<bool> _canOpenObjectBoxStore() async {
  try {
    final dir = await Directory.systemTemp.createTemp('obx_check_');
    final store = await openStore(directory: dir.path);
    store.close();
    await dir.delete(recursive: true);
    return true;
  } catch (_) {
    return false;
  }
}

/// Global flag set during setup to indicate if ObjectBox is available.
bool objectBoxAvailableForTests = false;

/// Compute and store whether ObjectBox native libs are available for tests.
Future<void> skipObjectBoxTestsIfUnavailable() async {
  objectBoxAvailableForTests = await _canOpenObjectBoxStore();
  if (!objectBoxAvailableForTests) {
    // ignore: avoid_print
    print('SKIP: ObjectBox native library not available on this environment');
  }
}

/// Initialize Hive and SharedPreferences for tests.
/// - Hive: initialize to a temp directory
/// - SharedPreferences: use in-memory test instance
Future<void> mockHiveAndPrefsForTests() async {
  final dir = await Directory.systemTemp.createTemp('hive_test_');
  hive.Hive.init(dir.path);
  SharedPreferences.setMockInitialValues(<String, Object>{});
  final prefs = await SharedPreferences.getInstance();
  SharedPrefsHolder.set(prefs);
}

/// One-shot test environment setup for all tests.
Future<void> setupTestEnvironment() async {
  disableMapTilesForTests();
  await mockHiveAndPrefsForTests();
  await skipObjectBoxTestsIfUnavailable();

  // Ensure WebSocketManager test mode so it doesn't throw unimplemented mocks
  WebSocketManager.testMode = true;
  // Disable enhanced WS auto-connect in tests by default
  ws_enhanced.WebSocketManagerEnhanced.testMode = true;
  // Disable background timers that cause pending timers in widget tests
  netmon.NetworkConnectivityMonitor.testMode = true;
  repo.VehicleDataRepository.testMode = true;
}
