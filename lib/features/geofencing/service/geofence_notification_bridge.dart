import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:my_app_gps/data/models/geofence.dart';
import 'package:my_app_gps/data/models/geofence_event.dart';
import 'package:my_app_gps/data/repositories/geofence_event_repository.dart';
import 'package:my_app_gps/services/notification_service.dart';

/// Bridge between geofence events and user-facing notifications.
///
/// This service:
/// - Listens to `GeofenceMonitorService.events` stream
/// - Applies notification rules based on geofence configuration
/// - Shows local notifications for immediate alerts
/// - Sends push notifications for remote delivery (optional)
/// - Persists events to repository for history
/// - Prevents duplicate notifications from flapping
///
/// ## Responsibilities
/// 1. **Event Routing**: Determine notification type (local/push/both)
/// 2. **Local Notifications**: Show in-app alerts with deep links
/// 3. **Push Notifications**: Send to FCM topic for remote delivery
/// 4. **Deduplication**: Prevent alert spam from boundary flapping
/// 5. **Persistence**: Record all events to repository
///
/// ## Lifecycle
/// - Call [attach] when monitoring starts
/// - Call [detach] when monitoring stops or user logs out
///
/// ## Example Usage
/// ```dart
/// final bridge = GeofenceNotificationBridge(
///   eventRepo: ref.read(geofenceEventRepositoryProvider),
///   notificationService: ref.read(notificationServiceProvider),
/// );
///
/// // Attach to monitor's event stream
/// await bridge.attach(
///   monitor.events,
///   geofences,
/// );
///
/// // Later, when stopping
/// await bridge.detach();
/// ```
class GeofenceNotificationBridge {
  final GeofenceEventRepository eventRepo;
  final NotificationService notificationService;
  // TODO: Add FirebaseMessaging for push notifications
  // final FirebaseMessaging? fcm;

  /// Event stream subscription
  StreamSubscription<GeofenceEvent>? _eventSubscription;

  /// Currently active geofences (for metadata lookup)
  List<Geofence> _geofences = [];

  /// Recent event cache to prevent duplicates (eventId -> timestamp)
  final Map<String, DateTime> _recentEvents = {};

  /// Deduplication window (events within this window are considered duplicates)
  final Duration deduplicationWindow;

  /// Whether service is currently attached
  bool _isAttached = false;

  /// Whether service is currently attached to event stream
  bool get isAttached => _isAttached;

  GeofenceNotificationBridge({
    required this.eventRepo,
    required this.notificationService,
    // this.fcm,
    this.deduplicationWindow = const Duration(seconds: 3),
  });

  /// Attach to geofence event stream and start processing notifications
  ///
  /// [events] - Stream of geofence events from monitor service
  /// [geofences] - List of active geofences for metadata lookup
  ///
  /// Example:
  /// ```dart
  /// await bridge.attach(
  ///   monitor.events,
  ///   ref.read(geofencesProvider).value ?? [],
  /// );
  /// ```
  Future<void> attach(
    Stream<GeofenceEvent> events,
    List<Geofence> geofences,
  ) async {
    if (_isAttached) {
      debugPrint('[GeofenceNotificationBridge] Already attached, ignoring');
      return;
    }

    debugPrint('[GeofenceNotificationBridge] Attaching to event stream');

    _geofences = geofences;
    _isAttached = true;

    // Subscribe to events
    _eventSubscription = events.listen(
      _handleEvent,
      onError: _handleError,
      cancelOnError: false,
    );

    debugPrint('[GeofenceNotificationBridge] Attached successfully');
  }

  /// Detach from event stream and clean up resources
  ///
  /// Example:
  /// ```dart
  /// await bridge.detach();
  /// ```
  Future<void> detach() async {
    if (!_isAttached) {
      debugPrint('[GeofenceNotificationBridge] Not attached, ignoring');
      return;
    }

    debugPrint('[GeofenceNotificationBridge] Detaching from event stream');

    _isAttached = false;

    // Cancel subscription
    await _eventSubscription?.cancel();
    _eventSubscription = null;

    // Clear state
    _geofences = [];
    _recentEvents.clear();

    debugPrint('[GeofenceNotificationBridge] Detached successfully');
  }

  /// Update geofence list (call when geofences change)
  ///
  /// [geofences] - Updated list of active geofences
  ///
  /// Example:
  /// ```dart
  /// // When geofences update
  /// bridge.updateGeofences(newGeofences);
  /// ```
  void updateGeofences(List<Geofence> geofences) {
    _geofences = geofences;
    debugPrint('[GeofenceNotificationBridge] Updated ${geofences.length} geofences');
  }

  /// Handle incoming geofence event
  Future<void> _handleEvent(GeofenceEvent event) async {
    try {
      debugPrint(
        '[GeofenceNotificationBridge] Processing event: '
        '${event.eventType} at ${event.geofenceName}',
      );

      // Check for duplicate (prevent flapping)
      if (_isDuplicate(event)) {
        debugPrint('[GeofenceNotificationBridge] Duplicate event, skipping notification');
        return;
      }

      // Record duplicate prevention
      _recentEvents[event.id] = DateTime.now();
      _pruneRecentEvents();

      // Find associated geofence
      final geofence = _findGeofence(event.geofenceId);
      if (geofence == null) {
        debugPrint('[GeofenceNotificationBridge] Geofence not found: ${event.geofenceId}');
        return;
      }

      // Check if event should trigger notification based on geofence config
      if (!_shouldNotify(event, geofence)) {
        debugPrint('[GeofenceNotificationBridge] Event does not trigger notification');
        return;
      }

      // Persist event to repository (idempotent by eventId)
      await _persistEvent(event);

      // Show notification based on type
      await _showNotification(event, geofence);

      debugPrint('[GeofenceNotificationBridge] Event processed successfully');
    } catch (e, stackTrace) {
      debugPrint('[GeofenceNotificationBridge] Error processing event: $e');
      debugPrint('[GeofenceNotificationBridge] Stack trace: $stackTrace');
    }
  }

  /// Check if event is a duplicate (within deduplication window)
  bool _isDuplicate(GeofenceEvent event) {
    final lastSeen = _recentEvents[event.id];
    if (lastSeen == null) return false;

    final now = DateTime.now();
    final timeSinceLastSeen = now.difference(lastSeen);

    return timeSinceLastSeen < deduplicationWindow;
  }

  /// Remove old entries from recent events cache
  void _pruneRecentEvents() {
    final now = DateTime.now();
    final cutoff = now.subtract(deduplicationWindow);

    _recentEvents.removeWhere((id, timestamp) => timestamp.isBefore(cutoff));
  }

  /// Find geofence by ID
  Geofence? _findGeofence(String geofenceId) {
    try {
      return _geofences.firstWhere((g) => g.id == geofenceId);
    } catch (e) {
      return null;
    }
  }

  /// Determine if event should trigger notification based on geofence config
  bool _shouldNotify(GeofenceEvent event, Geofence geofence) {
    // Check if geofence is enabled
    if (!geofence.enabled) {
      return false;
    }

    // Check trigger configuration
    switch (event.eventType) {
      case 'entry':
        return geofence.onEnter;
      case 'exit':
        return geofence.onExit;
      case 'dwell':
        // Dwell requires explicit configuration
        return geofence.dwellMs != null && geofence.dwellMs! > 0;
      default:
        return false;
    }
  }

  /// Persist event to repository
  Future<void> _persistEvent(GeofenceEvent event) async {
    try {
      await eventRepo.recordEvent(event);
      debugPrint('[GeofenceNotificationBridge] Event persisted: ${event.id}');
    } catch (e) {
      debugPrint('[GeofenceNotificationBridge] Failed to persist event: $e');
      // Continue even if persistence fails (notification should still show)
    }
  }

  /// Show notification based on geofence notification type
  Future<void> _showNotification(GeofenceEvent event, Geofence geofence) async {
    final notificationType = geofence.notificationType;

    debugPrint(
      '[GeofenceNotificationBridge] Notification type: $notificationType',
    );

    // Show local notification
    if (notificationType == 'local' || notificationType == 'both') {
      await _showLocalNotification(event, geofence);
    }

    // Send push notification
    if (notificationType == 'push' || notificationType == 'both') {
      await _sendPushNotification(event, geofence);
    }
  }

  /// Show local notification
  Future<void> _showLocalNotification(
    GeofenceEvent event,
    Geofence geofence,
  ) async {
    try {
      // Get friendly device name if available
      final deviceName = event.deviceName.isNotEmpty 
          ? event.deviceName 
          : event.deviceId;

      // Show notification using NotificationService
      await notificationService.showGeofenceEvent(
        event,
        geofence,
        deviceName: deviceName,
      );

      debugPrint(
        '[GeofenceNotificationBridge] Showed local notification for ${event.eventType} event',
      );
    } catch (e) {
      debugPrint(
        '[GeofenceNotificationBridge] Failed to show local notification: $e',
      );
    }
  }

  /// Send push notification via FCM
  Future<void> _sendPushNotification(
    GeofenceEvent event,
    Geofence geofence,
  ) async {
    try {
      // TODO: Implement when FirebaseMessaging is available
      // Send to topic: user_{userId}
      // await fcm?.send(...);

      // For now, just log
      final message = _buildNotificationMessage(event, geofence);
      debugPrint('[GeofenceNotificationBridge] Push notification: $message');
    } catch (e) {
      debugPrint('[GeofenceNotificationBridge] Failed to send push notification: $e');
    }
  }

  /// Build notification message based on event type
  String _buildNotificationMessage(GeofenceEvent event, Geofence geofence) {
    final deviceName = event.deviceName.isNotEmpty ? event.deviceName : 'Device';
    final geofenceName = geofence.name;

    switch (event.eventType) {
      case 'entry':
        return '$deviceName entered $geofenceName';

      case 'exit':
        final duration = event.dwellDurationMs != null
            ? _formatDuration(Duration(milliseconds: event.dwellDurationMs!))
            : '';
        return duration.isNotEmpty
            ? '$deviceName exited $geofenceName (stayed for $duration)'
            : '$deviceName exited $geofenceName';

      case 'dwell':
        final duration = event.dwellDurationMs != null
            ? _formatDuration(Duration(milliseconds: event.dwellDurationMs!))
            : 'some time';
        return '$deviceName stayed in $geofenceName for $duration';

      default:
        return '$deviceName triggered event at $geofenceName';
    }
  }

  /// Format duration for user-friendly display
  String _formatDuration(Duration duration) {
    if (duration.inDays > 0) {
      return '${duration.inDays}d ${duration.inHours % 24}h';
    } else if (duration.inHours > 0) {
      return '${duration.inHours}h ${duration.inMinutes % 60}m';
    } else if (duration.inMinutes > 0) {
      return '${duration.inMinutes}m';
    } else {
      return '${duration.inSeconds}s';
    }
  }

  /// Handle event stream errors
  void _handleError(Object error, StackTrace stackTrace) {
    debugPrint('[GeofenceNotificationBridge] Event stream error: $error');
    debugPrint('[GeofenceNotificationBridge] Stack trace: $stackTrace');
  }

  /// Simulate event for testing
  @visibleForTesting
  Future<void> simulateEvent(GeofenceEvent event) async {
    await _handleEvent(event);
  }

  /// Dispose and clean up resources
  Future<void> dispose() async {
    await detach();
    debugPrint('[GeofenceNotificationBridge] Disposed');
  }
}

// =============================================================================
// NOTIFICATION MESSAGE TEMPLATES
// =============================================================================

/// Notification message templates for different event types
class GeofenceNotificationTemplates {
  /// Entry event template
  static String entry({
    required String deviceName,
    required String geofenceName,
  }) {
    return '$deviceName entered $geofenceName';
  }

  /// Exit event template
  static String exit({
    required String deviceName,
    required String geofenceName,
    Duration? dwellDuration,
  }) {
    if (dwellDuration != null) {
      final duration = _formatDuration(dwellDuration);
      return '$deviceName exited $geofenceName (stayed for $duration)';
    }
    return '$deviceName exited $geofenceName';
  }

  /// Dwell event template
  static String dwell({
    required String deviceName,
    required String geofenceName,
    required Duration dwellDuration,
  }) {
    final duration = _formatDuration(dwellDuration);
    return '$deviceName stayed in $geofenceName for $duration';
  }

  /// Format duration helper
  static String _formatDuration(Duration duration) {
    if (duration.inDays > 0) {
      return '${duration.inDays}d ${duration.inHours % 24}h';
    } else if (duration.inHours > 0) {
      return '${duration.inHours}h ${duration.inMinutes % 60}m';
    } else if (duration.inMinutes > 0) {
      return '${duration.inMinutes}m';
    } else {
      return '${duration.inSeconds}s';
    }
  }
}

// =============================================================================
// NOTIFICATION RULES ENGINE
// =============================================================================

/// Rules engine for determining notification behavior
class GeofenceNotificationRules {
  /// Check if event should trigger notification
  static bool shouldNotify(GeofenceEvent event, Geofence geofence) {
    // Disabled geofences never notify
    if (!geofence.enabled) return false;

    // Check trigger configuration
    switch (event.eventType) {
      case 'entry':
        return geofence.onEnter;
      case 'exit':
        return geofence.onExit;
      case 'dwell':
        return geofence.dwellMs != null && geofence.dwellMs! > 0;
      default:
        return false;
    }
  }

  /// Check if should show local notification
  static bool shouldShowLocal(Geofence geofence) {
    return geofence.notificationType == 'local' ||
        geofence.notificationType == 'both';
  }

  /// Check if should send push notification
  static bool shouldSendPush(Geofence geofence) {
    return geofence.notificationType == 'push' ||
        geofence.notificationType == 'both';
  }

  /// Check if event is time-sensitive
  static bool isTimeSensitive(GeofenceEvent event) {
    // Entry/exit are immediate, dwell is not
    return event.eventType == 'entry' || event.eventType == 'exit';
  }

  /// Get notification priority
  static String getPriority(GeofenceEvent event) {
    return isTimeSensitive(event) ? 'high' : 'default';
  }
}

// =============================================================================
// EXAMPLE USAGE
// =============================================================================

/*
/// Example: Integrate with GeofenceMonitorService
class GeofenceIntegrationExample {
  final GeofenceMonitorService monitor;
  final GeofenceNotificationBridge bridge;
  final GeofenceRepository geofenceRepo;

  Future<void> start(String userId) async {
    // Start monitoring
    await monitor.startMonitoring(userId: userId);

    // Get active geofences
    final geofences = await geofenceRepo.getActiveGeofences(userId);

    // Attach notification bridge
    await bridge.attach(monitor.events, geofences);

    // Listen for geofence updates
    geofenceRepo.watchGeofences(userId).listen((updatedGeofences) {
      bridge.updateGeofences(updatedGeofences);
    });
  }

  Future<void> stop() async {
    await bridge.detach();
    await monitor.stopMonitoring();
  }
}

/// Example: Custom notification handling
class CustomNotificationHandler extends GeofenceNotificationBridge {
  CustomNotificationHandler({
    required super.eventRepo,
  });

  @override
  Future<void> _showLocalNotification(
    GeofenceEvent event,
    Geofence geofence,
  ) async {
    // Custom logic here
    final message = _buildNotificationMessage(event, geofence);
    
    // Show notification with custom styling
    await notificationService.show(
      title: 'Geofence Alert',
      body: message,
      payload: jsonEncode({
        'type': 'geofence',
        'geofenceId': geofence.id,
        'eventId': event.id,
      }),
      importance: Importance.high,
      priority: Priority.high,
      sound: RawResourceAndroidNotificationSound('geofence_alert'),
    );
  }
}
*/

// TODO: Future enhancements:
//
// 1. **Notification Channels**
//    - Create separate channels for entry/exit/dwell
//    - Allow per-channel notification preferences
//    - Support notification importance levels
//
// 2. **Rich Notifications**
//    - Include map preview of geofence location
//    - Add action buttons (acknowledge, view details, disable)
//    - Support notification grouping by geofence
//
// 3. **Smart Notifications**
//    - Quiet hours (no notifications during sleep)
//    - Do Not Disturb integration
//    - Notification frequency limits
//
// 4. **FCM Integration**
//    - Send via Cloud Functions
//    - Support FCM topic subscriptions
//    - Handle notification delivery receipts
//
// 5. **Analytics**
//    - Track notification delivery success
//    - Monitor notification open rates
//    - Alert on notification failures
//
// 6. **Notification History**
//    - Persist notification log to database
//    - Show notification history in UI
//    - Allow notification replay
//
// 7. **Customization**
//    - Per-geofence notification templates
//    - Custom sounds and vibration patterns
//    - Localized notification messages
