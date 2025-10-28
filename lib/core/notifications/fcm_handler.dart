import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:my_app_gps/l10n/app_localizations.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Firebase Cloud Messaging background handler with localized notifications.
///
/// This handler processes push notifications when the app is in the background
/// or terminated. It reads the user's saved language preference and uses it
/// to localize notification messages.
///
/// Supported notification types:
/// - `speed_alert`: Triggered when vehicle exceeds speed limit
/// - `ignition_on`: Triggered when vehicle ignition is turned on
/// - `ignition_off`: Triggered when vehicle ignition is turned off
/// - `geofence_enter`: Triggered when vehicle enters a geofence
/// - `geofence_exit`: Triggered when vehicle exits a geofence
/// - `device_online`: Triggered when device comes online
/// - `device_offline`: Triggered when device goes offline
///
/// Usage:
/// ```dart
/// // In main.dart, before runApp():
/// FirebaseMessaging.onBackgroundMessage(firebaseMessagingBackgroundHandler);
/// ```
@pragma('vm:entry-point')
Future<void> firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  // Ensure Flutter bindings are initialized
  WidgetsFlutterBinding.ensureInitialized();

  try {
    // Load user's saved language preference
    final prefs = await SharedPreferences.getInstance();
    final localeCode = prefs.getString('locale') ?? 'en';

    // Load localizations for the saved locale
    final localizations = await AppLocalizations.delegate.load(Locale(localeCode));
    
    // Extract notification data
    final notification = message.data;
    final notificationType = notification['type'] as String?;
    final speed = notification['speed'] as String?;
    final deviceName = notification['deviceName'] as String?;
    final location = notification['location'] as String?;
    final geofenceName = notification['geofenceName'] as String?;

    // Build localized title and body based on notification type
    String title;
    String body;

    switch (notificationType) {
      case 'speed_alert':
        title = localizations.speedAlert;
        body = speed != null
            ? '${localizations.vehicleMoving} ($speed km/h)'
            : localizations.vehicleMoving;
        if (deviceName != null) {
          body = '$deviceName: $body';
        }
        break;

      case 'ignition_on':
        title = localizations.ignitionOn;
        body = localizations.vehicleStarted;
        if (deviceName != null) {
          body = '$deviceName: $body';
        }
        if (location != null) {
          body = '$body\n📍 $location';
        }
        break;

      case 'ignition_off':
        title = localizations.ignitionOff;
        body = localizations.vehicleStopped;
        if (deviceName != null) {
          body = '$deviceName: $body';
        }
        if (location != null) {
          body = '$body\n📍 $location';
        }
        break;

      case 'geofence_enter':
        title = localizations.geofenceEnter;
        body = geofenceName != null
            ? '${localizations.vehicleMoving} $geofenceName'
            : localizations.vehicleMoving;
        if (deviceName != null) {
          body = '$deviceName: $body';
        }
        break;

      case 'geofence_exit':
        title = localizations.geofenceExit;
        body = geofenceName != null
            ? '${localizations.vehicleStopped} $geofenceName'
            : localizations.vehicleStopped;
        if (deviceName != null) {
          body = '$deviceName: $body';
        }
        break;

      case 'device_online':
        title = localizations.deviceOnline;
        body = deviceName ?? localizations.unknownDevice;
        break;

      case 'device_offline':
        title = 'Device Offline'; // Add to localizations if needed
        body = deviceName ?? localizations.unknownDevice;
        break;

      case 'overspeed':
        title = localizations.overspeed;
        body = speed != null
            ? '${localizations.vehicleMoving} ($speed km/h)'
            : localizations.vehicleMoving;
        if (deviceName != null) {
          body = '$deviceName: $body';
        }
        break;

      case 'maintenance_due':
        title = localizations.maintenanceDue;
        body = deviceName ?? localizations.unknownDevice;
        break;

      default:
        // Fallback for unknown notification types
        title = localizations.alertsTitle;
        body = notification['message'] as String? ?? localizations.noAlerts;
        if (deviceName != null) {
          body = '$deviceName: $body';
        }
    }

    // Show local notification
    await _showLocalNotification(title, body, notification);
  } catch (e, stackTrace) {
    // Log error but don't crash the background handler
    debugPrint('[FCM] Error in background handler: $e');
    debugPrint('[FCM] Stack trace: $stackTrace');
  }
}

/// Shows a local notification using flutter_local_notifications.
///
/// This ensures notifications are displayed even when the app is not running.
Future<void> _showLocalNotification(
  String title,
  String body,
  Map<String, dynamic> data,
) async {
  final flutterLocalNotificationsPlugin = FlutterLocalNotificationsPlugin();

  // Android notification channel configuration
  const androidChannel = AndroidNotificationChannel(
    'gps_alerts_channel', // Channel ID
    'GPS Alerts', // Channel name
    description: 'Vehicle tracking notifications and alerts',
    importance: Importance.max,
    playSound: true,
    enableVibration: true,
    showBadge: true,
  );

  // Initialize the plugin
  await flutterLocalNotificationsPlugin
      .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>()
      ?.createNotificationChannel(androidChannel);

  // Android notification details
  final androidDetails = AndroidNotificationDetails(
    androidChannel.id,
    androidChannel.name,
    channelDescription: androidChannel.description,
    importance: Importance.max,
    priority: Priority.high,
    ticker: 'GPS Alert',
    playSound: true,
    enableVibration: true,
    icon: '@mipmap/ic_launcher',
  );

  // iOS notification details (optional, for future iOS support)
  const iosDetails = DarwinNotificationDetails(
    presentAlert: true,
    presentBadge: true,
    presentSound: true,
  );

  final notificationDetails = NotificationDetails(
    android: androidDetails,
    iOS: iosDetails,
  );

  // Generate unique notification ID from timestamp
  final notificationId = DateTime.now().millisecondsSinceEpoch.remainder(100000);

  try {
    await flutterLocalNotificationsPlugin.show(
      notificationId,
      title,
      body,
      notificationDetails,
      payload: data['payload'] as String?, // Optional payload for tap handling
    );
  } catch (e) {
    debugPrint('[FCM] Failed to show local notification: $e');
  }
}
