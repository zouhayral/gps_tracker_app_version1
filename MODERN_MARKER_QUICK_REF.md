# Modern Marker Design - Quick Reference

## Overview
Modern Material Design markers with state-based colors, icon indicators, and zoom-adaptive sizing.

## Visual Design

### Colors (State-Based)
- **Green (#00C853)**: Vehicle moving (speed > 1 km/h)
- **Amber (#FFA726)**: Engine on but idle
- **Light Blue (#42A5F5)**: Online but engine off
- **Grey (#9E9E9E)**: Offline

### Sizes
- **Full**: 280x90px - Shows name, status text, speed, icon
- **Compact**: 140x32px - Shows name, status dot, icon

### Zoom Behavior
- **Zoom ≤ 10**: Compact markers only
- **Zoom ≥ 13**: Full markers only  
- **Zoom 10-13**: Full if selected, compact otherwise

## Implementation

### Core Files
1. **`lib/core/map/modern_marker_painter.dart`** (268 lines)
   - `ModernMarkerPainter` - CustomPainter for marker rendering
   - `ModernMarkerWidget` - Widget wrapper
   - `MarkerSize` enum - full(280,90), compact(140,32)

2. **`lib/core/map/modern_marker_flutter_map.dart`** (190 lines)
   - `ModernMarkerFlutterMapWidget` - flutter_map integration
   - `ModernMarkerBitmapWidget` - Pre-rendered bitmap alternative
   - Zoom-adaptive sizing logic

3. **`lib/core/map/modern_marker_generator.dart`** (270 lines)
   - `ModernMarkerGenerator` - PNG image generation
   - `MarkerData` - Container for bytes + metadata
   - `MarkerState` - State helper (online/engineOn/moving)

4. **`lib/core/map/modern_marker_cache.dart`** (190 lines)
   - `ModernMarkerCache` - LRU memory cache
   - `CacheStats` - Hit rate, evictions, memory usage

### Usage

#### Basic Widget
```dart
ModernMarkerFlutterMapWidget(
  name: 'Vehicle 1',
  online: true,
  engineOn: true,
  moving: true,
  isSelected: false,
  zoomLevel: 12.0,
  speed: 65.5,
)
```

#### With flutter_map
```dart
Marker(
  point: LatLng(48.8566, 2.3522),
  width: 280,
  height: 90,
  child: ModernMarkerFlutterMapWidget(
    name: device['name'],
    online: device['status'] == 'online',
    engineOn: device['ignition'] == true,
    moving: position.speed > 1.0,
    isSelected: selectedId == device['id'],
    zoomLevel: mapController.camera.zoom,
    speed: position.speed,
  ),
)
```

#### Generate PNG Bytes
```dart
final bytes = await ModernMarkerGenerator.generateMarkerBytes(
  name: 'Vehicle 1',
  online: true,
  engineOn: true,
  moving: true,
  compact: false,
  speed: 60.0,
);
```

#### With Caching
```dart
final cache = ModernMarkerCache(maxCacheSize: 100);

// Warm up cache
await cache.warmUp(['Vehicle 1', 'Vehicle 2']);

// Get or generate
final bytes = await cache.getOrGenerate(
  name: 'Vehicle 1',
  online: true,
  engineOn: true,
  moving: true,
);

// Stats
print(cache.stats); // CacheStats(size: 42/100, hits: 120, misses: 8, hitRate: 93.8%)
```

## Marker State Logic

### Status Determination
```dart
// Online
final online = device['status']?.toString().toLowerCase() == 'online';

// Engine On
final engineOn = device['ignition'] == true || 
                 device['engineOn'] == true;

// Moving
final moving = position.speed > 1.0; // km/h threshold
```

### Color Priority (Highest to Lowest)
1. Offline → Grey (overrides all)
2. Moving → Green
3. Engine On → Amber
4. Idle → Light Blue

## Performance

### Rendering
- **CustomPainter**: Direct canvas drawing
- **Frame time**: < 5ms per marker
- **Batch rendering**: 50+ markers at 60fps

### Caching
- **LRU eviction**: When cache reaches max size
- **Memory efficient**: ~3-5KB per marker (PNG @2x)
- **Hit rate target**: > 90% after warmup

### Optimization Tips
```dart
// 1. Pre-warm cache at app startup
await cache.warmUp(allVehicleNames);

// 2. Use compact markers at lower zoom
final compact = zoom <= 10.0;

// 3. Clear cache when not on map page
cache.clear();

// 4. Monitor memory usage
if (cache.memoryUsageMB > 10.0) {
  cache.clear();
}
```

## Testing

### Visual States Test
```dart
// Test all state combinations
for (final online in [true, false]) {
  for (final engineOn in [true, false]) {
    for (final moving in [true, false]) {
      final marker = ModernMarkerWidget(
        name: 'Test Vehicle',
        online: online,
        engineOn: engineOn,
        moving: moving,
      );
      await tester.pumpWidget(marker);
      await tester.pumpAndSettle();
      await expectLater(
        find.byType(ModernMarkerWidget),
        matchesGoldenFile('marker_${online}_${engineOn}_${moving}.png'),
      );
    }
  }
}
```

### Performance Test
```dart
test('Marker generation < 5ms', () async {
  final stopwatch = Stopwatch()..start();
  
  await ModernMarkerGenerator.generateMarkerBytes(
    name: 'Vehicle 1',
    online: true,
    engineOn: true,
    moving: true,
  );
  
  stopwatch.stop();
  expect(stopwatch.elapsedMilliseconds, lessThan(5));
});
```

## Migration Guide

### Old MapMarkerWidget → New
```dart
// OLD (SVG-based)
MapMarkerWidget(
  deviceId: deviceId,
  isSelected: isSelected,
)

// NEW (Modern CustomPainter)
MapMarkerWidget(
  deviceId: deviceId,
  isSelected: isSelected,
  zoomLevel: zoom, // Added
)
```

### Old Marker Size
```dart
// OLD
Marker(
  width: 32,
  height: 32,
  ...
)

// NEW (Full markers)
Marker(
  width: 280,
  height: 90,
  ...
)

// NEW (Compact markers)
Marker(
  width: 140,
  height: 32,
  ...
)
```

## Troubleshooting

### Markers not appearing
- Check marker size: Full (280x90) or Compact (140x32)
- Verify zoom level is being passed correctly
- Ensure device has valid position data

### Performance issues
- Enable cache: `cache.warmUp(deviceNames)`
- Use compact markers at lower zoom
- Limit visible markers (clustering)

### Wrong colors showing
- Verify status field: 'online', 'offline', 'disconnected'
- Check ignition/engineOn attribute
- Confirm speed threshold (> 1.0 km/h)

## Future Enhancements

### Planned
- [ ] Heading arrow indicator
- [ ] Battery level display
- [ ] Signal strength indicator
- [ ] Customizable color schemes
- [ ] Animation on state change
- [ ] Cluster markers (show count)

### Under Consideration
- [ ] Mini map preview in marker
- [ ] Last update timestamp
- [ ] Alert badge overlay
- [ ] Custom icon support

## References
- Material Design 3: https://m3.material.io/
- flutter_map Markers: https://docs.fleaflet.dev/layers/marker-layer
- CustomPainter: https://api.flutter.dev/flutter/rendering/CustomPainter-class.html
