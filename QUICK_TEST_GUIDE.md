# 🚀 Quick Test Guide - Traccar Events

## ⚡ 60-Second Test

### Step 1: Launch App (10s)
```bash
flutter run
```

### Step 2: Check Logs (20s)
Look for these lines:
```
✅ [NotificationsRepository] 🔌 Subscribing to WebSocket events
✅ [NotificationsRepository] ✅ WebSocket subscription initiated
✅ [NotificationsRepository] ✅ WebSocket provider active
```

### Step 3: Trigger Event (20s)
**Easiest: Turn ignition ON → OFF → ON**

### Step 4: Verify (10s)
Watch for:
```
✅ [SOCKET] 🔔 ✅ EVENTS RECEIVED from WebSocket (1 events)
✅ [NotificationsRepository] 🔔 CustomerEventsMessage received
✅ [NotificationsRepository] ✅ Persisted 1 WebSocket events
```

Check UI:
- [ ] Toast notification appeared
- [ ] Event in NotificationsPage list
- [ ] Badge count updated

---

## 🔍 Diagnostic Shortcuts

### If NO events appear:

**Check 1:** Are events being sent?
```
grep "EVENTS RECEIVED" # in console logs
```
- ✅ Found → Events working, check parsing
- ❌ Not found → Server not sending events

**Check 2:** Are events configured in Traccar?
```
Login: http://37.60.238.215:8082
Go to: Settings → Notifications
Verify: Event types are enabled
```

**Check 3:** Can you trigger events manually?
```
Easiest: Turn vehicle ignition on/off
Alternative: Create geofence and cross it
```

---

## 🎯 Test Event Types

### 1️⃣ Ignition Events (EASIEST) ⭐
- **Requirement:** Device reports `ignition` attribute ✅
- **Action:** Turn key on/off
- **Events:** `ignitionOn`, `ignitionOff`
- **Time:** Instant

### 2️⃣ Geofence Events
- **Requirement:** Geofence created in Traccar
- **Action:** Drive in/out of zone
- **Events:** `geofenceEnter`, `geofenceExit`
- **Time:** ~10 seconds

### 3️⃣ Device Online/Offline
- **Requirement:** None
- **Action:** Stop device for 5+ minutes
- **Events:** `deviceOffline`, `deviceOnline`
- **Time:** 5-10 minutes

### 4️⃣ Overspeed
- **Requirement:** Speed limit configured
- **Action:** Drive over limit
- **Events:** `overspeed`
- **Time:** Instant

---

## 📋 Expected Log Pattern

```
[SOCKET] 📨 RAW WebSocket message received:
[SOCKET] {"events":[{"id":123,"type":"ignitionOff",...}]}
[SOCKET] 🔑 Message contains keys: events, positions
[SOCKET] 🔔 ✅ EVENTS RECEIVED from WebSocket (1 events)
[NotificationsRepository] 🔔 CustomerEventsMessage received
[NotificationsRepository] 📨 Received WebSocket events
[NotificationsRepository] 📨 Parsed 1 events from WebSocket
[NotificationsRepository] ✅ Persisted 1 WebSocket events
[NotificationsRepository] 📤 Emitted 1 events to UI stream
[NotificationToast] 🔔 Ignition Off
```

---

## ⚠️ Common Mistakes

### ❌ Waiting for events without triggering them
**Fix:** Events don't come automatically - you must trigger them!

### ❌ Expecting events in WebSocket immediately
**Fix:** Events are sent when conditions occur, not continuously

### ❌ No geofences configured
**Fix:** Create geofences in Traccar UI first

### ❌ Device doesn't report ignition
**Fix:** Check if device attributes include `ignition` field

---

## 🆘 Emergency Debug

If NOTHING works:

```bash
# 1. Check WebSocket connection
grep "\[SOCKET\]" # Should show continuous messages

# 2. Check subscription
grep "Subscribing to WebSocket events" 

# 3. Check for events key
grep "NO EVENTS KEY" # If found → server issue

# 4. Manual API test
# Use Traccar UI to create event manually
# Then pull to refresh in app
# Should fetch from /api/events
```

---

## ✅ Success Checklist

Before reporting "not working":

- [ ] App running with debug logs
- [ ] WebSocket subscription confirmed in logs
- [ ] Actively triggered test event (ignition on/off)
- [ ] Waited at least 30 seconds after trigger
- [ ] Checked console for "EVENTS RECEIVED"
- [ ] Verified Traccar UI shows the event
- [ ] Read TRACCAR_EVENTS_DIAGNOSTIC.md

---

## 📞 Get Help

1. **Documentation:** `TRACCAR_EVENTS_DIAGNOSTIC.md`
2. **Summary:** `TRACCAR_EVENTS_FIX_SUMMARY.md`
3. **Forum:** https://www.traccar.org/forums/
4. **Share logs:** Copy console output and share for debugging

---

**Remember:** Events are TRIGGERED, not continuous! 🔔
