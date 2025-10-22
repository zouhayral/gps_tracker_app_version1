import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'dart:async';
import 'package:flutter/foundation.dart';

import 'package:my_app_gps/core/database/dao/devices_dao.dart';
import 'package:my_app_gps/core/database/dao/events_dao.dart';
import 'package:my_app_gps/core/utils/banner_prefs.dart' show BannerPrefs;
import 'package:my_app_gps/core/diagnostics/dev_diagnostics.dart';
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
  ref.onDispose(repository.dispose);

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
    StreamProvider<List<Event>>((ref) {
  final repository = ref.watch(notificationsRepositoryProvider);
  return repository.watchEvents();
});

/// Search query for notifications screen (raw, immediate input)
final searchQueryProvider = StateProvider.autoDispose<String>((_) => '');

/// Debounced stream of the search query to prevent over-triggering filters while typing.
final debouncedQueryProvider = StreamProvider.autoDispose<String>((ref) async* {
  final controller = StreamController<String>();
  Timer? t;

  // Seed with current value after debounce to keep behaviour consistent
  void emitDebounced(String value) {
    t?.cancel();
    t = Timer(const Duration(milliseconds: 250), () {
      // Reset to first page on new debounced query
      ref.read(notificationsPageProvider.notifier).state = 1;
      if (!controller.isClosed) controller.add(value);
    });
  }

  emitDebounced(ref.read(searchQueryProvider));

  ref.listen<String>(searchQueryProvider, (prev, next) {
    emitDebounced(next);
  });

  ref.onDispose(() {
    t?.cancel();
    controller.close();
  });

  yield* controller.stream;
});

/// Filtered notifications provider with optional heavy filtering offloaded to an isolate.
/// Uses a best-effort approach: returns cached events immediately when underlying streams
/// are still loading to avoid blocking the UI.
final filteredNotificationsProvider =
    FutureProvider.autoDispose<List<Event>>((ref) async {
  // Base events stream (may be loading); fall back to current cache if needed
  final repo = ref.watch(notificationsRepositoryProvider);
  final baseAsync = ref.watch(notificationsStreamProvider);
  final baseEvents = baseAsync.maybeWhen(
    data: (events) => events,
    orElse: repo.getCurrentEvents,
  );

  // Debounced search query
  final query = (await ref.watch(debouncedQueryProvider.future)).trim();
  if (query.isEmpty) {
    // Reset metric when not filtering
    if (kDebugMode) {
      DevDiagnostics.instance.recordFilterCompute(0);
    }
    return baseEvents;
  }

  // Lightweight in-thread filter for smaller lists
  if (baseEvents.length < 1000) {
    final q = query.toLowerCase();
    final sw = Stopwatch()..start();
    final out = baseEvents.where((e) {
      final msg = (e.message ?? '').toLowerCase();
      final dev = (e.deviceName ?? '').toLowerCase();
      final typ = e.type.toLowerCase();
      return msg.contains(q) || dev.contains(q) || typ.contains(q);
    }).toList(growable: false);
    sw.stop();
    // Record metric
    if (kDebugMode) {
      DevDiagnostics.instance.recordFilterCompute(sw.elapsedMilliseconds);
    }
    return out;
  }

  // Offload heavy filtering to a background isolate using compute().
  final q = query.toLowerCase();
  final proxies = List<Map<String, Object?>>.generate(baseEvents.length, (i) {
    final e = baseEvents[i];
    final msg = (e.message ?? '').toLowerCase();
    final dev = (e.deviceName ?? '').toLowerCase();
    final typ = e.type.toLowerCase();
    return {
      'i': i,
      't': '$msg\n$dev\n$typ',
    };
  }, growable: false,);

  final sw = Stopwatch()..start();
  final indices = await compute<List<Map<String, Object?>>, List<int>>(
    _filterIndices,
    proxies..add({'q': q}),
  );
  sw.stop();
  if (kDebugMode) {
    DevDiagnostics.instance.recordFilterCompute(sw.elapsedMilliseconds);
  }
  // Map back to original events in stable order
  return [for (final i in indices) baseEvents[i]];
});

/// Current page index for paginated notifications (1-based).
final notificationsPageProvider = StateProvider.autoDispose<int>((_) => 1);

/// Page size constant for pagination.
const int kNotificationsPageSize = 50;

/// Paged notifications based on filtered results and current page.
final pagedNotificationsProvider =
    Provider.autoDispose<List<Event>>((ref) {
  final filteredAsync = ref.watch(filteredNotificationsProvider);
  final page = ref.watch(notificationsPageProvider);
  final effective = filteredAsync.maybeWhen(
    data: (list) => list,
    orElse: () => ref.watch(notificationsRepositoryProvider).getCurrentEvents(),
  );
  final end = (page * kNotificationsPageSize).clamp(0, effective.length);
  return effective.sublist(0, end);
});

/// Per-notification provider by id to enable selective listening in item widgets.
final notificationByIdProvider =
    Provider.autoDispose.family<Event?, String>((ref, id) {
  final repo = ref.watch(notificationsRepositoryProvider);
  final listAsync = ref.watch(notificationsStreamProvider);
  final list = listAsync.maybeWhen(
    data: (v) => v,
    orElse: repo.getCurrentEvents,
  );
  for (final e in list) {
    if (e.id == id) return e;
  }
  return null;
});

/// Top-level function for compute() to filter indices based on a lowercased query.
/// Expects the last element in the list to contain the query under key 'q'.
List<int> _filterIndices(List<Map<String, Object?>> items) {
  if (items.isEmpty) return const <int>[];
  final q = (items.removeLast()['q'] as String?) ?? '';
  if (q.isEmpty) return List<int>.generate(items.length, (i) => i);
  final res = <int>[];
  for (final m in items) {
    final t = (m['t'] as String?) ?? '';
    if (t.contains(q)) res.add(m['i']! as int);
  }
  return res;
}

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
  // Temporarily disable API refresh to test cached events display
  // final repository = ref.watch(notificationsRepositoryProvider);
  // final now = DateTime.now();
  // final thirtyDaysAgo = now.subtract(const Duration(days: 30));
  // await repository.refreshEvents(
  //   from: thirtyDaysAgo,
  //   to: now,
  // );
  
  // Just return immediately - let cached events show
  return;
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

/// Provider for deleting a single notification by id
final deleteNotificationProvider =
    FutureProvider.autoDispose.family<void, String>((ref, eventId) async {
  final repository = ref.watch(notificationsRepositoryProvider);
  await repository.deleteEvent(eventId);
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
/// Filter state is automatically persisted to SharedPreferences
/// and restored on app restart.
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



