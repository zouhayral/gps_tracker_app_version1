import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:my_app_gps/controllers/connectivity_coordinator.dart';
import 'package:my_app_gps/services/websocket_manager.dart';

/// Riverpod provider for unified connectivity state
///
/// Exposes ConnectivityState combining:
/// - Device network connectivity (Wi-Fi, mobile, ethernet)
/// - Traccar backend reachability (WebSocket + REST health check)
///
/// Automatically manages:
/// - FMTC caching mode (online vs hit-only)
/// - Periodic backend health pings
/// - Map rebuild triggers on reconnect
///
/// Usage:
/// ```dart
/// final state = ref.watch(connectivityProvider);
/// if (state.isOffline) {
///   // Show cached data only
/// }
/// ```
final connectivityProvider =
    StateNotifierProvider<ConnectivityNotifier, ConnectivityState>((ref) {
  return ConnectivityNotifier(ref);
});

/// StateNotifier managing app-wide connectivity
class ConnectivityNotifier extends StateNotifier<ConnectivityState> {
  final Ref _ref;
  ConnectivityCoordinator? _coordinator;

  ConnectivityNotifier(this._ref)
      : super(const ConnectivityState(
          networkAvailable: true,
          backendReachable: true,
        ),) {
    _initialize();
  }

  Future<void> _initialize() async {
    if (kDebugMode) {
      debugPrint('[CONNECTIVITY_PROVIDER] 🎬 Initializing');
    }

    _coordinator = ConnectivityCoordinator(
      onBackendPing: _checkBackendHealth,
    );

    // Subscribe to coordinator state changes
    _coordinator!.stateStream.listen((newState) {
      if (!mounted) return;

      final wasOffline = state.isOffline;
      final nowOffline = newState.isOffline;

      state = newState;

      // Log significant transitions
      if (wasOffline && !nowOffline) {
        if (kDebugMode) {
          debugPrint(
            '[CONNECTIVITY_PROVIDER] 🟢 RECONNECTED after ${state.timeSinceLastPing?.inSeconds ?? "unknown"}s',
          );
        }
        _onReconnect();
      } else if (!wasOffline && nowOffline) {
        if (kDebugMode) {
          debugPrint('[CONNECTIVITY_PROVIDER] 🔴 OFFLINE detected');
        }
        _onOffline();
      }
    });

    await _coordinator!.initialize();
  }

  /// Check backend health via WebSocket status + REST ping
  Future<bool> _checkBackendHealth() async {
    try {
      // First check: WebSocket connection status
  final wsState = _ref.read(webSocketManagerProvider);
      if (wsState.status == WebSocketStatus.connected) {
        if (kDebugMode) {
          debugPrint('[CONNECTIVITY_PROVIDER] ✅ Backend check: WS connected');
        }
        return true;
      }

      // Second check: REST API health ping
      // Defensive: Accept JSON, HTML, or plain text responses
      final dio = Dio(BaseOptions(
        connectTimeout: const Duration(seconds: 5),
        receiveTimeout: const Duration(seconds: 5),
        responseType: ResponseType.plain, // Parse as string to avoid FormatException
      ),);

      // Try a lightweight endpoint (adjust URL to match your backend)
      // Example: GET /api/session (Traccar's session check)
      final response = await dio.get<dynamic>(
        'http://37.60.238.215:8082/api/session',
        options: Options(
          validateStatus: (status) =>
              status != null && status >= 200 && status < 500,
        ),
      );

      // Health check criteria:
      // 1. HTTP status 200-499 (server responded)
      // 2. Body contains indicators: "traccar", "OK", "Server", or is empty (204 No Content)
      final statusCode = response.statusCode ?? 0;
      final body = (response.data ?? '').toString().toLowerCase();
      
      final isHealthy = statusCode >= 200 && statusCode < 500 &&
          (body.contains('traccar') || 
           body.contains('ok') || 
           body.contains('server') ||
           body.isEmpty);

      if (kDebugMode) {
        debugPrint(
          '[CONNECTIVITY_PROVIDER] ${isHealthy ? "✅" : "❌"} Backend check: '
          'status=$statusCode healthy=$isHealthy (body preview: ${body.substring(0, body.length > 50 ? 50 : body.length)}...)',
        );
      }

      return isHealthy;
    } catch (e) {
      if (kDebugMode) {
        debugPrint('[CONNECTIVITY_PROVIDER] ❌ Backend check failed: $e');
      }
      return false;
    }
  }

  /// Handle transition to offline state
  void _onOffline() {
    if (kDebugMode) {
      debugPrint('[CONNECTIVITY_PROVIDER] 📦 Switching to FMTC hit-only mode');
    }

  // TODO(zouhayral): Enable FMTC hit-only mode when flutter_map_tile_caching supports it
    // FMTC.instance('main').setMode(FMTCMode.hitOnly);
    // For now, this is handled by not fetching tiles when offline

    // 🎯 NEW: Pause WebSocket retries when offline
    try {
  _ref.read(webSocketManagerProvider.notifier).suspend();
    } catch (e) {
      if (kDebugMode) {
        debugPrint('[CONNECTIVITY_PROVIDER] ⚠️ Failed to pause WebSocket: $e');
      }
    }

    // Note: Map rebuild NOT needed on offline transition
    // Cached tiles remain visible
  }

  /// Handle transition to online state
  void _onReconnect() {
    if (kDebugMode) {
      debugPrint('[CONNECTIVITY_PROVIDER] 🌐 Switching to FMTC normal mode');
    }

  // TODO(zouhayral): Restore FMTC normal mode
    // FMTC.instance('main').setMode(FMTCMode.normal);

    // 🎯 NEW: Resume WebSocket when back online
    try {
  _ref.read(webSocketManagerProvider.notifier).resume();
    } catch (e) {
      if (kDebugMode) {
        debugPrint('[CONNECTIVITY_PROVIDER] ⚠️ Failed to resume WebSocket: $e');
      }
    }

    // Trigger map rebuild to refresh tiles and resume live markers
    // This is handled by FlutterMapAdapter listening to this provider
  }

  /// Force immediate connectivity check
  Future<void> forceCheck() async {
    await _coordinator?.forceCheck();
  }

  @override
  void dispose() {
    _coordinator?.dispose();
    super.dispose();
  }
}
