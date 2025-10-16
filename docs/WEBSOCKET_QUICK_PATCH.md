# WebSocket Reconnection - Quick Integration Patch

## 🎯 Changes Required in Existing Files

### 1. MAP_PAGE.DART - Add Lifecycle Mixin

**Location:** `lib/features/map/view/map_page.dart`

#### A. Add Imports (top of file)
```dart
import 'map_page_lifecycle_mixin.dart';
import '../../../services/websocket_manager_enhanced.dart';
```

#### B. Modify Class Declaration (line ~104)
**BEFORE:**
```dart
class _MapPageState extends ConsumerState<MapPage> {
```

**AFTER:**
```dart
class _MapPageState extends ConsumerState<MapPage>
    with WidgetsBindingObserver, MapPageLifecycleMixin<MapPage> {
```

#### C. Add activeDeviceIds Getter (add after line ~107)
```dart
  // Required by MapPageLifecycleMixin
  @override
  List<int> get activeDeviceIds {
    final devicesAsync = ref.read(devicesNotifierProvider);
    final devices = devicesAsync.asData?.value ?? [];
    return devices
        .map((d) => d['id'] as int?)
        .whereType<int>()
        .toList();
  }
```

#### D. Enhance _onMarkerTap (line ~289)
**BEFORE:**
```dart
  void _onMarkerTap(String id) {
    final n = int.tryParse(id);
    if (n == null) return;

    final position = ref.read(positionByDeviceProvider(n));
    final hasValidPos = position != null &&
        _valid(position.latitude, position.longitude);

    setState(() {
      if (_selectedIds.contains(n)) {
        _selectedIds.remove(n);
      } else {
        _selectedIds.add(n);
        if (_selectedIds.length == 1 && hasValidPos) {
          _mapKey.currentState?.moveTo(
            LatLng(position.latitude, position.longitude),
          );
        }
      }
    });
  }
```

**AFTER:**
```dart
  void _onMarkerTap(String id) {
    final n = int.tryParse(id);
    if (n == null) return;

    final position = ref.read(positionByDeviceProvider(n));
    final hasValidPos = position != null &&
        _valid(position.latitude, position.longitude);

    // NEW: Refresh device when selecting (not deselecting)
    if (!_selectedIds.contains(n)) {
      refreshDevice(n); // Trigger fresh fetch from server
    }

    setState(() {
      if (_selectedIds.contains(n)) {
        _selectedIds.remove(n);
      } else {
        _selectedIds.add(n);
        if (_selectedIds.length == 1 && hasValidPos) {
          _mapKey.currentState?.moveTo(
            LatLng(position.latitude, position.longitude),
          );
        }
      }
    });
  }
```

---

### 2. WEBSOCKET_MANAGER_ENHANCED.DART - Update URL

**Location:** `lib/services/websocket_manager_enhanced.dart`

**Line ~11:** Replace placeholder URL with your Traccar server
```dart
  static const _wsUrl = 'wss://your.traccar.server/api/socket'; // <-- UPDATE THIS
```

**Common Traccar WebSocket URLs:**
- Production: `wss://traccar.yourdomain.com/api/socket`
- Local Dev: `ws://localhost:8082/api/socket`
- IP Address: `ws://192.168.1.100:8082/api/socket`

---

### 3. VEHICLE_DATA_REPOSITORY.DART - Update WebSocket Import

**Location:** `lib/core/data/vehicle_data_repository.dart`

**Find import (line ~3-10):**
```dart
import '../../services/websocket_manager.dart';
```

**Replace with:**
```dart
import '../../services/websocket_manager_enhanced.dart';
```

**Alternative:** Rename `websocket_manager_enhanced.dart` to `websocket_manager.dart` (no import changes needed)

---

## 🚀 One-Command Integration Script

If you want to apply all changes at once, use this PowerShell script:

### integration_script.ps1
```powershell
# Navigate to project root
cd "c:\Users\Acer\Desktop\soceur\my_app_gps_version1"

# Backup original websocket_manager
Copy-Item "lib\services\websocket_manager.dart" "lib\services\websocket_manager_backup.dart"

# Replace with enhanced version
Move-Item "lib\services\websocket_manager_enhanced.dart" "lib\services\websocket_manager.dart" -Force

Write-Host "✅ WebSocket manager replaced"
Write-Host "📝 Next steps:"
Write-Host "  1. Update WebSocket URL in lib/services/websocket_manager.dart (line ~11)"
Write-Host "  2. Add mixin to MapPage (see WEBSOCKET_RECONNECTION_GUIDE.md)"
Write-Host "  3. Test with: flutter run"
```

Run with:
```powershell
.\integration_script.ps1
```

---

## 📋 Verification Commands

### After Integration, Run:
```bash
# 1. Check for compile errors
flutter analyze

# 2. Run app in debug mode (watch console logs)
flutter run --debug

# 3. Test hot reload works
# (Make a small change and press 'r' in console)

# 4. Check for runtime errors
# Look for [WS] and [MapPage][LIFECYCLE] logs in console
```

### Expected Console Output After App Start:
```
[WS][CONNECTING] Attempt 1...
[WS] ✅ Connected successfully
[MapPage][LIFECYCLE] First open - fetching fresh data from server
[VehicleRepo] Fetching 25 devices in parallel
[VehicleRepo] ✅ Fetched 25 positions
[MapPage][FALLBACK] Started periodic refresh every 45s
```

### Expected Console Output After App Resume:
```
[MapPage][LIFECYCLE] App paused - suspending WebSocket
[WS][SUSPEND] Suspending connection
... (user returns to app) ...
[MapPage][LIFECYCLE] App resumed - reconnecting WebSocket and refreshing data
[WS][RESUME] Resuming connection
[WS][CONNECTING] Attempt 1...
[WS] ✅ Connected successfully
[VehicleRepo] Refreshing 25 devices
```

---

## 🐛 Common Integration Issues

### Issue 1: "MapPageLifecycleMixin not found"
**Fix:** Ensure file created at `lib/features/map/view/map_page_lifecycle_mixin.dart`

### Issue 2: "activeDeviceIds not implemented"
**Fix:** Add getter to `_MapPageState` (see section 1C above)

### Issue 3: "refreshDevice undefined"
**Fix:** Ensure `MapPageLifecycleMixin` is in class declaration (see section 1B)

### Issue 4: "WebSocket connection timeout"
**Fix:** Update `_wsUrl` with correct Traccar server address (see section 2)

### Issue 5: "devicesNotifierProvider not found"
**Fix:** Use your actual devices provider name in `activeDeviceIds` getter

---

## 🧪 Quick Test Procedure

1. **Clean Build:**
   ```bash
   flutter clean
   flutter pub get
   flutter run
   ```

2. **Test App Resume:**
   - Open map
   - Press home button
   - Wait 5 seconds
   - Return to app
   - Check console for `[WS][RESUME]`

3. **Test Device Selection:**
   - Tap any marker on map
   - Check console for `[MapPage][LIFECYCLE] Device X selected`
   - Verify device details update

4. **Test WebSocket Reconnect:**
   - Turn off WiFi
   - Wait 10 seconds
   - Turn on WiFi
   - Check console for `[WS][RETRY]` and `[WS] ✅ Connected`

---

## 📞 Need Help?

**Check logs first:**
- Look for `[WS]` prefix - WebSocket events
- Look for `[MapPage][LIFECYCLE]` - Lifecycle events
- Look for `[VehicleRepo]` - Data fetch events

**Common log patterns:**
- `[WS][CONNECTING]` → WebSocket attempting connection
- `[WS] ✅ Connected` → Success
- `[WS][RETRY]` → Reconnection in progress
- `[MapPage][LIFECYCLE]` → Lifecycle event triggered

**If markers still don't update:**
1. Verify WebSocket URL is correct
2. Check Traccar server is running and accessible
3. Ensure `activeDeviceIds` returns non-empty list
4. Look for errors in console
5. Check `VehicleDataRepository` has WebSocket subscription

---

## ✅ Success Indicators

You'll know it's working when:
- ✅ Console shows `[WS] ✅ Connected successfully` on app start
- ✅ Markers update within 2 seconds of app resume
- ✅ Device selection triggers `[MapPage][LIFECYCLE] Device X selected`
- ✅ WebSocket reconnects automatically after network loss
- ✅ No need to logout/login to see fresh data
- ✅ Periodic refresh logs appear every 45s when WebSocket down

---

## 🎉 Final Checklist

- [ ] Files created: `map_page_lifecycle_mixin.dart`, `websocket_manager_enhanced.dart`
- [ ] MapPage imports updated
- [ ] MapPage class uses mixin
- [ ] activeDeviceIds getter added
- [ ] _onMarkerTap calls refreshDevice()
- [ ] WebSocket URL configured
- [ ] Repository imports updated
- [ ] flutter analyze passes
- [ ] App runs without errors
- [ ] Console shows lifecycle logs
- [ ] Markers update on app resume
- [ ] Device selection refreshes data

**All done? Test it!** 🚀
```bash
flutter run --debug
# Then minimize app, wait 5s, return to app
# Markers should update immediately!
```
