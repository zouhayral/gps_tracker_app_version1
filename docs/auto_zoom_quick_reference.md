# Auto-Zoom Button - Quick Reference

## 🎯 What It Does

**One-tap button** that automatically centers the map on your selected device(s).

- **Single device selected** → Zooms directly to that device (zoom level 16)
- **Multiple devices selected** → Fits all devices in viewport with padding
- **No selection** → Shows all devices (full fleet view)

---

## 📍 Where to Find It

**Location:** Top-right corner of the map

**Visual:** 
- White rounded button
- Blue `center_focus_strong` icon (⊕ with arrows)
- Drop shadow
- Tooltip: "Auto-zoom to selected"

---

## 🚀 How to Use

### Scenario 1: Focus on One Device
```
1. Tap a device in the list or on the map
2. Tap the auto-zoom button (top-right)
→ Camera centers on the device at street level
```

### Scenario 2: View Multiple Devices
```
1. Enable multi-selection mode
2. Select 2 or more devices
3. Tap the auto-zoom button
→ Camera zooms out to show all selected devices
```

### Scenario 3: View Entire Fleet
```
1. Deselect all devices (or select all)
2. Tap the auto-zoom button
→ Camera shows all devices with comfortable padding
```

---

## 🎬 Expected Behavior

| Selection | Zoom Behavior | Zoom Level | Padding |
|-----------|---------------|------------|---------|
| 1 device | Center on device | 16 | N/A |
| 2+ devices | Fit all in viewport | Auto (max 16) | 50px all sides |
| None / All | Fit fleet | Auto (max 16) | 50px all sides |

---

## 🔍 Visual Examples

### Single Device
```
Before:                  After:
┌─────────────────┐     ┌─────────────────┐
│                 │     │                 │
│   🚗            │     │                 │
│                 │ →   │       🚗        │
│                 │     │    (centered)   │
│                 │     │                 │
└─────────────────┘     └─────────────────┘
Zoom: 10               Zoom: 16
```

### Multiple Devices
```
Before:                  After:
┌─────────────────┐     ┌─────────────────┐
│ 🚗              │     │  🚗    🚗    🚗 │
│                 │     │                 │
│      🚗         │ →   │   🚗      🚗    │
│                 │     │ (all visible    │
│            🚗   │     │  with padding)  │
└─────────────────┘     └─────────────────┘
Zoom: 10               Zoom: 13 (auto-calculated)
```

---

## 🐛 Troubleshooting

| Issue | Solution |
|-------|----------|
| Button does nothing | Wait for map to load, check if device has GPS data |
| Zoom too close | Normal for single device (zoom 16) |
| Zoom too far | Normal for devices spread across large area |
| Device not visible | Device may not have valid position data |

---

## 🔧 Technical Details

**Implementation:**
- Located in `flutter_map_adapter.dart`
- Uses `safeZoomTo()` for single device
- Uses `fitCamera()` with bounds for multiple devices
- Integrates with Riverpod state management

**Performance:**
- O(1) for single device
- O(n) for multiple devices (n = device count)
- Typical execution: <150ms

**State Providers Used:**
- `selectedDeviceIdProvider` - Single selection
- `selectedDeviceIdsProvider` - Multi-selection
- `multiSelectionModeProvider` - Selection mode
- Marker positions from `widget.markersNotifier` or `widget.markers`

---

## 📊 Debug Logs

When you tap the button, watch the console for these logs:

**Single Device:**
```
[AUTO_ZOOM] 🎯 Zooming to 1 device(s)
[AUTO_ZOOM] 📍 Single device: centered at (33.5731, -7.5898) @ zoom 16
```

**Multiple Devices:**
```
[AUTO_ZOOM] 🎯 Zooming to 3 device(s)
[AUTO_ZOOM] 🗺️ Multiple devices: fitted 3 markers
[AUTO_ZOOM] 📐 Fitted bounds: (33.5000, -7.6000) to (33.6000, -7.5000)
```

**Error Cases:**
```
[AUTO_ZOOM] ⚠️ Map not ready yet
[AUTO_ZOOM] ⚠️ No devices to zoom to
[AUTO_ZOOM] ⚠️ No valid positions for selected devices
```

---

## ⚙️ Configuration

**Adjustable in Code:**

```dart
// Single device zoom level (default: 16)
safeZoomTo(target, 16.0);

// Multi-device padding (default: 50px)
padding: const EdgeInsets.all(50)

// Multi-device max zoom (default: 16)
maxZoom: 16.0

// Button position (default: top-right)
Positioned(
  top: 16,
  right: 16,
  child: ...
)
```

---

## ✅ Best Practices

**Do:**
- ✅ Use for quick navigation to devices
- ✅ Use after selecting devices from list
- ✅ Use to reset view after manual panning
- ✅ Use to get overview of fleet distribution

**Don't:**
- ❌ Tap rapidly (wait for camera to settle)
- ❌ Expect it to work on devices without GPS
- ❌ Expect it to override manual zoom immediately

---

## 🎨 Future Enhancements

Potential improvements (not yet implemented):

- [ ] **Haptic feedback** on tap
- [ ] **Animation** indicator during zoom
- [ ] **Badge** showing device count
- [ ] **Follow mode** toggle (auto-update as devices move)
- [ ] **Custom zoom presets** (near/medium/far)
- [ ] **Remember last zoom** preference

---

## 📞 Support

**If the button doesn't work:**

1. Check console logs for warnings
2. Verify devices have valid GPS positions
3. Wait for map to fully load
4. Ensure at least one device is available

**Common false alarms:**
- "No devices to zoom to" → Normal if no devices loaded yet
- "Map not ready yet" → Normal during initial page load
- "No valid positions" → Device hasn't reported GPS yet

---

## 📚 Related Documentation

- [WebSocket Manager Refactor](./websocket_refactor_summary.md)
- [Connectivity Banner](./websocket_log_reference.md)
- [Map Optimization](./map_page/map_optimization.md)

---

**Last Updated:** October 18, 2025  
**Feature Version:** 1.0  
**Status:** ✅ Implemented & Tested
