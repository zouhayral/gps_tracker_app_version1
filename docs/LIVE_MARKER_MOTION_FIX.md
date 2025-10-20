# Live Marker Motion Fix

## Problem Statement

Map markers were not updating automatically when WebSocket position updates arrived. Users had to manually deselect and reselect devices to see the marker move to the new position.

**Symptoms:**
- WebSocket logs showed position updates: `[VehicleProvider] 🔄 Position updated`
- Markers remained frozen at old coordinates
- Manual reselection forced a marker rebuild with latest position

**Root Cause:**
The `MarkerMotionController` existed in the codebase but was **never instantiated or integrated**. Markers were being created with static coordinates from the position snapshots, with no interpolation or animation between updates.

---

## Solution Architecture

### 1. **Motion Controller Integration**

Added `MarkerMotionController` instance to `_MapPageState`:

```dart
late final MarkerMotionController _motionController;
```

**Initialization** (in `initState`):
```dart
_motionController = MarkerMotionController(
  motionInterval: const Duration(milliseconds: 200),      // 5 FPS tick rate
  interpolationDuration: const Duration(milliseconds: 1200), // Smooth 1.2s transitions
  curve: Curves.easeOutCubic,                            // Natural deceleration
  enableExtrapolation: true,                             // Dead-reckoning for moving vehicles
  maxExtrapolation: const Duration(seconds: 8),
  minSpeedKmhForExtrapolation: 3.0,
);
```

**Purpose:**
- Interpolates marker positions between discrete WebSocket updates
- Provides smooth animation at 5 FPS (200ms ticks)
- Extrapolates position for moving vehicles (speed ≥ 3 km/h) during update gaps
- Uses cubic easing for natural motion

---

### 2. **Position Feed Pipeline**

Modified `_setupPositionListenersInBuild` to feed the motion controller:

```dart
ref.listen(vehiclePositionProvider(deviceId), (previous, next) {
  final pos = next.valueOrNull;
  if (pos != null) {
    // Cache for fallback
    _lastPositions[deviceId] = pos;
    
    // CRITICAL: Feed to motion controller
    _motionController.updatePosition(
      deviceId: deviceId,
      target: LatLng(pos.latitude, pos.longitude),
      timestamp: pos.serverTime,
      speedKmh: pos.speed,
      courseDeg: pos.course,
    );
  }
  
  // Trigger immediate first-frame update
  _scheduleMarkerUpdate(currentDevices);
});
```

**Flow:**
1. WebSocket update → `vehiclePositionProvider` emits new `Position`
2. Position fed to `_motionController.updatePosition()` as target
3. Motion controller starts interpolation from current → target over 1200ms
4. `_scheduleMarkerUpdate` triggers immediate marker rebuild for first frame

---

### 3. **Motion Tick Listener**

Added `_onMotionTick` callback for continuous animation:

```dart
_motionController.globalTick.addListener(_onMotionTick);

void _onMotionTick() {
  if (!mounted) return;
  
  final devicesAsync = ref.read(devicesNotifierProvider);
  final devices = devicesAsync.asData?.value ?? [];
  
  _scheduleMarkerUpdate(devices);
}
```

**Purpose:**
- `globalTick` ValueNotifier increments when any device is animating
- Triggers marker layer rebuild at 5 FPS during active motion
- No widget rebuilds — only marker layer via `ValueListenableBuilder`

---

### 4. **Marker Position Injection**

Modified `_processMarkersAsync` to use interpolated coordinates:

```dart
// Merge motion-controlled positions with static fallbacks
final motionPositions = <int, Position>{};

for (final deviceId in devices...) {
  // Priority 1: Motion controller's live interpolated position
  final motionLatLng = _motionController.currentValue(deviceId);
  
  if (motionLatLng != null) {
    final basePos = positions[deviceId] ?? _lastPositions[deviceId];
    if (basePos != null) {
      // Create position with ANIMATED coordinates
      motionPositions[deviceId] = Position(
        latitude: motionLatLng.latitude,  // ← Interpolated
        longitude: motionLatLng.longitude, // ← Interpolated
        // ... original metadata (speed, course, etc.)
      );
    }
  } else {
    // Fallback: use static WebSocket position
    motionPositions[deviceId] = positions[deviceId] ?? _lastPositions[deviceId];
  }
}

// Pass motion-controlled positions to marker cache
final diffResult = _enhancedMarkerCache.getMarkersWithDiff(
  motionPositions,  // ← Animated coordinates
  devices,
  selectedIds,
  query,
);
```

**Key Points:**
- Markers now receive **interpolated** coordinates from motion controller
- Fallback to static position if motion controller hasn't started yet
- Metadata (speed, course, attributes) preserved from original WebSocket data

---

## Data Flow Diagram

```
┌──────────────────────┐
│  WebSocket Update    │
│  (new position)      │
└──────────┬───────────┘
           │
           ▼
┌──────────────────────────────────┐
│ vehiclePositionProvider(deviceId)│ ← StreamProvider
└──────────┬───────────────────────┘
           │
           ▼
┌──────────────────────────────────┐
│ ref.listen callback              │
│  1. Cache position               │
│  2. Feed to motion controller    │ ← updatePosition(target, speed, course)
│  3. Trigger first-frame update   │
└──────────┬───────────────────────┘
           │
           ├─────────────────────────────┐
           │                             │
           ▼                             ▼
┌────────────────────┐      ┌──────────────────────────┐
│ Motion Controller  │      │ _scheduleMarkerUpdate    │
│  - Interpolate     │      │  (immediate first frame) │
│  - Extrapolate     │      └──────────────────────────┘
│  - globalTick++    │                 │
└────────┬───────────┘                 │
         │                             │
         │ (every 200ms)               │
         ▼                             ▼
┌────────────────────┐      ┌──────────────────────────┐
│ _onMotionTick      │      │ _processMarkersAsync     │
│  (5 FPS rebuild)   │      │  - Get interpolated pos  │
└────────┬───────────┘      │  - Generate markers      │
         │                  │  - Update ValueNotifier  │
         │                  └──────────────────────────┘
         │                             │
         └─────────────────────────────┘
                      │
                      ▼
          ┌───────────────────────────┐
          │ ValueListenableBuilder    │
          │  (FlutterMapAdapter)      │
          │  → Rebuild marker layer   │
          └───────────────────────────┘
```

---

## Key Benefits

### ✅ **Live Updates**
- Markers update automatically when WebSocket data arrives
- No manual reselection required

### ✅ **Smooth Animation**
- 200ms tick rate (5 FPS) for fluid motion
- 1200ms interpolation window matches typical WebSocket intervals
- Cubic easing for natural acceleration/deceleration

### ✅ **Dead-Reckoning**
- Extrapolates position for moving vehicles (speed ≥ 3 km/h)
- Continues animating during WebSocket gaps (up to 8 seconds)
- Uses vehicle's course and speed for prediction

### ✅ **Performance**
- Only marker layer rebuilds (via `ValueListenableBuilder`)
- FlutterMap itself remains static
- Enhanced marker cache prevents unnecessary widget recreation
- Throttled updates (300ms minimum) prevent UI churn

### ✅ **Correct Riverpod Usage**
- `ref.watch` for data dependencies in build method
- `ref.listen` for side effects (feeding motion controller)
- `ref.read` in callbacks to avoid rebuild loops

---

## Testing Verification

Run `flutter analyze` and `flutter test`:
```bash
flutter analyze
# ✓ No issues found

flutter test
# ✓ All tests passing
```

**Manual Testing:**
1. Start app with live WebSocket connection
2. Select a device on the map
3. Observe marker smoothly animating to new positions as updates arrive
4. No manual reselection needed
5. Moving vehicles show dead-reckoning between updates

---

## Code Comments Guide

All changes are marked with `// LIVE MOTION FIX:` comments:

1. **Import addition** (line 22):
   ```dart
   import 'package:my_app_gps/core/map/marker_motion_controller.dart';
   ```

2. **Controller instance** (line 166):
   ```dart
   late final MarkerMotionController _motionController;
   ```

3. **Initialization** (lines 198-217):
   - Create motion controller with smooth interpolation settings
   - Register `_onMotionTick` listener

4. **Disposal** (lines 753-754):
   - Remove listener
   - Dispose controller resources

5. **Position listener** (lines 1297-1326):
   - Feed WebSocket updates to motion controller
   - Trigger immediate first-frame update

6. **Motion tick callback** (lines 1344-1357):
   - Rebuild markers during active animation
   - Called at 5 FPS by globalTick

7. **Position injection** (lines 925-990):
   - Merge interpolated positions from motion controller
   - Fallback to static positions if motion not started
   - Pass animated coordinates to marker cache

---

## Troubleshooting

### Markers still not moving?

1. **Check WebSocket connection:**
   ```dart
   // Look for logs:
   [VehicleProvider] 🔄 Position updated for device X
   ```

2. **Verify motion controller is receiving updates:**
   ```dart
   // Look for logs:
   [LIVE_MOTION] Device X: fed position to motion controller
   ```

3. **Check motion tick is firing:**
   ```dart
   // Look for logs:
   [LIVE_MOTION] Motion tick: N devices animating
   ```

4. **Verify interpolated positions are used:**
   ```dart
   // Look for logs when marker positions differ:
   [LIVE_MOTION] Device X: using interpolated position ... delta=Ym from WebSocket
   ```

### Animation too jerky?

Adjust motion controller settings in `initState`:
```dart
_motionController = MarkerMotionController(
  motionInterval: const Duration(milliseconds: 100),  // Increase to 10 FPS
  interpolationDuration: const Duration(milliseconds: 800), // Faster transitions
);
```

### Performance issues?

Check throttle settings:
```dart
// In _MapPageState initState:
_markersNotifier = ThrottledValueNotifier<List<MapMarkerData>>(
  const [],
  throttleDuration: const Duration(milliseconds: 500), // Increase to reduce CPU
);
```

---

## Related Files

- `lib/features/map/view/map_page.dart` — Main integration (this file)
- `lib/core/map/marker_motion_controller.dart` — Motion interpolation engine
- `lib/core/providers/vehicle_providers.dart` — Position data providers
- `lib/features/map/view/flutter_map_adapter.dart` — ValueListenableBuilder for markers

---

## Migration Notes

**Before this fix:**
- Markers used static coordinates from Position snapshots
- MarkerMotionController existed but was never used
- Manual reselection required to see updates

**After this fix:**
- Markers use interpolated coordinates from motion controller
- Smooth animation between WebSocket updates
- Automatic updates without user interaction

**Breaking changes:** None — fully backward compatible

**Performance impact:** Positive — reduces perceived jank, smooth motion
