# Real-Time Update Debugging Guide

## Problem Statement
Ignition status and attributes are not updating in real-time in the app even though Traccar server shows the updates immediately.

## What We Fixed

### 1. Enhanced WebSocket Message Handling
**File**: `lib/services/traccar_socket_service.dart`
- Added detailed logging for all incoming WebSocket messages
- Logs raw JSON payloads for `positions`, `events`, and `devices` messages
- Shows ignition attribute values for each position update

### 2. Repository Event/Device Processing
**File**: `lib/core/data/vehicle_data_repository.dart`
- Modified `_handleSocketMessage()` to process `events` and `devices` WebSocket messages
- When an event contains `positionId`, fetches the full Position and processes it
- When an event contains only `deviceId`, refreshes device data immediately
- Added debug logging at each step showing:
  - When events/devices payloads arrive
  - Which device IDs and position IDs are being processed
  - When Position fetches complete
  - When snapshots are updated (incoming, existing, merged)

### 3. Snapshot Creation Logging
**File**: `lib/core/data/vehicle_data_snapshot.dart`
- Added debug logging when creating snapshots from Position objects
- Shows ignition attribute type and value
- Displays extracted engineState (on/off/unknown)
- Lists all available attributes from the position

### 4. Provider Update Tracking
**File**: `lib/core/providers/vehicle_providers.dart`
- Added logging in `vehiclePositionProvider` to show when position data flows to UI
- Displays lat/lon, ignition, and speed for each update

### 5. Map Page Marker Rebuild Tracking
**File**: `lib/features/map/view/map_page.dart`
- Added logging when markers are processed and updated
- Shows how many positions are being processed
- Confirms when marker notifier is updated with new data

## How to Debug Real-Time Updates

### Step 1: Run the App in Debug Mode
```powershell
flutter run --debug
```

### Step 2: Watch the Console for These Log Patterns

#### A. WebSocket Connection
Look for:
```
[SOCKET] ═══════════════════════════════════════
[SOCKET] Attempting WebSocket connection...
[SOCKET] ✅ WebSocket channel created
[SOCKET] ✅ WebSocket stream listener attached
```

#### B. Incoming WebSocket Messages
When Traccar sends updates, you should see:
```
[SOCKET] 📨 RAW WebSocket message received:
[SOCKET] {"positions":[{...}]} (or {"events":[{...}]} or {"devices":[{...}]})
```

For position updates:
```
[SOCKET] 📍 Received 1 positions from WebSocket
[SOCKET]   Device 123: ignition=true, speed=45.5
```

For events:
```
[SOCKET] 🔔 Received events from WebSocket
[SOCKET] Events payload: [{"id":456,"deviceId":123,"positionId":789,...}]
```

For devices:
```
[SOCKET] 📱 Received device updates from WebSocket
[SOCKET] Devices payload: [{"id":123,"positionId":789,...}]
```

#### C. Repository Processing
Look for repository handling the message:
```
[VehicleRepo][WS] events payload: [...]
[VehicleRepo][WS] event for deviceId=123 posId=789
[VehicleRepo][WS] fetched Position for posId=789 -> device=123
```

OR for device-only updates:
```
[VehicleRepo][WS] refreshing device data for deviceId=123 (event)
```

#### D. Snapshot Creation
When creating snapshots from Position:
```
[VehicleSnapshot] Creating snapshot for device 123:
[VehicleSnapshot]   ignition attr: true (type: bool)
[VehicleSnapshot]   extracted engineState: EngineState.on
[VehicleSnapshot]   speed: 45.5 km/h
[VehicleSnapshot]   all attributes: ignition, motion, battery, totalDistance
```

#### E. Snapshot Updates
When merging and notifying:
```
[VehicleRepo] Updating snapshot for device=123
[VehicleRepo]   incoming: VehicleDataSnapshot(deviceId: 123, timestamp: 2025-10-17 ..., engine: on, speed: 45.5 km/h, ...)
[VehicleRepo]   existing: VehicleDataSnapshot(deviceId: 123, timestamp: 2025-10-17 ..., engine: off, speed: 0.0 km/h, ...)
[VehicleRepo]   merged: VehicleDataSnapshot(deviceId: 123, timestamp: 2025-10-17 ..., engine: on, speed: 45.5 km/h, ...)
```

#### F. Provider Updates
When the UI receives the update:
```
[VehicleProvider] Position for device 123: lat=35.73898, lon=-5.88946, ignition=true, speed=45.5
```

#### G. Map Page Marker Rebuild
When markers are rebuilt:
```
[MapPage] Processing 3 positions for markers...
[MapPage] ✅ Markers updated: 3 markers
[MapPage] Sample marker IDs: 123, 124, 125
```

### Step 3: Test Ignition Change

1. **In Traccar Web Panel**: Change ignition status for a device
2. **In Flutter Console**: Watch for the sequence above (A → B → C → D → E → F → G)
3. **In App UI**: Verify the bottom sheet shows updated Engine status immediately

### Expected Timeline
- **WebSocket message arrival**: < 500ms after Traccar change
- **Repository processing**: < 100ms
- **Snapshot update**: < 50ms
- **Provider notification**: < 50ms
- **Marker rebuild**: < 100ms (throttled to 80ms)
- **Total UI update**: < 1 second from Traccar change to visible UI change

## Common Issues and Solutions

### Issue 1: No WebSocket Messages Arriving
**Symptoms**: No `[SOCKET]` logs after connecting
**Check**:
- WebSocket connection logs show `✅ WebSocket channel created`
- Traccar server is reachable (check `baseUrl` in Dio config)
- JSESSIONID cookie is valid (look for Cookie header in connection log)

**Fix**: Verify authentication and network connectivity

### Issue 2: Events/Devices Not Processed
**Symptoms**: `[SOCKET] 🔔 Received events` but no `[VehicleRepo][WS]` logs
**Check**:
- Repository subscription is active (should see `[VehicleRepo] WebSocket connected`)
- Event payload structure matches expected format

**Fix**: Check if `_handleSocketMessage` is called (add breakpoint or more logs)

### Issue 3: Ignition Attribute Missing
**Symptoms**: `[VehicleSnapshot] ignition attr: null`
**Check**:
- Traccar position JSON includes `"attributes":{"ignition":true/false}`
- Position.fromJson correctly parses attributes map

**Fix**: Verify Traccar device sends ignition attribute

### Issue 4: Snapshot Not Merging
**Symptoms**: `[VehicleRepo] merged:` shows old values
**Check**:
- Timestamps: newer snapshot should have later timestamp
- Merge logic: `existing?.merge(snapshot)` should prefer non-null newer values

**Fix**: Check `VehicleDataSnapshot.merge()` logic

### Issue 5: UI Not Rebuilding
**Symptoms**: Logs show snapshot updated but UI doesn't change
**Check**:
- `ValueNotifier.value = ...` is called (triggers listeners)
- Widget watches the provider (uses `ref.watch()` not `ref.read()`)
- `vehiclePositionProvider` is being watched on the map page

**Fix**: Ensure widgets use `ref.watch(vehiclePositionProvider(deviceId))`

## Advanced Debugging

### Enable More Verbose Logging
Temporarily increase log verbosity in specific files:

**In `traccar_socket_service.dart`** (line ~120):
```dart
if (kDebugMode) {
  print('[SOCKET] Full message: $text'); // Print entire JSON
}
```

**In `vehicle_data_repository.dart`** (line ~180):
```dart
if (kDebugMode) {
  debugPrint('[VehicleRepo] Full event: ${jsonEncode(e)}'); // Print full event object
}
```

### Monitor ValueNotifier Manually
Add this to MapPage `initState()`:
```dart
WidgetsBinding.instance.addPostFrameCallback((_) {
  for (final deviceId in deviceIds) {
    final notifier = ref.read(vehicleSnapshotProvider(deviceId));
    notifier.addListener(() {
      debugPrint('[MapPage] Device $deviceId snapshot changed: ${notifier.value}');
    });
  }
});
```

### Check Network Traffic
Use Flutter DevTools Network tab to see:
- WebSocket connection established
- Incoming WebSocket frames
- REST API fallback calls

### Profile Mode Performance
```powershell
flutter run --profile
```
Check if updates are being throttled due to performance issues.

## Success Criteria

✅ WebSocket messages arrive within 500ms of Traccar change
✅ Repository processes events/devices messages
✅ Snapshots are created with correct ignition value
✅ Notifier updates trigger provider rebuilds
✅ Map markers reflect new state within 1 second
✅ Bottom sheet Engine status shows "on" or "off" immediately

## Rollback Instructions

If logging causes performance issues, remove debug blocks:

1. Search for `if (kDebugMode)` blocks added in this fix
2. Delete or comment out the debug print statements
3. Keep the actual logic (event/device processing) intact

## Contact Points

- WebSocket handling: `lib/services/traccar_socket_service.dart`
- Event processing: `lib/core/data/vehicle_data_repository.dart`
- Snapshot logic: `lib/core/data/vehicle_data_snapshot.dart`
- UI providers: `lib/core/providers/vehicle_providers.dart`
- Map rendering: `lib/features/map/view/map_page.dart`
