import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:my_app_gps/core/database/dao/devices_dao.dart';
import 'package:my_app_gps/core/database/dao/events_dao.dart';
import 'package:my_app_gps/data/models/event.dart';
import 'package:my_app_gps/repositories/notifications_repository.dart';
import 'package:my_app_gps/services/event_service.dart';

/// Filter model for notification list
@immutable
class NotificationFilter {
  final String? severity; // 'high', 'medium', 'low'
  final DateTime? date;
  final DateTimeRange? dateRange;

  const NotificationFilter({
    this.severity,
    this.date,
    this.dateRange,
  });

  NotificationFilter copyWith({
    String? Function()? severity,
    DateTime? Function()? date,
    DateTimeRange? Function()? dateRange,
  }) {
    return NotificationFilter(
      severity: severity != null ? severity() : this.severity,
      date: date != null ? date() : this.date,
      dateRange: dateRange != null ? dateRange() : this.dateRange,
    );
  }

  /// Check if any filter is active
  bool get isActive => severity != null || date != null || dateRange != null;

  /// Clear all filters
  NotificationFilter clear() => const NotificationFilter();

  /// Apply this filter to a list of events
  List<Event> apply(List<Event> events) {
    var filtered = events;

    // Filter by severity
    if (severity != null) {
      filtered = filtered.where((event) {
        final sel = severity!.toLowerCase();
        final evSeverity = event.severity?.toLowerCase();
        // First support new priority chip values via attributes['priority']
        final attrPriority = (event.attributes['priority'] as String?)?.toLowerCase();
        if (attrPriority != null) {
          return attrPriority == sel; // 'high'|'medium'|'low'
        }
        // Backward compatibility: if severity is used directly ('critical'|'warning'|'info')
        // Map selected chip ('high'|'medium'|'low') to severity buckets
        String? mappedSeverity;
        switch (sel) {
          case 'high':
            mappedSeverity = 'critical';
            break;
          case 'medium':
            mappedSeverity = 'warning';
            break;
          case 'low':
            mappedSeverity = 'info';
            break;
          default:
            mappedSeverity = sel;
        }
        return evSeverity == mappedSeverity;
      }).toList();
    }

    // Filter by date
    if (date != null) {
      final targetDate = DateTime(date!.year, date!.month, date!.day);
      filtered = filtered.where((event) {
        final eventDate = DateTime(
          event.timestamp.year,
          event.timestamp.month,
          event.timestamp.day,
        );
        return eventDate == targetDate;
      }).toList();
    }

    // Filter by date range
    if (dateRange != null) {
      filtered = filtered.where((event) {
        return event.timestamp.isAfter(dateRange!.start) &&
            event.timestamp.isBefore(
              dateRange!.end.add(const Duration(days: 1)),
            );
      }).toList();
    }

    return filtered;
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is NotificationFilter &&
        other.severity == severity &&
        other.date == date &&
        other.dateRange == dateRange;
  }

  @override
  int get hashCode => Object.hash(severity, date, dateRange);
}

/// Provider for the NotificationsRepository
///
/// This is a singleton provider that manages the notification state
/// across the entire app. It's not autoDispose to maintain the
/// WebSocket connection and cache.
final notificationsRepositoryProvider = Provider<NotificationsRepository>((ref) {
  final eventService = ref.watch(eventServiceProvider);
  final eventsDao = ref.watch(eventsDaoProvider).valueOrNull;
  final devicesDao = ref.watch(devicesDaoProvider).valueOrNull;

  // If DAOs are not ready yet, we need to handle this gracefully
  if (eventsDao == null) {
    throw StateError('EventsDao not initialized yet');
  }
  if (devicesDao == null) {
    throw StateError('DevicesDao not initialized yet');
  }

  final repository = NotificationsRepository(
    eventService: eventService,
    eventsDao: eventsDao,
    devicesDao: devicesDao,
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

/// Provider for notification filter state
///
/// Manages the current filter applied to the notifications list.
/// Use this to get/set severity, date, or date range filters.
///
/// Example:
/// ```dart
/// // Set severity filter
/// ref.read(notificationFilterProvider.notifier).state =
///   NotificationFilter(severity: 'high');
///
/// // Clear all filters
/// ref.read(notificationFilterProvider.notifier).state =
///   const NotificationFilter();
/// ```
final notificationFilterProvider =
    StateProvider.autoDispose<NotificationFilter>((ref) {
  return const NotificationFilter();
});

/// Provider for filtered notifications stream
///
/// Applies the current filter from notificationFilterProvider
/// to the notifications stream.
///
/// Example:
/// ```dart
/// final filteredEvents = ref.watch(filteredNotificationsProvider);
/// filteredEvents.when(
///   data: (events) => ListView.builder(...),
///   ...
/// )
/// ```
final filteredNotificationsProvider =
    StreamProvider.autoDispose<List<Event>>((ref) {
  final notificationsAsync = ref.watch(notificationsStreamProvider);
  final filter = ref.watch(notificationFilterProvider);

  return notificationsAsync.when(
    data: (events) {
      // Apply filter if active
      if (filter.isActive) {
        return Stream.value(filter.apply(events));
      }
      return Stream.value(events);
    },
    loading: () => Stream.value([]),
    error: (error, stack) => Stream.error(error, stack),
  );
});

/// Visibility state for the bottom notification banner.
/// Defaults to visible, but can be dismissed by the user and persisted for
/// the current session via [BannerPrefs].
// Banner visibility provider removed as the banner feature has been disabled.

/// Boot initializer to start NotificationsRepository only after DAOs are ready.
///
/// This avoids throwing "EventsDao not initialized yet" if something tries to
/// read the repository too early during app startup.
final notificationsBootInitializer = FutureProvider<void>((ref) async {
  // Await DAO readiness
  await ref.watch(eventsDaoProvider.future);
  await ref.watch(devicesDaoProvider.future);

  // Now initialize the repository (sets up websocket listeners etc.)
  // ignore: unused_result
  ref.read(notificationsRepositoryProvider);
});


