import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:my_app_gps/core/data/vehicle_data_repository.dart';

/// Provider for the background sync service singleton
final backgroundSyncServiceProvider = Provider<BackgroundSyncService>((ref) {
  final repository = ref.watch(vehicleDataRepositoryProvider);

  final service = BackgroundSyncService(repository: repository);

  ref.onDispose(service.dispose);

  return service;
});

/// Background sync statistics
class BackgroundSyncStats {
  int totalExecutions = 0;
  int successfulExecutions = 0;
  int failedExecutions = 0;
  DateTime? lastExecution;
  DateTime? lastSuccessfulExecution;
  Duration? lastExecutionDuration;
  List<DateTime> executionHistory = [];

  Map<String, dynamic> toJson() {
    return {
      'totalExecutions': totalExecutions,
      'successfulExecutions': successfulExecutions,
      'failedExecutions': failedExecutions,
      'lastExecution': lastExecution?.toIso8601String(),
      'lastSuccessfulExecution': lastSuccessfulExecution?.toIso8601String(),
      'lastExecutionDuration': lastExecutionDuration?.inMilliseconds,
      'executionCount': executionHistory.length,
    };
  }
}

/// Lightweight periodic sync service for background mode
///
/// **Current Implementation:**
/// Uses simple Timer-based scheduling for background sync.
///
/// **Production Upgrade Paths:**
///
/// **Android:**
/// ```yaml
/// dependencies:
///   workmanager: ^0.5.2
/// ```
///
/// **iOS:**
/// ```yaml
/// dependencies:
///   background_fetch: ^1.3.0
/// ```
///
/// **Android WorkManager Integration:**
/// ```dart
/// import 'package:workmanager/workmanager.dart';
///
/// void callbackDispatcher() {
///   Workmanager().executeTask((task, inputData) async {
///     // Initialize repository in background isolate
///     final repository = await initRepository();
///     await repository.refreshAll();
///     return true;
///   });
/// }
///
/// // In main():
/// await Workmanager().initialize(callbackDispatcher, isInDebugMode: kDebugMode);
///
/// // Register periodic task:
/// await Workmanager().registerPeriodicTask(
///   "vehicle-sync",
///   "vehicleDataSync",
///   frequency: Duration(minutes: 15), // Minimum 15 minutes on Android
///   constraints: Constraints(
///     networkType: NetworkType.connected,
///     requiresBatteryNotLow: true,
///   ),
/// );
/// ```
///
/// **iOS BGAppRefreshTask Integration:**
/// ```dart
/// import 'package:background_fetch/background_fetch.dart';
///
/// // In main() or app initialization:
/// BackgroundFetch.configure(
///   BackgroundFetchConfig(
///     minimumFetchInterval: 15, // Minutes
///     stopOnTerminate: false,
///     enableHeadless: true,
///     requiresBatteryNotLow: true,
///     requiresCharging: false,
///     requiresStorageNotLow: false,
///     requiresDeviceIdle: false,
///     requiredNetworkType: NetworkType.ANY,
///   ),
///   (String taskId) async {
///     // Background sync callback
///     final repository = await initRepository();
///     await repository.refreshAll();
///     BackgroundFetch.finish(taskId);
///   },
///   (String taskId) async {
///     // Timeout callback
///     BackgroundFetch.finish(taskId);
///   },
/// );
///
/// // Info.plist configuration:
/// // <key>BGTaskSchedulerPermittedIdentifiers</key>
/// // <array>
/// //   <string>com.transistorsoft.fetch</string>
/// // </array>
/// ```
///
/// **Isolate-based Execution (Advanced):**
/// ```dart
/// import 'dart:isolate';
///
/// Future<void> _executeOnIsolate() async {
///   final receivePort = ReceivePort();
///   await Isolate.spawn(_isolateEntry, receivePort.sendPort);
///
///   final sendPort = await receivePort.first as SendPort;
///   final resultPort = ReceivePort();
///   sendPort.send(resultPort.sendPort);
///
///   final result = await resultPort.first;
///   debugPrint('[BackgroundSync] Isolate result: $result');
/// }
///
/// void _isolateEntry(SendPort sendPort) async {
///   // Initialize repository in isolate
///   final repository = await initRepository();
///   await repository.refreshAll();
///   sendPort.send({'success': true});
/// }
/// ```
class BackgroundSyncService {
  BackgroundSyncService({required this.repository});

  final VehicleDataRepository repository;

  // Configuration
  static const _backgroundSyncInterval = Duration(minutes: 15);
  static const _maxExecutionHistory = 20;

  // State
  Timer? _syncTimer;
  bool _isEnabled = false;
  bool _isExecuting = false;

  // Statistics
  final BackgroundSyncStats _stats = BackgroundSyncStats();
  BackgroundSyncStats get stats => _stats;

  /// Enable background sync
  ///
  /// Note: Current implementation uses simple Timer. For production:
  /// - Android: Use WorkManager for battery-efficient scheduling
  /// - iOS: Use BGAppRefreshTask for system-managed scheduling
  void enable() {
    if (_isEnabled) return;

    _isEnabled = true;

    if (kDebugMode) {
      debugPrint(
        '[BackgroundSync] 🔄 Enabled with ${_backgroundSyncInterval.inMinutes}min interval\n'
        'ℹ️ For production: Migrate to WorkManager (Android) or background_fetch (iOS)',
      );
    }

    // Start periodic sync
    _scheduleSyncTimer();
  }

  /// Disable background sync
  void disable() {
    if (!_isEnabled) return;

    _isEnabled = false;
    _syncTimer?.cancel();
    _syncTimer = null;

    if (kDebugMode) {
      debugPrint('[BackgroundSync] ⏸️ Disabled');
    }
  }

  /// Dispose service
  void dispose() {
    disable();
  }

  /// Execute background sync immediately (for testing)
  Future<bool> executeNow() async {
    if (_isExecuting) {
      if (kDebugMode) {
        debugPrint('[BackgroundSync] ⏭️ Skipping - already executing');
      }
      return false;
    }

    return _executeSync();
  }

  // ---------- Internal Methods ----------

  void _scheduleSyncTimer() {
    _syncTimer?.cancel();

    if (!_isEnabled) return;

    _syncTimer = Timer.periodic(_backgroundSyncInterval, (_) {
      _executeSync();
    });
  }

  Future<bool> _executeSync() async {
    if (_isExecuting) return false;

    _isExecuting = true;
    _stats.totalExecutions++;
    _stats.lastExecution = DateTime.now();

    final startTime = DateTime.now();
    var success = false;

    try {
      if (kDebugMode) {
        debugPrint('[BackgroundSync] 🔄 Starting sync...');
      }

  // Execute sync on main isolate (for now)
  // TODO(zouhayral): For production, use Isolate.spawn() or WorkManager
      await repository.refreshAll();

      success = true;
      _stats.successfulExecutions++;
      _stats.lastSuccessfulExecution = DateTime.now();

      final duration = DateTime.now().difference(startTime);
      _stats.lastExecutionDuration = duration;

      if (kDebugMode) {
        debugPrint(
          '[BackgroundSync] ✅ Sync completed in ${duration.inMilliseconds}ms',
        );
      }
    } catch (e, st) {
      _stats.failedExecutions++;

      if (kDebugMode) {
        debugPrint('[BackgroundSync] ❌ Sync failed: $e');
        debugPrint(st.toString());
      }
    } finally {
      _isExecuting = false;

      // Track execution history
      _stats.executionHistory.add(DateTime.now());
      if (_stats.executionHistory.length > _maxExecutionHistory) {
        _stats.executionHistory.removeAt(0);
      }
    }

    return success;
  }
}

/// Production WorkManager setup guide (Android)
///
/// **Step 1: Add dependency**
/// ```yaml
/// dependencies:
///   workmanager: ^0.5.2
/// ```
///
/// **Step 2: Create callback dispatcher**
/// ```dart
/// // lib/background/work_manager_callback.dart
/// import 'package:workmanager/workmanager.dart';
///
/// @pragma('vm:entry-point')
/// void callbackDispatcher() {
///   Workmanager().executeTask((task, inputData) async {
///     debugPrint('[WorkManager] Task: $task');
///
///     try {
///       // Initialize necessary services
///       final repository = VehicleDataRepository(/* ... */);
///       await repository.refreshAll();
///
///       return true; // Success
///     } catch (e) {
///       debugPrint('[WorkManager] Task failed: $e');
///       return false; // Retry
///     }
///   });
/// }
/// ```
///
/// **Step 3: Initialize in main()**
/// ```dart
/// void main() async {
///   WidgetsFlutterBinding.ensureInitialized();
///
///   await Workmanager().initialize(
///     callbackDispatcher,
///     isInDebugMode: kDebugMode,
///   );
///
///   runApp(MyApp());
/// }
/// ```
///
/// **Step 4: Register periodic task**
/// ```dart
/// await Workmanager().registerPeriodicTask(
///   "vehicle-sync-task",
///   "vehicleDataPeriodicSync",
///   frequency: Duration(minutes: 15), // Minimum 15 min
///   constraints: Constraints(
///     networkType: NetworkType.connected,
///     requiresBatteryNotLow: true,
///     requiresCharging: false,
///     requiresDeviceIdle: false,
///     requiresStorageNotLow: false,
///   ),
///   backoffPolicy: BackoffPolicy.exponential,
///   backoffPolicyDelay: Duration(minutes: 5),
/// );
/// ```
///
/// **Step 5: AndroidManifest.xml permissions**
/// ```xml
/// <uses-permission android:name="android.permission.WAKE_LOCK" />
/// <uses-permission android:name="android.permission.RECEIVE_BOOT_COMPLETED"/>
/// ```

/// Production BGAppRefreshTask setup guide (iOS)
///
/// **Step 1: Add dependency**
/// ```yaml
/// dependencies:
///   background_fetch: ^1.3.0
/// ```
///
/// **Step 2: Configure in main()**
/// ```dart
/// import 'package:background_fetch/background_fetch.dart';
///
/// void main() async {
///   WidgetsFlutterBinding.ensureInitialized();
///
///   // Configure background fetch
///   await BackgroundFetch.configure(
///     BackgroundFetchConfig(
///       minimumFetchInterval: 15, // Minutes
///       stopOnTerminate: false,
///       startOnBoot: true,
///       enableHeadless: true,
///       requiresBatteryNotLow: true,
///       requiresCharging: false,
///       requiresStorageNotLow: false,
///       requiresDeviceIdle: false,
///       requiredNetworkType: NetworkType.ANY,
///     ),
///     _onBackgroundFetch,
///     _onBackgroundFetchTimeout,
///   );
///
///   runApp(MyApp());
/// }
///
/// @pragma('vm:entry-point')
/// void _onBackgroundFetch(String taskId) async {
///   debugPrint('[BGFetch] Task: $taskId');
///
///   try {
///     final repository = VehicleDataRepository(/* ... */);
///     await repository.refreshAll();
///     BackgroundFetch.finish(taskId);
///   } catch (e) {
///     BackgroundFetch.finish(taskId);
///   }
/// }
///
/// @pragma('vm:entry-point')
/// void _onBackgroundFetchTimeout(String taskId) {
///   debugPrint('[BGFetch] Timeout: $taskId');
///   BackgroundFetch.finish(taskId);
/// }
/// ```
///
/// **Step 3: Info.plist configuration**
/// ```xml
/// <key>UIBackgroundModes</key>
/// <array>
///   <string>fetch</string>
///   <string>processing</string>
/// </array>
///
/// <key>BGTaskSchedulerPermittedIdentifiers</key>
/// <array>
///   <string>com.transistorsoft.fetch</string>
/// </array>
/// ```
///
/// **Step 4: Schedule tasks**
/// ```dart
/// // One-time task
/// await BackgroundFetch.scheduleTask(TaskConfig(
///   taskId: "vehicle-sync-once",
///   delay: 60000, // 1 minute
///   periodic: false,
///   forceAlarmManager: false,
///   stopOnTerminate: false,
///   enableHeadless: true,
/// ));
/// ```
