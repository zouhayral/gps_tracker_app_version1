# FCM Localized Notifications - Testing Plan

## 🎯 Testing Objective
Verify that Firebase Cloud Messaging notifications are displayed in the user's selected language for all three supported locales: **English**, **French**, and **Arabic**.

---

## ⚙️ Prerequisites

### 1. Firebase Configuration
Before testing, ensure Firebase is properly configured:

#### Android Setup:
- [ ] `google-services.json` downloaded from Firebase Console
- [ ] File placed in `android/app/google-services.json`
- [ ] Google Services plugin added to `android/build.gradle.kts`:
  ```kotlin
  buildscript {
      dependencies {
          classpath("com.google.gms:google-services:4.4.2")
      }
  }
  ```
- [ ] Plugin applied in `android/app/build.gradle.kts`:
  ```kotlin
  plugins {
      id("com.google.gms.google-services")
  }
  ```

#### Permissions:
Verify in `android/app/src/main/AndroidManifest.xml`:
```xml
<uses-permission android:name="android.permission.INTERNET"/>
<uses-permission android:name="android.permission.POST_NOTIFICATIONS"/>

<application>
    <meta-data
        android:name="com.google.firebase.messaging.default_notification_channel_id"
        android:value="gps_alerts_channel" />
</application>
```

### 2. App Installation
- [ ] Clean build: `flutter clean`
- [ ] Get dependencies: `flutter pub get`
- [ ] Install on physical device (Firebase notifications don't work on emulators reliably)

### 3. Verify FCM Token
- [ ] Launch app and check terminal for:
  ```
  [FCM] Firebase initialized and background handler registered
  [FCM] ✅ FCM service initialized successfully
  [FCM] Device token: <your_token>...
  ```
- [ ] Copy the full FCM token from the logs for Firebase Console testing

---

## 🧪 Test Scenarios

### Test 1: English Language Notifications ✅

**Setup:**
1. Open app → Navigate to **Settings**
2. Tap **Language** → Select **English**
3. App should reload with English UI

**Foreground Test (App Open):**
1. Keep app open
2. Go to [Firebase Console](https://console.firebase.google.com/) → **Engage** → **Cloud Messaging**
3. Click **Send your first message** or **New campaign**
4. Select **Firebase Notification messages** → **Send test message**
5. Paste your FCM token
6. Add **Custom data**:
   ```json
   {
     "type": "speed_alert",
     "speed": "82",
     "deviceName": "Test Vehicle"
   }
   ```
7. Click **Test**

**Expected Result:**
- ✅ Notification appears **while app is open**
- ✅ Title: "Speed alert"
- ✅ Body: "Test Vehicle is going 82 km/h"

**Background Test (App in Background):**
1. Press Home button (app to background)
2. Send same test message from Firebase Console
3. Check notification tray

**Expected Result:**
- ✅ Notification appears in notification tray
- ✅ Title: "Speed alert"
- ✅ Body: "Test Vehicle is going 82 km/h"

**Lock Screen Test:**
1. Lock device screen
2. Send same test message
3. Check lock screen

**Expected Result:**
- ✅ Notification visible on lock screen
- ✅ Text in English

---

### Test 2: French Language Notifications 🇫🇷

**Setup:**
1. Open app → **Paramètres** (Settings)
2. **Langue** → Select **Français**
3. App reloads with French UI

**Test A: Ignition Alert (Foreground)**
- Send message:
  ```json
  {
    "type": "ignition_on",
    "deviceName": "Voiture Test",
    "location": "Paris, France"
  }
  ```
- **Expected:** 
  - Title: "Contact mis"
  - Body: "Voiture Test à Paris, France"

**Test B: Vehicle Started (Background)**
- Press Home button
- Send message:
  ```json
  {
    "type": "ignition_on",
    "deviceName": "Mon Véhicule"
  }
  ```
- **Expected:**
  - Notification tray shows: "Contact mis"
  - Body: "Mon Véhicule"

**Test C: Speed Alert (Lock Screen)**
- Lock device
- Send message:
  ```json
  {
    "type": "speed_alert",
    "speed": "120",
    "deviceName": "Camion"
  }
  ```
- **Expected:**
  - Lock screen: "Alerte de vitesse"
  - Body: "Camion va à 120 km/h"

---

### Test 3: Arabic Language Notifications 🇸🇦

**Setup:**
1. Open app → **الإعدادات** (Settings)
2. **اللغة** → Select **العربية**
3. App reloads with Arabic UI (RTL layout)

**Test A: Vehicle Stopped (Foreground)**
- Send message:
  ```json
  {
    "type": "ignition_off",
    "deviceName": "سيارة الاختبار",
    "location": "الرياض"
  }
  ```
- **Expected:**
  - Title: "تم إيقاف الإشعال"
  - Body: "سيارة الاختبار في الرياض"

**Test B: Geofence Enter (Background)**
- Press Home button
- Send message:
  ```json
  {
    "type": "geofence_enter",
    "deviceName": "مركبة التوصيل",
    "geofence": "المستودع الرئيسي"
  }
  ```
- **Expected:**
  - Title: "دخول المنطقة الجغرافية"
  - Body: "مركبة التوصيل دخلت المستودع الرئيسي"

**Test C: Overspeed (Lock Screen)**
- Lock device
- Send message:
  ```json
  {
    "type": "overspeed",
    "speed": "140",
    "deviceName": "شاحنة"
  }
  ```
- **Expected:**
  - Lock screen: "تجاوز السرعة"
  - Body: "شاحنة تسير بسرعة 140 كم/س"

---

## 📋 All Supported Notification Types

Test each type in at least one language:

| Type | English | French | Arabic |
|------|---------|--------|--------|
| `speed_alert` | Speed alert | Alerte de vitesse | تنبيه السرعة |
| `ignition_on` | Ignition On | Contact mis | تم تشغيل الإشعال |
| `ignition_off` | Ignition Off | Contact coupé | تم إيقاف الإشعال |
| `geofence_enter` | Geofence Entered | Entrée dans la zone | دخول المنطقة الجغرافية |
| `geofence_exit` | Geofence Exited | Sortie de la zone | خروج من المنطقة الجغرافية |
| `device_online` | Device Online | Appareil en ligne | الجهاز متصل |
| `device_offline` | Device Offline | Appareil hors ligne | الجهاز غير متصل |
| `overspeed` | Overspeed | Excès de vitesse | تجاوز السرعة |
| `maintenance_due` | Maintenance Due | Maintenance requise | صيانة مطلوبة |
| `device_moving` | Device Moving | Appareil en mouvement | الجهاز يتحرك |
| `device_stopped` | Device Stopped | Appareil arrêté | الجهاز متوقف |

---

## 🔍 Validation Checklist

### For Each Language:
- [ ] Foreground notification appears with correct language
- [ ] Background notification appears with correct language
- [ ] Lock screen notification displays correct language
- [ ] Notification title is translated
- [ ] Notification body is translated
- [ ] Special characters render correctly (Arabic, French accents)
- [ ] No English text appears when other language selected

### Technical Verification:
- [ ] Check logs for locale loading:
  ```
  [FCM] Loading locale: fr (or ar)
  [FCM] Locale loaded successfully
  ```
- [ ] No errors in console during notification display
- [ ] Notification sound plays
- [ ] Notification appears in notification history

---

## 🐛 Troubleshooting

### Issue: No Notifications Received
**Solutions:**
1. Verify FCM token is copied correctly
2. Check Firebase Console → Project Settings → Cloud Messaging → API enabled
3. Ensure device has internet connection
4. Check notification permissions: Settings → Apps → GPS Tracker → Notifications → Enabled
5. Verify `google-services.json` is in correct location

### Issue: Notifications in English Only
**Solutions:**
1. Verify language change is saved:
   ```dart
   final prefs = await SharedPreferences.getInstance();
   print('Saved locale: ${prefs.getString('locale')}');
   ```
2. Check logs for locale loading errors
3. Ensure `flutter gen-l10n` was run after ARB file updates
4. Restart app completely (not just hot reload)

### Issue: Background Notifications Not Working
**Solutions:**
1. Verify background handler is registered in `main.dart`:
   ```dart
   FirebaseMessaging.onBackgroundMessage(firebaseMessagingBackgroundHandler);
   ```
2. Check that function has `@pragma('vm:entry-point')` annotation
3. Ensure app is truly in background (not terminated)
4. Check Android battery optimization settings aren't killing the app

### Issue: Arabic Text Appears Broken
**Solutions:**
1. Verify Arabic ARB file has correct UTF-8 encoding
2. Check font supports Arabic characters
3. Ensure RTL layout is applied
4. Test on different Android versions (some have better Arabic support)

---

## 📊 Test Results Template

| Test Scenario | Language | Foreground | Background | Lock Screen | Status | Notes |
|---------------|----------|------------|------------|-------------|--------|-------|
| Speed Alert | English | ✅ | ✅ | ✅ | Pass | - |
| Speed Alert | French | | | | | |
| Speed Alert | Arabic | | | | | |
| Ignition On | English | | | | | |
| Ignition On | French | | | | | |
| Ignition On | Arabic | | | | | |
| Geofence Enter | English | | | | | |
| Geofence Enter | French | | | | | |
| Geofence Enter | Arabic | | | | | |

---

## 🎉 Success Criteria

**✅ All tests pass when:**
1. Every notification type shows in correct language
2. Foreground, background, and lock screen all work
3. Language switching takes immediate effect
4. No crashes or errors in logs
5. Special characters (Arabic, French accents) render properly
6. Notification tap opens app (even if navigation not implemented yet)

---

## 📝 Test Execution Log

### Date: _______________
### Tester: _______________
### Device: _______________
### Android Version: _______________

**Test Session Notes:**
```
[Record any observations, issues, or unexpected behavior here]
```

**FCM Token Used:**
```
[Paste your FCM token here for reference]
```

**Firebase Project:**
```
Project ID: _______________
```

---

## 🚀 Next Steps After Testing

Once all tests pass:
1. [ ] Implement notification tap navigation (TODOs in code)
2. [ ] Send FCM token to backend server
3. [ ] Set up server-side notification sending
4. [ ] Test with real device events (actual speed alerts, geofence triggers)
5. [ ] Monitor Firebase Console for delivery statistics
6. [ ] Consider adding notification categories/channels for better UX

---

## 📚 Additional Resources

- **Firebase Console**: https://console.firebase.google.com/
- **FCM Documentation**: https://firebase.google.com/docs/cloud-messaging
- **Flutter Firebase Messaging**: https://pub.dev/packages/firebase_messaging
- **Project Documentation**: `docs/FCM_LOCALIZATION_SETUP.md`

---

**Remember:** Firebase Cloud Messaging works best on **physical devices**. Emulators may have unreliable FCM support.

**Good luck with testing! 🎉**
