import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/data/vehicle_data_repository.dart';
import '../../../services/websocket_manager_enhanced.dart';

/// Mixin that handles lifecycle events for MapPage to ensure:
/// 1. WebSocket reconnection when app resumes
/// 2. Fresh data fetch when map page is first opened
/// 3. Immediate server refresh when device is selected (no stale cache)
/// 4. Fallback periodic refresh if WebSocket drops silently
mixin MapPageLifecycleMixin<T extends ConsumerStatefulWidget>
    on ConsumerState<T>, WidgetsBindingObserver {
  Timer? _periodicRefreshTimer;
  bool _hasInitializedOnce = false;

  /// Override this to provide device IDs to refresh
  List<int> get activeDeviceIds;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _startPeriodicRefresh();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _periodicRefreshTimer?.cancel();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);

    switch (state) {
      case AppLifecycleState.resumed:
        _onAppResumed();
        break;
      case AppLifecycleState.paused:
        _onAppPaused();
        break;
      default:
        break;
    }
  }

  /// Called when app comes back to foreground
  void _onAppResumed() {
    if (kDebugMode) {
      debugPrint(
          '[LIFECYCLE] Resumed → reconnecting WebSocket and refreshing data');
    }

    // 1. Force WebSocket reconnection
    final wsManager = ref.read(webSocketManagerProvider.notifier);
    wsManager.forceReconnect();

    // 2. Fetch fresh data from REST API (in case WebSocket was disconnected)
    final repo = ref.read(vehicleDataRepositoryProvider);
    final deviceIds = activeDeviceIds;

    if (deviceIds.isNotEmpty) {
      repo.refreshAll();
      if (kDebugMode) {
        debugPrint('[LIFECYCLE] Refreshing ${deviceIds.length} devices');
      }
    }

    // 3. Restart periodic refresh
    _startPeriodicRefresh();
  }

  /// Called when app goes to background
  void _onAppPaused() {
    if (kDebugMode) {
      debugPrint('[LIFECYCLE] Paused → suspending WebSocket');
    }

    // Suspend WebSocket to save battery (will auto-reconnect on resume)
    final wsManager = ref.read(webSocketManagerProvider.notifier);
    wsManager.suspend();

    // Stop periodic refresh
    _periodicRefreshTimer?.cancel();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();

    // Trigger fresh data fetch when map page first opens
    if (!_hasInitializedOnce) {
      _hasInitializedOnce = true;

      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;

        if (kDebugMode) {
          debugPrint(
              '[LIFECYCLE] First open → fetching fresh data from server');
        }

        // Force WebSocket health check
        final wsManager = ref.read(webSocketManagerProvider.notifier);
        wsManager.checkHealth();

        // Fetch fresh positions from REST API
        final repo = ref.read(vehicleDataRepositoryProvider);
        final deviceIds = activeDeviceIds;

        if (deviceIds.isNotEmpty) {
          repo.refreshAll();
        }
      });
    }
  }

  /// Refresh data for a specific device (call when user selects a marker)
  Future<void> refreshDevice(int deviceId) async {
    if (kDebugMode) {
      debugPrint('[LIFECYCLE] Device $deviceId selected → forcing fresh fetch');
    }

    final repo = ref.read(vehicleDataRepositoryProvider);
    await repo.refresh(deviceId);
  }

  /// Start periodic fallback refresh (every 45 seconds)
  /// Smart fallback: only triggers REST refresh if WebSocket has been silent for 20+ seconds
  void _startPeriodicRefresh() {
    _periodicRefreshTimer?.cancel();

    const refreshInterval = Duration(seconds: 45);
    const silenceThreshold = Duration(seconds: 20);

    _periodicRefreshTimer = Timer.periodic(refreshInterval, (_) {
      if (!mounted) return;

      final wsState = ref.read(webSocketManagerProvider);
      final wsManager = ref.read(webSocketManagerProvider.notifier);

      // Smart fallback: Only refresh if WebSocket is disconnected OR silent for 20+ seconds
      final shouldRefresh = wsState.status != WebSocketStatus.connected ||
          wsState.isSilent(silenceThreshold);

      if (shouldRefresh) {
        if (kDebugMode) {
          if (wsState.status != WebSocketStatus.connected) {
            debugPrint(
                '[FALLBACK] WebSocket not connected → using REST refresh');
          } else {
            debugPrint(
                '[FALLBACK] WebSocket silent for 20s → using REST refresh');
          }
        }

        final repo = ref.read(vehicleDataRepositoryProvider);
        final deviceIds = activeDeviceIds;

        if (deviceIds.isNotEmpty) {
          repo.fetchMultipleDevices(deviceIds);
        }
      } else {
        // WebSocket is connected and active - just do health check
        wsManager.checkHealth();
      }
    });

    if (kDebugMode) {
      debugPrint(
          '[FALLBACK] Started periodic refresh every ${refreshInterval.inSeconds}s');
    }
  }

  /// Check if data is stale and needs refresh
  bool isDataStale(DateTime? lastUpdate) {
    if (lastUpdate == null) return true;

    const staleThreshold = Duration(minutes: 2);
    return DateTime.now().difference(lastUpdate) > staleThreshold;
  }
}
