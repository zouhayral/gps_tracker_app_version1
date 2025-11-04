# Geofence Notification Debugging Guide

## Problem
You're still not receiving notifications when devices enter/exit geofences, even after the position feeder was implemented.

## Debug Logging Added

I've added comprehensive debug logging throughout the entire geofence notification pipeline. Run your app and watch the console output to diagnose the issue.

### Expected Log Flow (When Working)

When monitoring is enabled and a device crosses a geofence boundary, you should see these logs in order:

```
1. [AppRoot] 📍 Geofence position feeder initializing

2. [GeofencePositionFeederProvider] Started feeding (monitor active)
   [GeofencePositionFeeder] Starting position feed...
   [GeofencePositionFeeder] Adding subscription for device: Device Name (123)
   [GeofencePositionFeeder] ✅ Position feed active

3. [GeofenceMonitorService] Loading geofences...
   [GeofenceMonitorService] Loaded 2 active geofences

4. [GeofencePositionFeeder] 📍 Position received for device 123: (lat, lng)
   [GeofencePositionFeeder] ✅ Position processed for device 123

5. [GeofenceMonitorController] 📍 Forwarding position from device 123 to monitor

6. [GeofenceMonitorService] 🔍 Processing position for device 123: (lat, lng)
   [GeofenceMonitorService] 📊 Evaluating 2 geofences for device 123

7. [GeofenceMonitorService] 🎯 Generated 1 events for device 123
   [GeofenceMonitorService] ✅ Recorded event: entry for geofence Home (device: 123)
   [GeofenceMonitorService] 📢 Event emitted to stream

8. [GeofenceNotificationBridge] 🔔 Received event: entry at Home (device: 123)
   [GeofenceNotificationBridge] Found geofence: Home (onEnter: true, onExit: true)
   [GeofenceNotificationBridge] ✅ Event should trigger notification
   [GeofenceNotificationBridge] ✅ Event processed successfully - notification shown!
```

## Diagnostic Steps

### Step 1: Check if Monitoring is Active

1. Open the app
2. Go to **Geofence Settings** page
3. You'll see a **bug icon** 🐛 in the app bar (debug mode only)
4. Tap the bug icon
5. Check console output for:

```
=== GEOFENCE MONITORING DIAGNOSTICS ===
Active: true  ← MUST be true
Active Geofences Count: 2  ← Must be > 0
Events Triggered: 0
Last Update: null
Error: null
=====================================
```

**If Active is false**:
- Toggle the "Enable Geofencing" switch ON
- Make sure you're signed in
- Check console for error messages

**If Active Geofences Count is 0**:
- Go to Geofence List
- Create at least one geofence
- Ensure the geofence is **enabled** (toggle switch ON)

### Step 2: Check Position Feeder

Look for these logs on app startup:

```
[AppRoot] 📍 Geofence position feeder initializing
```

When you enable monitoring, look for:

```
[GeofencePositionFeederProvider] Started feeding (monitor active)
[GeofencePositionFeeder] Starting position feed...
[GeofencePositionFeeder] Adding subscription for device: Device 1 (123)
[GeofencePositionFeeder] Updated subscriptions: 1 active (added: 1, removed: 0)
[GeofencePositionFeeder] ✅ Position feed active
```

**If you don't see these logs**:
- The feeder might not be initialized
- Check `lib/app/app_root.dart` - the feeder should be initialized in `initState()`

### Step 3: Check Position Updates

Wait for device position updates (usually every 5-30 seconds). Look for:

```
[GeofencePositionFeeder] 📍 Position received for device 123: (lat, lng)
[GeofenceMonitorController] 📍 Forwarding position from device 123 to monitor
[GeofenceMonitorService] 🔍 Processing position for device 123: (lat, lng)
```

**If you see**: `[GeofencePositionFeeder] ⚠️ Monitor not active, skipping position`
- Problem: Monitor thinks it's not active
- Solution: Toggle monitoring OFF then ON again

**If you don't see position logs at all**:
- Problem: VehicleDataRepository not emitting positions
- Check if devices are online
- Check WebSocket connection status

### Step 4: Check Geofence Evaluation

When a device is near/inside a geofence, look for:

```
[GeofenceMonitorService] 📊 Evaluating 2 geofences for device 123
```

**If you see**: `[GeofenceMonitorService] ⚠️ No active geofences to evaluate`
- Problem: No geofences loaded
- Solution: Create geofences and ensure they're enabled

**If you see**: `[GeofenceMonitorService] ⏱️ Throttled position for device 123`
- This is normal - the monitor throttles frequent updates
- Wait a bit longer for the next evaluation

### Step 5: Check Event Generation

When device crosses boundary, look for:

```
[GeofenceMonitorService] 🎯 Generated 1 events for device 123
[GeofenceMonitorService] ✅ Recorded event: entry for geofence Home (device: 123)
[GeofenceMonitorService] 📢 Event emitted to stream
```

**If you see**: `[GeofenceMonitorService] No geofence transitions detected`
- This means the device is either:
  - Already inside/outside (no state change)
  - Too far from any geofence
  - Or geofence boundaries aren't correctly defined

**To test transitions**:
1. Note the current device position
2. Create a geofence that the device is currently OUTSIDE of
3. Wait for next position update
4. Manually move the device marker INSIDE the geofence (if testing with simulated positions)
5. You should see an "entry" event generated

### Step 6: Check Notification Bridge

When event is generated, look for:

```
[GeofenceNotificationBridge] 🔔 Received event: entry at Home (device: 123)
[GeofenceNotificationBridge] Found geofence: Home (onEnter: true, onExit: true)
```

**If you see**: `[GeofenceNotificationBridge] ⚠️ Geofence not found`
- Problem: Bridge doesn't have the geofence in its local cache
- Rare issue - restart the app

**If you see**: `[GeofenceNotificationBridge] ⚠️ Event does not trigger notification (check onEnter/onExit flags)`
- **CRITICAL**: Your geofence has `onEnter: false` or `onExit: false`
- Solution: Edit the geofence and enable entry/exit notifications

**If you see**: `[GeofenceNotificationBridge] ⚠️ Duplicate event detected`
- This is normal duplicate prevention
- The exact same event happened within the last 60 seconds

### Step 7: Check Notification Display

Final logs should show:

```
[GeofenceNotificationBridge] ✅ Event should trigger notification
[NotificationService] Showing geofence event: entry for Home
[GeofenceNotificationBridge] ✅ Event processed successfully - notification shown!
```

**If you see all these logs but NO notification appears**:
- Problem: Notification permissions
- Check:
  1. App has notification permissions granted
  2. Do Not Disturb is not enabled
  3. App notifications are not blocked in system settings
  4. Notification channels are enabled (Android)

## Common Issues and Solutions

### Issue 1: "Monitor not active" warnings

**Symptom**:
```
[GeofencePositionFeeder] ⚠️ Monitor not active, skipping position for device 123
```

**Solution**:
1. Go to Geofence Settings
2. Toggle "Enable Geofencing" OFF
3. Wait 2 seconds
4. Toggle "Enable Geofencing" ON
5. You should see: `✅ Geofence monitoring started`

### Issue 2: "No active geofences to evaluate"

**Symptom**:
```
[GeofenceMonitorService] ⚠️ No active geofences to evaluate
```

**Solution**:
1. Go to Geofence List
2. Verify you have at least one geofence created
3. Ensure the geofence toggle switch is ON (enabled)
4. Check console: `[GeofenceMonitorService] Loaded X active geofences` where X > 0

### Issue 3: "Event does not trigger notification"

**Symptom**:
```
[GeofenceNotificationBridge] ⚠️ Event does not trigger notification (check onEnter/onExit flags)
```

**Solution**:
1. Edit your geofence
2. Scroll to notification settings
3. Ensure **both** of these are enabled:
   - ☑️ Notify on Entry
   - ☑️ Notify on Exit
4. Save the geofence

### Issue 4: No position updates at all

**Symptom**: No logs starting with `[GeofencePositionFeeder] 📍 Position received`

**Causes**:
1. **Device offline**: Check if device shows as connected on map
2. **No devices configured**: Add at least one device
3. **WebSocket disconnected**: Check connection status
4. **Position feeder not subscribed**: Restart app

**Solution**:
1. Check device list - ensure you have devices
2. Verify devices are online (green indicator)
3. Restart the app
4. Re-enable monitoring

### Issue 5: Position received but not reaching monitor

**Symptom**: 
```
[GeofencePositionFeeder] 📍 Position received for device 123
```
But NO log: `[GeofenceMonitorController] 📍 Forwarding position`

**This means**:
- Position feeder is working
- But monitor controller is not processing

**Solution**:
1. Check if monitoring is active (Step 1)
2. Restart monitoring (toggle OFF/ON)
3. Check for error logs

## Testing Recommendations

### Test 1: Simple Entry/Exit Test

1. **Setup**:
   - Enable monitoring
   - Create a circular geofence with 100m radius
   - Place it where your device is NOT currently located
   - Enable `onEnter` and `onExit`

2. **Test Entry**:
   - Move device into the geofence area
   - Wait 30 seconds
   - Check logs for "entry" event
   - Verify notification appears

3. **Test Exit**:
   - Move device outside the geofence
   - Wait 30 seconds
   - Check logs for "exit" event
   - Verify notification appears

### Test 2: Multiple Geofences

1. Create 2-3 geofences in different locations
2. Enable monitoring
3. Check logs: Should show "Evaluating X geofences"
4. Move device through different zones
5. Verify notifications for each transition

### Test 3: Rapid Entry/Exit

1. Move device in and out of geofence quickly
2. You should see:
   - First event: Notification shown
   - Duplicate events within 60s: Skipped with "Duplicate event" log
3. This is correct behavior (prevents notification spam)

## Advanced Debugging

### Enable Verbose Position Logging

If you want to see EVERY position update, add this to `geofence_position_feeder.dart`:

```dart
_subscriptions[deviceId] = vehicleRepo.positionStream(deviceId).listen(
  (Position? position) async {
    debugPrint('[VERBOSE] Position: device=$deviceId, lat=${position?.latitude}, lng=${position?.longitude}');
    // ... rest of code
```

### Check Geofence Geometry

Add logging to see calculated distances:

```dart
// In GeofenceEvaluatorService.evaluate()
debugPrint('[Evaluator] Device at: $position');
for (final geofence in activeGeofences) {
  final distance = _calculateDistance(position, geofence.center);
  debugPrint('[Evaluator] Distance to ${geofence.name}: ${distance}m (radius: ${geofence.radius}m)');
}
```

## Quick Checklist

Before testing, verify:

- ✅ Signed in to app
- ✅ At least one device configured and online
- ✅ At least one geofence created and enabled
- ✅ Geofence has `onEnter: true` or `onExit: true`
- ✅ Monitoring toggle is ON (Geofence Settings page)
- ✅ Notification permissions granted
- ✅ App in debug mode to see logs

## Get Help

If notifications still don't work after following this guide:

1. **Collect these logs**:
   - App startup logs (first 100 lines)
   - Geofence settings diagnostics output
   - Position update logs (at least 5 position updates)
   - Any error messages

2. **Provide this info**:
   - How many geofences are created?
   - Are they enabled?
   - What are the onEnter/onExit flag values?
   - How far is the device from the geofence boundary?

3. **Share the complete log sequence** from when you:
   - Enable monitoring
   - Wait for position update
   - Device crosses boundary
   - (Expected notification but didn't appear)

---

**Status**: Debug logging implemented
**Date**: 2025-11-03
**Agent**: GitHub Copilot
