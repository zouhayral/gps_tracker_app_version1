# Auto-Zoom Button - Feature Documentation

## 🎯 Overview

The Auto-Zoom button is a new UI control that automatically adjusts the map camera to show selected device(s) in an optimal viewport. It provides one-tap access to center on devices without manual panning or zooming.

---

## 📍 Location

**File:** `lib/features/map/view/flutter_map_adapter.dart`

**UI Position:** Top-right corner of the map, positioned absolutely within the map's Stack

**Visual Style:**
- White semi-transparent background (90% opacity)
- Blue icon (`Icons.center_focus_strong`)
- Shadow for depth
- 44x44 touch target
- Tooltip: "Auto-zoom to selected"

---

## 🔧 Implementation Details

### 1. **UI Component**

```dart
Positioned(
  top: 16,
  right: 16,
  child: Material(
    color: Colors.transparent,
    child: Container(
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.9),
        borderRadius: BorderRadius.circular(8),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.2),
            blurRadius: 4,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: IconButton(
        icon: const Icon(Icons.center_focus_strong),
        color: Colors.blue.shade700,
        tooltip: 'Auto-zoom to selected',
        onPressed: _onAutoZoomPressed,
        // ... constraints ...
      ),
    ),
  ),
)
```

**Design Rationale:**
- **Top-right placement:** Doesn't overlap with attribution or other controls
- **Semi-transparent:** Ensures map content is visible underneath
- **Shadow:** Provides visual separation from map content
- **Icon choice:** `center_focus_strong` clearly communicates "focus/center" action

---

### 2. **Auto-Zoom Handler**

**Method:** `void _onAutoZoomPressed()`

**Logic Flow:**

```
1. Check if map is ready
   ├─ Not ready → Log warning and return
   └─ Ready → Continue

2. Determine selected devices
   ├─ Multi-selection mode + has selections → Use multiSelection
   ├─ Single selection exists → Use {singleSelection}
   └─ No selection → Use all devices (fallback)

3. Get marker positions for selected devices
   ├─ Filter markers by selected IDs
   └─ Validate positions (not NaN, within bounds)

4. Apply zoom strategy
   ├─ Single device (1 marker)
   │   └─ safeZoomTo(position, 16.0) → Direct zoom
   │
   └─ Multiple devices (2+ markers)
       └─ _fitBounds(positions) → Fit all in viewport
```

**Code:**
```dart
void _onAutoZoomPressed() {
  if (!_mapReady) {
    debugPrint('[AUTO_ZOOM] ⚠️ Map not ready yet');
    return;
  }

  // Get selected devices from Riverpod providers
  final singleSelection = ref.read(selectedDeviceIdProvider);
  final multiSelection = ref.read(selectedDeviceIdsProvider);
  final multiMode = ref.read(multiSelectionModeProvider);

  // Determine which devices are selected
  Set<int> selectedIds;
  if (multiMode && multiSelection.isNotEmpty) {
    selectedIds = multiSelection;
  } else if (singleSelection != null) {
    selectedIds = {singleSelection};
  } else {
    // No selection - show all devices
    final allMarkers = widget.markersNotifier?.value ?? widget.markers;
    selectedIds = allMarkers
        .map((m) => int.tryParse(m.id))
        .whereType<int>()
        .toSet();
  }

  // ... rest of logic
}
```

---

### 3. **Fit Bounds Helper**

**Method:** `void _fitBounds(List<LatLng> positions)`

**Algorithm:**

```
1. Calculate bounding box
   ├─ Find min/max latitude
   └─ Find min/max longitude

2. Create LatLngBounds
   └─ LatLngBounds(southwest, northeast)

3. Fit camera with constraints
   ├─ Padding: 50px all sides
   └─ MaxZoom: 16.0 (prevent excessive zoom for close markers)

4. Execute camera move
   └─ mapController.fitCamera(CameraFit.bounds(...))
```

**Code:**
```dart
void _fitBounds(List<LatLng> positions) {
  if (positions.isEmpty) return;
  if (!_mapReady) {
    _enqueueWhenReady(() => _fitBounds(positions));
    return;
  }

  // Calculate bounds
  double minLat = positions.first.latitude;
  double maxLat = positions.first.latitude;
  double minLng = positions.first.longitude;
  double maxLng = positions.first.longitude;

  for (final pos in positions) {
    if (pos.latitude < minLat) minLat = pos.latitude;
    if (pos.latitude > maxLat) maxLat = pos.latitude;
    if (pos.longitude < minLng) minLng = pos.longitude;
    if (pos.longitude > maxLng) maxLng = pos.longitude;
  }

  // Create bounds
  final bounds = LatLngBounds(
    LatLng(minLat, minLng),
    LatLng(maxLat, maxLng),
  );

  // Fit camera with padding and max zoom constraint
  mapController.fitCamera(
    CameraFit.bounds(
      bounds: bounds,
      padding: const EdgeInsets.all(50),
      maxZoom: 16.0, // Don't zoom in too much even if markers are close
    ),
  );

  debugPrint('[AUTO_ZOOM] 📐 Fitted bounds: ...');
}
```

---

## 🎬 User Experience

### Scenario 1: Single Device Selected

**User Action:**
1. Select one device from list or map
2. Tap auto-zoom button

**App Behavior:**
- Camera centers on device position
- Zooms to level 16 (street-level detail)
- Smooth animation
- Log: `[AUTO_ZOOM] 📍 Single device: centered at (...) @ zoom 16`

**Visual Result:**
- Device marker in center of screen
- Sufficient zoom to see surrounding streets/context
- No excessive zoom (capped at 16)

---

### Scenario 2: Multiple Devices Selected

**User Action:**
1. Enable multi-selection mode
2. Select 2+ devices
3. Tap auto-zoom button

**App Behavior:**
- Calculates bounding box containing all selected markers
- Zooms out to show all devices with 50px padding
- Max zoom limit of 16 (won't zoom in too much if devices are close)
- Log: `[AUTO_ZOOM] 🗺️ Multiple devices: fitted N markers`

**Visual Result:**
- All selected devices visible on screen
- 50px padding on all sides
- Comfortable overview of fleet distribution

---

### Scenario 3: No Selection (All Devices)

**User Action:**
1. No devices selected
2. Tap auto-zoom button

**App Behavior:**
- Treats all devices as "selected"
- Fits bounds to show entire fleet
- Same padding and maxZoom constraints

**Visual Result:**
- Full fleet overview
- All markers visible in viewport
- Good for "reset view" use case

---

### Scenario 4: Selected Device Has No Position

**User Action:**
1. Select device with no GPS data
2. Tap auto-zoom button

**App Behavior:**
- Filters out markers without valid positions
- If no valid positions remain:
  - Log: `[AUTO_ZOOM] ⚠️ No valid positions for selected devices`
  - No camera movement
  - User sees current map view unchanged

**Visual Result:**
- No camera movement
- Debug log explains why (no valid positions)

---

## 🧪 Testing

### Manual Test Cases

#### Test 1: Single Device Zoom
**Steps:**
1. Launch app
2. Select "Vehicle A" from list
3. Tap auto-zoom button (top-right)

**Expected:**
- Camera centers on Vehicle A
- Zoom level = 16
- Smooth animation
- Console log: `[AUTO_ZOOM] 📍 Single device: centered at (...) @ zoom 16`

**Pass Criteria:**
✅ Camera moves to device position  
✅ Zoom level is 16  
✅ Device marker is centered  
✅ Log appears in console  

---

#### Test 2: Multiple Devices Zoom
**Steps:**
1. Enable multi-selection mode
2. Select 3 devices (A, B, C)
3. Tap auto-zoom button

**Expected:**
- Camera fits all 3 devices in viewport
- 50px padding on all sides
- Max zoom = 16
- Console log: `[AUTO_ZOOM] 🗺️ Multiple devices: fitted 3 markers`

**Pass Criteria:**
✅ All 3 devices visible  
✅ Padding exists on all sides  
✅ Zoom level ≤ 16  
✅ Log shows correct count  

---

#### Test 3: No Selection (All Devices)
**Steps:**
1. Deselect all devices
2. Tap auto-zoom button

**Expected:**
- Camera fits all devices in fleet
- All markers visible with padding
- Console log: `[AUTO_ZOOM] 🎯 Zooming to N device(s)`

**Pass Criteria:**
✅ All fleet devices visible  
✅ Comfortable viewport  
✅ Log shows total device count  

---

#### Test 4: Map Not Ready
**Steps:**
1. Open map page (while still loading)
2. Immediately tap auto-zoom button

**Expected:**
- Warning log: `[AUTO_ZOOM] ⚠️ Map not ready yet`
- No camera movement
- No crash

**Pass Criteria:**
✅ Warning logged  
✅ No crash or error  
✅ Button remains functional after map loads  

---

#### Test 5: Device Without Position
**Steps:**
1. Select device with no GPS data
2. Tap auto-zoom button

**Expected:**
- Warning log: `[AUTO_ZOOM] ⚠️ No valid positions for selected devices`
- No camera movement

**Pass Criteria:**
✅ Warning logged  
✅ No crash  
✅ Camera stays in current position  

---

## 📊 Performance

### Complexity Analysis

**Single Device:**
- Time: O(1) - Direct zoom
- Memory: O(1) - Single position

**Multiple Devices:**
- Time: O(n) - Bounds calculation (n = number of markers)
- Memory: O(n) - Temporary position list

**Worst Case:**
- n = 1000 devices
- Bounds calculation: ~1-2ms
- Camera fit: ~50-100ms (flutter_map)
- Total: <150ms (imperceptible to user)

### Optimization Notes

1. **Lazy Evaluation:** Only processes selected devices, not entire fleet
2. **Early Returns:** Guards against invalid states (map not ready, no positions)
3. **Direct Access:** Uses `ref.read()` for one-time reads (no rebuilds)
4. **Reuses Existing API:** `safeZoomTo()` and `fitCamera()` are already optimized

---

## 🔧 Configuration

### Adjustable Parameters

**Single Device Zoom Level:**
```dart
// Current: 16.0
safeZoomTo(target, 16.0);

// To change: Adjust the second parameter
safeZoomTo(target, 18.0); // Closer zoom
safeZoomTo(target, 14.0); // Wider view
```

**Multi-Device Padding:**
```dart
// Current: 50px all sides
padding: const EdgeInsets.all(50)

// To change:
padding: const EdgeInsets.all(80) // More padding
padding: const EdgeInsets.only(top: 100, bottom: 50, left: 50, right: 50) // Custom
```

**Multi-Device Max Zoom:**
```dart
// Current: 16.0
maxZoom: 16.0

// To change:
maxZoom: 18.0 // Allow closer zoom for tight clusters
maxZoom: 14.0 // Force wider view
```

**Button Position:**
```dart
// Current: top-right
Positioned(
  top: 16,
  right: 16,
  child: ...
)

// To change:
Positioned(
  top: 16,
  left: 16, // Move to top-left
  child: ...
)
```

---

## 🐛 Troubleshooting

### Issue: Button doesn't appear

**Possible Causes:**
1. Stack positioning conflict
2. Z-index issue

**Solution:**
- Check that button is last in Stack children (highest z-index)
- Verify `Positioned` values don't place it off-screen

---

### Issue: Button tap does nothing

**Possible Causes:**
1. Map not ready yet
2. No devices selected or loaded
3. Selected devices have no positions

**Solution:**
- Check console logs for warnings
- Wait for map to fully load
- Ensure devices have valid GPS data

---

### Issue: Zoom level wrong for single device

**Possible Causes:**
1. `safeZoomTo()` clamps zoom to `kMaxZoom`
2. Custom zoom level doesn't match expectation

**Solution:**
- Check `kMaxZoom` constant in `flutter_map_adapter.dart`
- Adjust the `16.0` parameter in `safeZoomTo()` call

---

### Issue: Multiple devices don't fit in viewport

**Possible Causes:**
1. Padding too large
2. Max zoom prevents zooming out enough

**Solution:**
- Reduce padding: `EdgeInsets.all(30)`
- Remove or increase max zoom constraint

---

## 🎨 Customization Examples

### Example 1: Change Button Style

```dart
Container(
  decoration: BoxDecoration(
    color: Colors.blue.shade700.withOpacity(0.9), // Blue background
    borderRadius: BorderRadius.circular(50), // Circular button
    boxShadow: [
      BoxShadow(
        color: Colors.blue.withOpacity(0.3),
        blurRadius: 8,
        offset: const Offset(0, 4),
      ),
    ],
  ),
  child: IconButton(
    icon: const Icon(Icons.my_location), // Different icon
    color: Colors.white, // White icon
    tooltip: 'Center on devices',
    onPressed: _onAutoZoomPressed,
  ),
)
```

---

### Example 2: Add Animation

```dart
class _AutoZoomButton extends StatefulWidget {
  final VoidCallback onPressed;
  const _AutoZoomButton({required this.onPressed});
  
  @override
  State<_AutoZoomButton> createState() => _AutoZoomButtonState();
}

class _AutoZoomButtonState extends State<_AutoZoomButton>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  
  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      duration: const Duration(milliseconds: 200),
      vsync: this,
    );
  }
  
  @override
  Widget build(BuildContext context) {
    return ScaleTransition(
      scale: Tween<double>(begin: 1.0, end: 0.9).animate(
        CurvedAnimation(parent: _controller, curve: Curves.easeOut),
      ),
      child: IconButton(
        icon: const Icon(Icons.center_focus_strong),
        onPressed: () {
          _controller.forward().then((_) => _controller.reverse());
          widget.onPressed();
        },
      ),
    );
  }
  
  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }
}
```

---

### Example 3: Add Badge for Device Count

```dart
Stack(
  children: [
    IconButton(
      icon: const Icon(Icons.center_focus_strong),
      onPressed: _onAutoZoomPressed,
    ),
    if (selectedCount > 0)
      Positioned(
        right: 0,
        top: 0,
        child: Container(
          padding: const EdgeInsets.all(4),
          decoration: BoxDecoration(
            color: Colors.red,
            shape: BoxShape.circle,
          ),
          child: Text(
            '$selectedCount',
            style: const TextStyle(
              color: Colors.white,
              fontSize: 10,
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
      ),
  ],
)
```

---

## 📝 Summary

**✅ Implemented Features:**
- Auto-zoom button at top-right of map
- Single device: zoom to level 16
- Multiple devices: fit all in viewport with padding
- Fallback to "all devices" when no selection
- Defensive checks for map readiness and valid positions
- Comprehensive debug logging

**🎯 User Benefits:**
- One-tap navigation to devices
- Automatic optimal zoom level
- Clear visual feedback
- Always accessible from map view

**🔧 Developer Benefits:**
- Clean separation of concerns
- Reuses existing `safeZoomTo()` API
- Integrates with Riverpod state management
- Comprehensive error handling
- Easy to customize and extend

**📈 Next Steps:**
- [ ] Add haptic feedback on button press
- [ ] Add animation to camera movements
- [ ] Consider adding a "follow" mode toggle
- [ ] Add device count badge to button
