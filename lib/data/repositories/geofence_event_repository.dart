import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:my_app_gps/core/database/dao/geofences_dao.dart';
import 'package:my_app_gps/data/models/geofence_event.dart';

/// Repository for managing geofence events with local persistence.
///
/// Responsibilities:
/// - Provide stream of geofence events for UI
/// - Record entry/exit/dwell events
/// - Manage event status (pending, acknowledged, archived)
/// - Auto-cleanup old events
/// - [Future] Sync with Firebase Firestore
///
/// Architecture:
/// - Uses GeofencesDAO for ObjectBox event operations
/// - Stream controller for reactive UI updates
/// - In-memory cache for fast access
/// - Automatic cleanup of old archived events
class GeofenceEventRepository {
  GeofenceEventRepository({
    required GeofencesDaoBase dao,
  }) : _dao = dao {
    _init();
  }

  final GeofencesDaoBase _dao;

  // Stream controller for emitting events to UI
  final _eventsController = StreamController<List<GeofenceEvent>>.broadcast();

  // Cached events list (in-memory)
  List<GeofenceEvent> _cachedEvents = [];
  bool _initialized = false;
  bool _disposed = false;

  // Auto-cleanup timer
  Timer? _cleanupTimer;

  /// Stream of geofence events for UI
  ///
  /// Supports optional filtering by geofenceId or deviceId.
  Stream<List<GeofenceEvent>> watchEvents({
    String? geofenceId,
    String? deviceId,
  }) async* {
    _log('👀 watchEvents() called (geofenceId: $geofenceId, deviceId: $deviceId)');

    // Emit current cache immediately (filtered)
    if (_disposed) {
      _log('⏭️ Repository disposed, emitting empty list');
      yield const <GeofenceEvent>[];
    } else if (_cachedEvents.isNotEmpty) {
      final filteredEvents = _filterEvents(_cachedEvents, geofenceId, deviceId);
      _log('📤 Emitting initial cached events: ${filteredEvents.length}');
      yield List.unmodifiable(filteredEvents);
    } else {
      _log('📤 Emitting initial empty list');
      yield const <GeofenceEvent>[];
    }

    // Forward subsequent updates from broadcast controller (filtered)
    yield* _eventsController.stream.map((allEvents) {
      return _filterEvents(allEvents, geofenceId, deviceId);
    });
  }

  /// Filter events by geofenceId and/or deviceId
  List<GeofenceEvent> _filterEvents(
    List<GeofenceEvent> events,
    String? geofenceId,
    String? deviceId,
  ) {
    var filtered = events;

    if (geofenceId != null) {
      filtered = filtered.where((e) => e.geofenceId == geofenceId).toList();
    }

    if (deviceId != null) {
      filtered = filtered.where((e) => e.deviceId == deviceId).toList();
    }

    return filtered;
  }

  /// Initialize the repository
  void _init() {
    if (_initialized) return;
    _initialized = true;

    _log('🚀 Initializing GeofenceEventRepository');

    // Start async initialization
    _initAsync();
  }

  /// Async initialization
  Future<void> _initAsync() async {
    try {
      // Load cached events from ObjectBox
      await _loadCachedEvents();

      // Start cleanup timer (runs daily)
      _cleanupTimer = Timer.periodic(const Duration(hours: 24), (_) {
        archiveOldEvents(const Duration(days: 90));
      });

      _log('✅ Repository initialized');
    } catch (e, stackTrace) {
      _log('❌ Failed to initialize repository: $e');
      if (kDebugMode) {
        debugPrint('[GeofenceEventRepository] Stack trace: $stackTrace');
      }
    }
  }

  /// Load cached events from ObjectBox
  Future<void> _loadCachedEvents() async {
    try {
      _log('📦 Loading cached events from ObjectBox');
      
      // Load recent events (last 1000)
      final allEvents = await _dao.getPendingEvents(limit: 1000);
      _cachedEvents = allEvents;

      // Sort by timestamp (newest first)
      _cachedEvents.sort((a, b) => b.timestamp.compareTo(a.timestamp));

      _log('📦 Loaded ${_cachedEvents.length} cached events');
      _emitEvents();
    } catch (e) {
      _log('❌ Failed to load cached events: $e');
    }
  }

  /// Record a new geofence event
  ///
  /// Called when a device enters, exits, or dwells in a geofence.
  Future<void> recordEvent(GeofenceEvent event) async {
    try {
      _log('✏️ Recording event: ${event.eventType} for ${event.geofenceName}');

      // Save to ObjectBox
      await _dao.insertEvent(event);

      // Update cache (insert at beginning for newest-first order)
      _cachedEvents.insert(0, event);

      // Trim cache if too large (keep last 1000 events)
      if (_cachedEvents.length > 1000) {
        _cachedEvents = _cachedEvents.take(1000).toList();
      }

      _log('✅ Event recorded');
      _emitEvents();
    } catch (e, stackTrace) {
      _log('❌ Failed to record event: $e');
      if (kDebugMode) {
        debugPrint('[GeofenceEventRepository] Stack trace: $stackTrace');
      }
      rethrow;
    }
  }

  /// Acknowledge an event (mark as read)
  ///
  /// Updates the event status from 'pending' to 'acknowledged'.
  Future<void> acknowledgeEvent(String eventId) async {
    try {
      _log('✅ Acknowledging event: $eventId');

      // Update status in ObjectBox
      await _dao.updateEventStatus(eventId, 'acknowledged');

      // Update cache
      final index = _cachedEvents.indexWhere((e) => e.id == eventId);
      if (index >= 0) {
        _cachedEvents[index] = _cachedEvents[index].copyWith(
          status: 'acknowledged',
        );
      }

      _log('✅ Event acknowledged');
      _emitEvents();
    } catch (e) {
      _log('❌ Failed to acknowledge event: $e');
      rethrow;
    }
  }

  /// Acknowledge multiple events (batch operation)
  Future<void> acknowledgeMultipleEvents(List<String> eventIds) async {
    try {
      _log('✅ Acknowledging ${eventIds.length} events');

      for (final eventId in eventIds) {
        await _dao.updateEventStatus(eventId, 'acknowledged');

        // Update cache
        final index = _cachedEvents.indexWhere((e) => e.id == eventId);
        if (index >= 0) {
          _cachedEvents[index] = _cachedEvents[index].copyWith(
            status: 'acknowledged',
          );
        }
      }

      _log('✅ Events acknowledged');
      _emitEvents();
    } catch (e) {
      _log('❌ Failed to acknowledge multiple events: $e');
      rethrow;
    }
  }

  /// Archive old events
  ///
  /// Marks events older than the specified age as 'archived'.
  /// Archived events are hidden from the main UI but kept in the database.
  Future<void> archiveOldEvents(Duration age) async {
    try {
      _log('🗄️ Archiving events older than ${age.inDays} days');

      final cutoffTime = DateTime.now().subtract(age);
      var archivedCount = 0;

      // Find old events
      final oldEvents = _cachedEvents
          .where((e) => e.timestamp.isBefore(cutoffTime) && e.status != 'archived')
          .toList();

      // Archive each event
      for (final event in oldEvents) {
        await _dao.updateEventStatus(event.id, 'archived');
        archivedCount++;

        // Update cache
        final index = _cachedEvents.indexWhere((e) => e.id == event.id);
        if (index >= 0) {
          _cachedEvents[index] = _cachedEvents[index].copyWith(
            status: 'archived',
          );
        }
      }

      _log('✅ Archived $archivedCount old events');
      _emitEvents();
    } catch (e) {
      _log('❌ Failed to archive old events: $e');
      rethrow;
    }
  }

  /// Get events for a specific geofence
  Future<List<GeofenceEvent>> getEventsForGeofence(
    String geofenceId, {
    int limit = 100,
  }) async {
    try {
      return await _dao.getEventsForGeofence(geofenceId, limit: limit);
    } catch (e) {
      _log('❌ Failed to get events for geofence: $e');
      return [];
    }
  }

  /// Get events for a specific device
  Future<List<GeofenceEvent>> getEventsForDevice(
    String deviceId, {
    int limit = 100,
  }) async {
    try {
      return await _dao.getEventsForDevice(deviceId, limit: limit);
    } catch (e) {
      _log('❌ Failed to get events for device: $e');
      return [];
    }
  }

  /// Get pending (unread) events count
  int getPendingCount() {
    final count = _cachedEvents.where((e) => e.status == 'pending').length;
    _log('🔔 Pending count: $count');
    return count;
  }

  /// Get pending events
  Future<List<GeofenceEvent>> getPendingEvents({int limit = 100}) async {
    try {
      return await _dao.getPendingEvents(limit: limit);
    } catch (e) {
      _log('❌ Failed to get pending events: $e');
      return [];
    }
  }

  /// Get pending events for sync (with syncStatus = 'pending')
  /// 
  /// Returns events that need to be uploaded to server/Firestore
  Future<List<GeofenceEvent>> getPendingEventsForSync({int limit = 100}) async {
    try {
      // Filter events with syncStatus = 'pending'
      // Note: This requires a syncStatus field in your GeofenceEvent model
      // For now, return all pending events
      return await getPendingEvents(limit: limit);
    } catch (e) {
      _log('❌ Failed to get pending events for sync: $e');
      return [];
    }
  }

  /// Sync pending events to server/Firestore
  /// 
  /// Returns result with success and failure counts
  Future<SyncResults> syncPendingEvents() async {
    try {
      final pending = await getPendingEventsForSync();
      
      if (pending.isEmpty) {
        return const SyncResults(successCount: 0, failedCount: 0);
      }

      var success = 0;
      var failed = 0;

      for (final event in pending) {
        try {
          // TODO(owner): Replace with actual Firestore or API upload
          await _uploadEvent(event);
          
          // Mark as synced (update syncStatus if you have that field)
          // For now, just count as success
          success++;
          
          _log('✅ Uploaded event ${event.id}');
        } catch (e) {
          failed++;
          _log('❌ Failed to upload event ${event.id}: $e');
        }
      }

      return SyncResults(successCount: success, failedCount: failed);
    } catch (e) {
      _log('❌ Failed to sync pending events: $e');
      return const SyncResults(successCount: 0, failedCount: 0);
    }
  }

  /// Upload a single event to server/Firestore
  /// 
  /// TODO(owner): Implement actual upload logic (Firestore, REST API, etc.)
  Future<void> _uploadEvent(GeofenceEvent event) async {
    // Placeholder for actual upload implementation
    // 
    // Example implementations:
    // 
    // Firestore:
    // await FirebaseFirestore.instance
    //     .collection('geofence_events')
    //     .doc(event.id)
    //     .set(event.toJson());
    //
    // REST API:
    // await http.post(
    //   Uri.parse('$baseUrl/api/events'),
    //   body: jsonEncode(event.toJson()),
    // );
    
    // Simulate network delay
    await Future<void>.delayed(const Duration(milliseconds: 200));
    
    _log('📤 Uploaded event ${event.id} (placeholder)');
  }

  /// Clear all events (dangerous operation - use with caution)
  Future<void> clearAllEvents() async {
    try {
      _log('🗑️ Clearing all events');

      // Note: This would require implementing a clearAll method in DAO
      // For now, we'll just clear the cache
      _cachedEvents.clear();

      _log('✅ All events cleared from cache');
      _emitEvents();
    } catch (e) {
      _log('❌ Failed to clear events: $e');
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
    }
  }

  /// Get current events snapshot (synchronous)
  List<GeofenceEvent> getCurrentEvents() {
    return List.unmodifiable(_cachedEvents);
  }

  /// Structured logging
  void _log(String message) {
    if (kDebugMode) {
      debugPrint('[GeofenceEventRepository] $message');
    }
  }

  /// Dispose resources
  void dispose() {
    if (_disposed) {
      _log('⚠️ Double dispose prevented');
      return;
    }
    _disposed = true;

    _log('🛑 Disposing GeofenceEventRepository');

    // Cancel timers
    _cleanupTimer?.cancel();

    // Close stream controller
    _eventsController.close();

    // Clear cache
    _cachedEvents.clear();

    _log('✅ Repository disposed');
  }
}

/// Results of a sync operation
class SyncResults {
  final int successCount;
  final int failedCount;

  const SyncResults({
    required this.successCount,
    required this.failedCount,
  });

  /// Total events processed
  int get totalCount => successCount + failedCount;

  /// Success rate (0.0 to 1.0)
  double get successRate => 
      totalCount > 0 ? successCount / totalCount : 0.0;

  @override
  String toString() => 
      'SyncResults(success: $successCount, failed: $failedCount)';
}

/// Riverpod provider for GeofenceEventRepository
///
/// Returns a FutureProvider that resolves to the repository instance
/// once the DAO is ready. Uses keepAlive to maintain a single instance.
final geofenceEventRepositoryProvider =
    FutureProvider<GeofenceEventRepository>((ref) async {
  // Keep alive to maintain single repository instance
  final link = ref.keepAlive();
  Timer? timer;
  ref.onCancel(() {
    timer?.cancel();
    timer = Timer(const Duration(minutes: 10), link.close);
  });
  ref.onDispose(() => timer?.cancel());

  // Wait for DAO to be ready
  final dao = await ref.watch(geofencesDaoProvider.future);

  // Create repository
  final repository = GeofenceEventRepository(dao: dao);

  // Auto-dispose repository when provider is disposed
  ref.onDispose(repository.dispose);

  return repository;
});
