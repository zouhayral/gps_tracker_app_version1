import 'dart:async';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:logger/logger.dart';
import 'package:my_app_gps/data/repositories/geofence_event_repository.dart';
import 'package:my_app_gps/features/geofencing/providers/geofence_providers.dart' as geofence_providers;

/// Provider for SyncReplayService
/// 
/// Await repository initialization before creating service.
/// This service is auto-disposed when the provider is no longer needed.
/// Call `ref.watch(syncReplayServiceProvider)` in app startup to initialize.
final syncReplayServiceProvider =
    FutureProvider.autoDispose<SyncReplayService>((ref) async {
  // Await repository initialization before creating service
  final repo = await ref.watch(
    geofence_providers.geofenceEventRepositoryProvider.future,
  );
  final service = SyncReplayService(repo);
  ref.onDispose(service.dispose);
  service.start();
  return service;
});

/// Provider for tracking sync status
/// 
/// UI can watch this to display sync progress indicators.
final syncStatusProvider =
    StateProvider.autoDispose<SyncStatus>((ref) => SyncStatus.idle());

/// Model class for tracking sync status
/// 
/// Provides information about ongoing and completed sync operations.
class SyncStatus {
  final bool syncing;
  final DateTime? lastSync;
  final int? syncedCount;
  final int? failedCount;
  final String? error;

  const SyncStatus({
    required this.syncing,
    this.lastSync,
    this.syncedCount,
    this.failedCount,
    this.error,
  });

  factory SyncStatus.idle() => const SyncStatus(syncing: false);

  factory SyncStatus.syncing() => const SyncStatus(syncing: true);

  factory SyncStatus.success({
    required int syncedCount,
    required int failedCount,
  }) {
    return SyncStatus(
      syncing: false,
      lastSync: DateTime.now(),
      syncedCount: syncedCount,
      failedCount: failedCount,
    );
  }

  factory SyncStatus.error(String error) {
    return SyncStatus(
      syncing: false,
      error: error,
    );
  }

  SyncStatus copyWith({
    bool? syncing,
    DateTime? lastSync,
    int? syncedCount,
    int? failedCount,
    String? error,
  }) {
    return SyncStatus(
      syncing: syncing ?? this.syncing,
      lastSync: lastSync ?? this.lastSync,
      syncedCount: syncedCount ?? this.syncedCount,
      failedCount: failedCount ?? this.failedCount,
      error: error ?? this.error,
    );
  }

  @override
  String toString() {
    if (error != null) return 'SyncStatus.error($error)';
    if (syncing) return 'SyncStatus.syncing()';
    if (lastSync != null) {
      return 'SyncStatus.success(synced: $syncedCount, failed: $failedCount, time: $lastSync)';
    }
    return 'SyncStatus.idle()';
  }
}

/// Service for automatic network recovery and event replay
/// 
/// This service monitors network connectivity and automatically syncs
/// pending geofence events when connectivity is restored.
/// 
/// Features:
/// - Automatic sync on network recovery (offline → online)
/// - Periodic sync every 5 minutes (when online)
/// - Resilient to connection failures
/// - No user interaction needed
/// - Extensible for Firestore/REST API integration
/// 
/// Usage:
/// ```dart
/// // In app startup (main.dart or app_root.dart):
/// final syncService = ref.read(syncReplayServiceProvider);
/// ```
class SyncReplayService {
  final GeofenceEventRepository _repo;
  final _log = Logger();
  final _connectivity = Connectivity();
  StreamSubscription<List<ConnectivityResult>>? _sub;
  bool _isOnline = true;
  Timer? _periodicTimer;
  bool _disposed = false;

  SyncReplayService(this._repo);

  /// Start monitoring connectivity and periodic checks
  void start() {
    if (_disposed) {
      _log.w('[SyncReplayService] Cannot start - service is disposed');
      return;
    }

    _log.i('[SyncReplayService] 🚀 Starting SyncReplayService...');
    
    // Subscribe to connectivity changes
    _sub = _connectivity.onConnectivityChanged.listen(
      _onConnectivityChanged,
      onError: (Object error) {
        _log.e('[SyncReplayService] ❌ Connectivity subscription error: $error');
      },
    );

    // Start periodic sync timer (every 5 minutes)
    _periodicTimer = Timer.periodic(
      const Duration(minutes: 5),
      (_) => _attemptSync(),
    );

    // Initial sync attempt
    _attemptSync();
  }

  /// Handle connectivity changes
  Future<void> _onConnectivityChanged(List<ConnectivityResult> results) async {
    if (_disposed) return;

    final wasOnline = _isOnline;
    
    // Consider device online if any connection is available
    _isOnline = results.isNotEmpty && 
                !results.every((result) => result == ConnectivityResult.none);

    if (!_isOnline) {
      _log.w('[SyncReplayService] 📴 Device went offline');
    } else if (!wasOnline && _isOnline) {
      _log.i('[SyncReplayService] 📶 Connectivity restored – attempting event replay');
      await _attemptSync();
    }
  }

  /// Attempt to sync pending events
  Future<void> _attemptSync() async {
    if (_disposed) return;
    if (!_isOnline) {
      _log.d('[SyncReplayService] ⏸️ Skipping sync - device offline');
      return;
    }

    _log.i('[SyncReplayService] 🔄 Checking for pending geofence events...');
    
    try {
      final pending = await _repo.getPendingEventsForSync();
      
      if (pending.isEmpty) {
        _log.i('[SyncReplayService] ✅ No pending events to sync.');
        return;
      }

      _log.i('[SyncReplayService] 📤 Found ${pending.length} pending events to sync...');
      
      final results = await _repo.syncPendingEvents();
      final success = results.successCount;
      final failed = results.failedCount;

      _log.i(
        '[SyncReplayService] ✅ Sync complete. '
        'Success: $success, Failed: $failed. ${DateTime.now()}',
      );

      // Log detailed summary in debug mode
      if (success > 0) {
        _log.d('[SyncReplayService] 📊 Successfully synced $success events');
      }
      if (failed > 0) {
        _log.w('[SyncReplayService] ⚠️ Failed to sync $failed events (will retry later)');
      }
    } catch (e, st) {
      _log.e('[SyncReplayService] ❌ Sync failed with error: $e', error: e, stackTrace: st);
    }
  }

  /// Manually trigger a sync (for testing or manual refresh)
  Future<void> manualSync() async {
    _log.i('[SyncReplayService] 🔧 Manual sync triggered');
    await _attemptSync();
  }

  /// Dispose resources
  void dispose() {
    if (_disposed) {
      _log.w('[SyncReplayService] ⚠️ Double dispose prevented');
      return;
    }
    _disposed = true;

    _log.i('[SyncReplayService] 🛑 Disposing SyncReplayService');

    // Cancel connectivity subscription
    _sub?.cancel();
    _sub = null;

    // Cancel periodic timer
    _periodicTimer?.cancel();
    _periodicTimer = null;

    _log.i('[SyncReplayService] ✅ SyncReplayService disposed');
  }
}
