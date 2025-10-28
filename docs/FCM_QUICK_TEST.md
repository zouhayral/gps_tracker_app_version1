# 🚀 FCM Quick Test Reference

## Quick Start (3 Steps)

### 1️⃣ Get Your FCM Token
```bash
# Launch app and check terminal
[FCM] Device token: eyJhbGciOiJSUzI1NiIs...
```
Copy the full token!

### 2️⃣ Open Firebase Console
Go to: **Firebase Console → Engage → Cloud Messaging → Send test message**

### 3️⃣ Send Test Messages

---

## 📱 Test Message Examples

### English Test 🇬🇧
**Change app language to English first!**

```json
{
  "type": "speed_alert",
  "speed": "82",
  "deviceName": "Test Vehicle"
}
```
**Expected:** "Speed alert" - "Test Vehicle is going 82 km/h"

---

### French Test 🇫🇷
**Change app language to French first!**

```json
{
  "type": "ignition_on",
  "deviceName": "Ma Voiture",
  "location": "Paris"
}
```
**Expected:** "Contact mis" - "Ma Voiture à Paris"

---

### Arabic Test 🇸🇦
**Change app language to Arabic first!**

```json
{
  "type": "ignition_off",
  "deviceName": "سيارتي",
  "location": "الرياض"
}
```
**Expected:** "تم إيقاف الإشعال" - "سيارتي في الرياض"

---

## ✅ Quick Checklist

For **each language** (English, French, Arabic):

### Foreground Test (App Open)
- [ ] Open app
- [ ] Send test message
- [ ] See notification while app is open
- [ ] Correct language? ✅

### Background Test (App Minimized)
- [ ] Press Home button
- [ ] Send test message
- [ ] Check notification tray
- [ ] Correct language? ✅

### Lock Screen Test
- [ ] Lock device
- [ ] Send test message
- [ ] Check lock screen
- [ ] Correct language? ✅

---

## 🎯 All 11 Notification Types

Test at least one of each:

```json
{"type": "speed_alert", "speed": "82", "deviceName": "Car"}
{"type": "ignition_on", "deviceName": "Car", "location": "Paris"}
{"type": "ignition_off", "deviceName": "Car", "location": "Home"}
{"type": "geofence_enter", "deviceName": "Truck", "geofence": "Warehouse"}
{"type": "geofence_exit", "deviceName": "Truck", "geofence": "Warehouse"}
{"type": "device_online", "deviceName": "Vehicle 1"}
{"type": "device_offline", "deviceName": "Vehicle 1"}
{"type": "overspeed", "speed": "140", "deviceName": "Car"}
{"type": "maintenance_due", "deviceName": "Truck"}
{"type": "device_moving", "deviceName": "Car", "location": "Highway"}
{"type": "device_stopped", "deviceName": "Car", "location": "Parking"}
```

---

## 🐛 Quick Troubleshooting

**No notifications?**
- Check internet connection
- Verify FCM token is correct
- Check notification permissions in Settings
- Ensure `google-services.json` is installed

**Wrong language?**
- Restart app completely (not hot reload)
- Verify language changed in Settings
- Check terminal: `[FCM] Loading locale: <locale>`

**Background not working?**
- Close app completely and reopen
- Check battery optimization settings
- Verify background handler is registered

---

## 📊 Quick Results Log

| Language | Foreground | Background | Lock Screen |
|----------|------------|------------|-------------|
| 🇬🇧 English | ⬜ | ⬜ | ⬜ |
| 🇫🇷 French | ⬜ | ⬜ | ⬜ |
| 🇸🇦 Arabic | ⬜ | ⬜ | ⬜ |

✅ = Pass | ❌ = Fail | ⬜ = Not tested

---

## 🎉 Success!
**When all boxes are checked:**
- All notifications respect user language
- Fully localized UX achieved!
- Ready for production! 🚀

---

**Full documentation:** `docs/FCM_TESTING_PLAN.md`
