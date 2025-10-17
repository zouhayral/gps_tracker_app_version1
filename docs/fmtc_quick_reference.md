# FMTC Quick Reference

## What is FMTC?

**FleetMapTelemetryController** - An async-first controller for non-blocking device loading in the map page.

## Quick Enable

```dart
// In lib/features/map/view/map_page.dart
MapDebugFlags.useFMTCController = true;  // Line ~46
```

## Controller Methods

| Method | Purpose | When to Use |
|--------|---------|-------------|
| `build()` | Initial async load | Automatic on provider read |
| `refreshDevices()` | Manual refresh | Pull-to-refresh, retry button |
| `clear()` | Reset state | Logout, user switch |

## UI State Pattern

```dart
final fmState = ref.watch(fleetMapTelemetryControllerProvider);

return fmState.when(
  loading: () => CircularProgressIndicator(),
  error: (e, st) => ErrorWidget(error: e, onRetry: refresh),
  data: (fmtcState) => MapView(devices: fmtcState.devices),
);
```

## Debug Logs

All logs use `[FMTC]` prefix:

```bash
flutter run --debug
# Look for:
# [FMTC] Loading devices...
# [FMTC] Loaded 25 devices in 45ms
# [FMTC] Rendering with 25 devices...
```

## Testing

```bash
# Run all tests
flutter test

# Run specific test
flutter test test/map_page_test.dart

# Check analyzer
flutter analyze

# Format code
dart format .
```

## Troubleshooting

### Issue: "Unused import" warning for fleet_map_telemetry_controller

**Cause:** `MapDebugFlags.useFMTCController = false` (toggle disabled)

**Fix:** Set to `true` to use the controller

### Issue: Blank screen on map page

**Cause:** Error in async `build()` method

**Fix:** 
1. Check logs for `[FMTC] Error:` messages
2. Verify `devicesNotifierProvider` works
3. Try calling `refreshDevices()` from UI

### Issue: Stale data showing

**Cause:** Controller not refreshing on network reconnect

**Fix:** Call `refreshDevices()` on reconnection event

## Performance Monitoring

Key metrics to watch:

1. **Load Time**: Check `[FMTC] Loaded N devices in Xms` logs
2. **UI Jank**: No frame drops during device load (toggle on/off to compare)
3. **Memory**: Monitor `FMTCState` size with many devices

Target: < 100ms for 100 devices

## Best Practices

✅ **DO:**
- Enable toggle in staging first
- Monitor logs during testing
- Use `refreshDevices()` for manual updates
- Call `clear()` on logout

❌ **DON'T:**
- Enable in production without testing
- Modify `FMTCState` without updating provider
- Call `build()` manually (it's automatic)
- Ignore error logs

## Code Snippets

### Refresh on Button Press

```dart
ElevatedButton(
  onPressed: () {
    ref.read(fleetMapTelemetryControllerProvider.notifier)
       .refreshDevices();
  },
  child: Text('Refresh'),
)
```

### Clear on Logout

```dart
void logout() {
  ref.read(fleetMapTelemetryControllerProvider.notifier).clear();
  // ... other logout logic
}
```

### Watch for Changes

```dart
ref.listen(
  fleetMapTelemetryControllerProvider,
  (previous, next) {
    next.whenData((state) {
      print('Devices updated: ${state.devices.length}');
    });
  },
);
```

## Related Files

- Controller: `lib/features/map/controller/fleet_map_telemetry_controller.dart`
- MapPage: `lib/features/map/view/map_page.dart`
- Docs: `docs/fmtc_async_optimization.md`
