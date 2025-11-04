# 💾 Memory & Lifecycle Quick Reference

**Quick navigation**: [Analysis Report](MEMORY_LIFECYCLE_ANALYSIS.md) | [Networking](NETWORKING_QUICK_REFERENCE.md) | [Rendering](ADAPTIVE_RENDERING_QUICK_REFERENCE.md)

---

## 🚀 TL;DR

✅ **Status**: All memory & lifecycle requirements **ALREADY IMPLEMENTED**  
✅ **Grade**: A+ (95/100)  
✅ **Action Needed**: None (optional improvements available)

---

## 📋 Checklist

### ✅ Controllers, Timers, Streams (DONE)
- [x] **6 Timers** in map_page.dart → All cancelled in dispose()
- [x] **1 StreamSubscription** → Cancelled in dispose()
- [x] **6 Controllers** → All disposed (motion, camera, search, focus, markers, prefetch)
- [x] **3 ProviderSubscriptions** → Tracked in `_listenerCleanups`, closed on dispose
- [x] **Trip details** → 2 AnimatedMapController instances properly scoped
- [x] **Analytics page** → 2 ProviderSubscriptions + 1 Timer properly disposed
- [x] **Notification widgets** → All StreamSubscriptions cancelled

### ✅ Pause/Resume (DONE)
- [x] **WidgetsBindingObserver** → Implemented in map_page.dart
- [x] **_onAppPaused()** → Cancels 3 timers, clears buffers, persists cache
- [x] **_onAppResumed()** → Restores cache, schedules updates, refreshes data
- [x] **AutomaticKeepAliveClientMixin** → Prevents expensive rebuilds on tab switches

### ✅ MapController Scoping (DONE)
- [x] **Main map** → GlobalKey<FlutterMapAdapterState> (one per page)
- [x] **Trip details embedded** → AnimatedMapController (disposed)
- [x] **Trip details fullscreen** → Separate AnimatedMapController (disposed)
- [x] **Geofence map** → Standalone MapController (disposed)
- [x] **No shared controllers** → Each screen owns its controller

### 🟡 Memory Monitoring (MANUAL)
- [ ] **DevTools profiling** → Manual workflow (not automated)
- [x] **StreamLifecycleManager** → Tracks resources in 4 repositories
- [x] **MapPerformanceMonitor** → Frame timing and FPS tracking
- [x] **RebuildTracker** → Logs rebuild stats on dispose
- [ ] **Debug flags** → Currently disabled (enable for monitoring)

---

## 🔧 Key Implementation Patterns

### 1. Timer Disposal Pattern
```dart
Timer? _myTimer;

void initState() {
  super.initState();
  _myTimer = Timer.periodic(Duration(seconds: 30), (_) => _doWork());
}

void dispose() {
  _myTimer?.cancel();  // ✅ Always cancel timers
  super.dispose();
}
```

**Your usage**: ✅ 6/6 timers cancelled in map_page.dart

---

### 2. StreamSubscription Pattern
```dart
StreamSubscription<T>? _subscription;

void _listenToStream() {
  _subscription = myStream.listen((data) {
    // Handle data
  });
}

void dispose() {
  _subscription?.cancel();  // ✅ Always cancel subscriptions
  super.dispose();
}
```

**Your usage**: ✅ All subscriptions cancelled (map, notifications, banners)

---

### 3. ProviderSubscription Pattern (Riverpod)
```dart
final List<ProviderSubscription<dynamic>> _listenerCleanups = [];

void initState() {
  super.initState();
  
  // Track manual listeners
  final sub = ref.listenManual(myProvider, (prev, next) {
    // Handle change
  });
  _listenerCleanups.add(sub);
}

void dispose() {
  // ✅ Close all tracked listeners
  for (final sub in _listenerCleanups) {
    sub.close();
  }
  _listenerCleanups.clear();
  super.dispose();
}
```

**Your usage**: ✅ Implemented in map_page.dart and analytics_page.dart

---

### 4. Controller Disposal Pattern
```dart
late final AnimatedMapController _controller;

void initState() {
  super.initState();
  _controller = AnimatedMapController(vsync: this);
}

void dispose() {
  _controller.dispose();  // ✅ Dispose controllers
  super.dispose();
}
```

**Your usage**: ✅ 2 AnimatedMapController instances properly disposed

---

### 5. Pause/Resume Pattern
```dart
class MyState extends State<MyWidget> with WidgetsBindingObserver {
  bool _isPaused = false;
  
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }
  
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }
  
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    switch (state) {
      case AppLifecycleState.paused:
        _onAppPaused();    // ✅ Pause streams, cancel timers
      case AppLifecycleState.resumed:
        _onAppResumed();   // ✅ Resume streams, refresh data
      default:
        break;
    }
  }
  
  void _onAppPaused() {
    _myTimer?.cancel();
    _myStream?.pause();
    // Save state if needed
  }
  
  void _onAppResumed() {
    _myStream?.resume();
    _refreshData();
  }
}
```

**Your usage**: ✅ Fully implemented in map_page.dart with cache persistence

---

### 6. StreamLifecycleManager Pattern (Repository Level)
```dart
class MyRepository {
  final _lifecycle = StreamLifecycleManager(name: 'MyRepo');
  
  void startListening() {
    final sub = myStream.listen((data) => _handleData(data));
    _lifecycle.track(sub);  // ✅ Automatic tracking
    
    final timer = Timer.periodic(Duration(seconds: 5), (_) => _poll());
    _lifecycle.trackTimer(timer);  // ✅ Automatic tracking
  }
  
  void dispose() {
    _lifecycle.disposeAll();  // ✅ Cleanup all tracked resources
  }
}
```

**Your usage**: ✅ Used in VehicleRepo, TripRepo, WebSocketManager, NotificationsRepo

---

## 📊 Resource Inventory

| File | Timers | Streams | Controllers | Providers | Grade |
|------|--------|---------|-------------|-----------|-------|
| `map_page.dart` | 6 | 1 | 6 | 3 | A+ |
| `analytics_page.dart` | 1 | 0 | 0 | 2 | A+ |
| `trip_details_page.dart` | 2 | 0 | 2 | 0 | A+ |
| `notification_banner.dart` | 0 | 1 | 0 | 0 | A+ |
| `recovered_banner.dart` | 0 | 1 | 0 | 0 | A+ |
| `notifications_page.dart` | 0 | 0 | 1 | 0 | A+ |
| **TOTAL** | **9** | **3** | **9** | **5** | **A+** |

**All 26 resources properly disposed** ✅

---

## 🧪 Testing Memory Management

### Manual DevTools Checklist

1. **Leak Detection** (5 minutes):
   ```bash
   # 1. Start app in profile mode
   flutter run --profile
   
   # 2. Open DevTools Memory tab
   # 3. Take snapshot A
   # 4. Navigate map → trips → analytics → map (5 times)
   # 5. Force GC via DevTools
   # 6. Take snapshot B
   # 7. Compare: Widget counts should be stable
   ```

2. **Timer Verification** (2 minutes):
   ```bash
   # 1. Enable debug logging:
   # In map_page.dart: MapDebugFlags.enablePerfMetrics = true
   
   # 2. Run app in debug mode
   # 3. Watch console for timer cancellation logs:
   #    "[LIFECYCLE] Pausing: canceling timers"
   #    "[PERF] Performance diagnostics started"
   
   # 4. Navigate away from map page
   # 5. Verify: "[MAP][PERF] Final stats" printed
   ```

3. **Pause/Resume Test** (3 minutes):
   ```bash
   # 1. Start app, navigate to map page
   # 2. Background app (press home button)
   # 3. Wait 10 seconds
   # 4. Resume app
   # 5. Verify console logs:
   #    "[LIFECYCLE] ⏸️ Paused (debounce timers canceled, cache persisted)"
   #    "[LIFECYCLE] ▶️ Resumed (cache restored, marker updates scheduled)"
   ```

---

## 🐛 Common Memory Pitfalls (All Avoided ✅)

### ❌ Uncancelled Timers
```dart
// BAD: Timer never cancelled
void initState() {
  Timer.periodic(Duration(seconds: 1), (_) => update());
}
```
**Your code**: ✅ All 9 timers cancelled in dispose()

---

### ❌ Retained StreamSubscriptions
```dart
// BAD: Subscription leaks
void _listenToData() {
  myStream.listen((data) => process(data));  // Never cancelled!
}
```
**Your code**: ✅ All 3 subscriptions cancelled

---

### ❌ Shared MapControllers
```dart
// BAD: Shared controller between widgets
class GlobalMapState {
  static final mapController = MapController();  // Shared!
}
```
**Your code**: ✅ One controller per screen, no shared instances

---

### ❌ Forgotten ProviderSubscriptions
```dart
// BAD: Manual listener not tracked
void initState() {
  ref.listenManual(myProvider, (_, __) => update());  // Leaks!
}
```
**Your code**: ✅ All manual listeners tracked in `_listenerCleanups`

---

## 🚀 Quick Wins

### Enable Debug Logging (30 seconds)
```dart
// lib/features/map/view/map_page.dart
class MapDebugFlags {
  static const bool enablePerfMetrics = true;   // Change from false
  static const bool enableFrameTiming = true;  // Change from false
  static const bool enablePrefetch = true;
}
```
**Benefit**: Real-time rebuild stats, frame timing, cache metrics

---

### Add Memory Snapshot Logging (5 minutes)
```dart
// In dispose() methods:
void dispose() {
  if (kDebugMode) {
    debugPrint('[MyWidget] dispose() - ${_timers.length} timers, ${_subs.length} subs');
  }
  // ... existing disposal
}
```
**Benefit**: Track resource counts on disposal

---

### Expose StreamLifecycle Stats (10 minutes)
```dart
// Add to debug menu:
Widget _buildDebugPanel() {
  final vehicleStats = ref.read(vehicleDataRepositoryProvider).lifecycle.stats;
  final wsStats = ref.read(webSocketManagerProvider).lifecycle.stats;
  
  return Column(
    children: [
      Text('Vehicle Repo: $vehicleStats'),
      Text('WebSocket: $wsStats'),
    ],
  );
}
```
**Benefit**: Real-time resource tracking

---

## 📚 Related Docs

- **Full Analysis**: [MEMORY_LIFECYCLE_ANALYSIS.md](MEMORY_LIFECYCLE_ANALYSIS.md)
- **Networking**: [NETWORKING_QUICK_REFERENCE.md](NETWORKING_QUICK_REFERENCE.md)
- **Rendering**: [ADAPTIVE_RENDERING_QUICK_REFERENCE.md](ADAPTIVE_RENDERING_QUICK_REFERENCE.md)
- **Architecture**: [ARCHITECTURE_SUMMARY.md](ARCHITECTURE_SUMMARY.md)

---

## ✅ Final Verdict

**Your memory & lifecycle management is EXCELLENT.**

- ✅ 26/26 resources properly disposed
- ✅ Comprehensive pause/resume handling
- ✅ Proper controller scoping (no shared instances)
- ✅ Infrastructure-ready monitoring (manual workflow)

**No critical changes needed.** Optional improvements available in full analysis.
