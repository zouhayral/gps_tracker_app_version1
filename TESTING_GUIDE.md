# Quick Testing Guide - Marker Performance Optimization

## Enable Performance Overlay

**File**: `lib/features/map/view/map_page.dart`

Find line ~82 and change:
```dart
// BEFORE
MapDebugFlags.showMarkerPerformance = false;

// AFTER
MapDebugFlags.showMarkerPerformance = true;
```

## What to Look For

### 1. Performance Overlay (Top-Right Corner)
Green = Good | Orange = Warning

```
┌─────────────────────────┐
│ 📊 Marker Performance   │
│ Updates: 156            │
│ Avg Time: 8ms ✅        │ <- Should be <16ms (green)
│ Reuse: 87% ✅           │ <- Should be >70% (green)
│ Created: 24             │
│ Reused: 1,248           │
└─────────────────────────┘
```

### 2. Console Logs
Look for these patterns during live updates:

```
[MapPage] 📊 MarkerDiff(total=25, created=2, reused=23, removed=0, cached=25, efficiency=92.0%)
[MapPage] ⚡ Processing: 8ms
```

**Good Signs**:
- ✅ Efficiency >70%
- ✅ Processing <16ms
- ✅ Most updates show "reused" > "created"

**Bad Signs**:
- ❌ Efficiency <50% (too many creations)
- ❌ Processing >20ms (too slow)
- ❌ "created" count equals "total" (no reuse)

### 3. Icon Preloading (On Startup)
```
[MarkerIcons] ✅ Preloaded 5/5 icons in 68ms
```

**Or if assets missing**:
```
[MarkerIcons] ✗ Failed to load marker_online: Unable to load asset...
[MarkerIcons] Preloaded 0/5 icons in 42ms
```
*Note: Missing icons won't crash app, just logged*

## Quick Performance Test

### Test 1: Basic Operation (1-10 Devices)
1. Connect to live WebSocket feed
2. Wait for 30 seconds
3. Check overlay:
   - Avg Time should be <10ms (green)
   - Reuse should be >85% (green)

**Expected**: Most updates reuse existing markers

### Test 2: Device Selection
1. Click different devices rapidly (5-10 selections)
2. Check logs for `created=1, reused=X`
3. Only selected device marker should be recreated

**Expected**: 1 creation per selection, others reused

### Test 3: High Load (50-100 Devices)
1. Connect with large device count
2. Monitor for 5 minutes
3. Check:
   - Avg Time stays <16ms
   - Reuse stays >70%
   - FPS in DevTools >55

**Expected**: Performance stays consistent under load

### Test 4: Memory Stability
1. Open Flutter DevTools → Memory tab
2. Run app for 5 minutes with live updates
3. Watch memory graph

**Expected**: 
- No upward trend in memory usage
- Periodic GC cycles (normal)
- No marker object accumulation

## Performance Metrics Reference

| Metric | Target | Good | Warning | Bad |
|--------|--------|------|---------|-----|
| Avg Processing Time | <16ms | <10ms | 10-16ms | >16ms |
| Marker Reuse Rate | >70% | >85% | 70-85% | <70% |
| Efficiency Ratio | >70% | >85% | 70-85% | <70% |
| Map FPS | >55 fps | >58 fps | 55-58 fps | <55 fps |

## Programmatic Check

Add this to see performance targets validation:

```dart
// In MapPage after processing markers
if (MapDebugFlags.showMarkerPerformance) {
  final meetsTargets = MarkerPerformanceMonitor.instance.meetsPerformanceTargets();
  final stats = MarkerPerformanceMonitor.instance.getStats();
  
  debugPrint(meetsTargets 
    ? '✅ Performance targets met!' 
    : '⚠️ Avg: ${stats.avgProcessingTime}ms, Reuse: ${stats.avgReuseRate}%');
}
```

## Troubleshooting

### Overlay Not Showing
- Check `MapDebugFlags.showMarkerPerformance = true` (line 82)
- Hot restart app (hot reload may not update flag)
- Check that map page is actually visible

### Low Reuse Rate (<50%)
**Possible Causes**:
- Devices moving constantly (expected for moving vehicles)
- Position updates have high precision changes
- Check if lat/lon values change every update

**Solution**: This is normal for active tracking; focus on processing time instead

### High Processing Time (>20ms)
**Possible Causes**:
- Too many devices (>200)
- Complex marker rendering logic
- Background tasks blocking main thread

**Solution**: Profile with DevTools Performance tab to find bottleneck

### Missing Icon Errors
**Not Critical**: App continues without icons
**To Fix**: Add missing PNG files to `assets/icons/`:
- `online.png`
- `offline.png`
- `selected.png`
- `moving.png`
- `stopped.png`

## DevTools Integration

### Open DevTools
```bash
flutter run
# In another terminal:
flutter pub global activate devtools
flutter pub global run devtools
```

### Performance Tab
1. Click "Performance" tab
2. Click "Record" button
3. Let run for 30 seconds
4. Click "Stop"
5. Look for:
   - Frame rendering times (should be <16ms)
   - Any red bars (dropped frames)
   - Timeline gaps (UI thread blocking)

### Memory Tab
1. Click "Memory" tab
2. Click "Reset" to clear baseline
3. Let run for 5 minutes
4. Look for:
   - Steady memory line (good)
   - Upward trend (leak)
   - Large spikes during updates (excessive allocation)

## Success Criteria Checklist

- [ ] Overlay shows green indicators (time <16ms, reuse >70%)
- [ ] Console logs show high efficiency ratios (>80%)
- [ ] No red frames in DevTools Performance
- [ ] Memory graph stable over 5 minutes
- [ ] FPS counter shows >55 fps consistently
- [ ] Icon preloading completes without critical errors

## Quick Disable

To turn off performance overlay:
```dart
MapDebugFlags.showMarkerPerformance = false; // Line 82
```

Or comment out the overlay widget (line 640-644):
```dart
// if (MapDebugFlags.showMarkerPerformance)
//   Positioned(
//     top: 16, right: 16,
//     child: _MarkerPerformanceOverlay(),
//   ),
```

---

**Ready to Test!** Enable the overlay and connect to live data. 🚀
