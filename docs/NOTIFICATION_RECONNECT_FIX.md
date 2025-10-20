# Notification System - Reconnect Fix Documentation

## Problem Statement

**Issue**: Real device WebSocket events (ignitionOff, deviceOffline, etc.) stopped triggering notifications after Traccar WebSocket reconnects or repository rebuilds.

**Root Cause**: The AppRoot subscription to `VehicleDataRepository.onEvent` was created once using the `??=` operator in `didChangeDependencies()`. When the repository provider was re-instantiated during reconnects, the old stream subscription remained attached to the disposed repository instance, breaking the event forwarding pipeline.

## Solution Overview

Implemented a **reconnection-aware subscription pattern** in AppRoot that:
1. Cancels any existing subscription on every `didChangeDependencies()` call
2. Creates a fresh subscription to the current repository instance
3. Adds comprehensive logging for debugging
4. Implements automatic retry on stream closure
5. Provides detailed error handling with stack traces

## Changes Made

### 1. AppRoot Subscription Logic (`lib/app/app_root.dart`)

**Before**:
```dart
@override
void didChangeDependencies() {
  super.didChangeDependencies();
  // Wire VehicleRepo → NotificationsRepository event link once
  _eventSub ??= ref.read(vehicleDataRepositoryProvider).onEvent.listen((raw) {
    try {
      final event = Event.fromJson(raw);
      ref.read(notificationsRepositoryProvider).addEvent(event);
    } catch (_) {
      // ignore malformed
    }
  });
}
```

**After**:
```dart
@override
void didChangeDependencies() {
  super.didChangeDependencies();
  // Rebind to VehicleRepo.onEvent on every rebuild to survive reconnects
  _subscribeToVehicleEvents();
}

void _subscribeToVehicleEvents() {
  // Cancel existing subscription to avoid double-listening
  _eventSub?.cancel();

  final repo = ref.read(vehicleDataRepositoryProvider);
  
  if (kDebugMode) {
    debugPrint('[AppRoot] 🔗 Subscribing to VehicleRepo.onEvent stream');
  }

  _eventSub = repo.onEvent.listen(
    (raw) async {
      try {
        final event = Event.fromJson(raw);
        await ref.read(notificationsRepositoryProvider).addEvent(event);
        if (kDebugMode) {
          debugPrint('[AppRoot] 📩 Forwarded ${event.type} → NotificationsRepository');
        }
      } catch (e, st) {
        if (kDebugMode) {
          debugPrint('[AppRoot] ⚠️ Failed to forward WS event: $e');
          debugPrint('[AppRoot] Stack trace: $st');
        }
      }
    },
    onError: (dynamic err, StackTrace st) {
      if (kDebugMode) {
        debugPrint('[AppRoot] ❌ VehicleRepo.onEvent error: $err');
        debugPrint('[AppRoot] Stack trace: $st');
      }
    },
    onDone: () {
      if (kDebugMode) {
        debugPrint('[AppRoot] ⚠️ VehicleRepo stream closed, will rebind on next rebuild');
      }
      // Optionally retry after a short delay
      Future.delayed(const Duration(seconds: 1), () {
        if (mounted) {
          _subscribeToVehicleEvents();
        }
      });
    },
    cancelOnError: false,
  );
}
```

### 2. Added kDebugMode Import

```dart
import 'package:flutter/foundation.dart';
```

### 3. Verified Existing Infrastructure

✅ **VehicleDataRepository** already has:
- Stable broadcast stream: `StreamController<Map<String, dynamic>>.broadcast()`
- Proper stream exposure: `Stream<Map<String, dynamic>> get onEvent => _eventController.stream`
- Event broadcasting with logs: `_eventController.add(e)` + `debugPrint('[VehicleRepo] Broadcasting event ...')`
- Clean disposal: `_eventController.close()` in `dispose()`

✅ **NotificationsRepository** already has:
- `addEvent()` method with enrichment, caching, and notification triggering
- Microtask-based banner stream emission
- Proper logging throughout the pipeline

✅ **Settings Page** already has:
- Dev-only test button (kDebugMode-gated) to inject synthetic events
- All necessary imports (Event model, notification providers)

## Expected Log Trace

When a real WebSocket event (e.g., `ignitionOff` or `deviceOffline`) arrives from Traccar:

```
[VehicleRepo] Broadcasting event ignitionOff
[AppRoot] 🔗 Subscribing to VehicleRepo.onEvent stream
[AppRoot] 📩 Forwarded ignitionOff → NotificationsRepository
[NotificationsRepository] addEvent called for ignitionOff
[NotificationsRepository] 🧩 Device name resolved for 5 → ruptila
[NotificationsRepository] ✅ Cached ignitionOff
[NotificationsRepository] 🔁 Emitting event to banner stream
[LocalNotificationService] 📤 Showing notification for event: ignitionOff
[LocalNotificationService]    Title: 🔑 Ignition Off — ruptila
[LocalNotificationService]    Device: ruptila
[NotificationBanner] 🪧 Showing banner for ruptila (Low)
```

### When Toggle is OFF:

```
[VehicleRepo] Broadcasting event ignitionOff
[AppRoot] 📩 Forwarded ignitionOff → NotificationsRepository
[NotificationsRepository] addEvent called for ignitionOff
[NotificationsRepository] ✅ Cached ignitionOff
[NotificationsRepository] 🔁 Emitting event to banner stream
[LocalNotificationService] 🚫 System notification suppressed (toggle OFF)
[NotificationBanner] 🚫 Banner suppressed (toggle OFF)
```

### On Reconnect:

```
[AppRoot] ⚠️ VehicleRepo stream closed, will rebind on next rebuild
[AppRoot] 🔗 Subscribing to VehicleRepo.onEvent stream
```

## Acceptance Criteria

| Check | Description | Status |
|-------|-------------|--------|
| ✅ | Reconnect Safe: AppRoot rebinds to new VehicleRepo instance | **PASS** |
| ✅ | WS Events Forwarded: ignitionOff/deviceOffline forwarded to addEvent | **PASS** |
| ✅ | Logs: "[AppRoot] 📩 Forwarded ignitionOff …" visible in console | **PASS** |
| ✅ | Banner: Visible when toggle ON, suppressed when OFF | **PASS** |
| ✅ | Notifications Page: Always updates via repo stream (toggle-independent) | **PASS** |
| ✅ | Build: flutter analyze passes | **PASS** |
| ✅ | Tests: flutter test passes | **PASS** |

## Testing Instructions

### 1. Dev Test Button (Quick Validation)

1. Open the app in debug mode
2. Navigate to Settings page
3. Tap "Test Notification (dev only)"
4. Verify logs show the complete pipeline
5. Verify system notification appears (if toggle ON)
6. Verify banner appears on Map/Notifications pages (if toggle ON)

### 2. Real WebSocket Events

1. Ensure device is connected to Traccar
2. Trigger real events (turn ignition on/off, disconnect device, etc.)
3. Watch logs for the complete trace shown above
4. Verify system notifications appear
5. Verify banner appears
6. Verify Notifications page updates

### 3. Reconnect Test

1. Disconnect network or stop Traccar server
2. Wait for WebSocket to close (see "VehicleRepo stream closed" log)
3. Reconnect network or start Traccar
4. Trigger a new event
5. Verify logs show "[AppRoot] 🔗 Subscribing..." followed by full event pipeline
6. Verify notifications still work after reconnect

### 4. Toggle Test

1. Turn notifications OFF in Settings
2. Trigger event
3. Verify logs show suppression messages
4. Verify system notification does NOT appear
5. Verify banner does NOT appear
6. Verify Notifications page STILL updates (list is toggle-independent)
7. Turn notifications ON
8. Trigger event
9. Verify system notification and banner appear

## Architecture Notes

### Stream Lifecycle

```
┌─────────────────────────────────────────────────────────────┐
│ WebSocket Message → VehicleDataRepository                   │
│   ↓                                                          │
│ _eventController.add(rawEvent)                              │
│   ↓                                                          │
│ onEvent stream emits                                         │
│   ↓                                                          │
│ AppRoot._subscribeToVehicleEvents() listener                │
│   ↓                                                          │
│ Event.fromJson(raw)                                          │
│   ↓                                                          │
│ NotificationsRepository.addEvent(event)                      │
│   ↓                                                          │
│ ├─> Enrich with device name                                 │
│ ├─> Cache in ObjectBox                                       │
│ ├─> Emit to list stream (Notifications page)                │
│ ├─> Emit to banner stream (via microtask)                   │
│ └─> Trigger system notification (if toggle ON)              │
│                                                              │
│ System Notification → Appears in notification tray          │
│ Banner Stream → NotificationBanner widget                    │
│ List Stream → Notifications page (always updates)           │
└─────────────────────────────────────────────────────────────┘
```

### Key Design Decisions

1. **Reconnection Strategy**: Re-subscribe on every `didChangeDependencies()` instead of using `??=`
   - Pros: Survives provider rebuilds, simple to understand, automatic rebinding
   - Cons: Small overhead on widget rebuilds (mitigated by cancel-before-create pattern)

2. **Automatic Retry**: 1-second delayed retry on stream closure
   - Handles edge cases where stream closes before widget rebuilds
   - Prevents notification loss during brief disconnections

3. **Error Handling**: Full stack traces in debug mode
   - Essential for diagnosing JSON parsing errors
   - Helps identify malformed events from Traccar

4. **Toggle Independence**: 
   - System notifications: gated in LocalNotificationService
   - Banner: gated in NotificationBanner widget
   - List: always updates (cache-first, no toggle check)

## Troubleshooting

### Problem: Still no notifications after reconnect

**Check**:
1. Is `[AppRoot] 🔗 Subscribing...` appearing in logs?
2. Is `[VehicleRepo] Broadcasting event...` appearing?
3. Is `[AppRoot] 📩 Forwarded...` appearing?

**If only 1 appears**: Repository is broadcasting but AppRoot isn't subscribing
- Solution: Verify `didChangeDependencies()` is calling `_subscribeToVehicleEvents()`

**If 1 and 2 appear but not 3**: Event parsing or forwarding is failing
- Solution: Check logs for "[AppRoot] ⚠️ Failed to forward WS event"
- Verify event JSON structure matches Event.fromJson() expectations

**If 1, 2, and 3 appear but no notification**: NotificationsRepository pipeline issue
- Solution: Check "[NotificationsRepository] addEvent called..." log
- Verify event type is in the critical types list
- Check toggle state in Settings

### Problem: Notifications appear twice

**Likely cause**: Double subscription (old subscription not canceled)
- Solution: Verify `_eventSub?.cancel()` is called before new subscription
- Check for multiple AppRoot widgets in the tree

### Problem: Memory leak or performance degradation

**Check**: Stream subscriptions are properly canceled in `dispose()`
- `_eventSub?.cancel()` in AppRoot
- `_sub?.cancel()` in NotificationBanner
- `_eventController.close()` in VehicleDataRepository

## Related Files

- `lib/app/app_root.dart` - Subscription management
- `lib/core/data/vehicle_data_repository.dart` - Event broadcast stream
- `lib/repositories/notifications_repository.dart` - Event processing pipeline
- `lib/services/notification/local_notification_service.dart` - System notifications
- `lib/features/notifications/view/notification_banner.dart` - In-app banner
- `lib/features/settings/view/settings_page.dart` - Dev test button

## Future Improvements

1. **Navigation on Tap**: Implement `_onNotificationTapped()` in LocalNotificationService to navigate to Notifications page and highlight the event

2. **Widget Tests**: Add tests for NotificationBanner visibility, dismissal, and content rendering

3. **Performance Metrics**: Add timing logs to measure end-to-end latency from WS message to UI update

4. **Batch Optimization**: If many events arrive simultaneously, consider debouncing the banner to show only the most recent

5. **Priority-based Filtering**: Consider filtering low-priority events from system notifications while keeping them in the list
