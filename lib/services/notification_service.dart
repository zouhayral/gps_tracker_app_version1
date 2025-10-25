import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:my_app_gps/app/app_router.dart';
import 'package:my_app_gps/data/models/geofence.dart';
import 'package:my_app_gps/data/models/geofence_event.dart';

/// Service for managing local notifications for geofence events.
///
/// This service integrates with flutter_local_notifications to display
/// alerts for entry, exit, and dwell events. It supports:
/// - Android notification channels
/// - iOS notification permissions
/// - Deep-link navigation via GoRouter
/// - Event-specific styling and actions
///
/// ## Usage
///
/// Initialize in your app startup:
/// ```dart
/// await NotificationService().init(context: context);
/// ```
///
/// Show a geofence event notification:
/// ```dart
/// await NotificationService().showGeofenceEvent(event, geofence, deviceName: 'Device 1');
/// ```
///
/// ## Integration with GeofenceNotificationBridge
///
/// Inside your notification bridge:
/// ```dart
/// await ref.read(notificationServiceProvider).showGeofenceEvent(event, geofence);
/// ```
class NotificationService {
  static final NotificationService _instance = NotificationService._internal();
  factory NotificationService() => _instance;
  NotificationService._internal();

  final FlutterLocalNotificationsPlugin _local =
      FlutterLocalNotificationsPlugin();

  // Track initialization state
  bool _isInitialized = false;
  BuildContext? _cachedContext;

  /// Initialize notification plugin and create channels.
  ///
  /// This should be called during app startup, preferably in main() or
  /// in the first screen's initState.
  ///
  /// **This method is idempotent** - calling it multiple times is safe.
  /// If called with a new context, it will update the navigation context.
  ///
  /// **Parameters:**
  /// - `context`: Optional BuildContext for navigation handling. If provided,
  ///   tapping notifications will navigate using GoRouter.
  ///
  /// **Platform-specific behavior:**
  /// - **Android**: Creates a high-importance notification channel
  /// - **iOS**: Requests alert, badge, and sound permissions
  ///
  /// ## Example
  ///
  /// ```dart
  /// @override
  /// void initState() {
  ///   super.initState();
  ///   NotificationService().init(context: context);
  /// }
  /// ```
  Future<void> init({BuildContext? context}) async {
    // Store context for navigation
    if (context != null) {
      _cachedContext = context;
    }
    
    // Skip full initialization if already done
    if (_isInitialized) return;

    // Android-specific initialization settings
    const androidSettings =
        AndroidInitializationSettings('@mipmap/ic_launcher');

    // iOS-specific initialization settings
    const iosSettings = DarwinInitializationSettings(
      requestAlertPermission: true,
      requestBadgePermission: true,
      requestSoundPermission: true,
    );

    const initSettings = InitializationSettings(
      android: androidSettings,
      iOS: iosSettings,
    );

    // Initialize the plugin with tap handlers
    await _local.initialize(
      initSettings,
      onDidReceiveNotificationResponse: (response) {
        final payload = response.payload;
        if (payload != null) {
          // Try to use cached context first, then provided context, then global navigator key
          BuildContext? navContext = _cachedContext ?? context;
          
          if (navContext != null && navContext.mounted) {
            navContext.push(payload);
          } else {
            // Fallback to global navigator key for background navigation
            final globalContext = navigatorKey.currentContext;
            if (globalContext != null && globalContext.mounted) {
              globalContext.push(payload);
            } else {
              debugPrint(
                'NotificationService: Cannot navigate - no context available',
              );
            }
          }
        }
      },
    );

    // Request Android notification permissions (Android 13+)
    await _local
        .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>()
        ?.requestNotificationsPermission();

    // Request iOS permissions
    await _local
        .resolvePlatformSpecificImplementation<
            IOSFlutterLocalNotificationsPlugin>()
        ?.requestPermissions(
          alert: true,
          badge: true,
          sound: true,
        );

    // Create Android notification channel
    const androidChannel = AndroidNotificationChannel(
      'geofence_events',
      'Geofence Alerts',
      description: 'Alerts for entry, exit, and dwell geofence events',
      importance: Importance.high,
      playSound: true,
      enableVibration: true,
      showBadge: true,
    );

    await _local
        .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>()
        ?.createNotificationChannel(androidChannel);

    _isInitialized = true;
  }

  /// Show a local notification for a geofence event.
  ///
  /// Displays a notification with event-specific styling, including:
  /// - Custom title based on event type (entry/exit/dwell)
  /// - Timestamp of the event
  /// - Device name or ID
  /// - Deep-link payload to navigate to geofence detail page
  ///
  /// **Parameters:**
  /// - `event`: The geofence event to display
  /// - `geofence`: The geofence associated with the event
  /// - `deviceName`: Optional friendly device name (defaults to deviceId)
  ///
  /// **Event Types:**
  /// - `entry`: "Device entered [Geofence Name]"
  /// - `exit`: "Device exited [Geofence Name]"
  /// - `dwell`: "Device stayed in [Geofence Name]"
  ///
  /// ## Example
  ///
  /// ```dart
  /// final event = GeofenceEvent(...);
  /// final geofence = Geofence(...);
  ///
  /// await NotificationService().showGeofenceEvent(
  ///   event,
  ///   geofence,
  ///   deviceName: 'John\'s Phone',
  /// );
  /// ```
  Future<void> showGeofenceEvent(
    GeofenceEvent event,
    Geofence geofence, {
    String? deviceName,
  }) async {
    if (!_isInitialized) {
      debugPrint(
        'NotificationService: Cannot show notification - service not initialized',
      );
      return;
    }

    final eventType = event.eventType.toUpperCase();
    final timestamp = DateFormat('MMM d, HH:mm').format(event.timestamp);
    final deviceLabel = deviceName ?? event.deviceId;

    // Build title based on event type
    final title = switch (eventType) {
      'ENTRY' => '📍 $deviceLabel entered ${geofence.name}',
      'EXIT' => '🚪 $deviceLabel exited ${geofence.name}',
      'DWELL' => '⏱️ $deviceLabel stayed in ${geofence.name}',
      _ => '📌 Geofence Event',
    };

    final body = 'Time: $timestamp';

    // Android notification settings
    final androidDetails = AndroidNotificationDetails(
      'geofence_events',
      'Geofence Alerts',
      channelDescription: 'Alerts for entry, exit, and dwell geofence events',
      importance: Importance.max,
      priority: Priority.high,
      ticker: 'Geofence Alert',
      color: _getEventColor(eventType),
      enableVibration: true,
      playSound: true,
      icon: '@mipmap/ic_launcher',
      largeIcon: const DrawableResourceAndroidBitmap('@mipmap/ic_launcher'),
      styleInformation: BigTextStyleInformation(
        body,
        contentTitle: title,
      ),
      actions: <AndroidNotificationAction>[
        const AndroidNotificationAction(
          'view',
          'View Details',
          showsUserInterface: true,
        ),
        const AndroidNotificationAction(
          'dismiss',
          'Dismiss',
          cancelNotification: true,
        ),
      ],
    );

    // iOS notification settings
    const iosDetails = DarwinNotificationDetails(
      presentAlert: true,
      presentBadge: true,
      presentSound: true,
      sound: 'default',
      badgeNumber: 1,
    );

    final details = NotificationDetails(
      android: androidDetails,
      iOS: iosDetails,
    );

    // Generate unique notification ID from event
    final notificationId = event.hashCode.abs();

    // Show the notification with deep-link payload
    try {
      await _local.show(
        notificationId,
        title,
        body,
        details,
        payload: '/geofences/${geofence.id}', // GoRouter deep link
      );
      debugPrint(
        'NotificationService: Showed notification for ${event.eventType} event',
      );
    } catch (e) {
      debugPrint('NotificationService: Error showing notification: $e');
    }
  }

  /// Get color based on event type for Android notifications
  Color _getEventColor(String eventType) {
    return switch (eventType) {
      'ENTRY' => Colors.green,
      'EXIT' => Colors.red,
      'DWELL' => Colors.orange,
      _ => Colors.blue,
    };
  }

  /// Cancel all active notifications.
  ///
  /// This is useful for:
  /// - Clearing notifications when user logs out
  /// - Resetting notification state
  /// - Implementing "Mark All Read" functionality
  ///
  /// ## Example
  ///
  /// ```dart
  /// await NotificationService().cancelAll();
  /// ```
  Future<void> cancelAll() async {
    await _local.cancelAll();
    debugPrint('NotificationService: Cancelled all notifications');
  }

  /// Cancel a specific notification by ID.
  ///
  /// **Parameters:**
  /// - `id`: The notification ID (usually event.hashCode)
  ///
  /// ## Example
  ///
  /// ```dart
  /// await NotificationService().cancel(event.hashCode);
  /// ```
  Future<void> cancel(int id) async {
    await _local.cancel(id);
    debugPrint('NotificationService: Cancelled notification $id');
  }

  /// Get list of pending notifications.
  ///
  /// Returns a list of all scheduled notifications that haven't been
  /// delivered yet.
  ///
  /// ## Example
  ///
  /// ```dart
  /// final pending = await NotificationService().getPendingNotifications();
  /// print('Pending notifications: ${pending.length}');
  /// ```
  Future<List<PendingNotificationRequest>> getPendingNotifications() async {
    return await _local.pendingNotificationRequests();
  }

  /// Get list of active notifications.
  ///
  /// Returns a list of all notifications currently displayed in the
  /// notification tray.
  ///
  /// ## Example
  ///
  /// ```dart
  /// final active = await NotificationService().getActiveNotifications();
  /// print('Active notifications: ${active.length}');
  /// ```
  Future<List<ActiveNotification>> getActiveNotifications() async {
    final androidPlugin = _local.resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin>();
    if (androidPlugin != null) {
      return await androidPlugin.getActiveNotifications();
    }
    return [];
  }
}

/// Riverpod provider for NotificationService.
///
/// This provider creates a singleton instance of the NotificationService
/// and automatically initializes it.
///
/// ## Usage
///
/// ```dart
/// // In a ConsumerWidget
/// final notificationService = ref.watch(notificationServiceProvider);
/// await notificationService.showGeofenceEvent(event, geofence);
/// ```
///
/// ## Integration Example
///
/// Inside GeofenceNotificationBridge:
/// ```dart
/// Future<void> showLocalNotification(
///   GeofenceEvent event,
///   Geofence geofence,
/// ) async {
///   await ref.read(notificationServiceProvider).showGeofenceEvent(
///     event,
///     geofence,
///     deviceName: _getDeviceName(event.deviceId),
///   );
/// }
/// ```
final notificationServiceProvider = Provider<NotificationService>((ref) {
  final service = NotificationService();
  // Note: init() should be called in app startup with context
  // service.init() will be called separately in main() or first screen
  return service;
});
