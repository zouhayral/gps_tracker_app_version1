# Fix: "Bad state: Tried to read the state of an uninitialized provider"

## Problem

The application was crashing with the error:
```
Bad state: Tried to read the state of an uninitialized provider
```

This occurred because providers were trying to read other providers during their initialization (build phase) before the ProviderScope had finished setting up all dependencies.

## Root Cause

Three components were attempting synchronous operations during initialization that triggered provider reads before the provider graph was fully initialized:

1. **WebSocketManagerEnhanced** - Called `_connect()` directly in `build()`
2. **WebSocketManager** - Called `_connect()` directly in `build()`  
3. **VehicleDataRepository** - Called `socketService.connect()` in constructor's `_init()`

### Problem Flow

```
ProviderScope initialization starts
  ↓
WebSocketManagerEnhanced.build() called
  ↓
_connect() called synchronously
  ↓
Tries to read traccarSocketServiceProvider
  ↓
TraccarSocketService tries to read authServiceProvider
  ↓
❌ CRASH: authServiceProvider not yet initialized
```

## Solution

Deferred all network connection operations to **after** the build phase completes using `Future.microtask()`.

### Key Changes

#### 1. WebSocketManagerEnhanced (lib/services/websocket_manager_enhanced.dart)

**Before:**
```dart
@override
WebSocketState build() {
  _socketService = ref.watch(traccarSocketServiceProvider);
  
  // Auto-connect on initialization
  _connect();  // ❌ Synchronous - can read uninitialized providers
  
  ref.onDispose(_dispose);
  ref.keepAlive();
  
  return const WebSocketState(status: WebSocketStatus.connecting);
}
```

**After:**
```dart
@override
WebSocketState build() {
  _socketService = ref.watch(traccarSocketServiceProvider);
  
  // Defer connection to after build completes to avoid reading uninitialized providers
  Future.microtask(() {
    if (!_disposed && !_intentionalDisconnect) {
      _connect();  // ✅ Deferred - safe to read any provider
    }
  });
  
  ref.onDispose(_dispose);
  ref.keepAlive();
  
  return const WebSocketState(status: WebSocketStatus.connecting);
}
```

#### 2. WebSocketManager (lib/services/websocket_manager.dart)

**Before:**
```dart
@override
WebSocketState build() {
  _controller = StreamController<Map<String, dynamic>>.broadcast();
  if (!testMode) {
    _connect();  // ❌ Synchronous
  }
  ref.onDispose(_dispose);
  ref.keepAlive();
  return const WebSocketState(status: WebSocketStatus.connecting);
}
```

**After:**
```dart
@override
WebSocketState build() {
  _controller = StreamController<Map<String, dynamic>>.broadcast();
  
  // Defer connection to after build completes to avoid reading uninitialized providers
  if (!testMode) {
    Future.microtask(() {
      if (!_disposed) {
        _connect();  // ✅ Deferred
      }
    });
  }
  
  ref.onDispose(_dispose);
  ref.keepAlive();
  return const WebSocketState(status: WebSocketStatus.connecting);
}
```

#### 3. VehicleDataRepository (lib/core/data/vehicle_data_repository.dart)

**Before:**
```dart
void _init() {
  _prewarmCache();
  
  // Subscribe to WebSocket updates (connect returns a stream)
  _socketSub = socketService.connect().listen(_handleSocketMessage);  // ❌ Synchronous
  
  _startFallbackPolling();
  
  if (kDebugMode) {
    debugPrint('[VehicleRepo] Initialized');
  }
}
```

**After:**
```dart
void _init() {
  // Defer WebSocket connection to avoid reading uninitialized providers
  // Pre-warm cache synchronously (safe - only reads SharedPreferences)
  _prewarmCache();

  // Defer WebSocket subscription to after provider initialization completes
  Future.microtask(() {
    // Subscribe to WebSocket updates (connect returns a stream)
    _socketSub = socketService.connect().listen(_handleSocketMessage);  // ✅ Deferred

    // Start REST fallback timer
    _startFallbackPolling();

    if (kDebugMode) {
      debugPrint('[VehicleRepo] Initialized with deferred WebSocket connection');
    }
  });
}
```

## Why Future.microtask()?

`Future.microtask()` schedules work to run **after** the current synchronous code completes but **before** any timers or events. This ensures:

1. ✅ All providers finish their `build()` phase
2. ✅ ProviderScope is fully initialized
3. ✅ All dependencies are available for reading
4. ⚡ Minimal delay (< 1ms typically)
5. 🔄 Maintains async flow without blocking

### Alternative Approaches (Not Used)

- `Future.delayed(Duration.zero)` - Works but less precise timing
- `SchedulerBinding.instance.addPostFrameCallback()` - Requires Flutter framework (too late)
- `Timer.run()` - Works but less idiomatic than microtask
- Lazy initialization on first read - More complex state management

## Impact

### User Experience
- **No visible change** - Connection still happens immediately after startup
- **Typical delay**: < 1-2ms (imperceptible)
- **Improved stability** - No more crashes on cold start

### Technical Benefits
- ✅ Eliminates provider initialization race conditions
- ✅ Maintains current architecture (no major refactoring)
- ✅ Safe to read any provider after microtask
- ✅ Works with hot reload/hot restart
- ✅ Compatible with widget tests (no pending timers)

## Testing

### Manual Testing
1. **Cold Start**: Kill app → Launch → Verify no crash
2. **Hot Reload**: Make code change → Hot reload → Verify connection restored
3. **Hot Restart**: Full restart → Verify clean initialization
4. **Background → Foreground**: Minimize → Restore → Verify reconnection

### Debug Verification
Look for these logs in order:
```
[VehicleRepo] ✅ Pre-warmed cache with X devices
[WS] Connecting... (attempt 1)
[SOCKET] ═══════════════════════════════════════
[SOCKET] Attempting WebSocket connection...
[SOCKET] ✅ WebSocket channel created
[VehicleRepo] Initialized with deferred WebSocket connection
[WS] Connected
```

### Error Scenarios (Should Not Occur)
- ❌ "Bad state: Tried to read the state of an uninitialized provider"
- ❌ "Looking up a deactivated widget's ancestor is unsafe"
- ❌ Null reference exceptions during startup

## Provider Dependency Graph

```
ProviderScope (root)
 │
 ├─ sharedPreferencesProvider (override in main.dart)
 │   └─ vehicleDataCacheProvider
 │       └─ vehicleDataRepositoryProvider
 │           ├─ deviceServiceProvider
 │           ├─ positionsServiceProvider
 │           └─ traccarSocketServiceProvider
 │               └─ authServiceProvider
 │
 ├─ webSocketManagerProvider
 │   └─ traccarSocketServiceProvider (same as above)
 │
 └─ deviceUpdateServiceProvider
     └─ positionsNotifierProvider
```

All providers must complete their `build()` phase before any can safely read others.

## Related Files

- `lib/services/websocket_manager_enhanced.dart` - Enhanced WebSocket manager
- `lib/services/websocket_manager.dart` - Basic WebSocket manager
- `lib/core/data/vehicle_data_repository.dart` - Vehicle data repository
- `lib/services/traccar_socket_service.dart` - Traccar WebSocket client
- `lib/services/auth_service.dart` - Authentication service
- `lib/main.dart` - App entry point with ProviderScope

## Future Improvements

1. **Explicit Initialization Flag**: Add `isInitialized` getter to repository
2. **Health Checks**: Verify all providers ready before connecting
3. **Graceful Degradation**: Show loading state if providers not ready
4. **Provider Override for Testing**: Make providers easily mockable

## Rollback Plan

If this fix causes issues, revert to synchronous initialization:
```dart
// In build() methods:
_connect();  // Remove Future.microtask wrapper

// In _init():
_socketSub = socketService.connect().listen(_handleSocketMessage);  // Remove Future.microtask wrapper
```

**Note**: This will restore the original crash, so only use as emergency rollback.

## References

- [Riverpod Provider Lifecycle](https://riverpod.dev/docs/concepts/provider_lifecycle)
- [Flutter Future.microtask](https://api.flutter.dev/flutter/dart-async/Future/Future.microtask.html)
- [Provider Initialization Best Practices](https://riverpod.dev/docs/concepts/reading#avoid-using-ref-read-inside-build)
