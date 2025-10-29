import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart' show Color;
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

/// Service for managing connection-related local notifications.
///
/// This service shows notifications for:
/// - WebSocket disconnection events
/// - WebSocket reconnection events
/// - Optional: Data sync success events
///
/// ## Features
/// - High-priority Android channel for immediate visibility
/// - Throttling to prevent notification spam
/// - Auto-dismissal of previous connection notifications
/// - Integration with existing flutter_local_notifications setup
///
/// ## Usage
///
/// Initialize once during app startup:
/// ```dart
/// await ConnectionNotificationService.instance.init();
/// ```
///
/// Show notifications:
/// ```dart
/// await ConnectionNotificationService.instance.showDisconnected();
/// await ConnectionNotificationService.instance.showReconnected();
/// ```
///
/// ## Integration Example
///
/// In WebSocketManager or VehicleDataRepository:
/// ```dart
/// // On disconnect
/// await ConnectionNotificationService.instance.showDisconnected();
///
/// // On reconnect
/// await ConnectionNotificationService.instance.showReconnected();
/// ```
class ConnectionNotificationService {
  static final ConnectionNotificationService _instance =
      ConnectionNotificationService._internal();

  /// Singleton instance
  static ConnectionNotificationService get instance => _instance;

  ConnectionNotificationService._internal();

  final FlutterLocalNotificationsPlugin _notifications =
      FlutterLocalNotificationsPlugin();

  bool _isInitialized = false;
  DateTime? _lastDisconnectNotification;
  DateTime? _lastReconnectNotification;
  DateTime? _lastDataSyncNotification;

  /// Throttle duration to prevent notification spam
  static const _throttleDuration = Duration(seconds: 10);

  /// Notification IDs for auto-dismissal
  static const _disconnectedNotificationId = 9001;
  static const _reconnectedNotificationId = 9002;
  static const _dataSyncNotificationId = 9003;

  /// Android notification channel for connection events
  static const _channelId = 'connection_events';
  static const _channelName = 'Connection Status';
  static const _channelDescription =
      'Notifications for WebSocket connection status changes';

  /// Initialize the notification service.
  ///
  /// This method is idempotent - calling it multiple times is safe.
  /// Should be called during app startup, preferably in main().
  ///
  /// **Platform Behavior:**
  /// - **Android**: Creates a high-importance notification channel
  /// - **iOS**: No additional setup needed (uses default configuration)
  ///
  /// ## Example
  ///
  /// ```dart
  /// void main() async {
  ///   WidgetsFlutterBinding.ensureInitialized();
  ///   await ConnectionNotificationService.instance.init();
  ///   runApp(MyApp());
  /// }
  /// ```
  Future<void> init() async {
    if (_isInitialized) return;

    try {
      // Create Android notification channel
      const androidChannel = AndroidNotificationChannel(
        _channelId,
        _channelName,
        description: _channelDescription,
        importance: Importance.high,
        enableVibration: true,
        playSound: true,
      );

      await _notifications
          .resolvePlatformSpecificImplementation<
              AndroidFlutterLocalNotificationsPlugin>()
          ?.createNotificationChannel(androidChannel);

      _isInitialized = true;
      debugPrint(
        'ConnectionNotificationService: Initialized successfully',
      );
    } catch (e) {
      debugPrint('ConnectionNotificationService: Initialization error: $e');
    }
  }

  /// Show "Connection Lost" notification.
  ///
  /// Displays when WebSocket disconnects and app falls back to REST polling.
  /// Automatically dismisses after reconnection.
  ///
  /// **Throttling:** Only fires once per 10 seconds to prevent spam.
  ///
  /// ## Example
  ///
  /// ```dart
  /// // In WebSocketManager when connection drops
  /// if (!isConnected) {
  ///   await ConnectionNotificationService.instance.showDisconnected();
  /// }
  /// ```
  Future<void> showDisconnected() async {
    // DISABLED: Notifications removed to avoid annoying users
    return;
    
    // ignore: dead_code
    if (!_isInitialized) {
      debugPrint(
        'ConnectionNotificationService: Cannot show notification - not initialized',
      );
      return;
    }

    // Throttle: prevent spam
    if (_lastDisconnectNotification != null) {
      final timeSinceLast =
          DateTime.now().difference(_lastDisconnectNotification!);
      if (timeSinceLast < _throttleDuration) {
        debugPrint(
          'ConnectionNotificationService: Disconnect notification throttled (${timeSinceLast.inSeconds}s since last)',
        );
        return;
      }
    }

    _lastDisconnectNotification = DateTime.now();

    try {
      // Auto-dismiss any previous reconnect notification
      await _notifications.cancel(_reconnectedNotificationId);

      const androidDetails = AndroidNotificationDetails(
        _channelId,
        _channelName,
        channelDescription: _channelDescription,
        importance: Importance.high,
        priority: Priority.high,
        ticker: 'Connection Lost',
        icon: '@mipmap/ic_launcher',
        color: Color(0xFFFF5252), // Red
        styleInformation: BigTextStyleInformation(
          'Using REST fallback until connection restores. Data will still update, but may be slightly delayed.',
          contentTitle: '🔌 Connection Lost',
        ),
        ongoing: false,
        autoCancel: true,
      );

      const iosDetails = DarwinNotificationDetails(
        presentAlert: true,
        presentSound: true,
        sound: 'default',
      );

      final details = NotificationDetails(
        android: androidDetails,
        iOS: iosDetails,
      );

      await _notifications.show(
        _disconnectedNotificationId,
        '🔌 Connection Lost',
        'Using REST fallback until connection restores',
        details,
      );

      debugPrint(
        'ConnectionNotificationService: Showed disconnect notification',
      );
    } catch (e) {
      debugPrint(
        'ConnectionNotificationService: Error showing disconnect notification: $e',
      );
    }
  }

  /// Show "Connection Restored" notification.
  ///
  /// Displays when WebSocket successfully reconnects.
  /// Auto-dismisses previous "Connection Lost" notification.
  ///
  /// **Throttling:** Only fires once per 10 seconds to prevent spam.
  ///
  /// ## Example
  ///
  /// ```dart
  /// // In WebSocketManager when connection restored
  /// if (isConnected) {
  ///   await ConnectionNotificationService.instance.showReconnected();
  /// }
  /// ```
  Future<void> showReconnected() async {
    // DISABLED: Notifications removed to avoid annoying users
    return;
    
    // ignore: dead_code
    if (!_isInitialized) {
      debugPrint(
        'ConnectionNotificationService: Cannot show notification - not initialized',
      );
      return;
    }

    // Throttle: prevent spam
    if (_lastReconnectNotification != null) {
      final timeSinceLast =
          DateTime.now().difference(_lastReconnectNotification!);
      if (timeSinceLast < _throttleDuration) {
        debugPrint(
          'ConnectionNotificationService: Reconnect notification throttled (${timeSinceLast.inSeconds}s since last)',
        );
        return;
      }
    }

    _lastReconnectNotification = DateTime.now();

    try {
      // Auto-dismiss "Connection Lost" notification
      await _notifications.cancel(_disconnectedNotificationId);

      const androidDetails = AndroidNotificationDetails(
        _channelId,
        _channelName,
        channelDescription: _channelDescription,
        importance: Importance.high,
        priority: Priority.high,
        ticker: 'Connection Restored',
        icon: '@mipmap/ic_launcher',
        color: Color(0xFF4CAF50), // Green
        styleInformation: BigTextStyleInformation(
          'Real-time tracking resumed. You\'re now receiving live position updates.',
          contentTitle: '🌐 Connection Restored',
        ),
        ongoing: false,
        autoCancel: true,
        timeoutAfter: 5000, // Auto-dismiss after 5 seconds
      );

      const iosDetails = DarwinNotificationDetails(
        presentAlert: true,
        presentSound: true,
        sound: 'default',
      );

      final details = NotificationDetails(
        android: androidDetails,
        iOS: iosDetails,
      );

      await _notifications.show(
        _reconnectedNotificationId,
        '🌐 Connection Restored',
        'Real-time tracking resumed',
        details,
      );

      debugPrint(
        'ConnectionNotificationService: Showed reconnect notification',
      );
    } catch (e) {
      debugPrint(
        'ConnectionNotificationService: Error showing reconnect notification: $e',
      );
    }
  }

  /// Show "Vehicle Data Synced" notification.
  ///
  /// Optional enhancement to notify user when fresh data is fetched.
  /// Useful for confirming background sync operations.
  ///
  /// **Throttling:** Only fires once per 60 seconds to prevent spam.
  ///
  /// ## Example
  ///
  /// ```dart
  /// // In VehicleDataRepository after successful fetch
  /// await ConnectionNotificationService.instance.showDataSynced(
  ///   deviceCount: 5,
  /// );
  /// ```
  Future<void> showDataSynced({int? deviceCount}) async {
    // DISABLED: Notifications removed to avoid annoying users
    return;
    
    // ignore: dead_code
    if (!_isInitialized) return;

    // Throttle: prevent spam (longer duration for data sync)
    const dataSyncThrottle = Duration(seconds: 60);
    if (_lastDataSyncNotification != null) {
      final timeSinceLast =
          DateTime.now().difference(_lastDataSyncNotification!);
      if (timeSinceLast < dataSyncThrottle) {
        debugPrint(
          'ConnectionNotificationService: Data sync notification throttled (${timeSinceLast.inSeconds}s since last)',
        );
        return;
      }
    }

    _lastDataSyncNotification = DateTime.now();

    try {
      final deviceText = deviceCount != null
          ? '$deviceCount device${deviceCount != 1 ? 's' : ''}'
          : 'All devices';

      final androidDetails = AndroidNotificationDetails(
        _channelId,
        _channelName,
        channelDescription: _channelDescription,
        importance: Importance.defaultImportance,
        priority: Priority.defaultPriority,
        ticker: 'Data Synced',
        icon: '@mipmap/ic_launcher',
        color: const Color(0xFF2196F3), // Blue
        styleInformation: BigTextStyleInformation(
          '$deviceText updated with latest position data.',
          contentTitle: '📡 Vehicle Data Synced',
        ),
        ongoing: false,
        autoCancel: true,
        timeoutAfter: 3000, // Auto-dismiss after 3 seconds
      );

      const iosDetails = DarwinNotificationDetails(
        presentAlert: true,
        presentSound: false, // No sound for data sync
      );

      final details = NotificationDetails(
        android: androidDetails,
        iOS: iosDetails,
      );

      await _notifications.show(
        _dataSyncNotificationId,
        '📡 Vehicle Data Synced',
        '$deviceText updated',
        details,
      );

      debugPrint(
        'ConnectionNotificationService: Showed data sync notification',
      );
    } catch (e) {
      debugPrint(
        'ConnectionNotificationService: Error showing data sync notification: $e',
      );
    }
  }

  /// Cancel all connection-related notifications.
  ///
  /// Useful when user dismisses all notifications or logs out.
  ///
  /// ## Example
  ///
  /// ```dart
  /// await ConnectionNotificationService.instance.cancelAll();
  /// ```
  Future<void> cancelAll() async {
    if (!_isInitialized) return;

    try {
      await _notifications.cancel(_disconnectedNotificationId);
      await _notifications.cancel(_reconnectedNotificationId);
      await _notifications.cancel(_dataSyncNotificationId);
      debugPrint('ConnectionNotificationService: Cancelled all notifications');
    } catch (e) {
      debugPrint(
        'ConnectionNotificationService: Error cancelling notifications: $e',
      );
    }
  }

  /// Reset throttle timers.
  ///
  /// For testing purposes - allows notifications to fire immediately.
  @visibleForTesting
  void resetThrottles() {
    _lastDisconnectNotification = null;
    _lastReconnectNotification = null;
    _lastDataSyncNotification = null;
  }
}
