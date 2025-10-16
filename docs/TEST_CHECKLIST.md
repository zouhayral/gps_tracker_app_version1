# Quick Test Checklist - Ignition Real-Time Updates

## Before You Start
- [ ] Ensure Traccar server is running and accessible
- [ ] Verify you're logged into the app with valid credentials
- [ ] Have at least one device visible on the map

## Test Steps

### 1. Start the App
```powershell
cd C:\Users\Acer\Desktop\soceur\my_app_gps_version1
flutter clean
flutter pub get
flutter run --debug
```

**Wait for**: Console to show `[VehicleRepo] Initialized` and `[SOCKET] ✅ WebSocket channel created`

### 2. Select a Device
- [ ] Tap on a marker on the map
- [ ] Bottom sheet should slide up showing device details
- [ ] Note the current **Engine** status (on/off/unknown)

### 3. Change Ignition in Traccar
- [ ] Open Traccar web panel (http://37.60.238.215:8082)
- [ ] Find the same device
- [ ] Change its ignition status (or trigger a real ignition event if possible)
- [ ] Note the exact time of the change

### 4. Watch the Console
Within 1 second, you should see these logs (in order):

```
[SOCKET] 📨 RAW WebSocket message received:
[SOCKET] 🔔 Received events from WebSocket (or 📍 positions)
[VehicleRepo][WS] events payload: [...]
[VehicleRepo][WS] event for deviceId=X posId=Y
[VehicleRepo][WS] fetched Position for posId=Y -> device=X
[VehicleSnapshot] Creating snapshot for device X:
[VehicleSnapshot]   ignition attr: true/false (type: bool)
[VehicleSnapshot]   extracted engineState: EngineState.on/off
[VehicleRepo] Updating snapshot for device=X
[VehicleRepo]   incoming: VehicleDataSnapshot(...engine: on/off...)
[VehicleRepo]   merged: VehicleDataSnapshot(...engine: on/off...)
[VehicleProvider] Position for device X: ignition=true/false
[MapPage] ✅ Markers updated: N markers
```

### 5. Verify UI Update
- [ ] Check the bottom sheet **Engine** field
- [ ] It should now show the new ignition status
- [ ] The change should happen **within 1-2 seconds** of Traccar change

### 6. Test Multiple Devices
- [ ] Tap another device marker
- [ ] Change its ignition in Traccar
- [ ] Verify real-time update appears
- [ ] Both devices should update independently

## Success Criteria

✅ **WebSocket Connected**: See `[SOCKET] ✅` logs at startup
✅ **Messages Arriving**: See `[SOCKET] 📨` when Traccar sends updates
✅ **Events Processed**: See `[VehicleRepo][WS]` logs for events
✅ **Snapshots Created**: See `[VehicleSnapshot]` logs with ignition value
✅ **UI Updated**: Bottom sheet Engine field changes within 1-2 seconds
✅ **No Errors**: No red error logs in console

## Common Issues & Quick Fixes

### ❌ No WebSocket Logs
**Problem**: `[SOCKET]` logs never appear
**Fix**: 
- Check network connectivity
- Verify `baseUrl` in app points to your Traccar server
- Confirm you're logged in (valid JSESSIONID cookie)

### ❌ WebSocket Connected But No Messages
**Problem**: See `[SOCKET] ✅` but no `[SOCKET] 📨` when changing ignition
**Fix**:
- Verify Traccar is sending WebSocket updates (check Traccar logs)
- Try changing speed/position (not just ignition) to test WebSocket
- Restart Traccar server if needed

### ❌ Messages Arrive But No UI Update
**Problem**: See all logs but UI doesn't change
**Fix**:
- Check if `ignition attr: null` in logs (device doesn't send ignition)
- Verify timestamp: newer snapshot should have later time
- Try tapping the marker again to refresh selection

### ❌ UI Updates But Slowly (>3 seconds)
**Problem**: Updates work but take too long
**Fix**:
- Check for errors in `[VehicleRepo]` logs
- Verify marker throttling isn't too aggressive (should be 80ms)
- Run in profile mode: `flutter run --profile` to check performance

## Advanced Debugging

### If Nothing Works:
1. **Copy the entire console output** when you trigger an ignition change
2. **Take screenshots** of:
   - App UI before change
   - Traccar panel showing the change
   - App UI 5 seconds after change
3. **Check these specific logs**:
   - `[SOCKET] Events payload:` - does it contain the device ID?
   - `[VehicleSnapshot] ignition attr:` - is it null or a boolean?
   - `[VehicleRepo] merged:` - does engine state change?

### Enable Extra Verbose Logging:
In `traccar_socket_service.dart`, line ~120, add:
```dart
if (kDebugMode) {
  print('[SOCKET] FULL MESSAGE: $text');
}
```

This prints the entire JSON payload for deep inspection.

## Performance Check

While testing, watch for:
- **FPS**: Should stay above 50 fps (shown in debug overlay if enabled)
- **Frame drops**: Occasional drops acceptable, but not continuous
- **Memory**: Should not continuously grow

If performance degrades, check marker count: `[MapPage] ✅ Markers updated: N markers`
- If N > 500, consider filtering devices

## Test Complete ✅

If all checks pass:
- [ ] Ignition updates appear in <2 seconds
- [ ] Multiple devices update correctly
- [ ] No console errors
- [ ] App remains responsive

**Congratulations!** Real-time updates are working correctly.

## Report Issues

If problems persist, please provide:
1. Full console log from app startup to ignition change (copy the text)
2. Traccar server version
3. Device type/model that's not updating
4. Screenshots of app UI + Traccar panel

Save logs to a file:
```powershell
flutter run --debug > debug_log.txt 2>&1
```

Then share `debug_log.txt`.
