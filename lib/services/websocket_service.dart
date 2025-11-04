/// WebSocket liveness facade
///
/// This file documents and exposes lightweight helpers for WebSocket liveness
/// and REST fallback coordination without changing existing wiring.
///
/// Key behaviors implemented across services:
/// - WebSocket silence-based reconnect (>25s) remains the primary trigger
/// - Exponential backoff for reconnects (1s → 2s → 4s → … → 60s)
/// - Debounce overlapping connect attempts in `WebSocketManager`
/// - Optional lightweight text ping every 30s (configurable) to keep NATs alive
/// - Adaptive REST fallback polling (10s base → doubles to 120s) while WS offline
///
/// Where implemented:
/// - `websocket_manager.dart`: health monitor, reconnect, optional ping
/// - `traccar_socket_service.dart`: `ping()` extension that sends a small frame
/// - `positions_service.dart`: `fallbackPollLatestAdaptive()` for testing/targeted use
/// - `vehicle_data_repository.dart`: production REST fallback timer with backoff
///
/// To tune ping behavior at runtime:
/// ```dart
/// final ws = ref.read(webSocketManagerProvider.notifier);
/// ws.configurePing(enabled: true, every: const Duration(seconds: 30));
/// ```
///
/// To start a targeted adaptive REST fallback (usually not needed if repository is used):
/// ```dart
/// final svc = ref.read(positionsServiceProvider);
/// final stream = svc.fallbackPollLatestAdaptive(
///   deviceIds: [1,2,3],
///   isWebSocketOnline: () => ref.read(webSocketManagerProvider).status == WebSocketStatus.connected,
/// );
/// ```
library websocket_liveness_facade;

export 'websocket_manager.dart' show WebSocketManager, WebSocketState, WebSocketStatus, webSocketManagerProvider;

