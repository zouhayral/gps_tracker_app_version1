# Quick Fix Reference: Provider Initialization

## Problem
```
❌ Bad state: Tried to read the state of an uninitialized provider
```

## Solution Pattern

### ✅ CORRECT: Defer provider reads until after build

```dart
@override
State build() {
  // ✅ Safe: Watch dependencies
  final service = ref.watch(myServiceProvider);
  
  // ✅ Safe: Schedule async work AFTER build
  Future.microtask(() {
    final dependency = ref.read(otherProvider);  // Safe here
    service.initialize(dependency);
  });
  
  ref.onDispose(dispose);
  return initialState;
}
```

### ❌ WRONG: Synchronous provider reads in build

```dart
@override
State build() {
  // ❌ CRASH: Reading provider during build
  final dependency = ref.read(otherProvider);
  service.initialize(dependency);
  
  return initialState;
}
```

## Common Scenarios

### Scenario 1: Network Connection in Notifier

```dart
class MyNotifier extends Notifier<MyState> {
  @override
  MyState build() {
    // Get direct dependencies
    _service = ref.watch(serviceProvider);
    
    // Defer connection
    Future.microtask(() {
      if (!_disposed) {
        _service.connect();  // Safe: After build phase
      }
    });
    
    return MyState.initial();
  }
}
```

### Scenario 2: Repository Initialization

```dart
class MyRepository {
  MyRepository({required this.service}) {
    _init();
  }
  
  void _init() {
    // Synchronous setup (safe)
    _loadCache();
    
    // Defer async operations
    Future.microtask(() {
      _subscribeToUpdates();
      _startPolling();
    });
  }
}
```

### Scenario 3: Service with Dependencies

```dart
class MyService {
  Future<void> initialize() async {
    // Defer reading other providers
    await Future.microtask(() async {
      final config = _ref.read(configProvider);  // Safe
      await _setupWithConfig(config);
    });
  }
}
```

## Rules of Thumb

### DO ✅
- Use `ref.watch()` for dependencies in `build()`
- Defer `ref.read()` with `Future.microtask()`
- Schedule async work after build phase
- Check `_disposed` flag before deferred work
- Pre-warm synchronous caches in constructor

### DON'T ❌
- Call `ref.read()` directly in `build()` for unrelated providers
- Start network connections synchronously in `build()`
- Subscribe to streams during provider construction
- Assume all providers are ready during `build()`

## Debugging Tips

### Check Initialization Order
```dart
if (kDebugMode) {
  debugPrint('[MyProvider] build() called');
  Future.microtask(() {
    debugPrint('[MyProvider] deferred init starting');
  });
}
```

### Verify Provider Graph
1. List all `ref.watch()` calls
2. Trace dependency chains
3. Identify circular dependencies
4. Add delays for testing

### Test with Hot Reload
Hot reload can reveal initialization issues:
```bash
# Should not crash
1. Edit any file
2. Save (hot reload)
3. Verify no provider errors
```

## Migration Checklist

- [ ] Find all `Notifier.build()` methods
- [ ] Identify synchronous `ref.read()` calls
- [ ] Wrap async operations in `Future.microtask()`
- [ ] Test cold start (kill app → relaunch)
- [ ] Test hot reload (save file)
- [ ] Test hot restart (R in terminal)
- [ ] Verify no errors in console
- [ ] Check network connection timing

## Common Errors and Fixes

### Error: "Tried to read uninitialized provider"
```dart
// Before
@override
State build() {
  final dep = ref.read(depProvider);  // ❌
  return State();
}

// After
@override
State build() {
  Future.microtask(() {
    final dep = ref.read(depProvider);  // ✅
  });
  return State();
}
```

### Error: "Looking up deactivated widget"
```dart
// Before
Future<void> init() {
  _connect();  // ❌ Too early
}

// After
Future<void> init() {
  Future.microtask(_connect);  // ✅ Deferred
}
```

### Error: Widget tests fail with "pending timers"
```dart
// Use microtask, NOT Timer
Future.microtask(_init);  // ✅ Test-safe
Timer.run(_init);  // ❌ Fails in tests
```

## Performance Impact

| Approach | Delay | Test-Safe | Complexity |
|----------|-------|-----------|------------|
| Synchronous | 0ms | ❌ | Low |
| Future.microtask | <1ms | ✅ | Low |
| Future.delayed(Duration.zero) | 1-5ms | ✅ | Low |
| SchedulerBinding.addPostFrameCallback | 16ms | ⚠️ | Medium |
| Lazy initialization | Variable | ✅ | High |

**Recommended**: `Future.microtask()` - Best balance of speed, safety, and simplicity.

## Quick Test Script

```dart
// Add to main.dart for testing
void testProviderInitialization() {
  runApp(
    ProviderScope(
      observers: [
        ProviderLogger(), // Logs all provider events
      ],
      child: MyApp(),
    ),
  );
}

class ProviderLogger extends ProviderObserver {
  @override
  void didAddProvider(
    ProviderBase provider,
    Object? value,
    ProviderContainer container,
  ) {
    debugPrint('[Provider] Added: ${provider.name ?? provider.runtimeType}');
  }
}
```

## See Also

- [PROVIDER_INITIALIZATION_FIX.md](PROVIDER_INITIALIZATION_FIX.md) - Detailed explanation
- [Riverpod Documentation](https://riverpod.dev) - Official docs
- [provider_initialization_fix_test.dart](../test/provider_initialization_fix_test.dart) - Unit tests
