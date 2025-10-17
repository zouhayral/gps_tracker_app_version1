# Satellite Map Layer Integration

This module provides satellite imagery alongside the default OpenStreetMap layer, with persistent user preference management.

## Features

✅ **Two Free Base Maps**
- OpenStreetMap (default street map)
- Esri World Imagery (satellite/aerial imagery)

✅ **Global State Management**
- Riverpod StateNotifierProvider for reactive updates
- SharedPreferences persistence (survives app restart)

✅ **Easy UI Integration**
- Pre-built toggle buttons and selector widgets
- Automatic map layer switching

## Quick Start

### 1. Basic Usage in Map Page

```dart
import 'package:my_app_gps/map/map_layer_toggle_button.dart';

// Add floating action button to switch layers
Stack(
  children: [
    FlutterMapAdapter(...),
    Positioned(
      top: 16,
      right: 16,
      child: MapLayerToggleButton(), // Extended FAB with icon + label
    ),
  ],
)
```

### 2. Compact Icon Button

```dart
import 'package:my_app_gps/map/map_layer_toggle_button.dart';

AppBar(
  actions: [
    MapLayerToggleIconButton(), // Just an icon button
  ],
)
```

### 3. Bottom Sheet Selector

```dart
import 'package:my_app_gps/map/map_layer_toggle_button.dart';

IconButton(
  icon: Icon(Icons.layers),
  onPressed: () => MapLayerSelector.show(context),
)
```

### 4. Programmatic Control

```dart
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:my_app_gps/map/map_tile_source_provider.dart';
import 'package:my_app_gps/map/map_tile_providers.dart';

class MyWidget extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final currentSource = ref.watch(mapTileSourceProvider);
    final notifier = ref.read(mapTileSourceProvider.notifier);

    // Get current source
    print('Current: ${currentSource.name}');

    // Switch to satellite
    notifier.setSource(MapTileProviders.esriSatellite);

    // Toggle between sources
    notifier.toggleSource();

    // Reset to default (OSM)
    notifier.resetToDefault();

    return ...;
  }
}
```

## Architecture

### Files Created

```
lib/map/
├── map_tile_providers.dart         # Tile source definitions
├── map_tile_source_provider.dart   # Riverpod state management
└── map_layer_toggle_button.dart    # UI widgets
```

### Data Model

```dart
class MapTileSource {
  final String id;              // Unique identifier
  final String name;            // Display name
  final String urlTemplate;     // Tile URL with {z}/{x}/{y}
  final String attribution;     // Copyright text
  final int maxZoom;            // Maximum zoom level
  final int minZoom;            // Minimum zoom level
}
```

### Available Providers

| Provider | ID | URL |
|----------|----|----|
| OpenStreetMap | `osm` | `https://tile.openstreetmap.org/{z}/{x}/{y}.png` |
| Esri Satellite | `esri_sat` | `https://server.arcgisonline.com/.../tile/{z}/{y}/{x}` |

> **Note:** Esri uses `{z}/{y}/{x}` order (not `{z}/{x}/{y}`)

## State Management

### Provider Lifecycle

1. **App Start**
   - Provider initializes with default source (OpenStreetMap)
   - Automatically loads saved preference from SharedPreferences
   - Updates state if a saved preference exists

2. **User Changes Source**
   - State updates immediately (reactive UI)
   - New preference saved to SharedPreferences
   - Map tiles refresh automatically

3. **App Restart**
   - Saved preference restored
   - User sees their last selected map layer

### Storage Key

- SharedPreferences key: `selected_map_source`
- Stores tile source ID (e.g., `"osm"` or `"esri_sat"`)

## UI Widgets

### MapLayerToggleButton (Extended FAB)

```dart
MapLayerToggleButton()
// Shows icon + current layer name
// Toggles between available sources on tap
```

### MapLayerToggleIconButton (Compact)

```dart
MapLayerToggleIconButton()
// Icon-only button
// Tooltip shows next layer name
```

### MapLayerSelector (Bottom Sheet)

```dart
MapLayerSelector.show(context)
// Full selector with all available sources
// Shows icons, names, and attributions
// Checkmark indicates current selection
```

## Integration with flutter_map

The `FlutterMapAdapter` automatically uses the selected tile source:

```dart
// In flutter_map_adapter.dart
Consumer(
  builder: (context, ref, _) {
    final tileSource = ref.watch(mapTileSourceProvider);
    return TileLayer(
      urlTemplate: tileSource.urlTemplate,
      maxZoom: tileSource.maxZoom.toDouble(),
      minZoom: tileSource.minZoom.toDouble(),
      // ... other properties
    );
  },
)
```

## Adding New Tile Sources

To add more tile providers:

1. **Define the source in `map_tile_providers.dart`:**

```dart
class MapTileProviders {
  static const myNewSource = MapTileSource(
    id: 'my_source',
    name: 'My Custom Map',
    urlTemplate: 'https://example.com/{z}/{x}/{y}.png',
    attribution: '© My Map Provider',
    maxZoom: 18,
  );

  static final List<MapTileSource> all = [
    openStreetMap,
    esriSatellite,
    myNewSource, // Add to list
  ];
}
```

2. **Update icon mapping in toggle widgets:**

```dart
// In map_layer_toggle_button.dart
IconData _getIconForSource(MapTileSource source) {
  switch (source.id) {
    case 'my_source':
      return Icons.terrain; // Choose appropriate icon
    case 'esri_sat':
      return Icons.satellite_alt;
    case 'osm':
    default:
      return Icons.map;
  }
}
```

## Tile Provider Attribution

Always display attribution as required by tile providers:

```dart
// Already implemented in flutter_map_adapter.dart
Positioned(
  right: 8,
  bottom: 8,
  child: Consumer(
    builder: (context, ref, _) {
      final source = ref.watch(mapTileSourceProvider);
      return Container(
        padding: EdgeInsets.all(4),
        color: Colors.black54,
        child: Text(
          source.attribution,
          style: TextStyle(color: Colors.white, fontSize: 11),
        ),
      );
    },
  ),
)
```

## Performance Notes

- **FMTC Compatibility:** Tile caching works with all sources
- **Network Usage:** Satellite tiles are typically larger than street maps
- **Switching Cost:** Minimal - only TileLayer rebuilds, not entire map
- **State Updates:** Instant UI response via Riverpod reactivity

## Testing

Run tests to verify tile providers:

```bash
flutter test test/map_tile_providers_test.dart
```

## Legal & Attribution

### OpenStreetMap
- License: Open Database License (ODbL)
- Attribution: `© OpenStreetMap contributors`
- [Terms of Use](https://www.openstreetmap.org/copyright)

### Esri World Imagery
- Free for non-commercial use
- Attribution: `© Esri – Maxar – Earthstar Geographics`
- [Terms of Use](https://www.esri.com/en-us/legal/terms/full-master-agreement)

> ⚠️ **Important:** Always include proper attribution in your UI

## Troubleshooting

### Tiles Not Loading
- Check network connectivity
- Verify FMTC is properly initialized
- Ensure tile URL template is correct

### Preference Not Persisting
- Verify SharedPreferences is properly initialized
- Check for permission issues on device

### Map Shows Wrong Layer
- Clear app data and restart
- Check if saved preference ID matches available sources

## Future Enhancements

Potential additions:
- [ ] Hybrid mode (satellite + street labels overlay)
- [ ] Terrain/topographic maps
- [ ] Traffic layer
- [ ] Custom tile server support
- [ ] Offline map download management
