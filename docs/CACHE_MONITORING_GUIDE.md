# Cache Monitoring Guide - Development Testing

**Date**: November 2, 2025  
**Status**: Debug Logging Enabled ✅

## Overview

Cache debug logging has been enabled for both `CachedTripsDao` and `CachedDevicesDao` to monitor query result caching effectiveness during development.

## Debug Logging Configuration

### Enabled Services

**1. CachedTripsDao** (`lib/core/data/services/cached_trips_dao.dart`):
```dart
final cachedTripsDaoProvider = FutureProvider<CachedTripsDao>((ref) async {
  final dao = await ref.watch(tripsDaoProvider.future);
  return CachedTripsDao(
    dao: dao,
    cacheService: CachedQueryService(
      ttlSeconds: 30,
      maxCacheSize: 100,
      enableDebugLogging: true, // ✅ ENABLED
    ),
  );
});
```

**2. CachedDevicesDao** (`lib/core/data/services/cached_devices_dao.dart`):
```dart
final cachedDevicesDaoProvider = FutureProvider<CachedDevicesDao>((ref) async {
  final dao = await ref.watch(devicesDaoProvider.future);
  return CachedDevicesDao(
    dao: dao,
    cacheService: CachedQueryService(
      ttlSeconds: 30,
      maxCacheSize: 100,
      enableDebugLogging: true, // ✅ ENABLED
    ),
  );
});
```

## Expected Log Output

### Console Logs (VS Code Debug Console / Android Studio)

**Cache Miss (First Query)**:
```
[CACHE] ❌ MISS: trip_device_123 (executing query)
[CACHE] 💾 STORED: trip_device_123 (5 results, TTL: 30s)
```

**Cache Hit (Subsequent Query within 30s)**:
```
[CACHE] ✅ HIT: trip_device_123 (5 results cached, age: 2.3s/30s)
```

**Cache Invalidation (After Write)**:
```
[CACHE] 🗑️ INVALIDATE: trip_device_123 (write operation)
[CACHE] 🧹 CLEARED: 3 entries matching pattern 'trip_device_*'
```

**Cache Expiration**:
```
[CACHE] ⏰ EXPIRED: trip_device_123 (age: 31.2s > 30s TTL)
[CACHE] ❌ MISS: trip_device_123 (executing query)
```

**Cache Statistics**:
```
[CACHE] 📊 Stats: hits=45, misses=5, hit_rate=90.0%, size=12/100
```

## Monitoring Checklist

### During App Usage

**✅ Test Scenario 1: Trip List Page**
1. Navigate to trip list page
2. Observe first load: **❌ MISS** (expected)
3. Scroll list (trigger re-queries)
4. Observe subsequent queries: **✅ HIT** (expected within 30s)
5. Wait 30+ seconds
6. Scroll again: **❌ MISS** (expected after TTL expiration)

**Expected Cache Hit Rate**: 80-90% for typical usage

**✅ Test Scenario 2: Device Status Updates**
1. View device list/map
2. Observe initial device fetch: **❌ MISS** (expected)
3. Notification system polls for updates
4. Observe repeated queries: **✅ HIT** (expected within 30s)
5. Check logs every 5 seconds for 1 minute

**Expected Cache Hit Rate**: 85-95% (stable device data)

**✅ Test Scenario 3: Cache Invalidation**
1. View trip list (cache populated)
2. Create/edit/delete a trip
3. Observe: **🗑️ INVALIDATE** + **🧹 CLEARED** (expected)
4. View trip list again
5. Observe: **❌ MISS** (expected - cache cleared)

**Expected Behavior**: Immediate cache invalidation on writes

**✅ Test Scenario 4: Analytics Dashboard**
1. Open analytics page with date range selector
2. Select a date range
3. Observe: **❌ MISS** for fetchAggregates() (expected)
4. Change date range
5. Observe: **❌ MISS** (each range unique)
6. Switch back to original range
7. Observe: **✅ HIT** (if within 30s TTL)

**Expected Cache Hit Rate**: 60-70% (varies by user behavior)

## Performance Validation

### Key Metrics to Watch

**1. Cache Hit Rate**
- **Target**: 80-90% overall
- **Check**: Look for ratio of ✅ HIT vs ❌ MISS in logs
- **Formula**: hits / (hits + misses) * 100

**2. Query Latency**
- **Cache Hit**: <1ms (near-instant from memory)
- **Cache Miss**: 5-20ms (database query)
- **Improvement**: ~95% faster for cache hits

**3. Database Load**
- **Before**: Every query hits database
- **After**: 80-90% served from cache
- **Reduction**: ~90% fewer database reads

**4. Memory Usage**
- **Cache Overhead**: +2-4 MB (100 entries max)
- **Per Entry**: ~20-50 KB (varies by result size)
- **Monitor**: Check that app doesn't exceed memory budget

### Validation Commands

**Check Cache Statistics Programmatically**:
```dart
// In any widget or service with access to the DAO
final tripsDao = await ref.read(cachedTripsDaoProvider.future);
final stats = tripsDao.getCacheStats();

debugPrint('Cache Hit Rate: ${stats['hitRatePercent']}%');
debugPrint('Total Hits: ${stats['hits']}');
debugPrint('Total Misses: ${stats['misses']}');
debugPrint('Cache Size: ${stats['size']} / ${stats['maxSize']}');
```

**Expected Output After 5 Minutes of Usage**:
```
Cache Hit Rate: 87.5%
Total Hits: 350
Total Misses: 50
Cache Size: 18 / 100
```

## Troubleshooting

### Issue 1: No Cache Logs Visible

**Symptoms**: No `[CACHE]` logs in console

**Solutions**:
1. Check debug console is showing Flutter logs
2. Verify app is running in debug mode (`flutter run`, not `flutter run --release`)
3. Restart app to reload cache service configuration
4. Check VS Code > Output panel > Select "Flutter (Run)"

### Issue 2: Cache Hit Rate Too Low (<50%)

**Symptoms**: Mostly ❌ MISS logs, few ✅ HIT logs

**Possible Causes**:
1. **TTL too short**: Queries re-execute before reuse
   - Solution: Increase `ttlSeconds` to 60 or 90
2. **Unique query patterns**: Each query has different parameters
   - Solution: This is expected for unique queries (e.g., different date ranges)
3. **Write operations**: Frequent writes invalidate cache
   - Solution: Normal behavior, monitor write frequency

### Issue 3: Cache Hit Rate Too High (>95%)

**Symptoms**: Almost all ✅ HIT logs, very few ❌ MISS

**Possible Causes**:
1. **Stale data**: Cache serving old results
   - Check: Verify data freshness in UI
   - Solution: Reduce `ttlSeconds` to 15 or 20
2. **Limited usage patterns**: User repeating same queries
   - Solution: Normal for focused testing, expand test scenarios

### Issue 4: Memory Usage Increasing

**Symptoms**: App memory growing over time

**Solutions**:
1. Check cache size: `stats['size']` should be ≤ 100
2. Verify LRU eviction working (oldest entries removed when full)
3. Reduce `maxCacheSize` to 50 if needed
4. Monitor for memory leaks (unrelated to cache)

## Configuration Tuning

### Adjust TTL (Cache Lifetime)

**Current**: 30 seconds (balanced for most use cases)

**Shorter TTL (10-15s)**: For frequently changing data
```dart
cacheService: CachedQueryService(
  ttlSeconds: 15, // More aggressive freshness
  maxCacheSize: 100,
  enableDebugLogging: true,
),
```

**Longer TTL (60-90s)**: For stable data
```dart
cacheService: CachedQueryService(
  ttlSeconds: 60, // Longer cache retention
  maxCacheSize: 100,
  enableDebugLogging: true,
),
```

### Adjust Cache Size

**Current**: 100 entries (suitable for most devices)

**Smaller Cache (50 entries)**: For memory-constrained devices
```dart
cacheService: CachedQueryService(
  ttlSeconds: 30,
  maxCacheSize: 50, // Reduced memory footprint
  enableDebugLogging: true,
),
```

**Larger Cache (200 entries)**: For high-memory devices
```dart
cacheService: CachedQueryService(
  ttlSeconds: 30,
  maxCacheSize: 200, // More cache capacity
  enableDebugLogging: true,
),
```

## Disabling Debug Logging (Production)

**Before Production Deployment**, disable debug logging to reduce console noise:

**1. Update CachedTripsDao Provider**:
```dart
final cachedTripsDaoProvider = FutureProvider<CachedTripsDao>((ref) async {
  final dao = await ref.watch(tripsDaoProvider.future);
  return CachedTripsDao(
    dao: dao,
    cacheService: CachedQueryService(
      ttlSeconds: 30,
      maxCacheSize: 100,
      enableDebugLogging: false, // ❌ DISABLED for production
    ),
  );
});
```

**2. Update CachedDevicesDao Provider**:
```dart
final cachedDevicesDaoProvider = FutureProvider<CachedDevicesDao>((ref) async {
  final dao = await ref.watch(devicesDaoProvider.future);
  return CachedDevicesDao(
    dao: dao,
    cacheService: CachedQueryService(
      ttlSeconds: 30,
      maxCacheSize: 100,
      enableDebugLogging: false, // ❌ DISABLED for production
    ),
  );
});
```

**Or Use Conditional Logging**:
```dart
import 'package:flutter/foundation.dart';

cacheService: CachedQueryService(
  ttlSeconds: 30,
  maxCacheSize: 100,
  enableDebugLogging: kDebugMode, // Auto-disable in release builds
),
```

## Success Criteria

### Development Testing (This Session)

✅ **Cache logging visible**: See `[CACHE]` logs in console  
✅ **Cache hits observed**: ✅ HIT logs appear after initial queries  
✅ **Cache invalidation works**: 🗑️ INVALIDATE logs after writes  
✅ **Cache hit rate**: 80-90% for typical usage patterns  
✅ **No performance regressions**: App remains responsive  
✅ **Memory stable**: No excessive memory growth  

### Production Validation (Next Week)

⏳ Cache hit rate >80% sustained  
⏳ Database query reduction >90%  
⏳ Response time <1ms for cache hits  
⏳ Memory overhead +2-4 MB (acceptable)  
⏳ No cache-related crashes  
⏳ User experience improved (smoother, faster)  

## Next Steps

### After Development Testing

1. **Analyze Results**:
   - Review cache hit rate across different scenarios
   - Identify patterns (which queries benefit most)
   - Validate memory overhead acceptable

2. **Tune Configuration** (if needed):
   - Adjust TTL based on data volatility
   - Adjust cache size based on memory constraints
   - Consider per-DAO configurations

3. **Disable Debug Logging**:
   - Set `enableDebugLogging: false` before production
   - Or use `kDebugMode` for automatic disabling

4. **Production Deployment**:
   - Monitor cache effectiveness via analytics
   - Track database query reduction
   - Validate user experience improvements

## Related Documentation

- [QUERY_RESULT_CACHING_COMPLETE.md](./QUERY_RESULT_CACHING_COMPLETE.md) - Implementation details
- [REPOSITORY_PROVIDERS_UPDATE_COMPLETE.md](./REPOSITORY_PROVIDERS_UPDATE_COMPLETE.md) - Integration summary
- [EXECUTIVE_SUMMARY_PRODUCTION_READY.md](./EXECUTIVE_SUMMARY_PRODUCTION_READY.md) - Overall status

---

**Status**: Debug Logging Enabled ✅  
**Ready For**: Development Testing  
**Action Required**: Use app and monitor console for `[CACHE]` logs
