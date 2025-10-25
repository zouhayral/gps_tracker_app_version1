import 'dart:async';
import 'dart:ui';
import 'package:flutter/widgets.dart';
import 'package:workmanager/workmanager.dart';
import 'package:logger/logger.dart';
import 'package:connectivity_plus/connectivity_plus.dart';

/// Task identifier for WorkManager
const String geofenceSyncTaskKey = 'geofence_sync_task';
const String geofenceSyncTaskId = 'geofence_sync_task_id';

/// Background callback dispatcher for WorkManager
/// 
/// This function runs in a separate isolate when WorkManager triggers the task.
/// It must be a top-level function (not inside a class) and marked with @pragma('vm:entry-point').
@pragma('vm:entry-point')
void callbackDispatcher() {
  Workmanager().executeTask((task, inputData) async {
    final log = Logger();
    
    log.i('[GeofenceSyncWorker] 🚀 Background task started: $task');
    log.d('[GeofenceSyncWorker] Input data: $inputData');

    try {
      // Ensure Flutter bindings are initialized
      WidgetsFlutterBinding.ensureInitialized();
      DartPluginRegistrant.ensureInitialized();

      // Check network connectivity
      final connectivity = Connectivity();
      final connectivityResults = await connectivity.checkConnectivity();
      
      final hasNetwork = connectivityResults.isNotEmpty &&
          !connectivityResults.every((result) => result == ConnectivityResult.none);

      if (!hasNetwork) {
        log.w('[GeofenceSyncWorker] ⏸️ No network available. Skipping sync.');
        return Future.value(true); // Task succeeded (will retry next time)
      }

      log.i('[GeofenceSyncWorker] 📶 Network available. Starting sync...');

      // Note: In a real implementation, you would need to properly initialize
      // your ObjectBox store and repositories here. This is a simplified
      // version that demonstrates the concept.
      // 
      // For production, consider:
      // 1. Initializing ObjectBox with proper path
      // 2. Creating repository instances directly
      // 3. Using dependency injection or service locator pattern
      
      final startTime = DateTime.now();
      
      log.i('[GeofenceSyncWorker] 📤 Syncing pending geofence events...');
      
      // TODO: Initialize ObjectBox and repositories properly in background isolate
      // Example:
      // final store = await openStore(directory: '<path>');
      // final eventRepo = GeofenceEventRepository(store);
      // final results = await eventRepo.syncPendingEvents();
      
      // Placeholder: Simulate sync
      await Future<void>.delayed(const Duration(seconds: 2));
      
      final endTime = DateTime.now();
      final duration = endTime.difference(startTime);

      log.i('[GeofenceSyncWorker] ✅ Sync completed in ${duration.inSeconds}s');
      log.d('[GeofenceSyncWorker] Next sync in ~15 minutes');

      return Future.value(true); // Task succeeded
    } catch (e, stackTrace) {
      log.e(
        '[GeofenceSyncWorker] ❌ Background task failed: $e',
        error: e,
        stackTrace: stackTrace,
      );
      
      // Return false to trigger retry with backoff
      return Future.value(false);
    }
  });
}
