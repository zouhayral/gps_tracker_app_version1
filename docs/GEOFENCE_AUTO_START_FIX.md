# Geofence Notification Auto-Start Fix

## ✅ Problem Solved

The `GeofenceBackgroundService` was not starting automatically, preventing geofence notifications from working.

## What Was Fixed

Added auto-start logic in `app_root.dart` that:
- Starts `GeofenceBackgroundService` when user logs in
- Stops service when user logs out  
- Subscribes to position updates from WebSocket
- Processes positions through geofence monitoring pipeline

## Debug Logs You Should See Now

### On Login:
```
[AppRoot] 🎯 User authenticated, starting geofence background service for user: <userId>
[GeofenceBackgroundService] 🚀 Starting for user <userId>
[GeofenceMonitorService] Starting monitoring for user: <userId>
[GeofenceBackgroundService] ✅ Started successfully
[GeofenceProviders] 🔔 Notification bridge attached with N geofences
```

### During Operation:
```
[GeofenceBackgroundService] Processed 10 positions. Last update: ...
[GeofenceNotificationBridge] Processing event: entry at <GeofenceName>
[NotificationService] Showing geofence notification
```

## Testing Steps

1. **Restart app** (full restart, not hot reload)
2. **Log in** and watch for startup logs
3. **Open geofence settings** and verify:
   - ✅ Geofence is **Enabled**
   - ✅ **On Enter** or **On Exit** is enabled
   - ✅ **Notification Type** = "Local" or "Both"
4. **Cross geofence boundary** slowly (walk, don't drive)
5. **Wait for notification**

## If Still Not Working

Check these in order:

1. **Service not starting?**
   - Look for: `[AppRoot] 🎯 User authenticated, starting...`
   - If missing → Do full app restart

2. **No position processing?**
   - Look for: `[GeofenceBackgroundService] Processed N positions`
   - If missing → WebSocket not connected

3. **No events?**
   - Check geofence config (enabled, triggers ON, notification type)
   - Try sending test notification from Settings → Geofences → Diagnostics

4. **No notifications showing?**
   - Check Android notification permissions
   - Settings → Apps → Your App → Notifications → Allowed

## Files Modified

- `lib/app/app_root.dart` - Added auto-start listener for auth state
