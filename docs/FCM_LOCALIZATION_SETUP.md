# Firebase Cloud Messaging (FCM) Localization Setup

## ✅ Completed Steps

### 1. Dependencies Added
Added to `pubspec.yaml`:
```yaml
firebase_core: ^3.10.0
firebase_messaging: ^15.1.6
```

### 2. Translation Keys Added
Added `vehicleStarted` key to all language files:
- `lib/l10n/app_en.arb`: "Vehicle started"
- `lib/l10n/app_fr.arb`: "Véhicule démarré"
- `lib/l10n/app_ar.arb`: "تم تشغيل المركبة"

### 3. FCM Handler Created
Created `lib/core/notifications/fcm_handler.dart` with:
- ✅ Background message handler with `@pragma('vm:entry-point')`
- ✅ Reads user's saved language from SharedPreferences
- ✅ Loads AppLocalizations for saved locale
- ✅ Supports multiple notification types (speed_alert, ignition_on/off, geofence enter/exit, etc.)
- ✅ Shows localized notifications using flutter_local_notifications
- ✅ Includes device name and location in messages when available

### 4. Main.dart Updated
- ✅ Imported Firebase and FCM handler
- ✅ Initialize Firebase in main()
- ✅ Registered background message handler: `FirebaseMessaging.onBackgroundMessage(firebaseMessagingBackgroundHandler)`

---

## 📋 Required Next Steps

### Step 1: Install Dependencies
```bash
flutter pub get
```

### Step 2: Generate Localizations
```bash
flutter gen-l10n
```

### Step 3: Add Firebase Configuration Files

#### For Android:
1. Go to [Firebase Console](https://console.firebase.google.com/)
2. Create a new project or select existing project
3. Add Android app
4. Download `google-services.json`
5. Place it in: `android/app/google-services.json`
6. Update `android/build.gradle.kts`:
   ```kotlin
   buildscript {
       dependencies {
           classpath("com.google.gms:google-services:4.4.2")
       }
   }
   ```
7. Update `android/app/build.gradle.kts`:
   ```kotlin
   plugins {
       id("com.google.gms.google-services")
   }
   ```

#### For iOS (if needed):
1. In Firebase Console, add iOS app
2. Download `GoogleService-Info.plist`
3. Place it in: `ios/Runner/GoogleService-Info.plist`
4. Update `ios/Podfile` to add Firebase

### Step 4: Android Permissions
Add to `android/app/src/main/AndroidManifest.xml`:
```xml
<uses-permission android:name="android.permission.INTERNET"/>
<uses-permission android:name="android.permission.POST_NOTIFICATIONS"/>

<!-- Inside <application> tag -->
<meta-data
    android:name="com.google.firebase.messaging.default_notification_channel_id"
    android:value="gps_alerts_channel" />
```

### Step 5: Request FCM Token (Optional)
Add code to request and log FCM token for testing:
```dart
// In your app startup or settings page
final fcmToken = await FirebaseMessaging.instance.getToken();
print('FCM Token: $fcmToken');
```

---

## 🧪 Testing

### Test Background Notifications
1. Close the app completely
2. Send a test notification from Firebase Console:
   - Go to Cloud Messaging → Send test message
   - Use data payload:
     ```json
     {
       "type": "ignition_on",
       "deviceName": "Test Vehicle",
       "location": "Test Location"
     }
     ```
3. Notification should appear in user's saved language

### Test Foreground Notifications
Add foreground message listener in your app:
```dart
FirebaseMessaging.onMessage.listen((RemoteMessage message) {
  // Handle foreground messages
  print('Foreground message: ${message.data}');
});
```

---

## 🌐 Supported Notification Types

| Type | Localization Keys Used |
|------|----------------------|
| `speed_alert` | `speedAlert`, `vehicleMoving` |
| `ignition_on` | `ignitionOn`, `vehicleStarted` |
| `ignition_off` | `ignitionOff`, `vehicleStopped` |
| `geofence_enter` | `geofenceEnter`, `vehicleMoving` |
| `geofence_exit` | `geofenceExit`, `vehicleStopped` |
| `device_online` | `deviceOnline`, `unknownDevice` |
| `device_offline` | (needs translation), `unknownDevice` |
| `overspeed` | `overspeed`, `vehicleMoving` |
| `maintenance_due` | `maintenanceDue`, `unknownDevice` |
| default | `alertsTitle`, `noAlerts` |

---

## 🔧 Troubleshooting

### Issue: Firebase initialization fails
- **Solution**: Make sure `google-services.json` is in the correct location
- Check Firebase Console for correct package name

### Issue: Notifications not localized
- **Solution**: Check SharedPreferences for saved `locale` key
- Verify AppLocalizations are generated: `flutter gen-l10n`

### Issue: Background handler not triggered
- **Solution**: Ensure `@pragma('vm:entry-point')` annotation is present
- Check Android notification permissions are granted

### Issue: Import errors for AppLocalizations
- **Solution**: Run `flutter gen-l10n` to generate localization files
- Check `l10n.yaml` configuration

---

## 📝 Server-Side Integration

Your backend should send FCM messages in this format:

```json
{
  "to": "<device_fcm_token>",
  "data": {
    "type": "ignition_on",
    "deviceName": "FMB920",
    "location": "Latitude: 36.8065, Longitude: 10.1815",
    "speed": "65",
    "geofenceName": "Home Zone",
    "payload": "custom_data_for_tap_handling"
  }
}
```

**Important**: 
- Use `data` payload (not `notification` payload) for background handling
- Include `type` field to determine notification content
- Optional fields: `deviceName`, `location`, `speed`, `geofenceName`

---

## ✅ Summary

Your app now has:
1. ✅ **Localized FCM background handler** that reads user's language
2. ✅ **Multi-language support** for all notification types
3. ✅ **Clean separation** between FCM and local notifications
4. ✅ **Extensible system** - easy to add new notification types

Next: Complete Firebase configuration and test with real push notifications!
