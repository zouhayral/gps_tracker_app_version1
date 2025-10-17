// Re-export connectivity providers for easy access
//
// This file consolidates connectivity-related providers:
// - ReconnectionManager providers (from reconnection_manager.dart)
// - NetworkConnectivityMonitor providers
//
// Usage:
//   import 'package:my_app_gps/core/providers/connectivity_providers.dart';
//
//   // Watch WebSocket connection status
//   final status = ref.watch(connectionStatusProvider);
//
//   // Watch network connectivity
//   final networkState = ref.watch(networkStateProvider);

export 'package:my_app_gps/core/services/network_connectivity_monitor.dart'
    show NetworkState, networkConnectivityProvider, networkStateProvider;
export 'package:my_app_gps/core/services/reconnection_manager.dart'
    show
        ConnectionStatus,
        connectionStatusProvider,
        reconnectionManagerProvider;
