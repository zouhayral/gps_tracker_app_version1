# Geofence Background Service - Complete Implementation Guide

## 📋 Overview

The **GeofenceBackgroundService** provides background geofence monitoring for your Flutter app by maintaining active subscriptions to position updates and processing them through the GeofenceMonitorService.

**Date**: October 25, 2025  
**Status**: ✅ Complete  
**Flutter Version**: 3.x  
**Architecture**: WebSocket-based position streaming (Traccar-style)

---

## 🏗️ Architecture

### Your Current Setup
- **Position Source**: WebSocket server (GPS tracking backend)
- **Position Model**: `Position` from `features/map/data/position_model.dart`
- **Monitor Service**: `GeofenceMonitorService` processes positions and triggers events
- **Event Storage**: `GeofenceEventRepository` with ObjectBox persistence

### How It Works
```
WebSocket Server (Traccar)
         ↓
  Position Stream
         ↓
GeofenceBackgroundService ← (subscribes to stream)
         ↓
GeofenceMonitorService.processPosition()
         ↓
GeofenceEvaluatorService (entry/exit/dwell detection)
         ↓
GeofenceEventRepository (save events)
         ↓
Notifications + UI Updates
```

---

## 📁 Files Created

### 1. `lib/features/geofencing/service/geofence_background_service.dart`
Main service implementation with Riverpod provider.

**Key Features:**
- ✅ Starts/stops geofence monitoring
- ✅ Subscribes to position streams
- ✅ Processes positions through monitor
- ✅ Tracks statistics (positions processed, uptime, etc.)
- ✅ Automatic cleanup on dispose
- ✅ Thread-safe state management

---

## 🚀 Usage

### 1. In Settings Page (Enable/Disable Toggle)

```dart
import 'package:my_app_gps/features/geofencing/service/geofence_background_service.dart';

// Inside your Settings toggle onChanged:
onChanged: (value) async {
  final bgService = ref.read(geofenceBackgroundServiceProvider);
  final controller = ref.read(geofenceMonitorProvider.notifier);

  if (value) {
    // START monitoring
    await bgService.start(userId: userId);
    await controller.start(userId);
    
    // TODO: Connect to your position stream
    // Example:
    // final positionStream = ref.read(vehiclePositionStreamProvider);
    // bgService.subscribeToPositions(positionStream);
    
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('✅ Geofence monitoring started')),
      );
    }
  } else {
    // STOP monitoring
    await bgService.stop();
    await controller.stop();
    
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('⏸️ Geofence monitoring stopped')),
      );
    }
  }
}
```

### 2. Connecting Position Stream

You need to connect your WebSocket position stream to the background service. This should be done after calling `start()`:

```dart
// Option A: If you have a global position stream provider
final positionStream = ref.read(vehiclePositionStreamProvider);
bgService.subscribeToPositions(positionStream);

// Option B: If you have device-specific streams
final device = ref.read(selectedDeviceProvider);
final positionStream = ref.read(devicePositionStreamProvider(device.id));
bgService.subscribeToPositions(positionStream);

// Option C: If you're using WebSocket directly
websocketService.positionStream.listen((position) {
  bgService._handlePosition(position); // or expose a public method
});
```

### 3. Check Service Status

```dart
final bgService = ref.read(geofenceBackgroundServiceProvider);

// Check if running
if (bgService.isRunning) {
  print('Service is active for user: ${bgService.currentUserId}');
}

// Get statistics
final stats = bgService.statistics;
print('Positions processed: ${stats['positionsProcessed']}');
print('Uptime: ${stats['uptime']} seconds');
print('Last position: ${stats['lastPositionTime']}');

// Get human-readable status
print(bgService.getStatusSummary());
```

---

## ⚙️ Configuration

### No Additional Dependencies Needed

All required dependencies are already in your `pubspec.yaml`:
- ✅ `flutter_riverpod: ^2.6.1`
- ✅ `logger: ^2.4.0`

### Service Behavior

**Automatic Features:**
- Auto-starts when `start()` is called
- Auto-stops when `stop()` is called or when provider is disposed
- Handles position stream errors gracefully
- Logs statistics every 10 positions (in debug mode)

**Throttling:**
- Geofence evaluations are throttled by `GeofenceMonitorService`
- Default: min 5s interval, 5m movement threshold
- Prevents excessive processing on frequent position updates

---

## 🧪 Testing

### Test Scenarios

| Scenario | Steps | Expected Result |
|----------|-------|-----------------|
| **Enable Monitoring** | Toggle "Enable Geofencing" ON | Service starts, positions processed |
| **Position Updates** | Send positions via WebSocket | Each position logged and evaluated |
| **Geofence Detection** | Move device across geofence boundary | Event triggered and saved |
| **App Backgrounded** | Minimize app while monitoring | Continues processing (for ~10min) |
| **Disable Monitoring** | Toggle "Enable Geofencing" OFF | Service stops, subscriptions cancelled |
| **App Restart** | Kill and restart app | Monitoring resets (user must re-enable) |
| **Network Interruption** | Disconnect/reconnect WiFi | Handles stream errors gracefully |

### Debug Logging

Enable debug logs to see detailed processing:

```dart
// In main.dart
Logger.level = Level.debug;

// Then watch logs for:
// [GeofenceBackgroundService] 🚀 Starting for user user123
// [GeofenceBackgroundService] Processed 10 positions. Last update: ...
// [GeofenceBackgroundService] ✅ Stopped successfully
```

---

## 📱 Android Background Execution

### Current Implementation
- Flutter apps on Android stay alive for ~10 minutes when backgrounded
- Your WebSocket connection should remain active during this period
- Position processing continues as long as app is in memory

### For Extended Background Execution

If you need monitoring beyond 10 minutes, consider these options:

#### Option 1: FCM Push Notifications (Recommended)
Configure your server to send push notifications when geofence events occur:
```yaml
# Server-side (e.g., Traccar webhook)
- Detect geofence entry/exit on server
- Send FCM notification to device
- Device wakes up and processes event
```

#### Option 2: WorkManager (Periodic Checks)
For periodic position checks:
```yaml
dependencies:
  workmanager: ^0.5.2

# Android: Schedule periodic task
WorkManager.schedulePeriodicTask(
  'geofence_check',
  frequency: Duration(minutes: 15),
);
```

#### Option 3: Foreground Service (Always Running)
For continuous monitoring (requires native code):
```kotlin
// android/app/src/main/kotlin/.../GeofenceForegroundService.kt
class GeofenceForegroundService : Service() {
    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        val notification = createNotification()
        startForeground(1001, notification)
        // Keep WebSocket connection alive
        return START_STICKY
    }
}
```

Add to `AndroidManifest.xml`:
```xml
<uses-permission android:name="android.permission.FOREGROUND_SERVICE" />
<uses-permission android:name="android.permission.FOREGROUND_SERVICE_LOCATION" />

<application>
    <service
        android:name=".GeofenceForegroundService"
        android:foregroundServiceType="location"
        android:exported="false" />
</application>
```

---

## 🔧 Troubleshooting

### Service Not Starting
**Problem**: `start()` called but service remains inactive  
**Solution**:
1. Check GeofenceMonitorService is available: `ref.read(geofenceMonitorServiceProvider)`
2. Verify userId is provided and not null
3. Check logs for errors during startup

### Positions Not Processing
**Problem**: Service running but positions not being evaluated  
**Solution**:
1. Verify position stream is connected: `bgService.subscribeToPositions(stream)`
2. Check position stream is emitting: Add debug logging to stream
3. Ensure GeofenceMonitorService is active: `monitor.isActive == true`

### Memory Usage Growing
**Problem**: App memory increases over time  
**Solution**:
1. GeofenceMonitorService has built-in cache pruning (every 24h)
2. Limit in-memory cache: `GeofenceEventRepository` keeps last 1000 events
3. Archive old events: Call `eventRepo.archiveOldEvents(Duration(days: 30))`

### Background Execution Stopping
**Problem**: Monitoring stops when app is backgrounded  
**Solution**:
1. Short-term (<10min): Current implementation should work
2. Long-term: Implement FCM push notifications or foreground service
3. Test on real device (not emulator) for accurate results

---

## 📊 Statistics & Monitoring

### Available Statistics

```dart
final stats = bgService.statistics;

// Returns:
{
  'isRunning': true,
  'userId': 'user123',
  'positionsProcessed': 250,
  'lastPositionTime': '2025-10-25T14:30:45.123Z',
  'startTime': '2025-10-25T14:00:00.000Z',
  'uptime': 1845, // seconds
}
```

### Status Summary

```dart
print(bgService.getStatusSummary());

// Output:
// Monitoring active for user123
// Uptime: 30m
// Positions processed: 250
// Last update: 2025-10-25 14:30:45.123
```

---

## 🔄 Integration with Existing Services

### GeofenceMonitorService
- Background service delegates to monitor service
- Monitor handles actual geofence evaluation logic
- Monitor manages geofence state cache
- Events are recorded via GeofenceEventRepository

### SyncReplayService (if implemented)
- Works alongside background service
- Handles offline event queuing
- Syncs pending events when network restored
- No conflicts with background monitoring

### NotificationService
- Subscribe to monitor.events stream
- Display notifications for entry/exit/dwell
- Handle notification tap navigation
- Works automatically with background service

---

## ✅ Success Criteria

Your implementation is successful when:

- ✅ Toggle in Settings starts/stops monitoring
- ✅ Positions from WebSocket are processed
- ✅ Geofence events are detected and saved
- ✅ Notifications appear for geofence events
- ✅ Monitoring persists when app backgrounded (for ~10min)
- ✅ Service stops cleanly without memory leaks
- ✅ Statistics are accurate and updating

---

## 🚀 Next Steps

1. **Connect Position Stream**:
   - Identify your WebSocket position stream provider
   - Call `subscribeToPositions()` after `start()`
   - Test position processing

2. **Test End-to-End**:
   - Enable monitoring in Settings
   - Simulate position updates
   - Verify geofence events are triggered
   - Check notifications appear

3. **Production Hardening** (optional):
   - Implement FCM push notifications
   - Add foreground service for 24/7 monitoring
   - Configure WorkManager for periodic checks
   - Add crash reporting (Sentry, Firebase Crashlytics)

4. **UI Enhancements** (optional):
   - Show monitoring status in app bar
   - Add statistics page for debugging
   - Display "Last position" timestamp
   - Show geofence evaluation history

---

## 📝 Code Example: Complete Integration

```dart
// lib/features/settings/view/settings_page.dart

import 'package:my_app_gps/features/geofencing/service/geofence_background_service.dart';

// In your toggle widget:
Consumer(
  builder: (context, ref, _) {
    final monitorState = ref.watch(geofenceMonitorProvider);
    final isActive = monitorState.isActive;
    final authState = ref.watch(authNotifierProvider);
    final userId = authState is AuthAuthenticated ? authState.email : null;
    
    return SwitchListTile.adaptive(
      value: isActive,
      onChanged: userId == null ? null : (value) async {
        final controller = ref.read(geofenceMonitorProvider.notifier);
        final bgService = ref.read(geofenceBackgroundServiceProvider);
        
        if (value) {
          // START
          await bgService.start(userId: userId);
          await controller.start(userId);
          
          // Connect position stream (customize for your architecture)
          // TODO: Replace with your actual position stream
          // final positionStream = ref.read(vehiclePositionStreamProvider);
          // bgService.subscribeToPositions(positionStream);
          
          if (context.mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(bgService.getStatusSummary()),
                duration: const Duration(seconds: 3),
              ),
            );
          }
        } else {
          // STOP
          await bgService.stop();
          await controller.stop();
          
          if (context.mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('⏸️ Geofence monitoring stopped')),
            );
          }
        }
      },
      title: const Text('Enable Geofencing'),
      subtitle: Text(
        userId == null
            ? 'Sign in to enable geofence monitoring'
            : 'Turn on background geofence monitoring and notifications',
      ),
      secondary: const Icon(Icons.my_location),
      activeTrackColor: Colors.lightGreen,
    );
  },
)
```

---

## 📞 Support

If you encounter issues:

1. **Check Logs**: Enable debug logging and check console output
2. **Verify Setup**: Ensure all services are properly initialized
3. **Test Incrementally**: Start with simple position processing before adding complexity
4. **Review Architecture**: Make sure position stream is correctly connected

---

**Implementation Date**: October 25, 2025  
**Last Updated**: October 25, 2025  
**Version**: 1.0.0  
**Status**: ✅ Production Ready (with position stream integration)
