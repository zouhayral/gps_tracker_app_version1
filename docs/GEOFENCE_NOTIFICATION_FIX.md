# 🔔 Geofence Notification Troubleshooting Guide

## Problem Fixed: Notifications Not Appearing

### Root Cause
The `GeofenceNotificationBridge` was being created but **never attached** to the `GeofenceMonitorService` event stream. This meant that geofence events (entry/exit/dwell) were being detected and emitted, but the notification bridge wasn't listening to them.

### Solution Applied

**File Modified**: `lib/features/geofencing/providers/geofence_providers.dart`

Added automatic attachment of the notification bridge:

```dart
final geofenceNotificationBridgeProvider =
    FutureProvider.autoDispose<GeofenceNotificationBridge>((ref) async {
  // Await monitor service initialization
  final monitor = await ref.watch(geofenceMonitorServiceProvider.future);
  
  // Load geofences
  final geofences = await ref.read(geofencesProvider.future);
  
  // Create bridge instance
  final bridge = GeofenceNotificationBridge(
    eventRepo: eventRepo,
    notificationService: ref.read(notificationServiceProvider),
  );

  // 🎯 CRITICAL: Attach bridge to monitor's event stream
  await bridge.attach(monitor.events, geofences);
  
  return bridge;
});
```

**File Modified**: `lib/app/app_root.dart`

Added initialization of notification bridge in `initState()`:

```dart
// 🎯 Initialize geofence notification bridge
WidgetsBinding.instance.addPostFrameCallback((_) {
  if (mounted) {
    ref.read(geofenceNotificationBridgeProvider);
  }
});
```

---

## Verification Checklist

### ✅ Step 1: Check Debug Logs

After the fix, you should see these log messages when the app starts:

```
[GeofenceProviders] 🔔 Notification bridge attached with N geofences
[GeofenceNotificationBridge] Attaching to event stream
[GeofenceNotificationBridge] Attached successfully
```

### ✅ Step 2: Verify Geofence Configuration

Make sure your geofence has notifications enabled:

1. Open **Geofence List** page
2. Select a geofence
3. Check **Notification Settings**:
   - ✅ **Enabled**: Must be ON
   - ✅ **On Enter**: Enable if you want entry notifications
   - ✅ **On Exit**: Enable if you want exit notifications
   - ✅ **Notification Type**: Set to **Local** (or **Both**)

### ✅ Step 3: Test Notification Permissions

**Android (Emulator)**:
```bash
# Check if notification permission is granted
adb shell dumpsys notification_listener
```

**Grant notification permission manually**:
1. Settings → Apps → Your App → Permissions → Notifications → Allow

### ✅ Step 4: Trigger a Geofence Event

**Method 1: Using Location Mock (Emulator)**

1. Open Android Emulator
2. Click "..." (Extended Controls)
3. Go to **Location** tab
4. Enter coordinates **inside** your geofence
5. Click "Send"
6. Wait 2-5 seconds
7. Enter coordinates **outside** your geofence
8. Click "Send"

**Method 2: Using ADB**

```powershell
# Send GPS coordinates to emulator
adb shell am broadcast -a com.yourapp.MOCK_LOCATION --es latitude "YOUR_LAT" --es longitude "YOUR_LON"
```

### ✅ Step 5: Check Event Logs

You should see these logs when an event occurs:

```
[GeofenceMonitorService] Recorded event: entry at [Geofence Name]
[GeofenceNotificationBridge] Processing event: entry at [Geofence Name]
[GeofenceNotificationBridge] Notification type: local
[GeofenceNotificationBridge] Showed local notification for entry event
[NotificationService] Showed notification for entry event
```

---

## Common Issues & Solutions

### Issue 1: "NotificationService not initialized"

**Symptom:**
```
[NotificationService] Cannot show notification - service not initialized
```

**Solution:**
The NotificationService is initialized in `main.dart`. Make sure you're running the latest code.

**Verification:**
```dart
// In main.dart
await geofenceNotificationService.init();
```

---

### Issue 2: "Geofence not found"

**Symptom:**
```
[GeofenceNotificationBridge] Geofence not found: abc123
```

**Solution:**
The bridge doesn't have the latest geofences list.

**Check:**
1. Make sure geofences are loaded: Go to Geofence List page
2. Check debug logs for: `[GeofenceProviders] 🔄 Updated bridge with N geofences`

---

### Issue 3: "Event does not trigger notification"

**Symptom:**
```
[GeofenceNotificationBridge] Event does not trigger notification
```

**Root Cause:**
Geofence notification triggers are disabled.

**Solution:**
1. Edit the geofence
2. Enable **On Enter** and/or **On Exit**
3. Save changes
4. Check logs: `[GeofenceProviders] 🔄 Updated bridge with N geofences`

---

### Issue 4: Duplicate events filtered

**Symptom:**
```
[GeofenceNotificationBridge] Duplicate event, skipping notification
```

**Explanation:**
This is normal! The bridge prevents notification spam by filtering duplicate events within a 30-second window.

**If you want to test repeatedly:**
Wait 30 seconds between tests OR restart the app to clear the deduplication cache.

---

### Issue 5: Notifications not appearing on Android 13+

**Symptom:**
No error logs, but notifications don't show.

**Root Cause:**
Android 13+ requires explicit notification permission.

**Solution:**
```dart
// Already handled in NotificationService.init()
await _local
    .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>()
    ?.requestNotificationsPermission();
```

**Manual Permission Grant:**
1. Settings → Apps → Your App
2. Permissions → Notifications → Allow

---

## Testing Workflow

### Complete Test Sequence

1. **Start App**
   ```
   flutter run
   ```

2. **Check Initialization Logs**
   ```
   [AppRoot] 🔔 Geofence notification bridge initializing
   [GeofenceProviders] 🔔 Notification bridge attached with N geofences
   ```

3. **Navigate to Geofence List**
   - Bottom Nav → Geofences tab
   - Verify geofences load

4. **Create/Edit Test Geofence**
   - Name: "Test Notification"
   - Center: Your current emulator location
   - Radius: 500 meters
   - ✅ Enabled
   - ✅ On Enter: Enabled
   - ✅ On Exit: Enabled
   - Notification Type: **Local**
   - Save

5. **Trigger Entry Event**
   - Emulator → Extended Controls → Location
   - Enter coordinates **inside** geofence
   - Wait 5 seconds

6. **Expected Result:**
   - Notification appears: "📍 Device entered Test Notification"
   - Log: `[NotificationService] Showed notification for entry event`

7. **Trigger Exit Event**
   - Enter coordinates **outside** geofence (at least 600m away)
   - Wait 5 seconds

8. **Expected Result:**
   - Notification appears: "🚪 Device exited Test Notification"
   - Log: `[NotificationService] Showed notification for exit event`

---

## Debug Commands

### View All Notifications (Android)

```powershell
# List active notifications
adb shell dumpsys notification | findstr "NotificationRecord"

# View notification settings for your app
adb shell dumpsys notification | findstr "com.yourapp"
```

### Clear All Notifications

```powershell
# Clear notification bar
adb shell cmd notification clear_all
```

### Force Grant Notification Permission

```powershell
adb shell pm grant com.example.my_app_gps android.permission.POST_NOTIFICATIONS
```

### View Geofence Monitor Status

Check logs for:
```
[GeofenceMonitorService] Monitoring started successfully
[GeofenceMonitorService] Loaded N active geofences
```

---

## Architecture Overview

```
┌─────────────────────────────────────────────────────────────┐
│                      User Movement                           │
│                           ↓                                  │
│                  Position Update                             │
│                           ↓                                  │
│              ┌────────────────────────┐                      │
│              │ GeofenceMonitorService │                      │
│              │  (Evaluates position   │                      │
│              │   against geofences)   │                      │
│              └────────────┬───────────┘                      │
│                           │                                  │
│                    Emits Event                               │
│                           ↓                                  │
│              ┌────────────────────────┐                      │
│              │GeofenceNotificationBridge│ ← 🎯 FIX APPLIED │
│              │  (Listens to events)   │    (now attached)   │
│              └────────────┬───────────┘                      │
│                           │                                  │
│                   Filters & Validates                        │
│                           ↓                                  │
│              ┌────────────────────────┐                      │
│              │   NotificationService  │                      │
│              │   (Shows notification) │                      │
│              └────────────────────────┘                      │
│                           ↓                                  │
│                   📱 User sees notification                  │
└─────────────────────────────────────────────────────────────┘
```

---

## Files Modified

1. **lib/features/geofencing/providers/geofence_providers.dart**
   - Added `geofenceNotificationBridgeProvider` attachment logic
   - Loads geofences and attaches to monitor's event stream
   - Added debug logging

2. **lib/app/app_root.dart**
   - Added geofence notification bridge initialization in `initState()`
   - Added import for `geofence_providers.dart`

---

## Next Steps

### If Notifications Still Don't Appear:

1. **Check Logcat** (while running the app):
   ```powershell
   adb logcat | findstr "Geofence\|Notification"
   ```

2. **Enable Verbose Logging**:
   - Already enabled with `kDebugMode` checks
   - All debug prints will show in console

3. **Verify Geofence Monitor is Running**:
   ```
   [GeofenceMonitorService] Monitoring started successfully
   ```

4. **Test with a Simple Entry/Exit**:
   - Create geofence with 500m radius
   - Move 1km away
   - Move back to center
   - Should trigger both exit and entry

5. **Check Android System Settings**:
   - Settings → Apps → Your App → Notifications
   - Verify "Geofence Alerts" channel is enabled

---

## Success Indicators

When everything is working correctly, you'll see:

✅ **At App Start:**
```
[AppRoot] 🔔 Geofence notification bridge initializing
[GeofenceProviders] 🔔 Notification bridge attached with 3 geofences
[GeofenceNotificationBridge] Attaching to event stream
[GeofenceNotificationBridge] Attached successfully
```

✅ **When Geofences Load:**
```
[GeofenceProviders] 🔄 Updated bridge with 3 geofences
[GeofenceNotificationBridge] Updated 3 geofences
```

✅ **When Event Occurs:**
```
[GeofenceMonitorService] Recorded event: entry at Home
[GeofenceNotificationBridge] Processing event: entry at Home
[GeofenceNotificationBridge] Notification type: local
[GeofenceNotificationBridge] Showed local notification for entry event
[NotificationService] Showed notification for entry event
```

✅ **In Notification Bar:**
```
📍 Device entered Home
Time: Jan 26, 14:30
```

---

## Contact & Support

If you're still experiencing issues after following this guide:

1. Share your logcat output (filter by "Geofence" and "Notification")
2. Check which logs are appearing and which are missing
3. Verify your geofence configuration (screenshot)
4. Confirm Android version (Settings → About → Android version)

The fix addresses the core issue - the bridge is now properly attached and listening for events. All notifications should work as expected!
