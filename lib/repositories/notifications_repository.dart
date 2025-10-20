import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:my_app_gps/core/database/dao/devices_dao.dart';
import 'package:my_app_gps/core/database/dao/events_dao.dart';
import 'package:my_app_gps/core/database/entities/event_entity.dart';
import 'package:my_app_gps/data/models/event.dart';
import 'package:my_app_gps/core/data/vehicle_data_repository.dart';
import 'package:my_app_gps/services/customer/customer_websocket.dart';
import 'package:my_app_gps/services/event_service.dart';
import 'package:my_app_gps/services/notification/local_notification_service.dart';

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
    required DevicesDaoBase devicesDao,
    required Ref ref,
  })  : _eventService = eventService,
        _eventsDao = eventsDao,
        _devicesDao = devicesDao,
        _ref = ref {
    _init();
  }

  final EventService _eventService;
  final EventsDaoBase _eventsDao;
  final DevicesDaoBase _devicesDao;
  final Ref _ref;

  // Stream controller for emitting events to UI
  final _eventsController = StreamController<List<Event>>.broadcast();

  // WebSocket subscription
  StreamSubscription<CustomerWebSocketMessage>? _wsSubscription;

  // Cached events list (in-memory)
  List<Event> _cachedEvents = [];
  bool _initialized = false;

  // Device name cache for fast lookups
  final Map<int, String> _deviceNameCache = {};

  /// Stream of notification events for UI
  Stream<List<Event>> watchEvents() => _eventsController.stream;

  /// Initialize the repository
  void _init() {
    if (_initialized) return;
    _initialized = true;

    _log('🚀 Initializing NotificationsRepository');

    // Prefetch device names for fast lookups
    _prefetchDeviceNames();

    // Load initial cached events from ObjectBox
    _loadCachedEvents();

    // Listen to WebSocket for real-time events
    _listenToWebSocket();
  }

  /// Prefetch all device names into cache for fast lookups
  Future<void> _prefetchDeviceNames() async {
    try {
      _log('📋 Prefetching device names...');
      final devices = await _devicesDao.getAll();
      for (final device in devices) {
        _deviceNameCache[device.deviceId] = device.name;
      }
      _log('📋 Cached ${_deviceNameCache.length} device names');
    } catch (e) {
      _log('⚠️ Failed to prefetch device names: $e');
    }
  }

  /// Get device name from cache or fetch from DAO
  Future<String?> _getDeviceName(int deviceId) async {
    // Check cache first
    if (_deviceNameCache.containsKey(deviceId)) {
      return _deviceNameCache[deviceId];
    }

    // Fetch from DAO and cache
    try {
      final device = await _devicesDao.getById(deviceId);
      if (device != null) {
        _deviceNameCache[deviceId] = device.name;
        return device.name;
      }
    } catch (e) {
      _log('⚠️ Failed to fetch device name for deviceId=$deviceId: $e');
    }

    return null; // Fallback to null if not found
  }

  /// Enrich events with device names from cache/DAO
  Future<List<Event>> _enrichEventsWithDeviceNames(List<Event> events) async {
    final enrichedEvents = <Event>[];
    final vehicleRepo = _ref.read(vehicleDataRepositoryProvider);

    for (final event in events) {
      var resolvedName = event.deviceName;
      if (resolvedName == null || resolvedName.trim().isEmpty) {
        // 1) Try resolve from VehicleRepo cache
        resolvedName = vehicleRepo.resolveDeviceName(event.deviceId);

        // 2) If still unknown, try local DAO cache once
        if (resolvedName == 'Unknown Device') {
          final daoName = await _getDeviceName(event.deviceId);
          if (daoName != null && daoName.trim().isNotEmpty) {
            resolvedName = daoName;
          }
        }

        // 3) If still unknown, fetch once lazily via VehicleRepo
        if (resolvedName == 'Unknown Device') {
          try {
            final device = await vehicleRepo.fetchDeviceById(event.deviceId);
            final name = device != null ? device['name'] as String? : null;
            if (name != null && name.trim().isNotEmpty) {
              resolvedName = name;
              vehicleRepo.cacheDevice(device!);
            }
          } catch (_) {
            // ignore
          }
        }
      }

      // Attach to attributes as well for downstream consumers
      final attrs = Map<String, dynamic>.from(event.attributes);
      attrs['deviceName'] = resolvedName ?? 'Unknown Device';

      if (kDebugMode) {
        debugPrint('[NotificationsRepository] 🧩 Device name resolved for ${event.deviceId} → ${attrs['deviceName']}');
      }

      enrichedEvents.add(
        Event(
          id: event.id,
          deviceId: event.deviceId,
          deviceName: resolvedName ?? event.deviceName,
          type: event.type,
          timestamp: event.timestamp,
          message: event.message,
          severity: event.severity,
          positionId: event.positionId,
          geofenceId: event.geofenceId,
          attributes: attrs,
          isRead: event.isRead,
        ),
      );
    }

    return enrichedEvents;
  }

  /// Load cached events from ObjectBox and emit to stream
  Future<void> _loadCachedEvents() async {
    try {
      _log('📦 Loading cached events from ObjectBox');
      final entities = await _eventsDao.getAll();
      final events = entities.map((e) => Event.fromEntity(e)).toList();

      // Enrich with device names
      _cachedEvents = await _enrichEventsWithDeviceNames(events);

      // Sort by timestamp (newest first)
      _cachedEvents.sort((a, b) => b.timestamp.compareTo(a.timestamp));

      _log('📦 Loaded ${_cachedEvents.length} cached events');
      _emitEvents();
    } catch (e) {
      _log('❌ Failed to load cached events: $e');
    }
  }

  /// Listen to WebSocket for real-time event notifications
  /// 
  /// NOTE: We subscribe directly to the stream provider to avoid
  /// issues with ref.listen() being called from constructor context.
  /// 
  /// The use of .stream is deprecated but we suppress the warning as
  /// this is the correct pattern for subscribing from repository init.
  void _listenToWebSocket() {
    try {
      _log('🔌 Subscribing to WebSocket events');

      // Subscribe directly to the WebSocket provider stream
      // The provider returns a Stream<CustomerWebSocketMessage>
      _ref.read(customerWebSocketProvider.future).then((firstMessage) {
        _log('✅ WebSocket provider active, first message received');
        
        // Now subscribe to ongoing messages
        // ignore: deprecated_member_use
        _wsSubscription = _ref.read(customerWebSocketProvider.stream).listen(
          (message) {
            if (message is CustomerEventsMessage) {
              _log('🔔 CustomerEventsMessage received');
              _handleWebSocketEvents(message.events);
            }
          },
          onError: (dynamic error) {
            _log('❌ WebSocket subscription error: $error');
          },
        );
      }).catchError((dynamic error) {
        _log('❌ Failed to get initial WebSocket message: $error');
      });

      _log('✅ WebSocket subscription initiated');
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

      // Enrich events with device names
      final enrichedEvents = await _enrichEventsWithDeviceNames(newEvents);

      // Persist to ObjectBox via EventService
      final entities = enrichedEvents.map((e) => e.toEntity()).toList();
      await _eventsDao.upsertMany(entities);

      // Update in-memory cache
      for (final event in enrichedEvents) {
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

      _log('✅ Persisted ${enrichedEvents.length} WebSocket events');
      
      // Show local push notifications for critical events
      await _showNotificationsForEvents(enrichedEvents);
      
      _emitEvents();
    } catch (e, stackTrace) {
      _log('❌ Error handling WebSocket events: $e');
      if (kDebugMode) {
        debugPrint('[NotificationsRepository] Stack trace: $stackTrace');
      }
    }
  }

  /// Show local push notifications for critical events
  /// 
  /// Only shows notifications for unread events with critical severity.
  /// Supports: overspeed, ignition on/off, device offline/online, geofence enter/exit
  Future<void> _showNotificationsForEvents(List<Event> events) async {
    try {
      final criticalTypes = [
        'overspeed',
        'ignitionon',
        'ignitionoff',
        'deviceonline',
        'deviceoffline',
        'geofenceenter',
        'geofenceexit',
        'alarm',
      ];

      // Filter events that should trigger notifications
      final notifiableEvents = events.where((event) {
        return !event.isRead && 
               criticalTypes.contains(event.type.toLowerCase());
      }).toList();

      if (notifiableEvents.isEmpty) {
        _log('⏭️ No notifiable events in batch');
        return;
      }

      _log('🔔 Showing ${notifiableEvents.length} notifications');

      // Show individual notifications
      for (final event in notifiableEvents) {
        await LocalNotificationService.instance.showEventNotification(event);
      }

      // Show batch summary if multiple events
      if (notifiableEvents.length > 3) {
        await LocalNotificationService.instance.showBatchSummary(notifiableEvents);
      }
    } catch (e) {
      _log('⚠️ Failed to show notifications: $e');
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
    _wsSubscription?.cancel();
    _eventsController.close();
  }
}
