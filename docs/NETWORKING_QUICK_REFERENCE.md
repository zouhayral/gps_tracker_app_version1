# 🌐 Networking Optimization - Quick Reference

> **Status**: ✅ All optimizations FULLY IMPLEMENTED  
> **Last Updated**: 2025-11-03

---

## 🔍 Quick Health Check

### Is My WebSocket Persistent?
```dart
// ✅ YES - Single instance via Riverpod
final webSocketManagerProvider = NotifierProvider<WebSocketManager, WebSocketState>(
  WebSocketManager.new,
);

// Usage in UI
final wsState = ref.watch(webSocketManagerProvider);
print('Status: ${wsState.status}'); // connecting, connected, disconnected, retrying
```

### Is Compression Enabled?
```dart
// ✅ YES - Automatic via Dio
// Check network logs:
dio.interceptors.add(LogInterceptor(
  requestHeader: true,  // Shows Accept-Encoding: gzip, deflate
  responseHeader: true, // Shows Content-Encoding: gzip
));
```

### Is Exponential Backoff Working?
```dart
// ✅ YES - Check retry delays in logs
// Look for: "Reconnecting in Xs (attempt Y)"
// Expected sequence: 1s → 2s → 4s → 8s → 16s → 32s → 60s
final stats = _backoff.getStats();
print('Current attempt: ${stats['currentAttempt']}');
print('Next delay: ${stats['nextDelaySeconds']}s');
```

### Is Offline Mode Working?
```dart
// ✅ YES - Test by:
// 1. Enable airplane mode
// 2. Open app - should load cached data instantly
// 3. Disable airplane mode
// 4. Check logs for: "🔄 Backfilling missed positions"

final positions = ref.watch(allPositionsProvider);
print('Positions available: ${positions.length}'); // Should always have data
```

---

## 📊 Key Metrics Dashboard

### WebSocket Health
```dart
import 'package:my_app_gps/services/websocket_manager.dart';

class NetworkMetricsWidget extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final wsState = ref.watch(webSocketManagerProvider);
    
    return Column(
      children: [
        Text('Status: ${wsState.status}'),
        Text('Retry count: ${wsState.retryCount}'),
        Text('Last event: ${wsState.lastEventAt}'),
        Text('Connected for: ${_getUptime(wsState.lastConnected)}'),
      ],
    );
  }
}
```

### Cache Performance
```dart
import 'package:my_app_gps/core/data/vehicle_data_cache.dart';

void printCacheStats() {
  final cache = ref.read(vehicleDataCacheProvider);
  
  print('Cache size: ${cache.getPositionCount()} positions');
  print('Devices cached: ${cache.getDeviceCount()}');
  print('Oldest position: ${cache.getOldestPosition()}');
  print('Newest position: ${cache.getNewestPosition()}');
}
```

---

## 🔧 Configuration Reference

### WebSocket Settings
```dart
// Location: lib/services/websocket_manager.dart
class WebSocketManager extends Notifier<WebSocketState> {
  final _backoff = BackoffManager(
    initialDelay: Duration(seconds: 1),  // First retry after 1s
    maxDelay: Duration(seconds: 60),     // Cap at 60s
    multiplier: 2.0,                     // Double each time
  );
  
  // Silent disconnect detection
  static const _heartbeatThreshold = Duration(seconds: 20);
  
  // Verbosity (for debugging)
  static bool verboseSocketLogs = false; // Set to true for detailed logs
}
```

### HTTP Settings
```dart
// Location: lib/services/auth_service.dart
final dio = Dio(BaseOptions(
  baseUrl: 'http://37.60.238.215:8082',
  connectTimeout: Duration(seconds: 30),  // Connection timeout
  receiveTimeout: Duration(seconds: 60),  // Response timeout
  sendTimeout: Duration(seconds: 15),     // Upload timeout
));

// Cache TTL
dio.interceptors.add(ForceCacheInterceptor(
  ttl: Duration(seconds: 30), // Cache GET requests for 30s
));
```

### REST Fallback
```dart
// Location: lib/core/data/services/vehicle_data_network_service.dart
void startFallbackPolling() {
  Timer.periodic(Duration(seconds: 20), (timer) {
    // Only polls when WebSocket is disconnected
    if (!isWebSocketConnected()) {
      fetchLatestPositions();
    }
  });
}
```

---

## 🐛 Troubleshooting Guide

### WebSocket Won't Connect

**Symptoms**: `status == WebSocketStatus.disconnected`, no reconnection attempts

**Checks**:
1. **Verify base URL**:
   ```dart
   final dio = ref.read(dioProvider);
   print('Base URL: ${dio.options.baseUrl}');
   ```

2. **Check authentication**:
   ```dart
   final auth = ref.read(authServiceProvider);
   print('Logged in: ${await auth.isLoggedIn()}');
   ```

3. **Enable verbose logs**:
   ```dart
   WebSocketManager.verboseSocketLogs = true;
   ```

4. **Check for dispose races**:
   ```dart
   // Look for: "[WebSocket] ⚠️ Connect called but already disposed"
   ```

### Backoff Too Slow

**Symptoms**: Takes too long to reconnect

**Solution**: Adjust backoff parameters
```dart
final _backoff = BackoffManager(
  initialDelay: Duration(milliseconds: 500),  // Faster initial retry
  maxDelay: Duration(seconds: 30),            // Lower cap
  multiplier: 1.5,                            // Gentler growth
);
```

### Cache Not Persisting

**Symptoms**: Data lost after app restart

**Checks**:
1. **Verify ObjectBox initialization**:
   ```dart
   final store = await openStore();
   print('Store path: ${store.directoryPath}');
   ```

2. **Check cache writes**:
   ```dart
   await cache.cachePosition(position);
   final cached = cache.getLatestPosition(deviceId);
   print('Cache working: ${cached != null}');
   ```

### High Battery Drain

**Symptoms**: >2% battery per hour

**Causes**:
1. **WebSocket not suspending** - Check lifecycle logs
2. **Excessive polling** - Ensure REST fallback only when disconnected
3. **Too frequent backoff** - Increase initial delay

**Fix**:
```dart
// Verify suspension on background
void didChangeAppLifecycleState(AppLifecycleState state) {
  if (state == AppLifecycleState.paused) {
    ref.read(webSocketManagerProvider.notifier).suspend();
    print('✅ WebSocket suspended for battery savings');
  }
}
```

---

## 📈 Performance Targets

### WebSocket
- ✅ **Connection persistence**: 99.5%+ uptime
- ✅ **Reconnection time**: <5s average
- ✅ **Message latency**: <100ms
- ✅ **Battery usage**: <1% per hour

### HTTP
- ✅ **Cache hit rate**: 70%+
- ✅ **Bandwidth savings**: 60%+ (compression + caching)
- ✅ **Response time**: <200ms (uncached), <10ms (cached)

### Offline Mode
- ✅ **App launch time**: <500ms
- ✅ **Cache availability**: 100%
- ✅ **Backfill speed**: >100 positions/s
- ✅ **Data freshness**: <5s after reconnect

---

## 🎯 Common Patterns

### Pattern 1: Watching WebSocket Status
```dart
class MyWidget extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final wsState = ref.watch(webSocketManagerProvider);
    
    return switch (wsState.status) {
      WebSocketStatus.connected => ConnectedIndicator(),
      WebSocketStatus.connecting => ConnectingSpinner(),
      WebSocketStatus.retrying => RetryingBanner(wsState.retryCount),
      WebSocketStatus.disconnected => OfflineWarning(),
    };
  }
}
```

### Pattern 2: Force Reconnect (e.g., after login)
```dart
Future<void> onLoginSuccess() async {
  // Force immediate reconnection with fresh credentials
  final wsManager = ref.read(webSocketManagerProvider.notifier);
  await wsManager.forceReconnect();
  
  print('WebSocket reconnected with new session');
}
```

### Pattern 3: Accessing Cached Data Offline
```dart
Widget _buildOfflineMap() {
  // This ALWAYS works, even offline
  final positions = ref.watch(allPositionsProvider);
  
  return FlutterMap(
    children: [
      MarkerLayer(
        markers: positions.map((pos) => Marker(
          point: LatLng(pos.latitude, pos.longitude),
          child: VehicleMarker(position: pos),
        )).toList(),
      ),
    ],
  );
}
```

### Pattern 4: Manual Backfill (e.g., pull-to-refresh)
```dart
Future<void> onRefresh() async {
  final repo = ref.read(vehicleDataRepositoryProvider);
  await repo.refreshAllData(); // Fetches latest + backfills gaps
}
```

---

## 📚 Related Documentation

- **Full Audit Report**: `NETWORKING_OPTIMIZATION_AUDIT.md`
- **WebSocket Architecture**: `lib/services/websocket_manager.dart` (comments)
- **Cache Design**: `lib/core/data/vehicle_data_repository.dart` (comments)
- **Backoff Algorithm**: `lib/core/utils/backoff_manager.dart` (comments)

---

## 🎓 Best Practices

### DO ✅
- Use `ref.watch(webSocketManagerProvider)` to observe connection status
- Call `suspend()` when app is backgrounded
- Let automatic backfill handle reconnection gaps
- Trust the cache for UI rendering

### DON'T ❌
- Don't create multiple WebSocket connections
- Don't poll REST when WebSocket is connected
- Don't clear cache on every app start
- Don't block UI waiting for network

---

**Need Help?** Check logs for `[WebSocket]`, `[Cache]`, or `[Backoff]` prefixes for detailed diagnostics.
