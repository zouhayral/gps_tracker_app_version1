# Quick Test Guide - Repository Migration Validation

## 🚀 Running the App

```bash
# Make sure you're on the right branch
git status  # Should show: prep/objectbox5-ready

# Clean build (recommended after migration)
flutter clean
flutter pub get

# Run on device/emulator
flutter run

# Or run with performance overlay
flutter run --profile
```

---

## ✅ Quick Validation Checklist (5 minutes)

### 1. **Instant Startup Test**
- [ ] Launch app
- [ ] Markers appear immediately (from cache)
- [ ] Fresh data loads within 2 seconds

**Expected:** Instant marker rendering from cache

---

### 2. **Offline Mode Test**
- [ ] Enable airplane mode
- [ ] Force stop app
- [ ] Relaunch app
- [ ] Markers still appear (cached)

**Expected:** App works offline with cached data

---

### 3. **Refresh Test**
- [ ] Tap refresh button
- [ ] All markers update quickly
- [ ] No lag or freezing

**Expected:** Single batch update, <1 second

---

### 4. **Device Selection Test**
- [ ] Select a device from search
- [ ] Camera centers immediately
- [ ] Info panel shows correct data

**Expected:** <100ms response time

---

### 5. **WebSocket Streaming Test**
- [ ] Watch a moving vehicle
- [ ] Marker updates smoothly
- [ ] No UI stuttering

**Expected:** Smooth 300ms debounced updates

---

## 🐛 Known Issues to Check

### Issue: "Undefined name 'sharedPreferencesProvider'"

**Cause:** SharedPreferences provider not initialized in main.dart

**Fix:** Add to main.dart:

```dart
void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  
  // Initialize SharedPreferences
  final prefs = await SharedPreferences.getInstance();
  
  runApp(
    ProviderScope(
      overrides: [
        sharedPreferencesProvider.overrideWithValue(prefs),
      ],
      child: const MyApp(),
    ),
  );
}
```

---

### Issue: "Cache not loading instantly"

**Cause:** Cache might be empty on first run

**Test:** 
1. Run app once (populates cache)
2. Force stop app
3. Relaunch (should load from cache)

---

### Issue: "WebSocket not connecting"

**Check:**
- Network connection is active
- Traccar server is reachable
- Credentials are correct in auth service

**Debug:**
```dart
// Add to initState in map_page.dart
debugPrint('[MapPage] WebSocket status: ${socketService.isConnected}');
```

---

## 📊 Performance Monitoring

### Enable Debug Overlays

```dart
// In map_page.dart, set:
MapDebugFlags.showRebuildOverlay = true;

// In main.dart, add:
debugPrintRebuildDirtyWidgets = true;
```

---

### Check Cache Stats

```dart
// In Flutter DevTools console:
final repo = container.read(vehicleDataRepositoryProvider);
print(repo.cacheStats);

// Expected output:
// {hits: 25, misses: 5, hitRate: 0.83, size: 30}
```

---

### Monitor Rebuilds

```dart
// In Flutter DevTools console:
RebuildTracker.instance.start();

// After 30 seconds:
print(RebuildTracker.instance.getCount('MapPage'));
print(RebuildTracker.instance.getCount('FlutterMapAdapter'));

// Expected:
// MapPage: < 10 rebuilds
// FlutterMapAdapter: 0 rebuilds (should be static)
```

---

## 🔍 Debugging Tips

### 1. Check Repository Initialization

```dart
// Add to map_page.dart initState:
debugPrint('[MapPage] Repository initialized: ${deviceIds.length} devices');
```

**Expected log:**
```
[MapPage] Repository initialized: 12 devices
[VehicleRepo] Fetching 12 devices in parallel
[VehicleRepo] ✅ Fetched 12 positions
```

---

### 2. Verify Cache Hit/Miss

```dart
// Check logs for:
[VehicleCache] HIT device=1 (hits=5 misses=2)
[VehicleCache] MISS device=3 (hits=5 misses=3)
```

**Good:** 80%+ hit rate after first launch  
**Bad:** <50% hit rate indicates cache issues

---

### 3. Monitor WebSocket Updates

```dart
// Check logs for:
[VehicleRepo] WebSocket connected
[VehicleRepo] Processed 3 position updates
```

**Good:** Regular position updates every 30-60s  
**Bad:** No updates after 5 minutes

---

## 🎯 Success Criteria

| Test | Pass Criteria | Status |
|------|---------------|--------|
| **Cold Start** | Markers visible in < 500ms | ⬜ |
| **Cache Hit Rate** | > 80% after warm-up | ⬜ |
| **Frame Time** | < 16ms average | ⬜ |
| **API Calls** | < 10 per minute | ⬜ |
| **Rebuilds** | < 20 in 30 seconds | ⬜ |
| **Offline Mode** | Cached data loads | ⬜ |
| **WebSocket** | Updates within 2s | ⬜ |
| **Refresh** | Completes in < 1s | ⬜ |

---

## 📝 Reporting Results

After testing, update `MIGRATION_VALIDATION_REPORT.md` with:

1. **Actual metrics** in Section 5 benchmark table
2. **Test results** (PASS/FAIL) for each functional test
3. **Issues encountered** in Section 7
4. **Screenshots** if UI issues found

---

## 🚨 Rollback Instructions

If migration causes critical issues:

```bash
# Revert to legacy providers (temporary)
git stash
git checkout <previous-commit-hash>

# Or revert specific file:
git checkout HEAD~1 lib/features/map/view/map_page.dart
```

**Note:** Document reason for rollback in GitHub issue

---

## 🎉 Next Steps After Validation

1. ✅ Complete all functional tests
2. ✅ Collect and document metrics
3. ✅ Address any issues found
4. ✅ Update documentation
5. ✅ Merge to main branch
6. ✅ Deploy to production

**Questions?** Check `MIGRATION_VALIDATION_REPORT.md` or ask the team!
