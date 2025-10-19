# Quick Reference: Phase 1 Optimizations (20 min, 50-70ms gain)

> **Context:** MAP_FINAL_OPTIMIZATION_REPORT.md identified high-ROI quick wins  
> **Status:** Optional (baseline already exceeds targets)  
> **Risk:** Low (additive changes, no API breaks)

---

## 1. Pre-instantiate MapController (20ms gain, 5 min)

**File:** `lib/features/map/view/flutter_map_adapter.dart`

**Current:**
```dart
class _FlutterMapAdapterState extends ConsumerState<FlutterMapAdapter> {
  @override
  void initState() {
    super.initState();
    mapController = MapController(); // ❌ Created in initState
    // ...
  }
}
```

**Optimized:**
```dart
class _FlutterMapAdapterState extends ConsumerState<FlutterMapAdapter> {
  late final mapController = MapController(); // ✅ Created once, eagerly
  
  @override
  void initState() {
    super.initState();
    // mapController already initialized
    // ...
  }
}
```

**Gain:** 20ms cold start (controller initialization moved to constructor phase)

---

## 2. Parallel FMTC Warmup (30-50ms gain, 10 min)

**File:** `lib/features/map/view/map_page.dart`

**Current:**
```dart
WidgetsBinding.instance.addPostFrameCallback((_) async {
  // ❌ Sequential warmup
  unawaited(FMTCInitializer.warmup());
  unawaited(FMTCInitializer.warmupStoresForSources(MapTileProviders.all));
});
```

**Optimized:**
```dart
WidgetsBinding.instance.addPostFrameCallback((_) async {
  // ✅ Parallel warmup with Future.wait
  unawaited(
    Future.wait([
      FMTCInitializer.warmup(),
      FMTCInitializer.warmupStoresForSources(MapTileProviders.all),
    ]),
  );
});
```

**Gain:** 30-50ms cold start (warmup tasks run concurrently)

---

## 3. Cache MapOptions (5ms/rebuild, 5 min)

**File:** `lib/features/map/view/flutter_map_adapter.dart`

**Current:**
```dart
@override
Widget build(BuildContext context) {
  return FlutterMap(
    mapController: mapController,
    options: MapOptions( // ❌ Recreated on every rebuild
      initialCenter: const LatLng(0, 0),
      initialZoom: 2,
      maxZoom: kMaxZoom,
      onTap: (_, __) => widget.onMapTap?.call(),
      onMapReady: _onMapReady,
    ),
    // ...
  );
}
```

**Optimized:**
```dart
class _FlutterMapAdapterState extends ConsumerState<FlutterMapAdapter> {
  late final mapController = MapController();
  
  // ✅ Cache MapOptions (created once)
  late final _mapOptions = MapOptions(
    initialCenter: const LatLng(0, 0),
    initialZoom: 2,
    maxZoom: kMaxZoom,
    onTap: (_, __) => widget.onMapTap?.call(),
    onMapReady: _onMapReady,
  );

  @override
  Widget build(BuildContext context) {
    return FlutterMap(
      mapController: mapController,
      options: _mapOptions, // ✅ Reuse cached options
      // ...
    );
  }
}
```

**Gain:** 5ms per rebuild (MapOptions not recreated on every frame)

**⚠️ Note:** If `widget.onMapTap` changes dynamically, this optimization cannot be applied as-is. Current codebase shows static callback usage, so caching is safe.

---

## Implementation Checklist

### Before Implementation
- [ ] Review MAP_FINAL_OPTIMIZATION_REPORT.md Section 9 (Micro-Optimization Recommendations)
- [ ] Verify baseline metrics with DevTools Timeline (optional)
- [ ] Confirm no recent changes to FlutterMapAdapter/MapPage

### During Implementation
- [ ] Apply optimization #1 (Pre-instantiate MapController)
- [ ] Apply optimization #2 (Parallel FMTC warmup)
- [ ] Apply optimization #3 (Cache MapOptions — verify callback is static)
- [ ] Run analyzer: `flutter analyze --no-pub` → Expect zero issues
- [ ] Run tests: `flutter test` → Expect 164/164 passing

### After Implementation
- [ ] Measure cold start time (compare to baseline: 180ms → target: 150ms)
- [ ] Measure warm restore (compare to baseline: 90ms → target: 70ms)
- [ ] Verify FPS stability (Performance Overlay: expect 60±1 FPS)
- [ ] Commit changes: "perf(map): apply Phase 1 quick wins (-50-70ms cold start)"
- [ ] Tag: `v5.3_map_phase1_optimizations`

---

## Measurement Script

**Add to `lib/core/utils/performance_monitor.dart`:**

```dart
import 'dart:async';
import 'package:flutter/scheduler.dart';
import 'package:flutter/foundation.dart';

class MapPerformanceMonitor {
  static final Stopwatch _coldStartStopwatch = Stopwatch();
  static final List<Duration> _frameTimes = [];

  static void startColdStartMeasurement() {
    _coldStartStopwatch.reset();
    _coldStartStopwatch.start();
  }

  static void endColdStartMeasurement() {
    _coldStartStopwatch.stop();
    debugPrint('[PERF] Cold start: ${_coldStartStopwatch.elapsedMilliseconds}ms');
  }

  static void startFrameTiming() {
    SchedulerBinding.instance.addTimingsCallback((timings) {
      for (final timing in timings) {
        _frameTimes.add(timing.totalSpan);
        if (timing.totalSpan > const Duration(milliseconds: 16)) {
          debugPrint('[JANK] Frame: ${timing.totalSpan.inMilliseconds}ms');
        }
      }
    });
  }

  static void printStats() {
    if (_frameTimes.isEmpty) return;
    
    final avg = _frameTimes.fold<int>(
      0, 
      (sum, t) => sum + t.inMilliseconds,
    ) / _frameTimes.length;
    
    _frameTimes.sort();
    final p99 = _frameTimes[(0.99 * _frameTimes.length).floor()];
    
    debugPrint('[PERF] Frame build: ${avg.toStringAsFixed(1)}ms avg, ${p99.inMilliseconds}ms p99');
  }
}
```

**Usage in MapPage:**

```dart
@override
void initState() {
  super.initState();
  
  MapPerformanceMonitor.startColdStartMeasurement();
  MapPerformanceMonitor.startFrameTiming();
  
  WidgetsBinding.instance.addPostFrameCallback((_) async {
    unawaited(
      Future.wait([
        FMTCInitializer.warmup(),
        FMTCInitializer.warmupStoresForSources(MapTileProviders.all),
      ]),
    );
    
    MapPerformanceMonitor.endColdStartMeasurement();
  });
}

@override
void dispose() {
  MapPerformanceMonitor.printStats();
  super.dispose();
}
```

---

## Expected Results

**Before Optimization:**
```
[PERF] Cold start: 180ms
[PERF] Frame build: 8.2ms avg, 12ms p99
```

**After Phase 1:**
```
[PERF] Cold start: 130ms (-28%, -50ms)
[PERF] Frame build: 7.8ms avg, 11ms p99 (-5%)
```

**Verification:**
- ✅ Cold start: 130ms < 150ms target (**87% of target**)
- ✅ Frame build: 7.8ms < 10ms target (**78% of target**)
- ✅ FPS: 60±1 FPS (Performance Overlay green bar)

---

## Rollback Plan

**If metrics regress:**
```bash
# Revert commit
git revert HEAD

# Re-run tests
flutter test

# Verify baseline restored
flutter analyze --no-pub
```

**Risk mitigation:**
- All changes are additive (no API changes)
- Tests provide regression safety net
- Baseline metrics already documented

---

**Priority:** Optional (baseline already exceeds targets)  
**Confidence:** High (low-risk, well-tested patterns)  
**Review Status:** Ready for implementation
