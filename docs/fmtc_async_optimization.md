# FleetMapTelemetryController (FMTC) - Async Optimization

## Overview

Implemented an async-first controller using Riverpod's `AsyncNotifier` pattern to eliminate UI blocking during device loading on the map page. The controller orchestrates device loading and telemetry fetching with proper loading/error/data state handling.

## Architecture

### Controller: `FleetMapTelemetryController`

**Location:** `lib/features/map/controller/fleet_map_telemetry_controller.dart`

**Key Features:**
- Extends `AsyncNotifier<FMTCState>` for automatic loading/error state management
- Async `build()` method for non-blocking initialization
- `refreshDevices()` for manual refresh with error handling via `AsyncValue.guard`
- `clear()` for logout/user switch scenarios
- Debug logging with `[FMTC]` prefix throughout

### State Model: `FMTCState`

```dart
class FMTCState {
  final List<Map<String, dynamic>> devices;
  final DateTime lastUpdated;
}
```

Holds the list of devices and timestamp for cache validation.

### Provider

```dart
final fleetMapTelemetryControllerProvider = 
    AsyncNotifierProvider<FleetMapTelemetryController, FMTCState>(() {
  return FleetMapTelemetryController();
});
```

Exposes the controller to UI components.

## UI Integration

### MapPage Integration

**Method:** `_buildMapContentWithFMTC()` in `lib/features/map/view/map_page.dart`

Uses the `.when()` pattern for clean state handling:

1. **Loading State**: Shows centered spinner with "Loading fleet data..." message
2. **Error State**: Displays error message with retry button that calls `refreshDevices()`
3. **Data State**: Renders map with markers using existing marker processing logic

### Toggle-Based Activation

Controlled via `MapDebugFlags.useFMTCController` (defaults to `false`):

```dart
// In _buildMapContent()
if (MapDebugFlags.useFMTCController) {
  return _buildMapContentWithFMTC();
}
return devicesAsync.when(...); // Existing path
```

This allows safe A/B testing without breaking production code.

## Testing Results

✅ **All Tests Pass** (51 tests)
✅ **Analyzer Clean** (only lint warnings, no compile errors)
✅ **Formatted** (172 files, 4 changed)

## Performance Characteristics

- **Non-blocking**: Device loading happens asynchronously in `build()`
- **Reactive**: UI automatically updates when state changes
- **Error Resilient**: `AsyncValue.guard` prevents uncaught exceptions
- **Cancellable**: Async operations can be cancelled on dispose

## Debug Logging

All operations log with `[FMTC]` prefix:

```
[FMTC] Loading devices...
[FMTC] Loaded 25 devices in 45ms
[FMTC] Triggering position fetch for 25 devices
[FMTC] Rendering with 25 devices (updated: 2025-10-17T13:36:01.209399)
[FMTC] Error in UI: DioException [bad response]...
```

## Usage Instructions

### Enable Async Loading

1. Set `MapDebugFlags.useFMTCController = true` in `map_page.dart`
2. Reload the app
3. Observe non-blocking device load with spinner

### Manual Refresh

Call from UI:
```dart
ref.read(fleetMapTelemetryControllerProvider.notifier).refreshDevices();
```

### Logout/User Switch

Call to clear state:
```dart
ref.read(fleetMapTelemetryControllerProvider.notifier).clear();
```

## Future Enhancements

1. **Full UI Overlay**: Add search bar, bottom panel, and other controls to `_buildMapContentWithFMTC()`
2. **Telemetry Streaming**: Extend controller to handle WebSocket telemetry updates
3. **Performance Monitoring**: Add timing metrics for device load and render
4. **Error Retry Logic**: Implement exponential backoff for failed loads
5. **Progressive Loading**: Show partial results while loading continues

## Migration Path

1. Test with toggle enabled in staging environment
2. Monitor for performance improvements (no UI jank)
3. Gradually rollout to production users
4. Remove toggle and old synchronous path once stable

## Files Modified

- `lib/features/map/controller/fleet_map_telemetry_controller.dart` (NEW)
- `lib/features/map/view/map_page.dart` (MODIFIED - added toggle and async method)

## Related Documentation

- [Riverpod AsyncNotifier Guide](https://riverpod.dev/docs/concepts/reading#asyncnotifier)
- [Flutter Async Best Practices](https://dart.dev/codelabs/async-await)
- `docs/map_page/map_optimization.md`
- `docs/optimizition/performance_considerations.md`
