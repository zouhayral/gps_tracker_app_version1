# Phase 9 Step 2: Memory Lifecycle Quick Reference

**🎯 Goal:** Auto-cleanup idle streams, cap at 2000, monitor heap growth

---

## ✅ Implementation Checklist

- [x] Created `_StreamEntry` wrapper with listener count & last access tracking
- [x] Refactored `_deviceStreams` from `Map<int, StreamController>` to `Map<int, _StreamEntry>`
- [x] Added `_streamCleanupTimer` with 60s periodic sweep
- [x] Implemented `_cleanupIdleStreams()` (5-minute idle timeout)
- [x] Implemented `_capStreamsIfNeeded()` (LRU eviction at 2000 streams)
- [x] Created `MemoryWatchdog` utility for heap monitoring
- [x] Integrated MemoryWatchdog in `main.dart` (profile mode only)
- [x] Added `getStreamDiagnostics()` API to repository
- [x] Updated `positionStream()` to track listeners and refresh access
- [x] Updated `_broadcastPositionUpdate()` to refresh access time
- [x] Updated `dispose()` to cancel cleanup timer

---

## 🔧 Quick Diagnostic Commands

### 1. Check Stream Count (in code)
```dart
final repo = ref.read(vehicleDataRepositoryProvider);
final diag = repo.getStreamDiagnostics();
debugPrint('Total streams: ${diag['totalStreams']}');
debugPrint('Active streams: ${diag['activeStreams']}');
debugPrint('Idle streams: ${diag['idleStreams']}');
debugPrint('Total listeners: ${diag['totalListeners']}');
```

### 2. Force Memory Sample (in code)
```dart
import 'package:my_app_gps/core/utils/memory_watchdog.dart';
MemoryWatchdog.instance.forceSample();
```

### 3. Filter Logs (terminal)
```bash
# Stream lifecycle events
adb logcat | grep -E "📡|🧹|🔒"

# Memory monitoring
adb logcat | grep "\[MEM\]"

# Cleanup frequency
adb logcat | grep "🧹 Cleaned up"

# LRU eviction
adb logcat | grep "🔒 Evicted"
```

---

## 📊 Expected Log Output

### Stream Listener Tracking
```
[DEBUG] 📡 Stream listener added for device 42 (count: 1)
[DEBUG] 📡 Stream listener added for device 42 (count: 2)
[DEBUG] 📡 Stream listener removed for device 42 (count: 1)
[DEBUG] 📡 Stream listener removed for device 42 (count: 0)
```

### Position Broadcast
```
[DEBUG] 📡 Position broadcast to stream for device 42 (listeners: 2)
```

### Idle Cleanup (every 60s)
```
[DEBUG] 🧹 No idle streams to clean up (active: 150)
[DEBUG] 🧹 Cleaned up 10 idle streams (remaining: 140)
```

### LRU Eviction (when >2000 streams)
```
[DEBUG] 🔒 Evicted 50 streams (LRU cap: 2000)
```

### Memory Watchdog (every 10s in profile mode)
```
[MEM] Heap: 52 MB | Δ +2 MB | Total: +2 MB | Trend: STABLE ✅ | streams: 150 | listeners: 225
[MEM] Heap: 53 MB | Δ +1 MB | Total: +3 MB | Trend: STABLE ✅ | streams: 148 | listeners: 220
[MEM] ⚠️ Heap: 85 MB | Δ +32 MB | Total: +35 MB | Trend: RISING 📈 | streams: 2000 | listeners: 3000
```

---

## 🧪 Quick Validation (10 minutes)

### Setup
```bash
flutter run --profile
```

### Test 1: Idle Cleanup (6 minutes)
1. Open map page → Wait 1 minute → Navigate away
2. Wait 5 minutes (idle timeout)
3. Check logs: `🧹 Cleaned up N idle streams`
4. **Expected:** All streams closed after 5 min + 0 listeners

### Test 2: Listener Tracking (2 minutes)
1. Open map page
2. Tap 5 devices → Check logs: count increases
3. Close detail views → Check logs: count decreases
4. **Expected:** Accurate listener counts in logs

### Test 3: Memory Trend (10 minutes)
1. Navigate between pages every 2-3 minutes
2. Monitor [MEM] logs every 10 seconds
3. **Expected:** STABLE trend, <5 MB total growth

### Test 4: LRU Cap (2 minutes - requires 2000+ devices)
1. Open device details for 100+ devices rapidly
2. Check logs: `🔒 Evicted N streams` when approaching 2000
3. **Expected:** Stream count caps at 2000

---

## 🎯 Success Criteria

| Metric | Target | Pass/Fail |
|--------|--------|-----------|
| **Heap Growth** | <5 MB over 30 min | ⏳ Test |
| **Stream Cap** | ≤2000 streams | ⏳ Test |
| **Idle Cleanup** | 0 idle after 5 min | ⏳ Test |
| **Frame Times** | <16ms sustained | ⏳ Test |

---

## 🔥 Troubleshooting

### Problem: Streams not cleaning up
**Check:**
- Are listeners actually at 0? (check `listenerCount` in logs)
- Has 5 minutes passed since last access?
- Is cleanup timer running? (search logs for "Stream cleanup timer started")

**Fix:**
```dart
// Reduce idle timeout for testing
static const _kIdleTimeout = Duration(minutes: 1);
```

### Problem: LRU not evicting
**Check:**
- Is stream count > 2000? (check `getStreamDiagnostics()`)
- Are there idle streams to evict? (LRU only evicts idle)

**Fix:**
```dart
// Lower cap for testing
static const _kMaxStreams = 100;
```

### Problem: Memory still growing
**Check:**
- Is MemoryWatchdog running? (search logs for "[MEM]")
- Are other caches unbounded? (check `_latestPositions.length`)
- DevTools Memory tab → Check for leaks

**Fix:**
- Increase cleanup frequency: `_kCleanupInterval = Duration(seconds: 30)`
- Check for circular references preventing GC

### Problem: Frame drops during cleanup
**Check:**
- How many streams being closed at once? (check cleanup logs)
- Are cleanup operations blocking UI thread?

**Fix:**
```dart
// Limit cleanup batch size
final toRemove = idleStreams.take(50).toList(); // Max 50 per sweep
```

---

## 📁 Modified Files

### New Files
- `lib/core/utils/memory_watchdog.dart`
- `docs/PHASE9_STEP2_MEMORY_LIFECYCLE_VALIDATION.md`
- `docs/PHASE9_STEP2_QUICK_REFERENCE.md` (this file)

### Modified Files
- `lib/core/data/vehicle_data_repository.dart`
  - Added `_StreamEntry` class
  - Added cleanup timer and methods
  - Updated stream creation/disposal logic
- `lib/main.dart`
  - Added MemoryWatchdog initialization (profile mode)

---

## 📞 Next Steps

1. **Run `flutter analyze`** → Should pass with 0 errors
2. **Test in profile mode** → 10-15 minutes minimum
3. **Check [MEM] logs** → Verify STABLE trend
4. **Verify cleanup** → Wait 5+ minutes, check logs
5. **Commit changes** → Phase 9 Step 2 complete

---

**End of Quick Reference**
