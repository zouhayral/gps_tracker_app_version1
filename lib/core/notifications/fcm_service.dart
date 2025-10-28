import 'dart:async';

import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:my_app_gps/l10n/app_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Provider for FCM Service singleton
final fcmServiceProvider = Provider<FCMService>((ref) => FCMService.instance);

/// Firebase Cloud Messaging Service for handling foreground notifications.
///
/// This service handles FCM messages when the app is in the foreground,
/// providing localized notifications based on the user's saved language preference.
///
/// Key features:
/// - Handles foreground FCM messages
/// - Loads user's saved locale from SharedPreferences
/// - Shows localized notifications using flutter_local_notifications
/// - Provides FCM token for backend registration
/// - Handles notification permission requests
///
/// Usage:
/// ```dart
/// final fcmService = ref.watch(fcmServiceProvider);
/// await fcmService.initialize();
/// final token = await fcmService.getToken();
/// ```
class FCMService {
  FCMService._();

  static final FCMService instance = FCMService._();

  final FirebaseMessaging _firebaseMessaging = FirebaseMessaging.instance;
  final FlutterLocalNotificationsPlugin _localNotifications =
      FlutterLocalNotificationsPlugin();

  StreamSubscription<RemoteMessage>? _onMessageSubscription;
  StreamSubscription<RemoteMessage>? _onMessageOpenedAppSubscription;

  bool _initialized = false;

  /// Initialize FCM service and set up message listeners.
  ///
  /// This should be called once during app startup, after Firebase is initialized.
  Future<void> initialize() async {
    if (_initialized) {
      debugPrint('[FCM] Already initialized, skipping...');
      return;
    }

    try {
      // Request notification permissions (iOS and Android 13+)
      final settings = await _requestPermission();
      if (settings.authorizationStatus == AuthorizationStatus.denied) {
        debugPrint('[FCM] Notification permission denied');
        return;
      }

      // Initialize local notifications
      await _initializeLocalNotifications();

      // Set up foreground message listener
      _onMessageSubscription = FirebaseMessaging.onMessage.listen(_handleForegroundMessage);

      // Set up notification tap handler (when app is in background/terminated)
      _onMessageOpenedAppSubscription = 
          FirebaseMessaging.onMessageOpenedApp.listen(_handleNotificationTap);

      // Handle initial message if app was opened from terminated state
      final initialMessage = await _firebaseMessaging.getInitialMessage();
      if (initialMessage != null) {
        _handleNotificationTap(initialMessage);
      }

      _initialized = true;
      debugPrint('[FCM] Service initialized successfully');
    } catch (e, stackTrace) {
      debugPrint('[FCM] Initialization error: $e');
      debugPrint('[FCM] Stack trace: $stackTrace');
    }
  }

  /// Request notification permissions (required for iOS and Android 13+).
  Future<NotificationSettings> _requestPermission() async {
    final settings = await _firebaseMessaging.requestPermission(
      alert: true,
      announcement: false,
      badge: true,
      carPlay: false,
      criticalAlert: false,
      provisional: false,
      sound: true,
    );

    debugPrint('[FCM] Permission status: ${settings.authorizationStatus}');
    return settings;
  }

  /// Initialize flutter_local_notifications plugin.
  Future<void> _initializeLocalNotifications() async {
    const androidSettings = AndroidInitializationSettings('@mipmap/ic_launcher');
    const iosSettings = DarwinInitializationSettings(
      requestAlertPermission: false,
      requestBadgePermission: false,
      requestSoundPermission: false,
    );

    const settings = InitializationSettings(
      android: androidSettings,
      iOS: iosSettings,
    );

    await _localNotifications.initialize(
      settings,
      onDidReceiveNotificationResponse: _onNotificationTapped,
    );

    // Create Android notification channel
    const androidChannel = AndroidNotificationChannel(
      'gps_alerts_channel',
      'GPS Alerts',
      description: 'Vehicle tracking notifications and alerts',
      importance: Importance.max,
      playSound: true,
      enableVibration: true,
      showBadge: true,
    );

    await _localNotifications
        .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>()
        ?.createNotificationChannel(androidChannel);

    debugPrint('[FCM] Local notifications initialized');
  }

  /// Handle foreground FCM messages with localization.
  Future<void> _handleForegroundMessage(RemoteMessage message) async {
    debugPrint('[FCM] Foreground message received: ${message.messageId}');
    debugPrint('[FCM] Data: ${message.data}');

    try {
      // Load user's saved locale
      final prefs = await SharedPreferences.getInstance();
      final localeCode = prefs.getString('locale') ?? 'en';

      // Load localizations for saved locale with fallback to English
      AppLocalizations localizations;
      try {
        localizations = await AppLocalizations.delegate.load(Locale(localeCode));
      } catch (e) {
        debugPrint('[FCM] Failed to load locale $localeCode, falling back to English: $e');
        localizations = await AppLocalizations.delegate.load(const Locale('en'));
      }

      // Build localized notification
      final notification = message.data;
      final notificationType = notification['type'] as String?;
      final speed = notification['speed'] as String?;
      final deviceName = notification['deviceName'] as String?;
      final location = notification['location'] as String?;
      final geofenceName = notification['geofenceName'] as String?;

      final (title, body) = _buildLocalizedNotification(
        localizations,
        notificationType,
        speed: speed,
        deviceName: deviceName,
        location: location,
        geofenceName: geofenceName,
      );

      // Show notification
      await _showNotification(
        title,
        body,
        payload: notification['payload'] as String?,
      );
    } catch (e, stackTrace) {
      debugPrint('[FCM] Error handling foreground message: $e');
      debugPrint('[FCM] Stack trace: $stackTrace');
    }
  }

  /// Build localized notification title and body based on type.
  (String, String) _buildLocalizedNotification(
    AppLocalizations localizations,
    String? notificationType, {
    String? speed,
    String? deviceName,
    String? location,
    String? geofenceName,
  }) {
    String title;
    String body;

    switch (notificationType) {
      case 'speed_alert':
        title = localizations.speedAlert;
        body = speed != null
            ? '${localizations.vehicleMoving} ($speed km/h)'
            : localizations.vehicleMoving;
        break;

      case 'ignition_on':
        title = localizations.ignitionOn;
        body = localizations.vehicleStarted;
        if (location != null) {
          body = '$body\n📍 $location';
        }
        break;

      case 'ignition_off':
        title = localizations.ignitionOff;
        body = localizations.vehicleStopped;
        if (location != null) {
          body = '$body\n📍 $location';
        }
        break;

      case 'geofence_enter':
        title = localizations.geofenceEnter;
        body = geofenceName != null
            ? '${localizations.vehicleMoving} $geofenceName'
            : localizations.vehicleMoving;
        break;

      case 'geofence_exit':
        title = localizations.geofenceExit;
        body = geofenceName != null
            ? '${localizations.vehicleStopped} $geofenceName'
            : localizations.vehicleStopped;
        break;

      case 'device_online':
        title = localizations.deviceOnline;
        body = deviceName ?? localizations.unknownDevice;
        break;

      case 'device_offline':
        title = 'Device Offline'; // TODO: Add to localizations
        body = deviceName ?? localizations.unknownDevice;
        break;

      case 'overspeed':
        title = localizations.overspeed;
        body = speed != null
            ? '${localizations.vehicleMoving} ($speed km/h)'
            : localizations.vehicleMoving;
        break;

      case 'maintenance_due':
        title = localizations.maintenanceDue;
        body = deviceName ?? localizations.unknownDevice;
        break;

      case 'device_moving':
        title = localizations.deviceMoving;
        body = localizations.vehicleMoving;
        break;

      case 'device_stopped':
        title = localizations.deviceStopped;
        body = localizations.vehicleStopped;
        break;

      default:
        // Fallback for unknown notification types
        title = localizations.alertsTitle;
        body = localizations.noAlerts;
    }

    // Add device name prefix if provided
    if (deviceName != null && !body.startsWith(deviceName)) {
      body = '$deviceName: $body';
    }

    return (title, body);
  }

  /// Show a local notification.
  Future<void> _showNotification(
    String title,
    String body, {
    String? payload,
  }) async {
    const androidDetails = AndroidNotificationDetails(
      'gps_alerts_channel',
      'GPS Alerts',
      channelDescription: 'Vehicle tracking notifications and alerts',
      importance: Importance.max,
      priority: Priority.high,
      ticker: 'GPS Alert',
      playSound: true,
      enableVibration: true,
      icon: '@mipmap/ic_launcher',
    );

    const iosDetails = DarwinNotificationDetails(
      presentAlert: true,
      presentBadge: true,
      presentSound: true,
    );

    const notificationDetails = NotificationDetails(
      android: androidDetails,
      iOS: iosDetails,
    );

    // Generate unique notification ID from timestamp
    final notificationId = DateTime.now().millisecondsSinceEpoch.remainder(100000);

    try {
      await _localNotifications.show(
        notificationId,
        title,
        body,
        notificationDetails,
        payload: payload,
      );
      debugPrint('[FCM] Notification shown: $title');
    } catch (e) {
      debugPrint('[FCM] Failed to show notification: $e');
    }
  }

  /// Handle notification tap (when user taps on notification).
  void _handleNotificationTap(RemoteMessage message) {
    debugPrint('[FCM] Notification tapped: ${message.messageId}');
    debugPrint('[FCM] Data: ${message.data}');

    // TODO: Navigate to appropriate screen based on notification type
    // Example:
    // final type = message.data['type'];
    // if (type == 'speed_alert') {
    //   navigatorKey.currentState?.pushNamed('/alerts');
    // }
  }

  /// Handle local notification tap.
  void _onNotificationTapped(NotificationResponse response) {
    debugPrint('[FCM] Local notification tapped: ${response.payload}');

    // TODO: Handle navigation based on payload
    // Example:
    // if (response.payload != null) {
    //   final data = jsonDecode(response.payload!);
    //   // Navigate based on data
    // }
  }

  /// Get the FCM token for this device.
  ///
  /// This token should be sent to your backend server to enable
  /// push notifications for this device.
  Future<String?> getToken() async {
    try {
      final token = await _firebaseMessaging.getToken();
      debugPrint('[FCM] Token: $token');
      return token;
    } catch (e) {
      debugPrint('[FCM] Failed to get token: $e');
      return null;
    }
  }

  /// Subscribe to a topic for topic-based messaging.
  Future<void> subscribeToTopic(String topic) async {
    try {
      await _firebaseMessaging.subscribeToTopic(topic);
      debugPrint('[FCM] Subscribed to topic: $topic');
    } catch (e) {
      debugPrint('[FCM] Failed to subscribe to topic $topic: $e');
    }
  }

  /// Unsubscribe from a topic.
  Future<void> unsubscribeFromTopic(String topic) async {
    try {
      await _firebaseMessaging.unsubscribeFromTopic(topic);
      debugPrint('[FCM] Unsubscribed from topic: $topic');
    } catch (e) {
      debugPrint('[FCM] Failed to unsubscribe from topic $topic: $e');
    }
  }

  /// Dispose resources and cancel subscriptions.
  void dispose() {
    _onMessageSubscription?.cancel();
    _onMessageOpenedAppSubscription?.cancel();
    _initialized = false;
    debugPrint('[FCM] Service disposed');
  }
}
