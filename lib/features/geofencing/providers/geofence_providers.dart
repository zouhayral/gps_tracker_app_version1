import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:my_app_gps/data/models/geofence.dart';
import 'package:my_app_gps/data/models/geofence_event.dart';
import 'package:my_app_gps/data/repositories/geofence_event_repository.dart';
import 'package:my_app_gps/data/repositories/geofence_repository.dart';
import 'package:my_app_gps/features/geofencing/service/geofence_evaluator_service.dart';
import 'package:my_app_gps/features/geofencing/service/geofence_monitor_service.dart';
import 'package:my_app_gps/features/geofencing/service/geofence_notification_bridge.dart';
import 'package:my_app_gps/features/geofencing/service/geofence_state_cache.dart';
import 'package:my_app_gps/services/notification_service.dart';

// ignore_for_file: flutter_style_todos, comment_references
export 'package:my_app_gps/data/repositories/geofence_event_repository.dart'
    show geofenceEventRepositoryProvider;
/// Riverpod providers for geofencing functionality.
///
/// This file centralizes all geofence-related providers:
/// - Data providers (geofences, events)
/// - Service providers (evaluator, cache, monitor)
/// - State providers (monitoring status, statistics)
///
/// ## Example Usage
///
/// ```dart
/// // Watch geofences for current user
/// final geofencesAsync = ref.watch(geofencesProvider);
/// geofencesAsync.when(
///   data: (geofences) => ListView(
///     children: geofences.map((g) => GeofenceListTile(g)).toList(),
///   ),
///   loading: () => CircularProgressIndicator(),
///   error: (e, s) => Text('Error: $e'),
/// );
///
/// // Start monitoring
/// final monitor = ref.read(geofenceMonitorProvider.notifier);
/// await monitor.start(currentUser.id);
///
/// // Watch events
/// final eventsAsync = ref.watch(geofenceEventsProvider);
///
/// // Get statistics
/// final statsAsync = ref.watch(geofenceStatsProvider);
/// ```

// =============================================================================
// REPOSITORY PROVIDERS
// =============================================================================

// Note: GeofenceRepository and GeofenceEventRepository providers are
// defined in their respective repository files and exported below.
// Import them from:
// - lib/data/repositories/geofence_repository.dart
// - lib/data/repositories/geofence_event_repository.dart

// Re-export repository providers for convenience
export 'package:my_app_gps/data/repositories/geofence_repository.dart'
    show geofenceRepositoryProvider;

// =============================================================================
// SERVICE PROVIDERS
// =============================================================================

/// Provider for GeofenceEvaluatorService
///
/// Handles geometric calculations and state transitions
final geofenceEvaluatorServiceProvider = Provider<GeofenceEvaluatorService>((ref) {
  return GeofenceEvaluatorService(
    
  );
});

/// Provider for GeofenceStateCache
///
/// In-memory cache with TTL-based eviction
final geofenceStateCacheProvider = Provider<GeofenceStateCache>((ref) {
  final cache = GeofenceStateCache(
    
  );

  // Auto-dispose cache when provider is disposed
  ref.onDispose(cache.dispose);

  return cache;
});

/// Provider for GeofenceMonitorService
///
/// Orchestrates position processing and event generation
final geofenceMonitorServiceProvider = FutureProvider<GeofenceMonitorService>((ref) async {
  // Wait for repositories to be ready
  final geofenceRepo = await ref.watch(geofenceRepositoryProvider.future);
  final eventRepo = await ref.watch(geofenceEventRepositoryProvider.future);

  final monitor = GeofenceMonitorService(
    evaluator: ref.watch(geofenceEvaluatorServiceProvider),
    cache: ref.watch(geofenceStateCacheProvider),
    eventRepo: eventRepo,
    geofenceRepo: geofenceRepo,
  );

  // Auto-dispose monitor when provider is disposed
  ref.onDispose(monitor.dispose);

  return monitor;
});

// =============================================================================
// DATA PROVIDERS
// =============================================================================

/// Provider that exposes all geofences for the current user
///
/// Returns a stream of geofences that updates when:
/// - Geofences are added/removed
/// - Geofences are enabled/disabled
/// - Geofence properties are modified
///
/// Requires authentication. Returns empty stream if user is not logged in.
///
/// Example:
/// ```dart
/// final geofencesAsync = ref.watch(geofencesProvider);
/// geofencesAsync.when(
///   data: (geofences) => Text('${geofences.length} geofences'),
///   loading: () => CircularProgressIndicator(),
///   error: (e, s) => Text('Error: $e'),
/// );
/// ```
final geofencesProvider = StreamProvider.autoDispose<List<Geofence>>((ref) async* {
  // TODO: Replace with actual auth provider
  // final userId = ref.watch(authProvider).value?.uid;
  const userId = 'test-user-id'; // Placeholder

  if (kDebugMode) {
    debugPrint('[geofencesProvider] Starting stream for userId: $userId');
  }

  if (userId.isEmpty) {
    yield const <Geofence>[];
    return;
  }

  // Wait for repository to be ready
  final repo = await ref.watch(geofenceRepositoryProvider.future);
  
  if (kDebugMode) {
    debugPrint('[geofencesProvider] Repository ready, subscribing to watchGeofences');
  }
  
  // Forward the stream from the repository
  yield* repo.watchGeofences(userId);
});

/// Provider that exposes all geofence events
///
/// Returns a stream of recent events (typically last 100)
/// Await repository initialization before using event stream
///
/// Example:
/// ```dart
/// final eventsAsync = ref.watch(geofenceEventsProvider);
/// eventsAsync.when(
///   data: (events) => ListView(
///     children: events.map((e) => EventCard(e)).toList(),
///   ),
///   loading: () => CircularProgressIndicator(),
///   error: (e, s) => Text('Error: $e'),
/// );
/// ```
final geofenceEventsProvider = StreamProvider.autoDispose<List<GeofenceEvent>>((ref) async* {
  // Await repository initialization before using event stream
  final repo = await ref.watch(geofenceEventRepositoryProvider.future);
  yield* repo.watchEvents();
});

/// Provider that exposes events for a specific geofence
///
/// [geofenceId] - ID of the geofence to filter by
/// Await repository initialization before using event stream
///
/// Example:
/// ```dart
/// final eventsAsync = ref.watch(eventsByGeofenceProvider('geo123'));
/// eventsAsync.when(
///   data: (events) => Text('${events.length} events for this geofence'),
///   loading: () => CircularProgressIndicator(),
///   error: (e, s) => Text('Error: $e'),
/// );
/// ```
final eventsByGeofenceProvider = StreamProvider.family.autoDispose<List<GeofenceEvent>, String>(
  (ref, geofenceId) async* {
    // Await repository initialization before using event stream
    final repo = await ref.watch(geofenceEventRepositoryProvider.future);
    yield* repo.watchEvents(geofenceId: geofenceId);
  },
);

/// Provider that exposes events for a specific device
///
/// [deviceId] - ID of the device to filter by
/// Await repository initialization before using event stream
///
/// Example:
/// ```dart
/// final eventsAsync = ref.watch(eventsByDeviceProvider('device123'));
/// ```
final eventsByDeviceProvider = StreamProvider.family.autoDispose<List<GeofenceEvent>, String>(
  (ref, deviceId) async* {
    // Await repository initialization before using event stream
    final repo = await ref.watch(geofenceEventRepositoryProvider.future);
    yield* repo.watchEvents(deviceId: deviceId);
  },
);

/// Provider that exposes unacknowledged events
///
/// Useful for notification badges and alerts
/// Await repository initialization before using event stream
///
/// Example:
/// ```dart
/// final unacknowledgedAsync = ref.watch(unacknowledgedEventsProvider);
/// unacknowledgedAsync.whenData((events) {
///   if (events.isNotEmpty) {
///     showBadge(events.length);
///   }
/// });
/// ```
final unacknowledgedEventsProvider = StreamProvider.autoDispose<List<GeofenceEvent>>((ref) async* {
  // Await repository initialization before using event stream
  final repo = await ref.watch(geofenceEventRepositoryProvider.future);
  // Use watchEvents and filter for pending (unacknowledged) events
  await for (final events in repo.watchEvents()) {
    yield events.where((e) => e.status == 'pending').toList();
  }
});

// =============================================================================
// MONITORING STATE
// =============================================================================

/// State for geofence monitoring service
class GeofenceMonitorState {
  /// Whether monitoring is currently active
  final bool isActive;

  /// Number of active geofences being monitored
  final int activeGeofences;

  /// Timestamp of last position evaluation
  final DateTime? lastUpdate;

  /// Total events triggered since monitoring started
  final int eventsTriggered;

  /// Last error message (if any)
  final String? error;

  const GeofenceMonitorState({
    required this.isActive,
    required this.activeGeofences,
    required this.eventsTriggered, this.lastUpdate,
    this.error,
  });

  const GeofenceMonitorState.initial()
      : isActive = false,
        activeGeofences = 0,
        lastUpdate = null,
        eventsTriggered = 0,
        error = null;

  GeofenceMonitorState copyWith({
    bool? isActive,
    int? activeGeofences,
    DateTime? lastUpdate,
    int? eventsTriggered,
    String? error,
  }) {
    return GeofenceMonitorState(
      isActive: isActive ?? this.isActive,
      activeGeofences: activeGeofences ?? this.activeGeofences,
      lastUpdate: lastUpdate ?? this.lastUpdate,
      eventsTriggered: eventsTriggered ?? this.eventsTriggered,
      error: error ?? this.error,
    );
  }

  @override
  String toString() {
    return 'GeofenceMonitorState('
        'isActive: $isActive, '
        'activeGeofences: $activeGeofences, '
        'lastUpdate: $lastUpdate, '
        'eventsTriggered: $eventsTriggered, '
        'error: $error'
        ')';
  }
}

/// Controller for geofence monitoring service
///
/// Manages the lifecycle of GeofenceMonitorService and exposes
/// monitoring state to the UI.
class GeofenceMonitorController extends StateNotifier<GeofenceMonitorState> {
  final GeofenceMonitorService monitor;
  StreamSubscription<GeofenceEvent>? _eventSubscription;

  GeofenceMonitorController(this.monitor) : super(const GeofenceMonitorState.initial());

  /// Start monitoring geofences for the specified user
  ///
  /// [userId] - User ID to monitor geofences for
  ///
  /// Example:
  /// ```dart
  /// final controller = ref.read(geofenceMonitorProvider.notifier);
  /// await controller.start('user123');
  /// ```
  Future<void> start(String userId) async {
    try {
      // Start the monitor service
      await monitor.startMonitoring(userId: userId);

      // Subscribe to events
      _eventSubscription = monitor.events.listen(
        _onEvent,
        onError: _onError,
      );

      // Update state
      state = state.copyWith(
        isActive: true,
        activeGeofences: monitor.activeGeofenceCount,
      );
    } catch (e) {
      state = state.copyWith(
        isActive: false,
        error: 'Failed to start monitoring: $e',
      );
      rethrow;
    }
  }

  /// Stop monitoring and clean up resources
  ///
  /// Example:
  /// ```dart
  /// final controller = ref.read(geofenceMonitorProvider.notifier);
  /// await controller.stop();
  /// ```
  Future<void> stop() async {
    try {
      // Cancel event subscription
      await _eventSubscription?.cancel();
      _eventSubscription = null;

      // Stop the monitor service
      await monitor.stopMonitoring();

      // Update state
      state = state.copyWith(
        isActive: false,
        activeGeofences: 0,
      );
    } catch (e) {
      state = state.copyWith(
        error: 'Failed to stop monitoring: $e',
      );
      rethrow;
    }
  }

  /// Handle incoming geofence events
  void _onEvent(GeofenceEvent event) {
    state = state.copyWith(
      lastUpdate: DateTime.now(),
      eventsTriggered: state.eventsTriggered + 1,
      activeGeofences: monitor.activeGeofenceCount,
    );
  }

  /// Handle event stream errors
  void _onError(Object error) {
    state = state.copyWith(
      error: 'Event stream error: $error',
    );
  }

  @override
  void dispose() {
    _eventSubscription?.cancel();
    super.dispose();
  }
}

/// Provider for geofence monitoring controller
///
/// Exposes GeofenceMonitorService lifecycle and state to the UI.
///
/// Example:
/// ```dart
/// // Provider for the GeofenceMonitorController
/// // Usage: Ensure monitor service is ready before accessing
/// final monitorServiceAsync = ref.watch(geofenceMonitorServiceProvider);
/// if (monitorServiceAsync.hasValue) {
///   final controller = ref.read(geofenceMonitorProvider.notifier);
///   await controller.start(currentUser.id);
/// }
/// ```
final geofenceMonitorProvider =
    StateNotifierProvider.autoDispose<GeofenceMonitorController, GeofenceMonitorState>((ref) {
  // Await repository initialization before creating controller
  final monitorServiceAsync = ref.watch(geofenceMonitorServiceProvider);
  
  // Extract the monitor or throw if not ready
  return monitorServiceAsync.maybeWhen(
    data: GeofenceMonitorController.new,
    orElse: () => throw StateError('GeofenceMonitorService not initialized yet. Check monitorServiceAsync.hasValue before accessing.'),
  );
});

// =============================================================================
// STATISTICS AND AGGREGATIONS
// =============================================================================

/// Statistics summary for geofences
class GeofenceStats {
  /// Total number of geofences
  final int total;

  /// Number of enabled geofences
  final int active;

  /// Number of disabled geofences
  final int inactive;

  /// Number of recent events (last 24h)
  final int recentEvents;

  /// Number of unacknowledged events
  final int unacknowledgedEvents;

  const GeofenceStats({
    required this.total,
    required this.active,
    required this.inactive,
    required this.recentEvents,
    required this.unacknowledgedEvents,
  });

  @override
  String toString() {
    return 'GeofenceStats('
        'total: $total, '
        'active: $active, '
        'inactive: $inactive, '
        'recentEvents: $recentEvents, '
        'unacknowledgedEvents: $unacknowledgedEvents'
        ')';
  }
}

/// Provider that computes geofence statistics
///
/// Aggregates data from geofences and events to provide summary info
///
/// Example:
/// ```dart
/// final statsAsync = ref.watch(geofenceStatsProvider);
/// statsAsync.when(
///   data: (stats) => Column(
///     children: [
///       Text('Total: ${stats.total}'),
///       Text('Active: ${stats.active}'),
///       Text('Recent Events: ${stats.recentEvents}'),
///     ],
///   ),
///   loading: () => CircularProgressIndicator(),
///   error: (e, s) => Text('Error: $e'),
/// );
/// ```
final geofenceStatsProvider = FutureProvider.autoDispose<GeofenceStats>((ref) async {
  // Wait for all data
  final geofences = await ref.watch(geofencesProvider.future);
  final events = await ref.watch(geofenceEventsProvider.future);
  final unacknowledged = await ref.watch(unacknowledgedEventsProvider.future);

  // Filter recent events (last 24 hours)
  final now = DateTime.now();
  final oneDayAgo = now.subtract(const Duration(hours: 24));
  final recentEvents = events.where((e) => e.timestamp.isAfter(oneDayAgo)).toList();

  return GeofenceStats(
    total: geofences.length,
    active: geofences.where((g) => g.enabled).length,
    inactive: geofences.where((g) => !g.enabled).length,
    recentEvents: recentEvents.length,
    unacknowledgedEvents: unacknowledged.length,
  );
});

/// Provider that exposes monitoring statistics
///
/// Example:
/// ```dart
/// final state = ref.watch(geofenceMonitorProvider);
/// Text('Events: ${state.eventsTriggered}');
/// ```
final monitoringStatsProvider = Provider.autoDispose<Map<String, dynamic>>((ref) {
  final monitorState = ref.watch(geofenceMonitorProvider);

  return {
    'isActive': monitorState.isActive,
    'activeGeofences': monitorState.activeGeofences,
    'eventsTriggered': monitorState.eventsTriggered,
    'lastUpdate': monitorState.lastUpdate?.toIso8601String(),
    'error': monitorState.error,
  };
});

// =============================================================================
// CONVENIENCE PROVIDERS
// =============================================================================

/// Provider that checks if monitoring is active
///
/// Example:
/// ```dart
/// final isActive = ref.watch(isMonitoringActiveProvider);
/// if (!isActive) {
///   ElevatedButton(
///     onPressed: () => ref.read(geofenceMonitorProvider.notifier).start(userId),
///     child: Text('Start Monitoring'),
///   );
/// }
/// ```
final isMonitoringActiveProvider = Provider.autoDispose<bool>((ref) {
  final state = ref.watch(geofenceMonitorProvider);
  return state.isActive;
});

/// Provider that gets count of active geofences
///
/// Example:
/// ```dart
/// final count = ref.watch(activeGeofenceCountProvider);
/// Text('Monitoring $count geofences');
/// ```
final activeGeofenceCountProvider = Provider.autoDispose<int>((ref) {
  final geofencesAsync = ref.watch(geofencesProvider);
  return geofencesAsync.when(
    data: (geofences) => geofences.where((g) => g.enabled).length,
    loading: () => 0,
    error: (_, __) => 0,
  );
});

/// Provider that gets count of unacknowledged events
///
/// Useful for notification badges
///
/// Example:
/// ```dart
/// final count = ref.watch(unacknowledgedEventCountProvider);
/// if (count > 0) {
///   Badge(count: count);
/// }
/// ```
final unacknowledgedEventCountProvider = Provider.autoDispose<int>((ref) {
  final eventsAsync = ref.watch(unacknowledgedEventsProvider);
  return eventsAsync.when(
    data: (events) => events.length,
    loading: () => 0,
    error: (_, __) => 0,
  );
});

// =============================================================================
// EXAMPLE USAGE
// =============================================================================

/*
/// Example: Geofence List Screen
class GeofenceListScreen extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final geofencesAsync = ref.watch(geofencesProvider);
    final stats = ref.watch(geofenceStatsProvider);
    
    return Scaffold(
      appBar: AppBar(
        title: Text('Geofences'),
        actions: [
          // Show stats
          stats.whenData((s) => Chip(
            label: Text('${s.active}/${s.total}'),
          )),
        ],
      ),
      body: geofencesAsync.when(
        data: (geofences) => ListView.builder(
          itemCount: geofences.length,
          itemBuilder: (context, index) {
            final geofence = geofences[index];
            return ListTile(
              title: Text(geofence.name),
              subtitle: Text(geofence.enabled ? 'Active' : 'Disabled'),
              trailing: Switch(
                value: geofence.enabled,
                onChanged: (enabled) {
                  // Toggle geofence
                  ref.read(geofenceRepositoryProvider)
                    .toggleGeofence(geofence.id, enabled);
                },
              ),
            );
          },
        ),
        loading: () => Center(child: CircularProgressIndicator()),
        error: (e, s) => Center(child: Text('Error: $e')),
      ),
    );
  }
}

/// Example: Monitoring Control Widget
class MonitoringControlWidget extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(geofenceMonitorProvider);
    final controller = ref.read(geofenceMonitorProvider.notifier);
    
    return Card(
      child: Padding(
        padding: EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Monitoring Status', style: Theme.of(context).textTheme.headline6),
            SizedBox(height: 8),
            Row(
              children: [
                Icon(
                  state.isActive ? Icons.check_circle : Icons.cancel,
                  color: state.isActive ? Colors.green : Colors.grey,
                ),
                SizedBox(width: 8),
                Text(state.isActive ? 'Active' : 'Inactive'),
              ],
            ),
            if (state.isActive) ...[
              SizedBox(height: 8),
              Text('Geofences: ${state.activeGeofences}'),
              Text('Events: ${state.eventsTriggered}'),
              if (state.lastUpdate != null)
                Text('Last Update: ${formatDateTime(state.lastUpdate!)}'),
            ],
            if (state.error != null) ...[
              SizedBox(height: 8),
              Text('Error: ${state.error}', style: TextStyle(color: Colors.red)),
            ],
            SizedBox(height: 16),
            ElevatedButton(
              onPressed: () async {
                if (state.isActive) {
                  await controller.stop();
                } else {
                  final userId = 'current-user-id'; // Get from auth
                  await controller.start(userId);
                }
              },
              child: Text(state.isActive ? 'Stop Monitoring' : 'Start Monitoring'),
            ),
          ],
        ),
      ),
    );
  }
}

/// Example: Event Feed
class EventFeedScreen extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final eventsAsync = ref.watch(geofenceEventsProvider);
    final unacknowledgedCount = ref.watch(unacknowledgedEventCountProvider);
    
    return Scaffold(
      appBar: AppBar(
        title: Text('Events'),
        actions: [
          if (unacknowledgedCount > 0)
            Chip(
              label: Text('$unacknowledgedCount new'),
              backgroundColor: Colors.red,
            ),
        ],
      ),
      body: eventsAsync.when(
        data: (events) {
          if (events.isEmpty) {
            return Center(child: Text('No events yet'));
          }
          
          return ListView.builder(
            itemCount: events.length,
            itemBuilder: (context, index) {
              final event = events[index];
              return EventCard(event: event);
            },
          );
        },
        loading: () => Center(child: CircularProgressIndicator()),
        error: (e, s) => Center(child: Text('Error: $e')),
      ),
    );
  }
}
*/

// =============================================================================
// NOTIFICATION BRIDGE PROVIDER
// =============================================================================

/// Provider for GeofenceNotificationBridge
///
/// Manages the bridge between geofence events and user notifications.
///
/// This provider:
/// - Creates notification bridge instance
/// - Auto-attaches/detaches based on monitoring state
/// - Updates geofence list when data changes
/// - Handles lifecycle cleanup
///
/// ## Lifecycle
/// - Bridge attaches when monitoring starts
/// - Bridge detaches when monitoring stops
/// - Auto-disposes when provider is disposed
///
/// ## Example Usage
/// ```dart
/// // Bridge is automatically managed by monitoring state
/// // No manual interaction needed
///
/// // However, you can access it if needed:
/// final bridge = ref.read(geofenceNotificationBridgeProvider);
/// ```
final geofenceNotificationBridgeProvider =
    FutureProvider.autoDispose<GeofenceNotificationBridge>((ref) async {
  // Await repository initialization before creating bridge
  final eventRepo = await ref.watch(geofenceEventRepositoryProvider.future);
  
  // Await monitor service initialization
  final monitor = await ref.watch(geofenceMonitorServiceProvider.future);
  
  // Load geofences
  final geofences = await ref.read(geofencesProvider.future);
  
  // Create bridge instance
  final bridge = GeofenceNotificationBridge(
    eventRepo: eventRepo,
    notificationService: ref.read(notificationServiceProvider),
    // TODO: Add FCM when available
    // fcm: ref.read(firebaseMessagingProvider),
  );

  // 🎯 CRITICAL: Attach bridge to monitor's event stream with geofences
  await bridge.attach(monitor.events, geofences);
  
  if (kDebugMode) {
    debugPrint('[GeofenceProviders] 🔔 Notification bridge attached with ${geofences.length} geofences');
  }

  // Listen to geofence updates and propagate to bridge
  ref.listen<AsyncValue<List<Geofence>>>(
    geofencesProvider,
    (previous, next) {
      next.whenData((geofences) {
        bridge.updateGeofences(geofences);
        if (kDebugMode) {
          debugPrint('[GeofenceProviders] 🔄 Updated bridge with ${geofences.length} geofences');
        }
      });
    },
  );

  // Cleanup on dispose
  ref.onDispose(() async {
    await bridge.detach();
    if (kDebugMode) {
      debugPrint('[GeofenceProviders] 🔕 Notification bridge detached');
    }
  });

  return bridge;
});

// =============================================================================
// NOTIFICATION BRIDGE STATE PROVIDER
// =============================================================================

/// Provider for notification bridge attachment state
///
/// Returns whether the notification bridge is currently attached and processing events.
/// Await repository initialization before checking bridge status
///
/// ## Example Usage
/// ```dart
/// final isAttachedAsync = ref.watch(notificationBridgeAttachedProvider);
/// isAttachedAsync.when(
///   data: (isAttached) => Text(isAttached ? 'Notifications active' : 'Notifications paused'),
///   loading: () => CircularProgressIndicator(),
///   error: (e, _) => Text('Error: $e'),
/// );
/// ```
final notificationBridgeAttachedProvider = FutureProvider.autoDispose<bool>((ref) async {
  // Await repository initialization before checking bridge status
  final bridge = await ref.watch(geofenceNotificationBridgeProvider.future);
  return bridge.isAttached;
});
