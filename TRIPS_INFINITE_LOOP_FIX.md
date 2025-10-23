# Trips Infinite Loop Fix

## Problem

The TripsPage was showing an infinite loading spinner and making hundreds of API calls per minute. Logs showed:
- `[TripProviders] 🗄️ Loaded 6 trips from cache` (repeated continuously)
- `[TripRepository] ✅ Parsed 7 trips` (repeated continuously)
- `fetchTrips()` being called in an endless loop
- UI stuck in loading state or flickering

## Root Causes

### 1. Auto-Invalidation Loop (First Issue)
The `tripsByDeviceProvider` (FutureProvider) had a **background refresh pattern** that caused an infinite loop:

1. Provider loads cached data and returns it
2. Kicks off background refresh with `Future(() async { ... })`
3. Background refresh calls `ref.invalidateSelf()`
4. This triggers provider rebuild
5. Rebuild calls `build()` again
6. Go to step 2 → **INFINITE LOOP**

### 2. Recreating TripQuery on Every Build (Second Issue)
Even after fixing auto-invalidation, a new `TripQuery` object was being created on every widget build:

```dart
// BAD: Creates new TripQuery on every build
final tripsAsync = ref.watch(
  tripsByDeviceProvider(
    TripQuery(deviceId: widget.deviceId, from: _from, to: _to), // NEW OBJECT EVERY TIME
  ),
);
```

Since Riverpod family providers use the parameter for caching, creating a new `TripQuery` instance on each build made Riverpod think it's a different query, triggering a new fetch.

## Solution

### 1. Changed Provider Architecture

**Before:**
```dart
final tripsByDeviceProvider =
    FutureProvider.autoDispose.family<List<Trip>, TripQuery>((ref, q) async {
  // ... cache logic ...
  
  // BAD: This causes infinite rebuilds
  unawaited(Future(() async {
    final fetched = await repo.fetchTrips(...);
    if (fetched.isNotEmpty) {
      ref.invalidateSelf(); // ❌ TRIGGERS REBUILD LOOP
    }
  }));
  
  return cached;
});
```

**After:**
```dart
class TripsByDeviceNotifier extends AutoDisposeFamilyAsyncNotifier<List<Trip>, TripQuery> {
  bool _isLoading = false;
  bool _hasLoaded = false;
  TripQuery? _lastQuery;

  @override
  Future<List<Trip>> build(TripQuery arg) async {
    // Guard: Prevent multiple simultaneous fetches
    if (_isLoading && _lastQuery == arg) {
      debugPrint('[TripProviders] ⏸️ Already loading, skipping');
      return state.valueOrNull ?? const <Trip>[];
    }

    // Guard: Skip refetch if already loaded this exact query
    if (_hasLoaded && _lastQuery == arg && state.hasValue) {
      debugPrint('[TripProviders] ✅ Data already loaded, skipping');
      return state.valueOrNull ?? const <Trip>[];
    }

    _isLoading = true;
    _lastQuery = arg;

    try {
      final repo = ref.read(tripRepositoryProvider);
      final cached = await repo.getCachedTrips(arg.deviceId, arg.from, arg.to);
      
      if (cached.isNotEmpty) {
        _hasLoaded = true;
        return cached; // ✅ Simply return, no auto-refresh
      }

      final fetched = await repo.fetchTrips(...);
      _hasLoaded = true;
      return fetched;
    } finally {
      _isLoading = false;
    }
  }

  Future<void> refresh() async {
    if (_isLoading) return; // Guard
    // ... manual refresh logic
  }
}
```

### 2. Fixed Widget State Management

**Before:**
```dart
@override
Widget build(BuildContext context) {
  // BAD: Creates new TripQuery every build
  final tripsAsync = ref.watch(
    tripsByDeviceProvider(
      TripQuery(deviceId: widget.deviceId, from: _from, to: _to),
    ),
  );
}
```

**After:**
```dart
class _TripsPageState extends ConsumerState<TripsPage> {
  late TripQuery _currentQuery; // ✅ Store query as state

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    _to = now;
    _from = now.subtract(const Duration(days: 1));
    
    // Create query ONCE in initState
    _currentQuery = TripQuery(
      deviceId: widget.deviceId,
      from: _from,
      to: _to,
    );
  }

  @override
  Widget build(BuildContext context) {
    // ✅ Use stored query - same object every build
    final tripsAsync = ref.watch(tripsByDeviceProvider(_currentQuery));
  }

  Future<void> _pickRange() async {
    // ... date picker ...
    if (picked != null) {
      setState(() {
        _from = ...;
        _to = ...;
        // ✅ Create new query only when dates change
        _currentQuery = TripQuery(
          deviceId: widget.deviceId,
          from: _from,
          to: _to,
        );
      });
    }
  }
}
```

### 3. Key Changes

1. **Removed auto-invalidation** - No more background refresh loop
2. **Added loading guards** - `_isLoading`, `_hasLoaded`, `_lastQuery` prevent duplicate fetches
3. **AsyncNotifier pattern** - Better state control than FutureProvider
4. **Stored TripQuery** - Reuse same object across builds to prevent provider recreation
5. **@immutable TripQuery** - Proper equality/hashCode for caching
6. **Manual refresh only** - Users control when to fetch via pull-to-refresh

### 4. UI Improvements

Added to `TripsPage`:

```dart
// Better error UI with Retry button
Widget _buildError(BuildContext context, Object error) {
  return ElevatedButton.icon(
    onPressed: () {
      ref.invalidate(tripsByDeviceProvider(_currentQuery)); // Use stored query
    },
    icon: Icon(Icons.refresh),
    label: Text('Retry'),
  );
}

// Pull-to-refresh in list
RefreshIndicator(
  onRefresh: () async {
    await ref.read(tripsByDeviceProvider(_currentQuery).notifier).refresh(); // Use stored query
  },
  child: ListView.builder(...),
)
```

## Results

✅ **No more infinite loop** - Provider builds only once per query  
✅ **No duplicate fetches** - Loading guards prevent simultaneous requests  
✅ **Fast loading** - Cached data shows instantly  
✅ **Manual refresh** - Pull down to update  
✅ **Better errors** - Clear messages with retry  
✅ **Efficient caching** - Same TripQuery reused across builds

## Testing

Run the app and navigate to Trips page:
1. Should load instantly if cache available
2. **No repeated network calls** in logs (KEY FIX)
3. Pull down to refresh works
4. Error states show retry button
5. Date picker changes trigger new fetch
6. Logs show "⏸️ Already loading" or "✅ Data already loaded" if trying to refetch same query

## Architecture Notes

- **Riverpod family providers** cache by parameter equality - must reuse same object
- **AsyncNotifier** provides better state management than FutureProvider
- **No auto-refresh** prevents infinite loops and unexpected network calls
- **Manual refresh** gives users control over when to fetch fresh data
- **Loading guards** prevent race conditions and duplicate requests
- **Cache-first** approach ensures fast UI with offline support
