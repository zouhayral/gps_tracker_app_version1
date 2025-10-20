# 🧪 Notifications Feature Testing Guide

## Quick Start

```bash
# Launch the app
flutter run

# Or for detailed logs
flutter run --verbose
```

---

## 📋 Test Scenarios

### ✅ Scenario 1: Bottom Navigation Badge

**Steps:**
1. Launch app (should open on Map page)
2. Look at bottom navigation bar
3. Find "Alerts" tab (3rd icon)

**Expected Results:**
- ✅ Badge shows unread count if events exist
- ✅ Badge displays "99+" if count > 99
- ✅ Badge hidden if count is 0
- ✅ Badge updates automatically when events marked as read

**Visual Check:**
```
┌─────────────────────────┐
│  Map  │ Trips │ 🔔 (3) │ Settings │
└─────────────────────────┘
           ↑
     Unread badge
```

---

### ✅ Scenario 2: Settings Page Badge

**Steps:**
1. Tap "Settings" tab in bottom navigation
2. Look at AppBar (top right)
3. Find notification badge icon

**Expected Results:**
- ✅ Badge visible in AppBar actions
- ✅ Badge shows unread count
- ✅ Tapping badge navigates to Alerts page
- ✅ Badge color matches theme

**Visual Check:**
```
┌─────────────────────────┐
│ Settings         🔔 (3) │ ← Badge in AppBar
├─────────────────────────┤
│                         │
│  Account                │
│  user@example.com       │
│                         │
└─────────────────────────┘
```

---

### ✅ Scenario 3: Navigate to Notifications Page

**Steps:**
1. Tap "Alerts" tab in bottom navigation  
   **OR**  
   Tap notification badge in Settings AppBar

**Expected Results:**
- ✅ NotificationsPage opens
- ✅ AppBar shows "Notifications" title
- ✅ AppBar shows badge in top right
- ✅ Event list loads from cache
- ✅ Loading indicator if fetching from API
- ✅ Empty state if no events

**Visual Check:**
```
┌─────────────────────────────┐
│ Notifications      🔔 (3)   │
├─────────────────────────────┤
│ ⟳ Pull to refresh           │
├─────────────────────────────┤
│ 🟢 deviceEnteredGeofence    │ ← Unread (highlighted)
│    Device 123 entered zone  │
│    5 minutes ago        ●   │ ← Blue dot
├─────────────────────────────┤
│ 🔴 geofenceExit             │
│    Device 456 left zone     │
│    2 hours ago          ✓   │ ← Checkmark (read)
├─────────────────────────────┤
│ ⚠️ alarm                     │ ← Unread
│    Low battery alert        │
│    Yesterday            ●   │
└─────────────────────────────┘
```

---

### ✅ Scenario 4: View Event List

**Steps:**
1. Open Alerts page
2. Observe event list
3. Scroll through events

**Expected Results:**
- ✅ Events sorted by timestamp (newest first)
- ✅ Unread events have background color
- ✅ Read events have normal background
- ✅ Unread indicator (blue dot) on unread events
- ✅ Checkmark on read events
- ✅ Event icon shows correct type
- ✅ Relative timestamps ("5 minutes ago")
- ✅ Smooth scrolling

**Event Display Format:**
```
┌─────────────────────────────────┐
│ [Icon] Event Type               │
│        Event message text       │
│        Relative time      [●/✓] │
└─────────────────────────────────┘
```

---

### ✅ Scenario 5: Mark Event as Read

**Steps:**
1. Open Alerts page
2. Find an unread event (has blue dot)
3. Tap the event

**Expected Results:**
- ✅ Bottom sheet opens with event details
- ✅ Bottom sheet shows:
  - Event type
  - Device name/ID
  - Full timestamp (formatted)
  - Full message
  - Additional attributes
- ✅ Event marked as read immediately
- ✅ Background color removed
- ✅ Blue dot changes to checkmark
- ✅ Badge count decrements
- ✅ Bottom nav badge updates
- ✅ AppBar badge updates

**Bottom Sheet Format:**
```
┌─────────────────────────────────┐
│ Event Details                   │
├─────────────────────────────────┤
│ Type: deviceEnteredGeofence     │
│ Device: Vehicle 123             │
│ Time: Oct 20, 2025 • 14:30     │
│ Message: Device entered zone A  │
│                                 │
│ Attributes:                     │
│ • Geofence: Zone A              │
│ • Position ID: 456789           │
│                                 │
│         [Close]                 │
└─────────────────────────────────┘
```

---

### ✅ Scenario 6: Pull-to-Refresh

**Steps:**
1. Open Alerts page
2. Pull down from top of list
3. Release

**Expected Results:**
- ✅ Circular progress indicator appears
- ✅ API call triggered to `/api/events`
- ✅ List updates with new events
- ✅ Spinner disappears when complete
- ✅ Success even if no new events
- ✅ Error message if network fails

**Visual Feedback:**
```
┌─────────────────────────────────┐
│ Notifications      🔔 (3)       │
├─────────────────────────────────┤
│         ⟳ Refreshing...         │ ← Loading
├─────────────────────────────────┤
│ Events list...                  │
└─────────────────────────────────┘
```

---

### ✅ Scenario 7: WebSocket Toast Notification

**Pre-requisites:**
- App must be running
- WebSocket must be connected
- Traccar server accessible

**Steps:**
1. Keep app open (any page)
2. Trigger event via Traccar:
   - Create geofence alert
   - Trigger device alarm
   - Send custom command
3. Wait for WebSocket event

**Expected Results:**
- ✅ SnackBar appears at bottom of screen
- ✅ Shows event type as title
- ✅ Shows event message
- ✅ Shows "View" button
- ✅ Toast auto-dismisses after 4 seconds
- ✅ Tapping "View" navigates to Alerts page
- ✅ Badge count increments
- ✅ Event appears in NotificationsPage list

**Toast Format:**
```
┌─────────────────────────────────┐
│                                 │
│  ┌───────────────────────────┐  │
│  │ 🟢 Geofence Entry    [View]│  │ ← SnackBar
│  │ Device 123 entered zone   │  │
│  └───────────────────────────┘  │
│                                 │
└─────────────────────────────────┘
```

---

### ✅ Scenario 8: Real-Time Updates

**Steps:**
1. Open Alerts page
2. Keep page open
3. Trigger new event via Traccar
4. Observe list

**Expected Results:**
- ✅ Toast appears first (if on other page)
- ✅ List updates automatically (no refresh needed)
- ✅ New event appears at top of list
- ✅ Badge count increments
- ✅ Smooth animation of list update
- ✅ No page flicker or rebuild

**Timing:**
- WebSocket event: < 1 second
- List update: Immediate
- Badge update: Immediate

---

### ✅ Scenario 9: Empty State

**Steps:**
1. Fresh install OR mark all events as read
2. Open Alerts page

**Expected Results:**
- ✅ Empty state message displayed
- ✅ Icon shown (e.g., notification bell)
- ✅ Text: "No notifications yet"
- ✅ Subtitle: "You'll see notifications here"
- ✅ No error or crash

**Visual:**
```
┌─────────────────────────────────┐
│ Notifications      🔔 (0)       │
├─────────────────────────────────┤
│                                 │
│                                 │
│          🔔                     │
│   No notifications yet          │
│ You'll see notifications here   │
│                                 │
│                                 │
└─────────────────────────────────┘
```

---

### ✅ Scenario 10: Error Handling

**Steps:**
1. Disconnect from network
2. Open Alerts page
3. Pull-to-refresh

**Expected Results:**
- ✅ Error message displayed
- ✅ Shows cached events (if available)
- ✅ Pull-to-refresh shows error
- ✅ User can retry
- ✅ No crash or freeze

**Error Display:**
```
┌─────────────────────────────────┐
│ Notifications      🔔 (3)       │
├─────────────────────────────────┤
│ ⚠️ Connection error             │
│ Showing cached events           │
├─────────────────────────────────┤
│ Cached events list...           │
└─────────────────────────────────┘
```

---

## 🔍 Debug Logging

### Enable Debug Prints

Check console logs for:

```
[NotificationsRepo] Event received: {type: geofenceEnter, ...}
[NotificationsRepo] Emitting 5 events to stream
[NotificationsRepo] Marked event 123 as read
[WS] Connected to WebSocket
[WS] Event received: CustomerEventsMessage
[EventService] Fetching events with params: {...}
[EventService] ✅ Fetched 10 events
```

### Check Provider State

In Flutter DevTools:
1. Open "Provider" tab
2. Find `notificationsStreamProvider`
3. Check state: `AsyncData`, `AsyncLoading`, `AsyncError`
4. Verify event count matches UI

---

## 📊 Performance Metrics

### Expected Performance

| Metric | Target | Acceptable |
|--------|--------|------------|
| App startup | < 2s | < 3s |
| Page load | < 500ms | < 1s |
| WebSocket latency | < 200ms | < 500ms |
| Mark as read | < 100ms | < 200ms |
| Pull-to-refresh | < 2s | < 3s |
| Scroll FPS | 60 | 55 |

### Measure Performance

```bash
# Profile build
flutter run --profile

# Check FPS
# Open DevTools Performance tab
# Interact with app
# Look for frame drops (>16ms)
```

---

## 🐛 Common Issues & Fixes

### Issue 1: Badge Not Updating

**Symptoms:**
- Badge shows old count
- Count doesn't change after marking read

**Possible Causes:**
1. WebSocket disconnected
2. Provider not watching correctly
3. Repository not emitting updates

**Debug Steps:**
```dart
// Check WebSocket status
final ws = ref.read(customerWebSocketProvider);
debugPrint('WebSocket: $ws');

// Check unread count
final count = ref.read(unreadCountProvider);
debugPrint('Unread count: $count');

// Check repository stream
final repo = ref.read(notificationsRepositoryProvider);
repo.watchEvents().listen((events) {
  debugPrint('Events in stream: ${events.length}');
});
```

**Fix:**
- Check Settings page for connection indicator
- Logout and login again
- Restart app

---

### Issue 2: Events Not Loading

**Symptoms:**
- Empty list even with events
- Loading spinner forever
- Error message

**Possible Causes:**
1. Network error
2. Auth token expired
3. API endpoint changed
4. ObjectBox database corrupted

**Debug Steps:**
```dart
// Check EventService
final service = ref.read(eventServiceProvider);
final events = await service.fetchEvents();
debugPrint('Fetched: ${events.length} events');

// Check ObjectBox
final dao = ref.read(eventsBoxProvider);
final cachedCount = dao.count();
debugPrint('Cached: $cachedCount events');
```

**Fix:**
- Pull-to-refresh
- Logout and login
- Clear app data (reinstall)

---

### Issue 3: Toast Not Showing

**Symptoms:**
- No SnackBar when event received
- WebSocket working but no UI feedback

**Possible Causes:**
1. NotificationToastListener not wrapping app
2. WebSocket events not parsed
3. SnackBar blocked by other widget

**Debug Steps:**
```dart
// Check NotificationToastListener
// In app_root.dart, verify structure:
NotificationToastListener(
  child: MaterialApp.router(...)
)

// Check WebSocket messages
ref.listen(customerWebSocketProvider, (prev, next) {
  debugPrint('WebSocket message: $next');
});
```

**Fix:**
- Verify app_root.dart structure
- Check WebSocket connection
- Restart app

---

### Issue 4: Mark as Read Not Working

**Symptoms:**
- Tapping event does nothing
- Event stays unread
- Badge doesn't decrement

**Possible Causes:**
1. API call failing
2. ObjectBox update failing
3. Provider not triggering

**Debug Steps:**
```dart
// Check mark as read
await ref.read(markEventAsReadProvider.notifier).markAsRead(eventId);
debugPrint('Marked event $eventId as read');

// Check ObjectBox
final dao = ref.read(eventsBoxProvider);
final event = dao.get(eventId);
debugPrint('Event isRead: ${event?.isRead}');
```

**Fix:**
- Check network connection
- Pull-to-refresh
- Restart app

---

## ✅ Testing Checklist

### Manual Testing

- [ ] Launch app successfully
- [ ] Bottom nav badge shows count
- [ ] Settings badge shows count
- [ ] Navigate to Alerts page
- [ ] Event list loads
- [ ] Unread events highlighted
- [ ] Tap event opens bottom sheet
- [ ] Event marked as read
- [ ] Badge count decrements
- [ ] Pull-to-refresh works
- [ ] WebSocket toast appears
- [ ] Real-time list updates
- [ ] Empty state displays correctly
- [ ] Error handling works
- [ ] Smooth scrolling
- [ ] No crashes or freezes

### Automated Testing (Future)

```dart
// Example integration test
testWidgets('Notification flow end-to-end', (tester) async {
  // 1. Pump app
  await tester.pumpWidget(const MyApp());
  
  // 2. Verify badge
  expect(find.byType(Badge), findsWidgets);
  
  // 3. Tap Alerts
  await tester.tap(find.text('Alerts'));
  await tester.pumpAndSettle();
  
  // 4. Verify page
  expect(find.byType(NotificationsPage), findsOneWidget);
  
  // 5. Tap event
  await tester.tap(find.byType(NotificationTile).first);
  await tester.pumpAndSettle();
  
  // 6. Verify bottom sheet
  expect(find.text('Event Details'), findsOneWidget);
});
```

---

## 📱 Device Testing

### Test Devices

**Minimum:**
- Android 7.0+ (API 24+)
- iOS 11.0+

**Recommended:**
- Android 10+ (API 29+)
- iOS 14+

### Screen Sizes

- Small: 4.7" (iPhone SE)
- Medium: 5.5" (Pixel 4)
- Large: 6.5" (iPhone 13 Pro Max)
- Tablet: 10" (iPad)

### Network Conditions

- Wi-Fi (fast)
- 4G (medium)
- 3G (slow)
- Offline (cached)

---

## 🎯 Success Criteria

### All scenarios pass ✅
- Bottom nav badge works
- Settings badge works
- Alerts page navigation works
- Event list displays correctly
- Mark as read works
- Pull-to-refresh works
- WebSocket toasts work
- Real-time updates work
- Empty state works
- Error handling works

### Performance meets targets ✅
- Page load < 1s
- Scroll FPS > 55
- Mark as read < 200ms

### No crashes or errors ✅
- Flutter analyze: 0 errors
- Runtime: 0 exceptions
- UI: No flickering

---

## 📝 Test Report Template

```markdown
# Notifications Feature Test Report

**Date:** October 20, 2025
**Tester:** [Your Name]
**Device:** [Device Model]
**OS:** [OS Version]
**Build:** [App Version]

## Test Results

| Scenario | Pass | Fail | Notes |
|----------|------|------|-------|
| 1. Bottom Nav Badge | ✅ | | Badge shows correctly |
| 2. Settings Badge | ✅ | | Navigation works |
| 3. Alerts Navigation | ✅ | | Page loads fast |
| 4. Event List | ✅ | | All events visible |
| 5. Mark as Read | ✅ | | Instant update |
| 6. Pull-to-Refresh | ✅ | | Smooth animation |
| 7. WebSocket Toast | ✅ | | Toast appears |
| 8. Real-Time Updates | ✅ | | Auto-refresh works |
| 9. Empty State | ✅ | | Displays correctly |
| 10. Error Handling | ✅ | | Graceful failure |

## Performance

| Metric | Result | Target | Pass |
|--------|--------|--------|------|
| App startup | 1.2s | < 2s | ✅ |
| Page load | 0.4s | < 0.5s | ✅ |
| Mark as read | 0.08s | < 0.1s | ✅ |

## Issues Found

1. None

## Overall Status

✅ **PASS** - All tests successful, ready for production
```

---

## 🚀 Next Steps

1. **Complete manual testing** using this guide
2. **Document any issues** found
3. **Fix critical bugs** before deployment
4. **Write integration tests** for CI/CD
5. **Deploy to staging** for beta testing
6. **Gather user feedback**
7. **Deploy to production** 🎉

---

**Happy Testing!** 🧪✨

If you encounter any issues not covered in this guide, please document and report them.
