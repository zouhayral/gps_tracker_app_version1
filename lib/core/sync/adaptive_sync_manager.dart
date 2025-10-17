import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:my_app_gps/core/data/vehicle_data_repository.dart';
import 'package:my_app_gps/core/services/network_connectivity_monitor.dart';
import 'package:my_app_gps/core/services/reconnection_manager.dart';

/// Provider for the adaptive sync manager singleton
final adaptiveSyncManagerProvider = Provider<AdaptiveSyncManager>((ref) {
  final repository = ref.watch(vehicleDataRepositoryProvider);
  final networkMonitor = ref.watch(networkConnectivityProvider);

  final manager = AdaptiveSyncManager(
    repository: repository,
    networkMonitor: networkMonitor,
    ref: ref,
  );

  // Start monitoring
  manager.start();

  ref.onDispose(() {
    manager.dispose();
  });

  return manager;
});

/// Sync context for adaptive scheduling decisions
enum SyncContext {
  foregroundMoving, // App visible, vehicles moving
  foregroundIdle, // App visible, vehicles idle
  backgroundActive, // App background, recent activity
  backgroundSuspended, // App background, long idle
  offline, // No network
  reconnecting, // WebSocket reconnecting
}

/// Statistics for adaptive sync manager
class SyncStats {
  int totalSyncs = 0;
  int foregroundSyncs = 0;
  int backgroundSyncs = 0;
  int skippedOffline = 0;
  int skippedReconnecting = 0;
  DateTime? lastSync;
  Duration? averageInterval;
  List<Duration> recentIntervals = [];

  Map<String, dynamic> toJson() {
    return {
      'totalSyncs': totalSyncs,
      'foregroundSyncs': foregroundSyncs,
      'backgroundSyncs': backgroundSyncs,
      'skippedOffline': skippedOffline,
      'skippedReconnecting': skippedReconnecting,
      'lastSync': lastSync?.toIso8601String(),
      'averageInterval': averageInterval?.inSeconds,
    };
  }
}

/// Manages adaptive sync scheduling based on app lifecycle, motion, network, and battery
///
/// Features:
/// - Dynamic interval adjustment (5s moving → 30s idle → 60-120s background)
/// - Pause sync during reconnection attempts
/// - Skip sync when offline (cache-only)
/// - Reduce sync when battery low
/// - Fast resume when returning to foreground
///
/// Usage:
/// ```dart
/// final manager = ref.watch(adaptiveSyncManagerProvider);
///
/// // Notify motion state change
/// manager.notifyVehicleMotion(deviceId: 42, isMoving: true);
///
/// // Notify app lifecycle change
/// manager.notifyLifecycleChange(AppLifecycleState.paused);
///
/// // Get statistics
/// final stats = manager.stats;
/// ```
class AdaptiveSyncManager {
  AdaptiveSyncManager({
    required this.repository,
    required this.networkMonitor,
    required Ref ref,
  }) : _ref = ref;

  final VehicleDataRepository repository;
  final NetworkConnectivityMonitor networkMonitor;
  final Ref _ref;

  // Configuration: Sync intervals by context
  static const _intervalForegroundMoving = Duration(seconds: 5);
  static const _intervalForegroundIdle = Duration(seconds: 30);
  static const _intervalBackgroundActive = Duration(seconds: 60);
  static const _intervalBackgroundSuspended = Duration(seconds: 120);

  // Thresholds (kept for future motion-based logic)
  // ignore: unused_field
  static const _movingSpeedThreshold = 2.0; // km/h
  static const _backgroundActiveWindow = Duration(minutes: 5);
  // ignore: unused_field
  static const _idleTimeout = Duration(minutes: 2);
  static const _maxRecentIntervals = 10;

  // State
  Timer? _syncTimer;
  SyncContext _currentContext = SyncContext.foregroundIdle;
  Duration _currentInterval = _intervalForegroundIdle;
  bool _isStarted = false;
  bool _isPaused = false;

  // Motion tracking
  final Map<int, bool> _vehicleMotionState = {}; // deviceId -> isMoving
  // ignore: unused_field
  DateTime? _lastMotionUpdate;

  // Lifecycle tracking
  bool _isInForeground = true;
  DateTime? _backgroundSince;

  // Statistics
  final SyncStats _stats = SyncStats();
  SyncStats get stats => _stats;

  // Network state subscription
  StreamSubscription<NetworkState>? _networkSub;
  ProviderSubscription<ConnectionStatus>? _connectionStatusSub;

  /// Start adaptive sync manager
  void start() {
    if (_isStarted) return;
    _isStarted = true;

    if (kDebugMode) {
      debugPrint(
          '[AdaptiveSync] 🚀 Starting with interval: ${_currentInterval.inSeconds}s');
    }

    // Subscribe to network state changes
    _networkSub = networkMonitor.stateStream.listen((state) {
      if (state == NetworkState.offline) {
        _pauseSync('offline');
      } else if (state == NetworkState.online && _isPaused) {
        _resumeSync();
      }
    });

    // Subscribe to connection status (watch provider)
    _connectionStatusSub = _ref.listen<ConnectionStatus>(
      connectionStatusProvider,
      (previous, next) {
        if (next == ConnectionStatus.reconnecting) {
          _pauseSync('reconnecting');
        } else if (next == ConnectionStatus.online && _isPaused) {
          _resumeSync();
        }
      },
    );

    // Start sync timer
    _scheduleSyncTimer();
  }

  /// Stop adaptive sync manager
  void dispose() {
    _syncTimer?.cancel();
    _syncTimer = null;
    _networkSub?.cancel();
    _connectionStatusSub?.close();
    _isStarted = false;

    if (kDebugMode) {
      debugPrint(
          '[AdaptiveSync] 🛑 Stopped. Total syncs: ${_stats.totalSyncs}');
    }
  }

  /// Notify app lifecycle state change
  void notifyLifecycleChange(AppLifecycleState state) {
    final wasForeground = _isInForeground;

    switch (state) {
      case AppLifecycleState.resumed:
        _isInForeground = true;
        _backgroundSince = null;

        if (!wasForeground) {
          if (kDebugMode) {
            debugPrint('[AdaptiveSync] 📱 Foreground resumed - fast sync');
          }
          // Fast sync on foreground return
          _triggerImmediateSync();
        }

      case AppLifecycleState.paused:
      case AppLifecycleState.inactive:
        _isInForeground = false;
        _backgroundSince = DateTime.now();

        if (kDebugMode) {
          debugPrint('[AdaptiveSync] 📴 Background mode - reduced sync');
        }

      case AppLifecycleState.detached:
      case AppLifecycleState.hidden:
        _isInForeground = false;
    }

    _updateSyncContext();
  }

  /// Notify vehicle motion state change
  void notifyVehicleMotion({required int deviceId, required bool isMoving}) {
    final wasMoving = _vehicleMotionState[deviceId] ?? false;
    _vehicleMotionState[deviceId] = isMoving;
    _lastMotionUpdate = DateTime.now();

    if (wasMoving != isMoving) {
      if (kDebugMode) {
        debugPrint(
            '[AdaptiveSync] 🚗 Device $deviceId: ${isMoving ? "MOVING" : "IDLE"}');
      }
      _updateSyncContext();
    }
  }

  /// Notify battery state change
  void notifyBatteryState({required bool isLow}) {
    if (isLow) {
      // Increase interval to save battery
      _currentInterval = _intervalBackgroundSuspended;
      if (kDebugMode) {
        debugPrint(
            '[AdaptiveSync] 🔋 Low battery - reduced sync: ${_currentInterval.inSeconds}s');
      }
      _rescheduleSyncTimer();
    }
  }

  /// Force an immediate sync (used by UI actions)
  Future<void> forceSync() async {
    if (kDebugMode) {
      debugPrint('[AdaptiveSync] ⚡ Force sync requested');
    }
    await _executeSync(forced: true);
  }

  // ---------- Internal Methods ----------

  void _updateSyncContext() {
    final oldContext = _currentContext;

    // Determine new context based on state
    if (_networkSub == null ||
        networkMonitor.currentState == NetworkState.offline) {
      _currentContext = SyncContext.offline;
    } else if (_ref.read(connectionStatusProvider) ==
        ConnectionStatus.reconnecting) {
      _currentContext = SyncContext.reconnecting;
    } else if (_isInForeground) {
      final hasMovingVehicles =
          _vehicleMotionState.values.any((moving) => moving);
      _currentContext = hasMovingVehicles
          ? SyncContext.foregroundMoving
          : SyncContext.foregroundIdle;
    } else {
      // Background mode
      final backgroundDuration = _backgroundSince != null
          ? DateTime.now().difference(_backgroundSince!)
          : Duration.zero;

      _currentContext = backgroundDuration > _backgroundActiveWindow
          ? SyncContext.backgroundSuspended
          : SyncContext.backgroundActive;
    }

    // Update interval based on context
    final oldInterval = _currentInterval;
    _currentInterval = _getIntervalForContext(_currentContext);

    if (oldContext != _currentContext || oldInterval != _currentInterval) {
      if (kDebugMode) {
        debugPrint(
          '[AdaptiveSync] Context: ${oldContext.name} → ${_currentContext.name} '
          '| Interval: ${oldInterval.inSeconds}s → ${_currentInterval.inSeconds}s',
        );
      }
      _rescheduleSyncTimer();
    }
  }

  Duration _getIntervalForContext(SyncContext context) {
    switch (context) {
      case SyncContext.foregroundMoving:
        return _intervalForegroundMoving;
      case SyncContext.foregroundIdle:
        return _intervalForegroundIdle;
      case SyncContext.backgroundActive:
        return _intervalBackgroundActive;
      case SyncContext.backgroundSuspended:
        return _intervalBackgroundSuspended;
      case SyncContext.offline:
      case SyncContext.reconnecting:
        return Duration.zero; // No sync
    }
  }

  void _scheduleSyncTimer() {
    _syncTimer?.cancel();

    if (_currentInterval == Duration.zero || _isPaused) {
      return; // Don't schedule if offline/reconnecting or paused
    }

    _syncTimer = Timer.periodic(_currentInterval, (_) => _executeSync());
  }

  void _rescheduleSyncTimer() {
    _scheduleSyncTimer();
  }

  void _pauseSync(String reason) {
    if (_isPaused) return;

    _isPaused = true;
    _syncTimer?.cancel();

    if (kDebugMode) {
      debugPrint('[AdaptiveSync] ⏸️ Paused: $reason');
    }

    if (reason == 'offline') {
      _stats.skippedOffline++;
    } else if (reason == 'reconnecting') {
      _stats.skippedReconnecting++;
    }
  }

  void _resumeSync() {
    if (!_isPaused) return;

    _isPaused = false;
    if (kDebugMode) {
      debugPrint('[AdaptiveSync] ▶️ Resumed - triggering immediate sync');
    }

    // Immediate sync on resume, then schedule periodic
    _triggerImmediateSync();
  }

  Future<void> _triggerImmediateSync() async {
    await _executeSync();
    _scheduleSyncTimer();
  }

  Future<void> _executeSync({bool forced = false}) async {
    // Skip if offline or reconnecting (unless forced)
    if (!forced) {
      if (_currentContext == SyncContext.offline) {
        _stats.skippedOffline++;
        return;
      }
      if (_currentContext == SyncContext.reconnecting) {
        _stats.skippedReconnecting++;
        return;
      }
    }

    final startTime = DateTime.now();

    try {
      // Call repository refreshAll (fetches all tracked devices)
      await repository.refreshAll();

      // Update statistics
      _stats.totalSyncs++;
      if (_isInForeground) {
        _stats.foregroundSyncs++;
      } else {
        _stats.backgroundSyncs++;
      }

      final now = DateTime.now();
      if (_stats.lastSync != null) {
        final interval = now.difference(_stats.lastSync!);
        _stats.recentIntervals.add(interval);
        if (_stats.recentIntervals.length > _maxRecentIntervals) {
          _stats.recentIntervals.removeAt(0);
        }

        // Calculate average interval
        final totalMs = _stats.recentIntervals.fold<int>(
          0,
          (sum, d) => sum + d.inMilliseconds,
        );
        _stats.averageInterval = Duration(
          milliseconds: totalMs ~/ _stats.recentIntervals.length,
        );
      }
      _stats.lastSync = now;

      final elapsed = DateTime.now().difference(startTime);
      if (kDebugMode) {
        debugPrint(
          '[AdaptiveSync] ✅ Sync completed in ${elapsed.inMilliseconds}ms '
          '(context: ${_currentContext.name}, forced: $forced)',
        );
      }
    } catch (e, st) {
      if (kDebugMode) {
        debugPrint('[AdaptiveSync] ❌ Sync failed: $e');
        debugPrint(st.toString());
      }
    }
  }
}
