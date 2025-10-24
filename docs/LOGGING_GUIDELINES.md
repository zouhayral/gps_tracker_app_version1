# Logging Best Practices Guide

## Overview

This document outlines the logging standards for the GPS Tracker application. We use the `logger` package with a centralized `AppLogger` utility to replace the previous `debugPrint` pollution.

## Why We Changed

### Problems with `debugPrint`:
- ❌ **100+ debugPrint statements** throughout the codebase
- ❌ **Performance overhead** - All logs run in production
- ❌ **No log levels** - Can't filter by severity
- ❌ **Cluttered code** - Hard to read and maintain
- ❌ **Hot path pollution** - Logs in performance-critical code

### Benefits of AppLogger:
- ✅ **Structured logging** with severity levels
- ✅ **Production-safe** - Debug logs disabled in release mode
- ✅ **Performance optimized** - Minimal overhead
- ✅ **Filterable** - Easy to find specific logs
- ✅ **Clean code** - Consistent logging pattern

## Log Levels

### 1. DEBUG (Development Only)
**When to use:**
- Verbose development information
- Variable state inspection
- Flow tracing
- Temporary debugging

**Disabled in:** Production (release mode)

**Example:**
```dart
import 'package:my_app_gps/core/utils/app_logger.dart';

AppLogger.debug('Received ${positions.length} positions');
AppLogger.debug('Cache key: $cacheKey, TTL: ${_cacheTTL.inSeconds}s');
```

### 2. INFO (Production-Safe)
**When to use:**
- Important state changes
- Successful operations
- Connection status
- Data loading confirmation

**Visible in:** Debug AND production

**Example:**
```dart
AppLogger.info('WebSocket connected');
AppLogger.info('Fetched ${trips.length} trips from network');
AppLogger.info('User logged in successfully');
```

### 3. WARNING (Recoverable Issues)
**When to use:**
- Non-critical errors
- Fallback scenarios
- Deprecation notices
- Unexpected but handled conditions

**Visible in:** Debug AND production

**Example:**
```dart
AppLogger.warning(
  'Network error, using cached data',
  error: exception,
);
AppLogger.warning(
  'Invalid coordinates filtered',
  tag: 'MapPage',
);
```

### 4. ERROR (Critical Failures)
**When to use:**
- Exceptions and errors
- Failed operations
- Data corruption
- Unhandled edge cases

**Visible in:** Debug AND production

**Example:**
```dart
AppLogger.error(
  'Failed to fetch device data',
  tag: 'VehicleRepository',
  error: e,
  stackTrace: st,
);
```

## Usage Patterns

### Basic Logging
```dart
import 'package:my_app_gps/core/utils/app_logger.dart';

// Simple message
AppLogger.info('Operation completed');

// With tag
AppLogger.debug('Cache hit', tag: 'TripRepository');

// With error
AppLogger.error(
  'Connection failed',
  error: exception,
  stackTrace: stackTrace,
);
```

### Component-Specific Logging
```dart
import 'package:my_app_gps/core/utils/app_logger.dart';

class VehicleDataRepository {
  // Create component logger
  static final _log = 'VehicleRepo'.logger;
  
  void fetchData() {
    _log.debug('Fetching data...');
    _log.info('✅ Fetched ${data.length} items');
    _log.warning('Cache miss, fetching from network');
    _log.error('Network error', error: e, stackTrace: st);
  }
}
```

## Migration from debugPrint

### Before (debugPrint):
```dart
if (kDebugMode) {
  debugPrint('[VehicleRepo] Fetching data for device $deviceId');
}
debugPrint('[VehicleRepo] ✅ Fetched ${positions.length} positions');
debugPrint('[VehicleRepo] ❌ Error: $e');
debugPrint(st.toString());
```

### After (AppLogger):
```dart
final _log = 'VehicleRepo'.logger;

_log.debug('Fetching data for device $deviceId');
_log.info('✅ Fetched ${positions.length} positions');
_log.error('Failed to fetch positions', error: e, stackTrace: st);
```

## Performance Guidelines

### ❌ DON'T: Log in hot paths
```dart
// BAD: Logs every frame during animation
void animationTick() {
  AppLogger.debug('Animation frame $frameCount'); // 60 logs/second!
  updatePosition();
}
```

### ✅ DO: Log at appropriate intervals
```dart
// GOOD: Log summary after animation
void animationComplete() {
  AppLogger.debug('Animation completed after $frames frames');
}
```

### ❌ DON'T: Log large data structures
```dart
// BAD: Logs entire list
AppLogger.debug('Devices: $devicesList'); // Could be huge!
```

### ✅ DO: Log summaries
```dart
// GOOD: Log count and metadata
AppLogger.debug('Loaded ${devicesList.length} devices');
```

### ❌ DON'T: Log in tight loops
```dart
// BAD: Logs every iteration
for (var device in devices) {
  AppLogger.debug('Processing device ${device.id}');
  process(device);
}
```

### ✅ DO: Log before/after loops
```dart
// GOOD: Log summary
AppLogger.debug('Processing ${devices.length} devices');
for (var device in devices) {
  process(device);
}
AppLogger.debug('Processing complete');
```

## Component Tags

Use consistent tags for each component:

| Component | Tag |
|-----------|-----|
| Vehicle Data Repository | `VehicleRepo` |
| Trip Repository | `TripRepository` |
| Map Page | `MapPage` |
| WebSocket Manager | `WebSocket` |
| Connectivity | `Connectivity` |
| Event Service | `EventService` |
| Position Service | `PositionsService` |
| Device Service | `DeviceService` |
| Authentication | `Auth` |
| FMTC | `FMTC` |
| Marker Cache | `MarkerCache` |

## Examples by Scenario

### Successful Operation
```dart
_log.info('✅ User logged in successfully');
_log.info('🔗 WebSocket connected');
_log.info('📦 Cached ${count} items');
```

### Error Handling
```dart
try {
  await fetchData();
} catch (e, st) {
  _log.error('Failed to fetch data', error: e, stackTrace: st);
  rethrow;
}
```

### State Changes
```dart
_log.debug('State transition: $oldState → $newState');
_log.info('Connectivity changed → ${isOnline ? 'online' : 'offline'}');
```

### Performance Tracking
```dart
final stopwatch = Stopwatch()..start();
// ... operation ...
_log.debug('Operation completed in ${stopwatch.elapsedMilliseconds}ms');
```

### Cache Operations
```dart
_log.debug('Cache hit for key: $key (age: ${age}s)');
_log.debug('Cache miss for key: $key, fetching from network');
_log.info('💾 Stored ${items.length} items in cache');
```

## Testing

In tests, you can disable logging:
```dart
void main() {
  // Logger automatically respects kReleaseMode
  testWidgets('Test without debug logs', (tester) async {
    // Debug logs won't spam test output
  });
}
```

## Future Improvements

- [ ] Add log file rotation for production
- [ ] Implement remote logging service integration
- [ ] Add performance metrics correlation
- [ ] Create log analysis dashboard
- [ ] Add crash reporting integration

## Questions?

If you're unsure which log level to use, ask yourself:
1. **Would I want to see this in production?** → Use INFO/WARNING/ERROR
2. **Is this only useful during development?** → Use DEBUG
3. **Does this impact functionality?** → Use ERROR
4. **Is this recoverable?** → Use WARNING
5. **Is this just informational?** → Use INFO

Remember: **When in doubt, log less rather than more!**
