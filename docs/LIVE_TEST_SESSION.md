# 🧪 Live Notification Testing Session
**Date:** October 20, 2025  
**Branch:** feat/notification-page  
**Device:** Infinix X663 (Android)

---

## 📋 Pre-Test Checklist

### ✅ App Launch Status
- [x] Flutter app launched successfully
- [x] WebSocket connected (logs show position updates)
- [ ] Logged in to Traccar account
- [ ] Initial badge count noted

### 🔍 Initial Observations
```
WebSocket: ✅ Connected
Device 1: ✅ Sending positions (ignition=false, speed=0.0)
Position ID: 11476
Server: 37.60.238.215:8082
```

---

## 🎯 Test Scenario 1: Check Initial State

### Steps:
1. **Log in to the app** (if not already logged in)
   - Use your Traccar credentials
   - Wait for login to complete

2. **Check WebSocket connection**
   - Look at Settings page
   - Verify cloud icon shows connected (green)

3. **Note initial badge count**
   - Look at bottom navigation "Alerts" tab
   - Note the badge number (or 0 if none)
   - Look at Settings page AppBar badge
   - Verify both badges show same count

### Expected Results:
- ✅ Login successful
- ✅ WebSocket connected (green cloud icon in Settings)
- ✅ Badge shows current unread count
- ✅ Both badges (bottom nav + AppBar) show same number

### Actual Results:
```
Login: [ ] Success / [ ] Failed
WebSocket: [ ] Connected / [ ] Disconnected
Bottom Nav Badge: Count = ___
AppBar Badge: Count = ___
Match: [ ] Yes / [ ] No
```

---

## 🎯 Test Scenario 2: Navigate to Notifications Page

### Steps:
1. **Tap "Alerts" tab** in bottom navigation
2. **Verify page loads**
   - Check title shows "Notifications"
   - Check badge appears in AppBar
3. **Observe event list**
   - Count total events
   - Count unread events (with blue dot)
   - Count read events (with checkmark)

### Expected Results:
- ✅ NotificationsPage opens
- ✅ AppBar shows "Notifications" + badge
- ✅ Event list displays
- ✅ Unread events have background color
- ✅ Read events have normal background
- ✅ List sorted by timestamp (newest first)

### Actual Results:
```
Page Opened: [ ] Yes / [ ] No
Total Events: ___
Unread Events: ___
Read Events: ___
Sorting: [ ] Newest first / [ ] Oldest first
```

---

## 🎯 Test Scenario 3: Trigger WebSocket Event

### 🚨 ACTION REQUIRED: Trigger Event on Traccar

You need to trigger an event on your Traccar server. Here are several options:

#### Option A: Use Traccar Web Interface
1. Open http://37.60.238.215:8082 in browser
2. Log in with same credentials
3. Go to **Settings** → **Geofences**
4. Create a test geofence around device location
5. Wait for device to enter geofence
   - OR move device physically
   - OR simulate with "Send Command" → Set Position

#### Option B: Use Traccar API (via terminal/Postman)
```bash
# Create alarm event
curl -X POST "http://37.60.238.215:8082/api/notifications/test" \
  -H "Content-Type: application/json" \
  -u "your_email:your_password" \
  -d '{"deviceId": 1, "type": "alarm", "message": "Test notification"}'

# Or trigger command
curl -X POST "http://37.60.238.215:8082/api/commands/send" \
  -H "Content-Type: application/json" \
  -u "your_email:your_password" \
  -d '{"deviceId": 1, "type": "custom", "attributes": {"data": "test"}}'
```

#### Option C: Physical Device Action
1. Turn device ignition ON/OFF (if supported)
2. Move device to trigger motion event
3. Disconnect/reconnect device to trigger deviceOffline/deviceOnline

### Steps After Triggering Event:
1. **Watch the app** for SnackBar toast
2. **Check console logs** for WebSocket message
3. **Note badge count change**

### Expected Results:
- ✅ Console shows: `[SOCKET] {"events":[...]}`
- ✅ SnackBar appears at bottom of screen
- ✅ Toast shows event type (e.g., "Geofence Entry")
- ✅ Toast shows event message
- ✅ Toast shows "View" button
- ✅ Toast auto-dismisses after 4 seconds
- ✅ Badge count increments immediately
- ✅ Both badges update (bottom nav + AppBar)

### Actual Results:
```
Console Log: [ ] Seen / [ ] Not seen
Toast Appeared: [ ] Yes / [ ] No
Toast Message: ___________________________
Toast Duration: ___ seconds
Badge Incremented: [ ] Yes / [ ] No
Bottom Nav Badge: Old ___ → New ___
AppBar Badge: Old ___ → New ___
```

### 📸 Screenshot Opportunity
Take a screenshot when toast appears!

---

## 🎯 Test Scenario 4: Verify Real-Time List Update

### Steps:
1. **Keep NotificationsPage open** (or navigate to it after toast)
2. **Look at top of event list**
3. **Find the new event** (should be at top)

### Expected Results:
- ✅ New event appears at top of list
- ✅ Event has background color (unread)
- ✅ Event shows blue dot indicator
- ✅ Event shows correct icon
- ✅ Event shows correct type
- ✅ Event shows correct message
- ✅ Event shows relative time ("just now" or "a few seconds ago")
- ✅ List updates WITHOUT pull-to-refresh

### Actual Results:
```
Event at Top: [ ] Yes / [ ] No
Background Color: [ ] Present / [ ] Missing
Blue Dot: [ ] Present / [ ] Missing
Event Type: ___________________________
Event Message: ___________________________
Relative Time: ___________________________
Auto-Update: [ ] Yes (no refresh needed) / [ ] No (had to refresh)
```

---

## 🎯 Test Scenario 5: Mark Event as Read

### Steps:
1. **Tap the new unread event** (the one with blue dot)
2. **Wait for bottom sheet** to open
3. **Observe changes**

### Expected Results:
- ✅ Bottom sheet opens with event details
- ✅ Shows event type
- ✅ Shows device name/ID
- ✅ Shows formatted timestamp (e.g., "Oct 20, 2025 • 17:18")
- ✅ Shows full message
- ✅ Shows attributes (if any)
- ✅ Event marked as read INSTANTLY
- ✅ Background color removed
- ✅ Blue dot changes to checkmark
- ✅ Badge count decrements
- ✅ Both badges update (bottom nav + AppBar)
- ✅ Change persists if bottom sheet closed

### Actual Results:
```
Bottom Sheet Opened: [ ] Yes / [ ] No
Event Type: ___________________________
Device: ___________________________
Timestamp: ___________________________
Background Removed: [ ] Yes / [ ] No
Blue Dot → Checkmark: [ ] Yes / [ ] No
Badge Decremented: [ ] Yes / [ ] No
Bottom Nav Badge: Old ___ → New ___
AppBar Badge: Old ___ → New ___
Persistence: [ ] Yes / [ ] No
```

### 📸 Screenshot Opportunity
Take screenshot of bottom sheet!

---

## 🎯 Test Scenario 6: Pull-to-Refresh

### Steps:
1. **Close bottom sheet** (if open)
2. **Pull down on event list** from top
3. **Release when refresh indicator appears**
4. **Wait for refresh to complete**

### Expected Results:
- ✅ Circular progress indicator appears
- ✅ Console shows: `[EventService] Fetching events...`
- ✅ Console shows: `[EventService] ✅ Fetched X events`
- ✅ List updates with any new events
- ✅ Spinner disappears
- ✅ Badge count matches ObjectBox state
- ✅ Previously read events still show as read
- ✅ Previously unread events still show as unread

### Actual Results:
```
Refresh Indicator: [ ] Appeared / [ ] Missing
Console Log (Fetch): [ ] Seen / [ ] Not seen
Events Fetched: ___ events
New Events: ___ events
Badge Count After: ___
Read State Preserved: [ ] Yes / [ ] No
```

---

## 🎯 Test Scenario 7: Navigate Away and Back

### Steps:
1. **Tap "Map" tab** in bottom navigation
2. **Wait 2 seconds**
3. **Tap "Alerts" tab** again

### Expected Results:
- ✅ NotificationsPage state preserved
- ✅ Scroll position maintained
- ✅ Read/unread states unchanged
- ✅ Badge count same as before
- ✅ No unnecessary re-fetch

### Actual Results:
```
State Preserved: [ ] Yes / [ ] No
Scroll Position: [ ] Maintained / [ ] Reset
Read States: [ ] Unchanged / [ ] Changed
Badge Count: [ ] Same / [ ] Different
Re-fetch Triggered: [ ] Yes / [ ] No
```

---

## 🎯 Test Scenario 8: Settings Badge Navigation

### Steps:
1. **Navigate to Settings tab**
2. **Look at AppBar** (top right)
3. **Tap notification badge**

### Expected Results:
- ✅ Badge visible in Settings AppBar
- ✅ Badge shows correct unread count
- ✅ Tapping badge navigates to Alerts page
- ✅ Navigation smooth (no transition animation)

### Actual Results:
```
Badge Visible: [ ] Yes / [ ] No
Badge Count: ___
Navigation: [ ] Worked / [ ] Failed
Transition: [ ] Smooth / [ ] Janky
```

---

## 🎯 Test Scenario 9: Multiple Events

### 🚨 ACTION REQUIRED: Trigger Multiple Events

Trigger 2-3 more events on Traccar (use same methods as Scenario 3)

### Steps:
1. **Trigger event #1**
2. **Wait for toast**
3. **Trigger event #2**
4. **Wait for toast**
5. **Trigger event #3**
6. **Check badge count**

### Expected Results:
- ✅ Each event triggers separate toast
- ✅ Badge increments for each event
- ✅ All events appear in list
- ✅ All events show as unread
- ✅ Events sorted by timestamp

### Actual Results:
```
Event #1: [ ] Toast / [ ] No toast
Event #2: [ ] Toast / [ ] No toast
Event #3: [ ] Toast / [ ] No toast
Badge Count After: ___
All Events in List: [ ] Yes / [ ] No
Sorting Correct: [ ] Yes / [ ] No
```

---

## 🎯 Test Scenario 10: Mark Multiple as Read

### Steps:
1. **Tap event #1** → mark as read
2. **Tap event #2** → mark as read
3. **Tap event #3** → mark as read
4. **Check badge count**

### Expected Results:
- ✅ Each tap marks event as read
- ✅ Badge decrements for each
- ✅ All events show checkmark
- ✅ All backgrounds removed
- ✅ Badge count reaches 0 (if no other unread events)

### Actual Results:
```
Event #1 Read: [ ] Yes / [ ] No
Event #2 Read: [ ] Yes / [ ] No
Event #3 Read: [ ] Yes / [ ] No
Badge Count After: ___
All Checkmarks: [ ] Yes / [ ] No
```

---

## 🎯 Test Scenario 11: Performance Check

### Steps:
1. **Scroll through event list** (fast)
2. **Tap events repeatedly** (mark as read)
3. **Pull-to-refresh multiple times**
4. **Navigate between tabs quickly**

### Expected Results:
- ✅ Smooth scrolling (60 FPS)
- ✅ No frame drops
- ✅ Instant tap response
- ✅ No lag when marking as read
- ✅ Fast navigation between tabs

### Actual Results:
```
Scroll FPS: [ ] 60 / [ ] 55 / [ ] <50
Frame Drops: [ ] None / [ ] Some / [ ] Many
Tap Response: [ ] Instant / [ ] Delayed
Mark Read Speed: [ ] <100ms / [ ] <200ms / [ ] >200ms
Navigation Speed: [ ] Fast / [ ] Slow
```

---

## 📊 Test Summary

### ✅ Passed Tests
- [ ] Initial state verification
- [ ] Navigate to notifications
- [ ] WebSocket toast
- [ ] Real-time list update
- [ ] Mark as read
- [ ] Pull-to-refresh
- [ ] Navigate away and back
- [ ] Settings badge navigation
- [ ] Multiple events
- [ ] Mark multiple as read
- [ ] Performance check

### ❌ Failed Tests
_List any failed tests here with details_

### 🐛 Issues Found
_Document any bugs or unexpected behavior_

### 📈 Performance Metrics
```
App Startup: ___ seconds
Page Load: ___ seconds
Mark as Read: ___ ms
Pull-to-Refresh: ___ seconds
Scroll FPS: ___
```

---

## 🔍 Debug Information

### Console Logs to Check

Look for these log patterns:

**WebSocket Connection:**
```
[WS] Connected to WebSocket
[SOCKET] 📨 RAW WebSocket message received
```

**Event Reception:**
```
[SOCKET] {"events":[...]}
[NotificationsRepo] Event received: ...
[NotificationsRepo] Emitting X events to stream
```

**Mark as Read:**
```
[NotificationsRepo] Marked event X as read
[EventService] ✅ Marked event as read
```

**API Calls:**
```
[EventService] Fetching events with params: {...}
[EventService] ✅ Fetched X events
```

### Current Console Output
```
_Paste relevant console logs here_
```

---

## 🎬 Video/Screenshot Evidence

### Screenshots Taken:
1. [ ] Initial badge count
2. [ ] Toast notification
3. [ ] Event list with unread items
4. [ ] Bottom sheet with event details
5. [ ] Event marked as read
6. [ ] Badge count after marking read
7. [ ] Pull-to-refresh in action

### Video Recorded:
- [ ] Full end-to-end flow (recommended)
- Duration: ___ seconds
- Shows: _______________________________

---

## ✅ Overall Assessment

### Functionality
- **WebSocket Integration:** [ ] ✅ Working / [ ] ⚠️ Partial / [ ] ❌ Broken
- **Toast Notifications:** [ ] ✅ Working / [ ] ⚠️ Partial / [ ] ❌ Broken
- **Badge Updates:** [ ] ✅ Working / [ ] ⚠️ Partial / [ ] ❌ Broken
- **Real-Time List:** [ ] ✅ Working / [ ] ⚠️ Partial / [ ] ❌ Broken
- **Mark as Read:** [ ] ✅ Working / [ ] ⚠️ Partial / [ ] ❌ Broken
- **Pull-to-Refresh:** [ ] ✅ Working / [ ] ⚠️ Partial / [ ] ❌ Broken

### User Experience
- **Visual Feedback:** [ ] Excellent / [ ] Good / [ ] Needs Improvement
- **Response Time:** [ ] Instant / [ ] Fast / [ ] Acceptable / [ ] Slow
- **UI Polish:** [ ] Excellent / [ ] Good / [ ] Needs Improvement

### Production Readiness
- **Ready for Production:** [ ] ✅ Yes / [ ] ⚠️ With minor fixes / [ ] ❌ No

---

## 🚀 Next Steps

### If All Tests Pass:
1. ✅ Merge feat/notification-page to main
2. ✅ Deploy to production
3. ✅ Monitor user feedback
4. ✅ Plan enhancements (filtering, etc.)

### If Issues Found:
1. 🐛 Document all bugs
2. 🔧 Prioritize fixes
3. 🧪 Re-test after fixes
4. ✅ Verify fixes work

---

## 📝 Tester Notes

_Add any additional observations, suggestions, or comments here_

```
Notes:
_______________________________________________________________________
_______________________________________________________________________
_______________________________________________________________________
```

---

**Test Completed:** ___ / ___ / ___  
**Tester Signature:** _________________________  
**Status:** [ ] PASS / [ ] FAIL / [ ] NEEDS REVIEW
