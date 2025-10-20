import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:my_app_gps/core/database/dao/events_dao.dart';
import 'package:my_app_gps/core/database/entities/event_entity.dart';
import 'package:my_app_gps/data/models/event.dart';
import 'package:my_app_gps/services/customer/customer_websocket.dart';
import 'package:my_app_gps/services/event_service.dart';

/// Repository for managing notification events with live updates.
///
/// Responsibilities:
/// - Provide stream of events for UI (real-time updates)
/// - Fetch and cache events from Traccar API via EventService
/// - Listen to WebSocket for real-time event notifications
/// - Manage read/unread state
/// - Synchronize between local ObjectBox cache and remote API
///
/// Architecture:
/// - Uses EventService for API calls and caching
/// - Uses EventsDao for direct ObjectBox queries
/// - Listens to CustomerEventsMessage from WebSocket
/// - Emits events through StreamController for UI reactivity
class NotificationsRepository {
  NotificationsRepository({
    required EventService eventService,
    required EventsDaoBase eventsDao,
    required Ref ref,
  })  : _eventService = eventService,
        _eventsDao = eventsDao,
        _ref = ref {
    _init();
  }

  final EventService _eventService;
  final EventsDaoBase _eventsDao;
  final Ref _ref;

  // Stream controller for emitting events to UI
  final _eventsController = StreamController<List<Event>>.broadcast();

  // Cached events list (in-memory)
  List<Event> _cachedEvents = [];
  bool _initialized = false;

  /// Stream of notification events for UI
  Stream<List<Event>> watchEvents() => _eventsController.stream;

  /// Initialize the repository
  void _init() {
    if (_initialized) return;
    _initialized = true;

    _log('🚀 Initializing NotificationsRepository');

    // Load initial cached events from ObjectBox
    _loadCachedEvents();

    // Listen to WebSocket for real-time events
    _listenToWebSocket();
  }

  /// Load cached events from ObjectBox and emit to stream
  Future<void> _loadCachedEvents() async {
    try {
      _log('📦 Loading cached events from ObjectBox');
      final entities = await _eventsDao.getAll();
      _cachedEvents = entities.map((e) => Event.fromEntity(e)).toList();

      // Sort by timestamp (newest first)
      _cachedEvents.sort((a, b) => b.timestamp.compareTo(a.timestamp));

      _log('📦 Loaded ${_cachedEvents.length} cached events');
      _emitEvents();
    } catch (e) {
      _log('❌ Failed to load cached events: $e');
    }
  }

  /// Listen to WebSocket for real-time event notifications
  void _listenToWebSocket() {
    try {
      _log('🔌 Subscribing to WebSocket events');

      // Listen to WebSocket provider changes
      _ref.listen<AsyncValue<CustomerWebSocketMessage>>(
        customerWebSocketProvider,
        (previous, next) {
          next.whenData((message) {
            if (message is CustomerEventsMessage) {
              _handleWebSocketEvents(message.events);
            }
          });
        },
        onError: (Object error, StackTrace stackTrace) {
          _log('❌ WebSocket error: $error');
        },
      );
    } catch (e) {
      _log('⚠️ Failed to subscribe to WebSocket: $e');
    }
  }

  /// Handle incoming WebSocket events
  Future<void> _handleWebSocketEvents(dynamic eventsData) async {
    try {
      _log('📨 Received WebSocket events');

      if (eventsData == null) {
        _log('⚠️ WebSocket events data is null');
        return;
      }

      // Parse events from WebSocket payload
      final List<Event> newEvents = [];

      if (eventsData is List) {
        for (final eventJson in eventsData) {
          if (eventJson is Map<String, dynamic>) {
            try {
              final event = Event.fromJson(eventJson);
              newEvents.add(event);
            } catch (e) {
              _log('⚠️ Failed to parse WebSocket event: $e');
            }
          }
        }
      } else if (eventsData is Map<String, dynamic>) {
        // Single event
        try {
          final event = Event.fromJson(eventsData);
          newEvents.add(event);
        } catch (e) {
          _log('⚠️ Failed to parse WebSocket event: $e');
        }
      }

      if (newEvents.isEmpty) {
        _log('⚠️ No valid events parsed from WebSocket');
        return;
      }

      _log('📨 Parsed ${newEvents.length} events from WebSocket');

      // Persist to ObjectBox via EventService
      final entities = newEvents.map((e) => e.toEntity()).toList();
      await _eventsDao.upsertMany(entities);

      // Update in-memory cache
      for (final event in newEvents) {
        // Check if event already exists
        final existingIndex = _cachedEvents.indexWhere((e) => e.id == event.id);
        if (existingIndex >= 0) {
          // Update existing event
          _cachedEvents[existingIndex] = event;
        } else {
          // Add new event
          _cachedEvents.insert(0, event); // Insert at beginning (newest first)
        }
      }

      // Sort again to maintain order
      _cachedEvents.sort((a, b) => b.timestamp.compareTo(a.timestamp));

      _log('✅ Persisted ${newEvents.length} WebSocket events');
      _emitEvents();
    } catch (e, stackTrace) {
      _log('❌ Error handling WebSocket events: $e');
      if (kDebugMode) {
        debugPrint('[NotificationsRepository] Stack trace: $stackTrace');
      }
    }
  }

  /// Get all events (with optional filtering)
  ///
  /// Parameters:
  /// - [unreadOnly]: If true, return only unread events
  /// - [deviceId]: Filter by specific device (optional)
  /// - [type]: Filter by event type (optional)
  Future<List<Event>> getAllEvents({
    bool unreadOnly = false,
    int? deviceId,
    String? type,
  }) async {
    try {
      _log('🔍 Getting all events (unreadOnly: $unreadOnly, deviceId: $deviceId, type: $type)');

      List<Event> events;

      // Fetch from cache first
      if (deviceId != null || type != null) {
        // Need to query ObjectBox for filtered results
        List<dynamic> entities;

        if (deviceId != null && type != null) {
          entities = await _eventsDao.getByDeviceAndType(deviceId, type);
        } else if (deviceId != null) {
          entities = await _eventsDao.getByDevice(deviceId);
        } else if (type != null) {
          entities = await _eventsDao.getByType(type);
        } else {
          entities = await _eventsDao.getAll();
        }

        events = entities
            .cast<EventEntity>()
            .map((e) => Event.fromEntity(e))
            .toList();
      } else {
        // Use cached events
        events = List.from(_cachedEvents);
      }

      // Filter by read status if requested
      if (unreadOnly) {
        events = events.where((e) => !e.isRead).toList();
      }

      _log('📊 Returning ${events.length} events');
      return events;
    } catch (e) {
      _log('❌ Failed to get all events: $e');
      return [];
    }
  }

  /// Refresh events from API
  ///
  /// Fetches latest events from Traccar server and updates cache.
  ///
  /// Parameters:
  /// - [deviceId]: Filter by specific device (optional)
  /// - [from]: Start date for time range (optional)
  /// - [to]: End date for time range (optional)
  /// - [type]: Filter by event type (optional)
  Future<void> refreshEvents({
    int? deviceId,
    DateTime? from,
    DateTime? to,
    String? type,
  }) async {
    try {
      _log('🔄 Refreshing events from API');

      // Fetch from API via EventService
      final freshEvents = await _eventService.fetchEvents(
        deviceId: deviceId,
        from: from,
        to: to,
        type: type,
      );

      _log('✅ Fetched ${freshEvents.length} events from API');

      // Reload cache from ObjectBox (EventService already persisted)
      await _loadCachedEvents();
    } catch (e) {
      _log('❌ Failed to refresh events: $e');
      rethrow; // Propagate error to UI for error handling
    }
  }

  /// Mark an event as read
  ///
  /// Updates the event's read status in both ObjectBox and in-memory cache.
  Future<void> markAsRead(String eventId) async {
    try {
      _log('✅ Marking event $eventId as read');

      // Update via EventService (handles ObjectBox persistence)
      final success = await _eventService.markAsRead(eventId);

      if (!success) {
        _log('⚠️ Failed to mark event as read (not found)');
        return;
      }

      // Update in-memory cache
      final index = _cachedEvents.indexWhere((e) => e.id == eventId);
      if (index >= 0) {
        _cachedEvents[index] = _cachedEvents[index].copyWith(isRead: true);
        _log('✅ Updated in-memory cache');
        _emitEvents();
      }
    } catch (e) {
      _log('❌ Failed to mark event as read: $e');
      rethrow;
    }
  }

  /// Mark multiple events as read (batch operation)
  Future<void> markMultipleAsRead(List<String> eventIds) async {
    try {
      _log('✅ Marking ${eventIds.length} events as read');

      // Update via EventService (handles ObjectBox persistence)
      final successCount = await _eventService.markMultipleAsRead(eventIds);

      _log('✅ Marked $successCount/${eventIds.length} events as read');

      // Update in-memory cache
      for (final eventId in eventIds) {
        final index = _cachedEvents.indexWhere((e) => e.id == eventId);
        if (index >= 0) {
          _cachedEvents[index] = _cachedEvents[index].copyWith(isRead: true);
        }
      }

      _emitEvents();
    } catch (e) {
      _log('❌ Failed to mark multiple events as read: $e');
      rethrow;
    }
  }

  /// Get count of unread events
  ///
  /// Returns the number of unread events in the cache.
  /// This is a synchronous operation using cached data.
  int getUnreadCount() {
    final count = _cachedEvents.where((e) => !e.isRead).length;
    _log('🔔 Unread count: $count');
    return count;
  }

  /// Get count of unread events for a specific device
  Future<int> getUnreadCountForDevice(int deviceId) async {
    try {
      final events = await _eventsDao.getByDevice(deviceId);
      final count = events.where((e) => !e.isRead).length;
      _log('🔔 Unread count for device $deviceId: $count');
      return count;
    } catch (e) {
      _log('❌ Failed to get unread count for device: $e');
      return 0;
    }
  }

  /// Clear all events from cache and ObjectBox
  Future<void> clearAllEvents() async {
    try {
      _log('🗑️ Clearing all events');

      await _eventService.clearCache();
      _cachedEvents.clear();
      _emitEvents();

      _log('✅ All events cleared');
    } catch (e) {
      _log('❌ Failed to clear events: $e');
      rethrow;
    }
  }

  /// Emit current events to stream
  void _emitEvents() {
    if (!_eventsController.isClosed) {
      _eventsController.add(List.unmodifiable(_cachedEvents));
    }
  }

  /// Structured logging
  void _log(String message) {
    if (kDebugMode) {
      debugPrint('[NotificationsRepository] $message');
    }
  }

  /// Dispose resources
  void dispose() {
    _log('🛑 Disposing NotificationsRepository');
    _eventsController.close();
  }
}
