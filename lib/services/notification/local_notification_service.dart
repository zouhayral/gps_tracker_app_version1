import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:my_app_gps/data/models/event.dart';
import 'package:intl/intl.dart';
import 'package:timezone/data/latest_all.dart' as tz;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:my_app_gps/core/utils/shared_prefs_holder.dart';

/// Service for managing local push notifications for Traccar events
/// 
/// Handles system-level notifications for critical events like:
/// - overspeed
/// - ignitionOn/Off
/// - deviceOffline/Online
/// - geofenceEnter/Exit
/// 
/// Notifications appear even when app is in background or terminated.
class LocalNotificationService {
  LocalNotificationService._();
  
  static final LocalNotificationService instance = LocalNotificationService._();

  final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();

  /// Track recently notified event IDs to prevent duplicates
  final Set<int> _recentlyNotifiedIds = {};
  
  bool _initialized = false;

  /// Global gate for notifications, persisted via SharedPreferences
  static Future<bool> isNotificationsEnabled() async {
    try {
      if (SharedPrefsHolder.isInitialized) {
        return SharedPrefsHolder.instance.getBool('notifications_enabled') ?? true;
      }
      final prefs = await SharedPreferences.getInstance();
      return prefs.getBool('notifications_enabled') ?? true;
    } catch (_) {
      // Fail-open: if reading prefs fails, treat as enabled to avoid missing critical alerts silently
      return true;
    }
  }

  /// Convenience helper to attempt showing a notification using the global gate.
  /// This delegates to instance.showEventNotification which already performs the check.
  static Future<void> tryShowEventNotification(Event event) async {
    await instance.showEventNotification(event);
  }

  /// Initialize the notification service
  /// 
  /// Must be called during app startup, typically in main().
  /// Requests permissions and sets up notification channels.
  Future<bool> initialize() async {
    if (_initialized) {
      _log('✅ Already initialized');
      return true;
    }

    try {
      _log('🔔 Initializing LocalNotificationService');

      // Initialize timezone database
      tz.initializeTimeZones();
      
      // Android initialization settings
      const androidSettings = AndroidInitializationSettings('@mipmap/ic_launcher');
      
      // iOS initialization settings
      const iosSettings = DarwinInitializationSettings(
        requestAlertPermission: true,
        requestBadgePermission: true,
        requestSoundPermission: true,
      );

      const initSettings = InitializationSettings(
        android: androidSettings,
        iOS: iosSettings,
      );

      // Initialize plugin
      final initialized = await _plugin.initialize(
        initSettings,
        onDidReceiveNotificationResponse: _onNotificationTapped,
      );

      if (initialized != true) {
        _log('❌ Failed to initialize plugin');
        return false;
      }

      // Create Android notification channel
      if (Platform.isAndroid) {
        await _createAndroidChannel();
      }

      // Request permissions
      final permissionsGranted = await _requestPermissions();
      
      if (!permissionsGranted) {
        _log('⚠️ Notification permissions not fully granted');
      }

      _initialized = true;
      _log('✅ LocalNotificationService initialized successfully');
      return true;
    } catch (e, stackTrace) {
      _log('❌ Failed to initialize: $e');
      if (kDebugMode) {
        print('[LocalNotificationService] Stack trace: $stackTrace');
      }
      return false;
    }
  }

  /// Create Android notification channel with high importance
  Future<void> _createAndroidChannel() async {
    const channel = AndroidNotificationChannel(
      'traccar_alerts', // Channel ID
      'Traccar Alerts', // Channel name
      description: 'Critical alerts from Traccar devices',
      importance: Importance.high,
      enableVibration: true,
      enableLights: true,
      playSound: true,
      showBadge: true,
    );

    await _plugin
        .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>()
        ?.createNotificationChannel(channel);

    _log('✅ Created Android notification channel: traccar_alerts');
  }

  /// Request notification permissions
  Future<bool> _requestPermissions() async {
    if (Platform.isAndroid) {
      // Android 13+ requires runtime permission
      final androidPlugin = _plugin
          .resolvePlatformSpecificImplementation<
              AndroidFlutterLocalNotificationsPlugin>();
      
      final granted = await androidPlugin?.requestNotificationsPermission();
      _log('Android notification permission: ${granted ?? false}');
      return granted ?? false;
    } else if (Platform.isIOS) {
      // iOS permissions
      final iosPlugin = _plugin
          .resolvePlatformSpecificImplementation<
              IOSFlutterLocalNotificationsPlugin>();
      
      final granted = await iosPlugin?.requestPermissions(
        alert: true,
        badge: true,
        sound: true,
      );
      _log('iOS notification permission: ${granted ?? false}');
      return granted ?? false;
    }
    
    return true;
  }

  /// Show notification for a Traccar event
  /// 
  /// Maps event types to appropriate notification titles and messages.
  /// Only shows notification if event hasn't been notified recently.
  Future<void> showEventNotification(Event event) async {
    if (!_initialized) {
      _log('⚠️ Service not initialized, call initialize() first');
      return;
    }

    // Respect global notification toggle
    if (!await isNotificationsEnabled()) {
      _log('� System notification suppressed (toggle OFF)');
      return;
    }

    // Prevent duplicate notifications
    if (_recentlyNotifiedIds.contains(event.id.hashCode)) {
      _log('⏭️ Skipping duplicate notification for event ${event.id}');
      return;
    }

    // Only notify for unread critical events
    if (event.isRead) {
      _log('⏭️ Skipping notification for read event ${event.id}');
      return;
    }

    try {
      final notificationData = _getNotificationData(event);
      
  _log('📤 Showing notification for event: ${event.type}');
  _log('   Title: ${notificationData.title}');
  _log('   Device: ${event.deviceName ?? 'ID ${event.deviceId}'}');

      // Use event.id hashCode as notification ID (notifications need int ID)
      final notificationId = event.id.hashCode;

      await _plugin.show(
        notificationId,
        notificationData.title,
        notificationData.body,
        _getNotificationDetails(event.severity ?? 'info'),
        payload: 'event:${event.id}',
      );

      // Track this notification (using hashCode)
      _recentlyNotifiedIds.add(event.id.hashCode);
      
      // Clean up old tracked IDs (keep last 100)
      if (_recentlyNotifiedIds.length > 100) {
        final toRemove = _recentlyNotifiedIds.take(50).toList();
        _recentlyNotifiedIds.removeAll(toRemove);
      }

      _log('✅ Notification shown successfully (ID: $notificationId)');
    } catch (e, stackTrace) {
      _log('❌ Failed to show notification: $e');
      if (kDebugMode) {
        print('[LocalNotificationService] Stack trace: $stackTrace');
      }
    }
  }

  /// Show summary notification for multiple events
  /// 
  /// Useful when multiple events arrive simultaneously.
  Future<void> showBatchSummary(List<Event> events) async {
    if (!_initialized || events.isEmpty) return;
    if (!await isNotificationsEnabled()) {
      _log('🔕 Notifications disabled, skipping batch summary');
      return;
    }

    try {
      final criticalCount = events.where((e) => e.severity == 'critical').length;
      final warningCount = events.where((e) => e.severity == 'warning').length;
      
      final title = '${events.length} New Alerts';
      final body = criticalCount > 0
          ? '$criticalCount critical, $warningCount warnings'
          : '${events.length} new notifications';

      _log('📤 Showing batch summary: $title');

      await _plugin.show(
        999999, // Special ID for summary
        title,
        body,
        _getNotificationDetails('critical'),
        payload: 'batch:${events.length}',
      );

      _log('✅ Batch summary shown');
    } catch (e) {
      _log('❌ Failed to show batch summary: $e');
    }
  }

  /// Cancel a specific notification
  Future<void> cancelNotification(int notificationId) async {
    await _plugin.cancel(notificationId);
    _recentlyNotifiedIds.remove(notificationId);
    _log('🗑️ Cancelled notification: $notificationId');
  }

  /// Cancel all notifications
  Future<void> cancelAll() async {
    await _plugin.cancelAll();
    _recentlyNotifiedIds.clear();
    _log('🗑️ Cancelled all notifications');
  }

  /// Get notification details based on severity
  NotificationDetails _getNotificationDetails(String severity) {
    final androidDetails = _getAndroidDetails(severity);
    const iosDetails = DarwinNotificationDetails(
      presentAlert: true,
      presentBadge: true,
      presentSound: true,
    );

    return NotificationDetails(
      android: androidDetails,
      iOS: iosDetails,
    );
  }

  /// Get Android-specific notification details based on severity
  AndroidNotificationDetails _getAndroidDetails(String severity) {
    switch (severity.toLowerCase()) {
      case 'critical':
        return AndroidNotificationDetails(
          'traccar_alerts',
          'Traccar Alerts',
          channelDescription: 'Critical alerts from Traccar devices',
          importance: Importance.high,
          priority: Priority.high,
          color: Color(0xFFFF383C), // Red
          enableVibration: true,
          enableLights: true,
          playSound: true,
          icon: '@mipmap/ic_launcher',
          largeIcon: DrawableResourceAndroidBitmap('@mipmap/ic_launcher'),
        );
      case 'warning':
        return AndroidNotificationDetails(
          'traccar_alerts',
          'Traccar Alerts',
          channelDescription: 'Critical alerts from Traccar devices',
          importance: Importance.defaultImportance,
          priority: Priority.defaultPriority,
          color: Color(0xFFFFBD28), // Orange
          enableVibration: true,
          playSound: true,
          icon: '@mipmap/ic_launcher',
        );
      case 'info':
      default:
        return AndroidNotificationDetails(
          'traccar_alerts',
          'Traccar Alerts',
          channelDescription: 'Critical alerts from Traccar devices',
          importance: Importance.low,
          priority: Priority.low,
          color: Color(0xFF49454F), // Grey
          playSound: false,
          icon: '@mipmap/ic_launcher',
        );
    }
  }

  /// Get notification title and body based on event type
  _NotificationData _getNotificationData(Event event) {
    final device = _deviceLabel(event);
    final timeText = _formatShortTime(event.timestamp);

    String baseTitle;
    switch (event.type.toLowerCase()) {
      case 'ignitionon':
        baseTitle = '🔑 Ignition On';
        break;
      case 'ignitionoff':
        baseTitle = '🔑 Ignition Off';
        break;
      case 'deviceonline':
        baseTitle = '✅ Device Online';
        break;
      case 'deviceoffline':
        baseTitle = '⚠️ Device Offline';
        break;
      case 'geofenceenter':
        baseTitle = '📍 Geofence Entered';
        break;
      case 'geofenceexit':
        baseTitle = '📍 Geofence Exited';
        break;
      case 'alarm':
        baseTitle = '🚨 Alarm';
        break;
      case 'overspeed':
        baseTitle = '⚠️ Overspeed';
        break;
      case 'maintenance':
        baseTitle = '🔧 Maintenance Due';
        break;
      case 'devicemoving':
        baseTitle = '🚗 Device Moving';
        break;
      case 'devicestopped':
        baseTitle = '🛑 Device Stopped';
        break;
      default:
        baseTitle = '📢 ${_formatEventType(event.type)}';
        break;
    }

  // Prefer Event.deviceName but also accept attributes['deviceName'] as fallback
  final enrichedName = event.deviceName ?? (event.attributes['deviceName'] as String?);
  final effectiveDevice = (enrichedName != null && enrichedName.trim().isNotEmpty)
    ? enrichedName
    : device;
  final title = '$baseTitle — $effectiveDevice';
    final body = 'At $timeText';

    return _NotificationData(title: title, body: body);
  }

  /// Format event type for display
  String _formatEventType(String type) {
    // Convert camelCase to Title Case
    final words = type.replaceAllMapped(
      RegExp(r'([A-Z])'),
      (match) => ' ${match.group(1)}',
    ).trim();
    
    return words[0].toUpperCase() + words.substring(1);
  }

  /// Handle notification tap
  void _onNotificationTapped(NotificationResponse response) {
    final payload = response.payload;
    _log('👆 Notification tapped: $payload');

    if (payload != null && payload.startsWith('event:')) {
      final eventId = int.tryParse(payload.substring(6));
      if (eventId != null) {
        _log('   Opening event: $eventId');
        // TODO: Navigate to notifications page
        // This will be handled by the router when integrated
      }
    }
  }

  /// Prefer a friendly device label
  String _deviceLabel(Event event) {
    final name = event.deviceName?.trim();
    if (name != null && name.isNotEmpty) return name;
    return 'Device ${event.deviceId}';
  }

  /// Format time like HH:mm in local time
  String _formatShortTime(DateTime dt) => DateFormat('HH:mm').format(dt.toLocal());

  /// Log message with prefix
  void _log(String message) {
    if (kDebugMode) {
      print('[LocalNotificationService] $message');
    }
  }
}

/// Data class for notification content
class _NotificationData {
  final String title;
  final String body;

  _NotificationData({required this.title, required this.body});
}
