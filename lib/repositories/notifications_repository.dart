import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:my_app_gps/core/data/vehicle_data_repository.dart';
import 'package:my_app_gps/core/database/dao/devices_dao.dart';
import 'package:my_app_gps/core/database/dao/events_dao.dart';
import 'package:my_app_gps/core/database/entities/event_entity.dart';
import 'package:my_app_gps/core/diagnostics/dev_diagnostics.dart';
import 'package:my_app_gps/data/models/event.dart';
import 'package:my_app_gps/services/customer/customer_websocket.dart';
import 'package:my_app_gps/services/event_service.dart';
import 'package:my_app_gps/services/notification/local_notification_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

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
  // Stream controller for emitting individual enriched events (banner usage)
  final _newEventsController = StreamController<Event>.broadcast();

  // WebSocket subscription
  StreamSubscription<CustomerWebSocketMessage>? _wsSubscription;
  // Vehicle repo backfill subscription (raw event maps rebroadcast on reconnect)
  StreamSubscription<Map<String, dynamic>>? _vehicleEventSubscription;
  // Provider subscription to customerWebSocketProvider to avoid dispose race
  ProviderSubscription<AsyncValue<CustomerWebSocketMessage>>?
      _wsProviderSubscription;

  // Cached events list (in-memory)
  List<Event> _cachedEvents = [];
  bool _initialized = false;
  bool _disposed = false; // Disposal guard
  // Recent event IDs for deduplication (rolling window)
  final Set<String> _recentEventIds = <String>{};
  Timer? _recentIdsCleanupTimer;
  int _newEventsSinceLastPersist = 0;
  static const int _persistThreshold = 20; // Persist after every 20 new events
  static const int _maxStoredIds = 1000; // Bounded dedup storage
  static const String _prefKey = 'recent_event_ids';
  static const String _anchorPrefKey = 'last_replay_anchor_ms';

  // Replay anchor - timestamp of last successfully processed event
  DateTime? _lastReplayAnchor;

  /// Public getter for replay anchor (used by VehicleDataRepository for backfill)
  DateTime? get lastReplayAnchor => _lastReplayAnchor;

  // Device name cache for fast lookups
  final Map<int, String> _deviceNameCache = {};

  /// Stream of notification events for UI
  ///
  /// Important: Emit a first value immediately (cached or empty) so any
  /// StreamProvider listening does not stay in the loading state waiting
  /// for the first onData from the broadcast controller.
  Stream<List<Event>> watchEvents() async* {
    _log('👀 watchEvents() called - someone is listening to the stream');

    // Emit current cache (or empty) right away to unblock UI
    if (_disposed) {
      _log('⏭️ Repository disposed, emitting empty list');
      yield const <Event>[];
    } else if (_cachedEvents.isNotEmpty) {
      _log('📤 Emitting initial cached events: ${_cachedEvents.length}');
      yield List.unmodifiable(_cachedEvents);
    } else {
      _log('📤 Emitting initial empty list');
      yield const <Event>[];
    }

    // Then forward any subsequent updates from the broadcast controller
    yield* _eventsController.stream;
  }

  /// Stream of enriched events as they are added (for banner/toast usage)
  Stream<Event> watchNewEvents() => _newEventsController.stream;

  /// Initialize the repository
  void _init() {
    if (_initialized) return;
    _initialized = true;

    _log('🚀 Initializing NotificationsRepository');

    // Start async initialization without blocking constructor
    _initAsync();
  }

  /// Async initialization to properly handle await operations
  Future<void> _initAsync() async {
    try {
      // Load persistent dedup IDs from SharedPreferences
      await _loadRecentEventIds();

      // Load replay anchor timestamp
      await _loadReplayAnchor();

      // Prefetch device names for fast lookups
      await _prefetchDeviceNames();

      // Load initial cached events from ObjectBox
      await _loadCachedEvents();

      // Listen to WebSocket for real-time events
      _listenToWebSocket();

      // Also listen to VehicleDataRepository.onEvent to capture backfilled events
      _listenToVehicleRepoEvents();

      // Periodically persist the dedup set to disk and prune old entries
      _recentIdsCleanupTimer?.cancel();
      _recentIdsCleanupTimer = Timer.periodic(const Duration(minutes: 5), (_) {
        unawaited(_persistRecentEventIds());
      });
    } catch (e) {
      _log('❌ Failed to initialize repository: $e');
    }
  }

  /// Load persistent dedup IDs from SharedPreferences on startup
  Future<void> _loadRecentEventIds() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final stored = prefs.getStringList(_prefKey) ?? <String>[];
      _recentEventIds.addAll(stored);
      _log('💾 Loaded ${stored.length} dedup IDs from prefs');
    } catch (e) {
      _log('⚠️ Failed to load dedup IDs: $e');
    }
  }

  /// Persist recent event IDs to SharedPreferences (bounded to max 1000 IDs)
  Future<void> _persistRecentEventIds() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      // Keep only the most recent _maxStoredIds entries
      final ids = _recentEventIds.take(_maxStoredIds).toList();
      await prefs.setStringList(_prefKey, ids);
      _newEventsSinceLastPersist = 0;
      _log('🧹 Dedup persisted (count: ${ids.length})');

      // Prune excess IDs from in-memory set to prevent unbounded growth
      if (_recentEventIds.length > _maxStoredIds) {
        final excess = _recentEventIds.length - _maxStoredIds;
        final pruned = _recentEventIds.toList().sublist(0, excess);
        _recentEventIds.removeAll(pruned);
        _log('🧹 Pruned $excess old dedup IDs from memory');
      }
    } catch (e) {
      _log('⚠️ Failed to persist dedup IDs: $e');
    }
  }

  /// Load replay anchor timestamp from SharedPreferences on startup
  Future<void> _loadReplayAnchor() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final ts = prefs.getInt(_anchorPrefKey);
      if (ts != null) {
        _lastReplayAnchor = DateTime.fromMillisecondsSinceEpoch(ts);
        _log('⏱️ Loaded replay anchor at $_lastReplayAnchor');
      } else {
        _log('⏱️ No replay anchor found — cold start');
      }
    } catch (e) {
      _log('⚠️ Failed to load replay anchor: $e');
    }
  }

  /// Update replay anchor after successfully processing an event
  Future<void> _updateReplayAnchor(DateTime timestamp) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setInt(_anchorPrefKey, timestamp.millisecondsSinceEpoch);
      _lastReplayAnchor = timestamp;
      _log('💾 Updated replay anchor → $timestamp');
    } catch (e) {
      _log('⚠️ Failed to update replay anchor: $e');
    }
  }

  /// Public helper to persist the latest event timestamp as a replay anchor.
  /// Useful for external callers or tests that want to set the anchor explicitly.
  Future<void> saveLatestEventTimestamp(DateTime ts) async {
    await _updateReplayAnchor(ts);
  }

  /// Public helper to retrieve the saved replay anchor timestamp from prefs.
  Future<DateTime?> getSavedLatestEventTimestamp() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final ms = prefs.getInt(_anchorPrefKey);
      return ms != null ? DateTime.fromMillisecondsSinceEpoch(ms) : null;
    } catch (e) {
      _log('⚠️ Failed to get saved replay anchor: $e');
      return null;
    }
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

      // Determine severity based on type if missing
      final resolvedSeverity =
          (event.severity != null && event.severity!.trim().isNotEmpty)
              ? event.severity!.toLowerCase()
              : _severityForEventType(event.type);

      // Attach to attributes as well for downstream consumers
      final attrs = Map<String, dynamic>.from(event.attributes);
      attrs['deviceName'] = resolvedName ?? 'Unknown Device';
      // Also attach priority in high/medium/low form for UI chips using attributes
      attrs['priority'] = _priorityForSeverity(resolvedSeverity);

      enrichedEvents.add(
        Event(
          id: event.id,
          deviceId: event.deviceId,
          deviceName: resolvedName ?? event.deviceName,
          type: event.type,
          timestamp: event.timestamp,
          message: event.message,
          severity: resolvedSeverity,
          positionId: event.positionId,
          geofenceId: event.geofenceId,
          attributes: attrs,
          isRead: event.isRead,
        ),
      );
    }

    return enrichedEvents;
  }

  /// Map event type to severity buckets used by UI filtering ('critical','warning','info').
  String _severityForEventType(String type) {
    // Normalize for robust matching
    final t = type.trim().toLowerCase();

    // High priority (critical): moving/stopped, overspeed, alarms
    if (t == 'devicemoving' ||
        t == 'devicestopped' ||
        t == 'moving' ||
        t == 'stopped') {
      return 'critical';
    }
    switch (t) {
      case 'overspeed':
      case 'alarm':
      case 'sos':
        return 'critical';
      // Medium priority (warning): device online/offline, geofence exits if desired
      case 'deviceonline':
      case 'deviceoffline':
        return 'warning';
      // Low priority (info): ignition changes
      case 'ignitionon':
      case 'ignitionoff':
        return 'info';
      // Keep previously treated geofence exits as medium to align with mock variety
      case 'geofenceexit':
        return 'warning';
      default:
        return 'info';
    }
  }

  /// Map severity to priority chip values ('high','medium','low')
  String _priorityForSeverity(String severity) {
    switch (severity.toLowerCase()) {
      case 'critical':
        return 'high';
      case 'warning':
        return 'medium';
      default:
        return 'low';
    }
  }

  /// Load cached events from ObjectBox and emit to stream
  Future<void> _loadCachedEvents() async {
    try {
      _log('📦 Loading cached events from ObjectBox');
      final entities = await _eventsDao.getAll();
      final events = entities.map(Event.fromEntity).toList();

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
  /// Uses Riverpod's ref.listen to subscribe to the StreamProvider in a
  /// lifecycle-safe manner, avoiding awaiting the provider's future which can
  /// be disposed during initialization and cause state errors.
  void _listenToWebSocket() {
    try {
      _log('🔌 Subscribing to WebSocket events');

      if (_disposed) {
        _log('⏭️ Skipping WebSocket subscription: repository already disposed');
        return;
      }

      // Close any existing subscription before creating a new one
      _wsProviderSubscription?.close();
      _wsSubscription?.cancel();

      _wsProviderSubscription =
          _ref.listen<AsyncValue<CustomerWebSocketMessage>>(
        customerWebSocketProvider,
        (AsyncValue<CustomerWebSocketMessage>? prev,
            AsyncValue<CustomerWebSocketMessage> next,) {
          if (_disposed) return;

          next.when(
            data: (CustomerWebSocketMessage message) {
              if (message is CustomerEventsMessage) {
                _log('🔔 CustomerEventsMessage received');
                unawaited(_handleWebSocketEvents(message.events));
              }
            },
            error: (Object err, StackTrace st) {
              _log('❌ WebSocket provider error: $err');
              if (kDebugMode) {
                debugPrint(
                    '[NotificationsRepository] WebSocket error stack: $st',);
              }
            },
            loading: () {
              // No-op
            },
          );
        },
        fireImmediately: false,
      );

      _log('✅ WebSocket subscription (ref.listen) initiated');
    } catch (e) {
      _log('⚠️ Failed to subscribe to WebSocket: $e');
    }
  }

  /// Listen to VehicleDataRepository raw events stream.
  ///
  /// VehicleDataRepository emits raw event maps on reconnect backfill.
  /// We convert them into Event models and push through the same pipeline
  /// as live WebSocket events to update cache/UI immediately.
  void _listenToVehicleRepoEvents() {
    try {
      _log('🧩 Subscribing to VehicleDataRepository.onEvent');
      _vehicleEventSubscription?.cancel();
      final vehicleRepo = _ref.read(vehicleDataRepositoryProvider);
      _vehicleEventSubscription = vehicleRepo.onEvent.listen((raw) {
        if (_disposed) return;
        try {
          final event = Event.fromJson(raw);
          // Reuse common addEvent path (enriches, persists, updates cache, anchor, notifications)
          unawaited(addEvent(event));
        } catch (e) {
          _log('⚠️ Failed to parse VehicleRepo event: $e');
        }
      });
      _log('✅ VehicleRepo events subscription started');
    } catch (e) {
      _log('⚠️ Failed to subscribe to VehicleRepo events: $e');
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
      final newEvents = <Event>[];

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

      // Enrich events with device names (timestamps already local in Event.fromJson)
      final enrichedEvents = await _enrichEventsWithDeviceNames(newEvents);

      // Persist to ObjectBox via EventService
      final entities = enrichedEvents.map((e) => e.toEntity()).toList();
      await _eventsDao.upsertMany(entities);

      // Update replay anchor with the latest event timestamp
      if (enrichedEvents.isNotEmpty) {
        final latestEvent = enrichedEvents.reduce(
          (a, b) => a.timestamp.isAfter(b.timestamp) ? a : b,
        );
        await _updateReplayAnchor(latestEvent.timestamp);
      }

      // Update in-memory cache
      for (final event in enrichedEvents) {
        // Deduplicate recently seen events by id
        if (_recentEventIds.contains(event.id)) {
          _log('🔁 Skipping duplicate event ${event.id}');
          if (kDebugMode) {
            DevDiagnostics.instance.incrementDedupSkipped();
          }
          continue;
        }
        _recentEventIds.add(event.id);
        _newEventsSinceLastPersist++;
        // Auto-persist after threshold to keep disk state fresh
        if (_newEventsSinceLastPersist >= _persistThreshold) {
          unawaited(_persistRecentEventIds());
        }
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
  /// 
  /// For backfilled events (reconnection): Shows notifications for events within
  /// the last 30 minutes, even if marked as read, to ensure users see missed events
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

      // Time window for showing notifications on backfilled events
      final notificationWindow = DateTime.now().subtract(const Duration(minutes: 30));

      // Filter events that should trigger notifications
      final notifiableEvents = events.where((event) {
        // Must be a critical event type
        if (!criticalTypes.contains(event.type.toLowerCase())) {
          return false;
        }
        
        // Recent events (within 30 min) should show regardless of read status
        // This ensures missed events during disconnection are shown
        final isRecent = event.timestamp.isAfter(notificationWindow);
        if (isRecent) {
          return true; // Show notification for recent events
        }
        
        // Older events only if unread
        return !event.isRead;
      }).toList();

      if (notifiableEvents.isEmpty) {
        _log('⏭️ No notifiable events in batch');
        return;
      }

      // Log breakdown of recent vs older events
      final recentCount = notifiableEvents.where(
        (e) => e.timestamp.isAfter(notificationWindow)
      ).length;
      _log('🔔 Showing ${notifiableEvents.length} notifications ($recentCount recent, ${notifiableEvents.length - recentCount} older unread)');

      // Show individual notifications (deviceName already enriched)
      for (final event in notifiableEvents) {
        final isRecent = event.timestamp.isAfter(notificationWindow);
        if (isRecent && event.isRead) {
          _log('📤 Showing notification for backfilled event: ${event.type} (${event.deviceName})');
        }
        await LocalNotificationService.tryShowEventNotification(event);
      }

      // Show batch summary if multiple events
      if (notifiableEvents.length > 3) {
        await LocalNotificationService.instance
            .showBatchSummary(notifiableEvents);
      }
    } catch (e) {
      _log('⚠️ Failed to show notifications: $e');
    }
  }

  /// Add a single event coming from an external stream (e.g., VehicleRepo.onEvent)
  /// Always caches/persists the event, regardless of toggle. Banner/system push
  /// remains controlled elsewhere (LocalNotificationService already checks the toggle).
  Future<void> addEvent(Event event) async {
    try {
      _log('addEvent called for ${event.type}');
      
      // For recent events (within last hour), bypass duplicate check to ensure
      // backfilled events are properly processed and notifications are shown
      final oneHourAgo = DateTime.now().subtract(const Duration(hours: 1));
      final isRecent = event.timestamp.isAfter(oneHourAgo);
      
      // Deduplicate by id (but allow recent events through for notifications)
      if (_recentEventIds.contains(event.id) && !isRecent) {
        _log('🔁 Skipping duplicate addEvent ${event.id} (older than 1h)');
        if (kDebugMode) {
          DevDiagnostics.instance.incrementDedupSkipped();
        }
        return;
      }
      
      // For recent events that are duplicates, still show notification but skip caching
      final isDuplicate = _recentEventIds.contains(event.id);
      if (isDuplicate && isRecent) {
        _log('🔄 Processing recent duplicate event ${event.id} for notifications only');
      }
      
      _recentEventIds.add(event.id);
      _newEventsSinceLastPersist++;
      // Auto-persist after threshold
      if (_newEventsSinceLastPersist >= _persistThreshold) {
        unawaited(_persistRecentEventIds());
      }
      // Timestamps already normalized in Event.fromJson
      // Enrich with device name and priority
      final enrichedList = await _enrichEventsWithDeviceNames([event]);
      final enriched = enrichedList.first;

      // If this is a recent duplicate, only show notification, don't re-cache
      if (isDuplicate && isRecent) {
        _log('📤 Showing notification for recent duplicate event');
        await _showNotificationsForEvents([enriched]);
        return; // Skip caching and list emission
      }

      // Persist to ObjectBox
      await _eventsDao.upsertMany([enriched.toEntity()]);

      // Update replay anchor after successful persistence
      await _updateReplayAnchor(enriched.timestamp);

      // Update in-memory cache (dedupe by id)
      final existingIndex =
          _cachedEvents.indexWhere((e) => e.id == enriched.id);
      if (existingIndex >= 0) {
        _cachedEvents[existingIndex] = enriched;
      } else {
        _cachedEvents.insert(0, enriched);
      }
      _cachedEvents.sort((a, b) => b.timestamp.compareTo(a.timestamp));

      _log('✅ Cached ${enriched.type}');

      // Show any system notifications (toggle checked inside LocalNotificationService too)
      await _showNotificationsForEvents([enriched]);

      // Emit single enriched event for banner listeners
      if (!_newEventsController.isClosed) {
        _log('🔁 Emitting event to banner stream');
        // Ensure delivery occurs on the next microtask to avoid race conditions
        unawaited(Future.microtask(() {
          if (!_newEventsController.isClosed) {
            _newEventsController.add(enriched);
          }
        }),);
      }

      // Emit updated list
      _emitEvents();
    } catch (e, st) {
      _log('❌ addEvent error: $e');
      if (kDebugMode) {
        debugPrint('[NotificationsRepository] addEvent stack: $st');
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
      _log(
          '🔍 Getting all events (unreadOnly: $unreadOnly, deviceId: $deviceId, type: $type)',);

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

        events = entities.cast<EventEntity>().map(Event.fromEntity).toList();
      } else {
        // Use cached events when available; if empty (for example very early
        // during app startup before _loadCachedEvents() finishes), fall back to
        // querying ObjectBox directly so callers like unread-only counts don't
        // temporarily see zero.
        if (_cachedEvents.isNotEmpty) {
          events = List.from(_cachedEvents);
        } else {
          _log('📦 In-memory cache empty → falling back to DAO.getAll()');
          final entities = await _eventsDao.getAll();
          events = entities.cast<EventEntity>().map(Event.fromEntity).toList();
          // Note: We intentionally skip enrichment here for speed since most
          // callers (e.g., unread counts) don't require deviceName/priority.
          // Full enrichment is performed by _loadCachedEvents() and for
          // live updates via WebSocket.
        }
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
      // Fallback to local cache so UI still shows something
      await _loadCachedEvents();
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

  /// Returns the timestamp of the most recent event known to the app (local time).
  ///
  /// Uses in-memory cache if present; otherwise queries ObjectBox directly.
  Future<DateTime?> getLatestEventTimestamp() async {
    try {
      if (_cachedEvents.isNotEmpty) {
        // _cachedEvents is maintained newest-first
        return _cachedEvents.first.timestamp;
      }

      final entities = await _eventsDao.getAll();
      if (entities.isEmpty) return null;
      final latestMs = entities
          .cast<EventEntity>()
          .map((e) => e.eventTimeMs)
          .reduce((a, b) => a > b ? a : b);
      return DateTime.fromMillisecondsSinceEpoch(latestMs).toLocal();
    } catch (e) {
      _log('⚠️ Failed to get latest event timestamp: $e');
      return null;
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

  /// Delete a single event by id from local cache and ObjectBox
  Future<void> deleteEvent(String eventId) async {
    try {
      _log('🗑️ Deleting event $eventId');
      await _eventsDao.delete(eventId);

      // Remove from in-memory cache
      _cachedEvents.removeWhere((e) => e.id == eventId);

      // Also clean from recent dedup set
      _recentEventIds.remove(eventId);

      _emitEvents();
      _log('✅ Event $eventId deleted');
    } catch (e) {
      _log('❌ Failed to delete event: $e');
      rethrow;
    }
  }

  /// Emit current events to stream
  void _emitEvents() {
    if (_disposed) {
      _log('⏭️ Skipping emit: repository disposed');
      return;
    }

    if (!_eventsController.isClosed) {
      _log('📤 Emitting ${_cachedEvents.length} events to stream');
      _eventsController.add(List.unmodifiable(_cachedEvents));
    } else {
      _log('⚠️ Cannot emit: events controller is closed');
    }
  }

  /// Synchronous snapshot of the current in-memory cached events.
  ///
  /// Returns an unmodifiable list. Safe to call at any time; if the repository
  /// hasn't loaded cached events yet, this may be an empty list. Useful for
  /// UI providers that want to avoid transient loading states and show the
  /// best-known data immediately while the stream initializes.
  List<Event> getCurrentEvents() {
    return List.unmodifiable(_cachedEvents);
  }

  /// Structured logging
  void _log(String message) {
    if (kDebugMode) {
      debugPrint('[NotificationsRepository] $message');
    }
  }

  /// Dispose resources
  void dispose() {
    if (_disposed) {
      _log('⚠️ Double dispose prevented');
      return;
    }
    _disposed = true;

    _log('🛑 Disposing NotificationsRepository');

    // Persist dedup state before cleanup
    unawaited(_persistRecentEventIds());

    // Cancel WebSocket subscriptions
    _wsSubscription?.cancel();
    _wsProviderSubscription?.close();
    _vehicleEventSubscription?.cancel();

    // Close stream controllers
    _eventsController.close();
    _newEventsController.close();
    _recentIdsCleanupTimer?.cancel();

    // Clear caches
    _cachedEvents.clear();
    _deviceNameCache.clear();
    _recentEventIds.clear();

    _log('✅ Repository disposed');
  }
}
