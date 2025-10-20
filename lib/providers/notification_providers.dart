import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:my_app_gps/core/database/dao/events_dao.dart';
import 'package:my_app_gps/data/models/event.dart';
import 'package:my_app_gps/repositories/notifications_repository.dart';
import 'package:my_app_gps/services/event_service.dart';

/// Provider for the NotificationsRepository
///
/// This is a singleton provider that manages the notification state
/// across the entire app. It's not autoDispose to maintain the
/// WebSocket connection and cache.
final notificationsRepositoryProvider = Provider<NotificationsRepository>((ref) {
  final eventService = ref.watch(eventServiceProvider);
  final eventsDao = ref.watch(eventsDaoProvider).valueOrNull;

  // If DAO is not ready yet, we need to handle this gracefully
  if (eventsDao == null) {
    throw StateError('EventsDao not initialized yet');
  }

  final repository = NotificationsRepository(
    eventService: eventService,
    eventsDao: eventsDao,
    ref: ref,
  );

  // Dispose when provider is no longer needed
  ref.onDispose(() {
    repository.dispose();
  });

  return repository;
});

/// Stream provider for real-time notification updates
///
/// Emits a new list of events whenever:
/// - Initial load from ObjectBox completes
/// - Events are refreshed from API
/// - An event is marked as read
/// - New events arrive via WebSocket
///
/// Use this for UI widgets that need to reactively display notifications.
final notificationsStreamProvider =
    StreamProvider.autoDispose<List<Event>>((ref) {
  final repository = ref.watch(notificationsRepositoryProvider);
  return repository.watchEvents();
});

/// Provider for unread notification count
///
/// Computed from the notifications stream. Returns 0 if stream has no data.
/// Useful for displaying badge counts in UI.
///
/// Example:
/// ```dart
/// final unreadCount = ref.watch(unreadCountProvider);
/// Badge(count: unreadCount.value ?? 0)
/// ```
final unreadCountProvider = Provider.autoDispose<int>((ref) {
  final notificationsAsync = ref.watch(notificationsStreamProvider);

  return notificationsAsync.when(
    data: (events) => events.where((e) => !e.isRead).length,
    loading: () => 0,
    error: (_, __) => 0,
  );
});

/// Provider for manual notification refresh
///
/// Use this to trigger a refresh from the API (e.g., pull-to-refresh).
///
/// Example:
/// ```dart
/// // In a RefreshIndicator
/// onRefresh: () async {
///   await ref.refresh(refreshNotificationsProvider.future);
/// }
/// ```
final refreshNotificationsProvider =
    FutureProvider.autoDispose<void>((ref) async {
  final repository = ref.watch(notificationsRepositoryProvider);
  await repository.refreshEvents();
});

/// Provider for filtered notifications (unread only)
///
/// Returns only unread events. Useful for notification pages that
/// show only unread items.
final unreadNotificationsProvider =
    FutureProvider.autoDispose<List<Event>>((ref) async {
  final repository = ref.watch(notificationsRepositoryProvider);
  return repository.getAllEvents(unreadOnly: true);
});

/// Provider for notifications filtered by device
///
/// Family provider that accepts a deviceId and returns events
/// for that specific device.
///
/// Example:
/// ```dart
/// final deviceEvents = ref.watch(deviceNotificationsProvider(123));
/// ```
final deviceNotificationsProvider =
    FutureProvider.autoDispose.family<List<Event>, int>((ref, deviceId) async {
  final repository = ref.watch(notificationsRepositoryProvider);
  return repository.getAllEvents(deviceId: deviceId);
});

/// Provider for notifications filtered by type
///
/// Family provider that accepts an event type and returns matching events.
///
/// Example:
/// ```dart
/// final alarmEvents = ref.watch(typeNotificationsProvider('alarm'));
/// ```
final typeNotificationsProvider = FutureProvider.autoDispose
    .family<List<Event>, String>((ref, type) async {
  final repository = ref.watch(notificationsRepositoryProvider);
  return repository.getAllEvents(type: type);
});

/// Provider for marking an event as read
///
/// This is a state notifier that can be used to mark events as read
/// from anywhere in the app.
///
/// Example:
/// ```dart
/// await ref.read(markEventAsReadProvider.notifier).call(eventId);
/// ```
final markEventAsReadProvider =
    StateNotifierProvider<MarkEventAsReadNotifier, AsyncValue<void>>((ref) {
  final repository = ref.watch(notificationsRepositoryProvider);
  return MarkEventAsReadNotifier(repository);
});

/// Notifier for marking events as read
class MarkEventAsReadNotifier extends StateNotifier<AsyncValue<void>> {
  MarkEventAsReadNotifier(this._repository) : super(const AsyncValue.data(null));

  final NotificationsRepository _repository;

  /// Mark a single event as read
  Future<void> call(String eventId) async {
    state = const AsyncValue.loading();
    state = await AsyncValue.guard(() async {
      await _repository.markAsRead(eventId);
    });
  }

  /// Mark multiple events as read
  Future<void> markMultiple(List<String> eventIds) async {
    state = const AsyncValue.loading();
    state = await AsyncValue.guard(() async {
      await _repository.markMultipleAsRead(eventIds);
    });
  }
}

/// Provider for marking all events as read
///
/// Convenience provider for "mark all as read" functionality.
final markAllAsReadProvider = FutureProvider.autoDispose<void>((ref) async {
  final repository = ref.watch(notificationsRepositoryProvider);
  final events = await repository.getAllEvents(unreadOnly: true);
  final eventIds = events.map((e) => e.id).toList();

  if (eventIds.isNotEmpty) {
    await repository.markMultipleAsRead(eventIds);
  }
});

/// Provider for clearing all notifications
///
/// Use with caution - this will delete all cached events from ObjectBox.
final clearAllNotificationsProvider =
    FutureProvider.autoDispose<void>((ref) async {
  final repository = ref.watch(notificationsRepositoryProvider);
  await repository.clearAllEvents();
});

/// Provider for event statistics
///
/// Returns a map of event types to their counts.
/// Useful for analytics or dashboard views.
///
/// Example:
/// ```dart
/// final stats = ref.watch(notificationStatsProvider);
/// stats.when(
///   data: (map) => Text('Alarms: ${map['alarm'] ?? 0}'),
///   ...
/// )
/// ```
final notificationStatsProvider =
    FutureProvider.autoDispose<Map<String, int>>((ref) async {
  final repository = ref.watch(notificationsRepositoryProvider);
  final events = await repository.getAllEvents();

  final stats = <String, int>{};
  for (final event in events) {
    stats[event.type] = (stats[event.type] ?? 0) + 1;
  }

  return stats;
});
