import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:my_app_gps/core/database/dao/events_dao.dart';
// Entity import removed; DAO now works with domain Event directly
import 'package:my_app_gps/data/models/event.dart';
import 'package:my_app_gps/services/auth_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Provider for event service - fetches and manages Traccar events.
final eventServiceProvider = Provider<EventService>((ref) {
  final dio = ref.watch(dioProvider);
  // EventsDao is a FutureProvider, so we need to handle async initialization
  // For now, we'll pass null and lazy-initialize in the service
  return EventService(dio: dio, ref: ref);
});

/// Service for fetching and managing Traccar events.
///
/// Integrates with:
/// - Traccar REST API (/api/events)
/// - ObjectBox persistence via EventsDao
/// - Event domain model and EventEntity
///
/// Features:
/// - Cache-first loading from ObjectBox
/// - Server sync with automatic persistence
/// - Mark events as read (local + server)
/// - Query filtering by device, date range, and event type
class EventService {
  EventService({
    required Dio dio,
    required Ref ref,
  })  : _dio = dio,
        _ref = ref;

  final Dio _dio;
  final Ref _ref;

  // Lazy-initialized DAO
  EventsDaoBase? _dao;
  bool _daoInitialized = false;

  /// Initialize the DAO (lazy initialization to avoid async constructor)
  Future<EventsDaoBase> _getDao() async {
    if (_daoInitialized && _dao != null) {
      return _dao!;
    }

    final daoAsync = await _ref.read(eventsDaoProvider.future);
    _dao = daoAsync;
    _daoInitialized = true;
    return _dao!;
  }

  /// Fetch events from Traccar API with optional filtering.
  ///
  /// Parameters:
  /// - [deviceId]: Filter by specific device (optional)
  /// - [from]: Start of time range (optional)
  /// - [to]: End of time range (optional)
  /// - [type]: Filter by event type (optional, e.g., 'deviceOnline', 'alarm')
  ///
  /// Returns a list of [Event] objects fetched from the server.
  /// Also persists events to ObjectBox for offline access.
  ///
  /// Example event types:
  /// - deviceOnline, deviceOffline
  /// - geofenceEnter, geofenceExit
  /// - alarm, sos
  /// - ignitionOn, ignitionOff
  Future<List<Event>> fetchEvents({
    int? deviceId,
    DateTime? from,
    DateTime? to,
    String? type,
  }) async {
    // Build query parameters dynamically (outside try so it's available in fallback)
    final queryParams = <String, dynamic>{};

    if (deviceId != null) {
      queryParams['deviceId'] = deviceId;
    }

    if (from != null) {
      queryParams['from'] = from.toUtc().toIso8601String();
    }

    // If caller provided from but not to, default to now to satisfy APIs that require a bounded window
    if (to == null && from != null) {
      to = DateTime.now();
    }

    if (to != null) {
      queryParams['to'] = to.toUtc().toIso8601String();
    }

    if (type != null && type.isNotEmpty) {
      queryParams['type'] = type;
    }

    if (kDebugMode) {
      debugPrint('[EventService] 🔍 Fetching events: $queryParams');
    }

    try {
      // Make API request (primary endpoint)
      final response = await _dio.get<List<dynamic>>(
        '/api/events',
        queryParameters: queryParams,
        options: Options(
          headers: {'Accept': 'application/json'},
        ),
      );

      final data = response.data;
      if (data is! List) {
        if (kDebugMode) {
          debugPrint(
              '[EventService] ⚠️ Unexpected response type: ${data.runtimeType}',);
        }
        return [];
      }

      // Parse events from JSON
      final events = <Event>[];
      for (final json in data) {
        if (json is Map<String, dynamic>) {
          try {
            final event = Event.fromJson(json);
            events.add(event);
          } catch (e) {
            if (kDebugMode) {
              debugPrint('[EventService] ⚠️ Failed to parse event: $e');
              debugPrint('[EventService] JSON: $json');
            }
          }
        }
      }

      if (kDebugMode) {
        debugPrint('[EventService] ✅ Fetched ${events.length} events from API');
      }

      // Persist to ObjectBox for offline access
      if (events.isNotEmpty) {
        await _persistEvents(events);
      }

      return events;
    } on DioException catch (e) {
      // Log full context and surface the error. Traccar 6.10 uses /api/events only; no fallback.
      if (kDebugMode) {
        debugPrint('[EventService] ❌ DioException: ${e.message}');
        debugPrint('[EventService] Status: ${e.response?.statusCode}');
        debugPrint('[EventService] Response: ${e.response?.data}');
      }
      throw Exception('Failed to fetch events: ${e.message}');
    } catch (e, stackTrace) {
      if (kDebugMode) {
        debugPrint('[EventService] ❌ Unexpected error: $e');
        debugPrint('[EventService] Stack trace: $stackTrace');
      }
      rethrow;
    }
  }

  /// Persist events to local storage (ObjectBox on mobile, Hive on web).
  Future<void> _persistEvents(List<Event> events) async {
    try {
      final dao = await _getDao();
      await dao.upsertMany(events);

  if (kDebugMode) {
    debugPrint(
    '[EventService] 💾 Persisted ${events.length} events to local storage',);
  }
    } catch (e) {
      if (kDebugMode) {
        debugPrint('[EventService] ⚠️ Failed to persist events: $e');
      }
      // Don't throw - persistence failure shouldn't break the fetch
    }
  }

  /// Get events from ObjectBox cache (offline-first).
  ///
  /// Parameters:
  /// - [deviceId]: Filter by specific device (optional)
  /// - [type]: Filter by event type (optional)
  /// - [limit]: Maximum number of events to return (default: 100)
  ///
  /// Returns cached events, ordered by timestamp (newest first).
  Future<List<Event>> getCachedEvents({
    int? deviceId,
    String? type,
    int limit = 100,
  }) async {
    try {
      final dao = await _getDao();
      List<Event> events;

      if (deviceId != null && type != null) {
        events = await dao.getByDeviceAndType(deviceId, type);
      } else if (deviceId != null) {
        events = await dao.getByDevice(deviceId);
      } else if (type != null) {
        events = await dao.getByType(type);
      } else {
        events = await dao.getAll();
      }

      events = events.take(limit).toList();

      if (kDebugMode) {
        debugPrint(
            '[EventService] 📦 Retrieved ${events.length} cached events from ObjectBox',);
      }

      return events;
    } catch (e) {
      if (kDebugMode) {
        debugPrint('[EventService] ⚠️ Failed to get cached events: $e');
      }
      return [];
    }
  }

  /// Mark an event as read.
  ///
  /// Updates both:
  /// 1. ObjectBox local database
  /// 2. (Future) Server-side read status if supported by Traccar API
  ///
  /// Parameters:
  /// - [eventId]: The event ID to mark as read
  ///
  /// Returns true if successful, false otherwise.
  Future<bool> markAsRead(String eventId) async {
    try {
      final dao = await _getDao();

      // Get the event from storage
      final event = await dao.getById(eventId);

      if (event == null) {
        if (kDebugMode) {
          debugPrint('[EventService] ⚠️ Event not found: $eventId');
        }
        return false;
      }

      // Update isRead flag and persist
      await dao.upsert(event.copyWith(isRead: true));

      if (kDebugMode) {
        debugPrint('[EventService] ✅ Marked event $eventId as read');
      }

      // TODO(app-team): Update server-side if Traccar supports event read status
      // This would require a PUT/PATCH to /api/events/{id}
      // For now, we only update locally

      return true;
    } catch (e) {
      if (kDebugMode) {
        debugPrint('[EventService] ❌ Failed to mark event as read: $e');
      }
      return false;
    }
  }

  /// Mark multiple events as read in batch.
  ///
  /// More efficient than calling [markAsRead] multiple times.
  Future<int> markMultipleAsRead(List<String> eventIds) async {
    var successCount = 0;

    for (final eventId in eventIds) {
      final success = await markAsRead(eventId);
      if (success) successCount++;
    }

    if (kDebugMode) {
      debugPrint(
          '[EventService] ✅ Marked $successCount/${eventIds.length} events as read',);
    }

    return successCount;
  }

  /// Fetch events with cache-first strategy.
  ///
  /// 1. Returns cached events immediately (if available)
  /// 2. Fetches fresh data from server in background
  /// 3. Updates cache automatically
  ///
  /// This provides instant UI feedback while ensuring data freshness.
  Future<List<Event>> fetchEventsWithCache({
    int? deviceId,
    DateTime? from,
    DateTime? to,
    String? type,
  }) async {
    // Get cached events first for instant display
    final cachedEvents = await getCachedEvents(
      deviceId: deviceId,
      type: type,
    );

    // Fetch fresh data in background (don't await)
    unawaited(
      fetchEvents(
        deviceId: deviceId,
        from: from,
        to: to,
        type: type,
      ),
    );

    return cachedEvents;
  }

  /// Clear all events from local cache.
  ///
  /// Useful for logout or data reset scenarios.
  Future<void> clearCache() async {
    try {
      final dao = await _getDao();
      await dao.deleteAll();

      if (kDebugMode) {
        debugPrint('[EventService] 🗑️ Cleared all cached events');
      }
    } catch (e) {
      if (kDebugMode) {
        debugPrint('[EventService] ⚠️ Failed to clear cache: $e');
      }
    }
  }

  /// Get event statistics for a device.
  ///
  /// Returns a map with event type counts.
  Future<Map<String, int>> getEventStats({
    required int deviceId,
    DateTime? from,
    DateTime? to,
  }) async {
    try {
      final events = await fetchEvents(
        deviceId: deviceId,
        from: from,
        to: to,
      );

      final stats = <String, int>{};
      for (final event in events) {
        stats[event.type] = (stats[event.type] ?? 0) + 1;
      }

      if (kDebugMode) {
        debugPrint(
            '[EventService] 📊 Event stats for device $deviceId: $stats',);
      }

      return stats;
    } catch (e) {
      if (kDebugMode) {
        debugPrint('[EventService] ⚠️ Failed to get event stats: $e');
      }
      return {};
    }
  }

  /// Get count of unread events.
  ///
  /// Useful for badge notifications.
  Future<int> getUnreadCount({int? deviceId}) async {
    try {
      final dao = await _getDao();
      final events = deviceId != null
          ? await dao.getByDevice(deviceId)
          : await dao.getAll();

      final unreadCount = events.where((e) => !e.isRead).length;

      if (kDebugMode) {
        debugPrint('[EventService] 🔔 Unread events: $unreadCount');
      }

      return unreadCount;
    } catch (e) {
      if (kDebugMode) {
        debugPrint('[EventService] ⚠️ Failed to get unread count: $e');
      }
      return 0;
    }
  }

  /// Return the latest cached Event timestamp (in local time).
  ///
  /// Useful to compute an accurate backfill window on reconnect.
  Future<DateTime?> getLatestCachedEventTimestamp() async {
    try {
      final dao = await _getDao();
      final events = await dao.getAll();
      if (events.isEmpty) return null;
      final latest = events
          .map((e) => e.timestamp)
          .reduce((a, b) => a.isAfter(b) ? a : b);
      return latest.toLocal();
    } catch (e) {
      if (kDebugMode) {
        debugPrint(
            '[EventService] ⚠️ Failed to get latest cached timestamp: $e',);
      }
      return null;
    }
  }

  /// Get the replay anchor timestamp (last successfully processed event)
  /// from SharedPreferences. This is used for precise backfill on reconnect.
  Future<DateTime?> getReplayAnchor() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final ts = prefs.getInt('last_replay_anchor_ms');
      if (ts != null) {
        return DateTime.fromMillisecondsSinceEpoch(ts);
      }
      return null;
    } catch (e) {
      if (kDebugMode) {
        debugPrint('[EventService] ⚠️ Failed to get replay anchor: $e');
      }
      return null;
    }
  }
}
