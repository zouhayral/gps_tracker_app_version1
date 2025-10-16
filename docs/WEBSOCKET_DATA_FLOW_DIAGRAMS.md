# WebSocket Reconnection - Data Flow Diagrams

## 1. App Resume Flow

```
┌──────────────────────────────────────────────────────────────────┐
│                         USER ACTION                               │
│                    (Returns to app)                               │
└──────────────────────┬───────────────────────────────────────────┘
                       │
                       ▼
┌──────────────────────────────────────────────────────────────────┐
│                  Flutter WidgetsBinding                           │
│         didChangeAppLifecycleState(AppLifecycleState.resumed)    │
└──────────────────────┬───────────────────────────────────────────┘
                       │
                       ▼
┌──────────────────────────────────────────────────────────────────┐
│              MapPageLifecycleMixin._onAppResumed()               │
│  [1] webSocketManager.forceReconnect()                           │
│  [2] repository.refreshAll()                                     │
│  [3] _startPeriodicRefresh()                                     │
└──────────────────────┬───────────────────────────────────────────┘
                       │
           ┌───────────┴───────────┐
           │                       │
           ▼                       ▼
┌──────────────────────┐  ┌──────────────────────┐
│ WebSocketManager     │  │ VehicleDataRepo      │
│ - Cancel retry timer │  │ - Clear memo cache   │
│ - Close old socket   │  │ - Fetch all devices  │
│ - Connect new socket │  │ - Update notifiers   │
└──────────┬───────────┘  └──────────┬───────────┘
           │                         │
           │ WebSocket               │ REST API
           │ Message                 │ /api/positions
           │                         │
           ▼                         ▼
    ┌──────────────────────────────────┐
    │        Traccar Server            │
    │  WebSocket: Real-time updates    │
    │  REST API: Bulk fetch            │
    └──────────┬───────────────────────┘
               │
               ▼
    ┌──────────────────────────────────┐
    │    VehicleDataRepository         │
    │  - Merge WS + REST updates       │
    │  - Update cache                  │
    │  - Notify listeners              │
    └──────────┬───────────────────────┘
               │
               ▼
    ┌──────────────────────────────────┐
    │    ValueNotifier<Snapshot>       │
    │  - Per-device notifiers          │
    │  - Debounced updates (100ms)     │
    └──────────┬───────────────────────┘
               │
               ▼
    ┌──────────────────────────────────┐
    │         MapPage UI                │
    │  - Watch notifiers               │
    │  - Update markers                │
    │  - Show fresh positions          │
    └──────────────────────────────────┘

Timing: < 2 seconds from resume to fresh markers
```

---

## 2. Device Selection Flow

```
┌──────────────────────────────────────────────────────────────────┐
│                         USER ACTION                               │
│                    (Taps marker on map)                           │
└──────────────────────┬───────────────────────────────────────────┘
                       │
                       ▼
┌──────────────────────────────────────────────────────────────────┐
│                   MapPage._onMarkerTap(id)                       │
│  [Check] if (!_selectedIds.contains(id))                         │
│  [Call]  refreshDevice(id) ← NEW                                 │
│  [Then]  setState() to update selection                          │
└──────────────────────┬───────────────────────────────────────────┘
                       │
                       ▼
┌──────────────────────────────────────────────────────────────────┐
│         MapPageLifecycleMixin.refreshDevice(deviceId)            │
│  debugPrint('[MapPage][LIFECYCLE] Device selected')              │
│  repository.refresh(deviceId)                                    │
└──────────────────────┬───────────────────────────────────────────┘
                       │
                       ▼
┌──────────────────────────────────────────────────────────────────┐
│           VehicleDataRepository.refresh(deviceId)                │
│  [1] _lastFetchTime.remove(deviceId) // Clear memo cache         │
│  [2] _fetchDeviceData(deviceId) // Force fresh fetch             │
└──────────────────────┬───────────────────────────────────────────┘
                       │
                       ▼
┌──────────────────────────────────────────────────────────────────┐
│         VehicleDataRepository._fetchDeviceData(deviceId)         │
│  [1] deviceService.fetchDevices() // Get device info             │
│  [2] positionsService.latestByPositionId(posId) // Get position  │
│  [3] _updateDeviceSnapshot(snapshot) // Update cache + notifier  │
└──────────────────────┬───────────────────────────────────────────┘
                       │
                       │ REST API
                       │ GET /api/devices
                       │ GET /api/positions/{id}
                       │
                       ▼
    ┌──────────────────────────────────┐
    │        Traccar Server            │
    │  Returns latest position data    │
    └──────────┬───────────────────────┘
               │
               ▼
    ┌──────────────────────────────────┐
    │  VehicleDataSnapshot.fromPosition│
    │  - deviceId, lat, lng, speed...  │
    └──────────┬───────────────────────┘
               │
               ▼
    ┌──────────────────────────────────┐
    │  VehicleDataCache.put(snapshot)  │
    │  - Disk cache (SharedPrefs)      │
    │  - In-memory cache               │
    └──────────┬───────────────────────┘
               │
               ▼
    ┌──────────────────────────────────┐
    │  ValueNotifier<Snapshot>.value = │
    │  - Trigger rebuild               │
    │  - Update device detail panel    │
    │  - Refresh marker icon (if moved)│
    └──────────────────────────────────┘

Latency: ~200-500ms depending on network
```

---

## 3. Map Page Open Flow

```
┌──────────────────────────────────────────────────────────────────┐
│                         USER ACTION                               │
│              (Navigates to map page or logs in)                   │
└──────────────────────┬───────────────────────────────────────────┘
                       │
                       ▼
┌──────────────────────────────────────────────────────────────────┐
│               MapPage.didChangeDependencies()                     │
│  [Check] if (!_hasInitializedOnce)                               │
│  [Set]   _hasInitializedOnce = true                              │
│  [PostFrameCallback]                                              │
└──────────────────────┬───────────────────────────────────────────┘
                       │
                       ▼
┌──────────────────────────────────────────────────────────────────┐
│         MapPageLifecycleMixin Post-Frame Callback                │
│  [1] webSocketManager.checkHealth()                              │
│  [2] repository.refreshAll()                                     │
└──────────────────────┬───────────────────────────────────────────┘
                       │
           ┌───────────┴───────────┐
           │                       │
           ▼                       ▼
┌──────────────────────┐  ┌──────────────────────┐
│ WebSocketManager     │  │ VehicleDataRepo      │
│ checkHealth()        │  │ refreshAll()         │
│ - If not open:       │  │ - Clear memo cache   │
│   forceReconnect()   │  │ - Fetch all devices  │
│ - If stale (5min):   │  │ - Parallel fetch     │
│   forceReconnect()   │  │ - Update all caches  │
└──────────┬───────────┘  └──────────┬───────────┘
           │                         │
           │ WebSocket               │ REST API
           │ Subscribe               │ GET /api/positions
           │                         │
           ▼                         ▼
    ┌──────────────────────────────────┐
    │        Traccar Server            │
    └──────────┬───────────────────────┘
               │
               ▼
    ┌──────────────────────────────────┐
    │  VehicleDataRepository           │
    │  fetchMultipleDevices()          │
    │  - Batch fetch all positions     │
    │  - Update cache                  │
    │  - Trigger notifiers             │
    └──────────┬───────────────────────┘
               │
               ▼
    ┌──────────────────────────────────┐
    │       MapPage Build              │
    │  - Cache hit: instant markers    │
    │  - Background: fresh fetch       │
    │  - Best of both worlds           │
    └──────────────────────────────────┘

Initial render: < 100ms (cache)
Fresh data: < 1 second (background)
```

---

## 4. WebSocket Disconnection & Reconnection Flow

```
┌──────────────────────────────────────────────────────────────────┐
│                      NETWORK EVENT                                │
│                 (WiFi drops, server restart)                      │
└──────────────────────┬───────────────────────────────────────────┘
                       │
                       ▼
┌──────────────────────────────────────────────────────────────────┐
│              WebSocket.onDone / onError                          │
│  debugPrint('[WS][CLOSED] Connection closed')                    │
│  _scheduleReconnect(error)                                       │
└──────────────────────┬───────────────────────────────────────────┘
                       │
                       ▼
┌──────────────────────────────────────────────────────────────────┐
│           WebSocketManager._scheduleReconnect()                  │
│  [1] retryCount++                                                │
│  [2] Calculate backoff: 2s → 4s → 8s → 16s → 30s max            │
│  [3] Set retry timer                                             │
│  [4] Update state to WebSocketStatus.retrying                    │
└──────────────────────┬───────────────────────────────────────────┘
                       │
                       │ Timer(backoffDelay)
                       │
                       ▼
┌──────────────────────────────────────────────────────────────────┐
│              WebSocketManager._connect()                         │
│  [Try] WebSocket.connect(url).timeout(10s)                       │
└──────────────────────┬───────────────────────────────────────────┘
                       │
           ┌───────────┴───────────┐
           │                       │
           ▼ Success               ▼ Failure
┌──────────────────────┐  ┌──────────────────────┐
│ Connected!           │  │ Retry Again          │
│ - retryCount = 0     │  │ - Increase backoff   │
│ - Start ping timer   │  │ - Schedule reconnect │
│ - Listen for msgs    │  │ - Max 10 attempts    │
│ - State: connected   │  │ - State: retrying    │
└──────────┬───────────┘  └──────────┬───────────┘
           │                         │
           ▼                         │
    Repository receives              │
    WebSocket messages        ┌──────┘
                             │
                             ▼
                    After 10 failures:
                    - Stop retrying
                    - Fall back to periodic REST
                    - User can manually reconnect

Meanwhile: Periodic Refresh Timer (45s)
    │
    ▼
┌──────────────────────────────────────────────────────────────────┐
│        MapPageLifecycleMixin Periodic Refresh                    │
│  [Check] if WebSocket NOT connected:                             │
│  [Then]  repository.fetchMultipleDevices(activeDeviceIds)        │
│  [Else]  webSocketManager.checkHealth()                          │
└──────────────────────────────────────────────────────────────────┘
    │
    │ REST API fallback
    │ GET /api/positions
    │
    ▼
Markers update via REST
(slower but reliable)
```

---

## 5. Complete System Architecture

```
┌────────────────────────────────────────────────────────────────────────────┐
│                              USER INTERFACE                                 │
│  ┌────────────────────────────────────────────────────────────────────┐    │
│  │                           MapPage                                   │    │
│  │  ┌──────────────────────────────────────────────────────────────┐  │    │
│  │  │              MapPageLifecycleMixin                            │  │    │
│  │  │  • WidgetsBindingObserver (app lifecycle)                     │  │    │
│  │  │  • _onAppResumed() → reconnect + refresh                      │  │    │
│  │  │  • _onAppPaused() → suspend WebSocket                         │  │    │
│  │  │  • didChangeDependencies() → initial fetch                    │  │    │
│  │  │  • refreshDevice(id) → per-device refresh                     │  │    │
│  │  │  • _startPeriodicRefresh() → 45s fallback timer              │  │    │
│  │  └──────────────────────────────────────────────────────────────┘  │    │
│  │                                                                      │    │
│  │  • MarkerClusterLayer (cached widgets)                             │    │
│  │  • ThrottledValueNotifier (50ms throttle)                          │    │
│  │  • Background isolate (marker processing)                          │    │
│  │  • FrameTimingSummarizer (performance monitoring)                  │    │
│  └────────────────────────────────────────────────────────────────────┘    │
└────────────────────────────────────────────────────────────────────────────┘
                │                                        │
                │ ref.watch                              │ ref.read
                │                                        │
                ▼                                        ▼
┌────────────────────────────────────────────────────────────────────────────┐
│                          STATE MANAGEMENT (Riverpod)                        │
│  ┌──────────────────────────┐      ┌──────────────────────────────────┐    │
│  │  webSocketProvider       │      │  vehicleDataRepositoryProvider   │    │
│  │  (WebSocketState)        │      │  (VehicleDataRepository)         │    │
│  │  • status                │      │  • Per-device notifiers          │    │
│  │  • retryCount            │      │  • Cache (disk + memory)         │    │
│  │  • pingMs                │◄─────┤  • WebSocket subscription        │    │
│  │  • lastConnected         │      │  • REST fallback timer           │    │
│  └──────────────────────────┘      │  • Debounced updates             │    │
│                                     └──────────────────────────────────┘    │
└────────────────────────────────────────────────────────────────────────────┘
                │                                        │
                │                                        │
                ▼                                        ▼
┌────────────────────────────────────────────────────────────────────────────┐
│                            SERVICES LAYER                                   │
│  ┌──────────────────────────┐      ┌──────────────────────────────────┐    │
│  │  WebSocketManager        │      │  PositionsService                │    │
│  │  • _connect()            │      │  (REST API Client)               │    │
│  │  • _scheduleReconnect()  │      │  • fetchLatestPositions()        │    │
│  │  • forceReconnect()      │      │  • latestByPositionId()          │    │
│  │  • suspend()             │      │  • latestForDevices()            │    │
│  │  • resume()              │      │  • Cache with 24h TTL            │    │
│  │  • checkHealth()         │      └──────────────────────────────────┘    │
│  │  • Ping/pong (30s)       │                                               │
│  │  • Exponential backoff   │      ┌──────────────────────────────────┐    │
│  │  • Max 10 retries        │      │  DeviceService                   │    │
│  └──────────────────────────┘      │  (REST API Client)               │    │
│                                     │  • fetchDevices()                │    │
│                                     │  • Cache with 5min TTL           │    │
│                                     └──────────────────────────────────┘    │
└────────────────────────────────────────────────────────────────────────────┘
                │                                        │
                │ WebSocket                              │ HTTP
                │ wss://server/api/socket                │ GET /api/positions
                │                                        │ GET /api/devices
                ▼                                        ▼
┌────────────────────────────────────────────────────────────────────────────┐
│                          TRACCAR SERVER                                     │
│  ┌──────────────────────────┐      ┌──────────────────────────────────┐    │
│  │  WebSocket Endpoint      │      │  REST API Endpoints              │    │
│  │  /api/socket             │      │  /api/devices                    │    │
│  │  • Real-time position    │      │  /api/positions                  │    │
│  │  • Device updates        │      │  /api/positions/{id}             │    │
│  │  • Event notifications   │      │  • Bulk fetch                    │    │
│  └──────────────────────────┘      │  • Time range queries            │    │
│                                     │  • Device filtering              │    │
│                                     └──────────────────────────────────┘    │
└────────────────────────────────────────────────────────────────────────────┘

Data Flows:
[A] Real-time: WebSocket → Repository → Cache → Notifier → UI (< 100ms)
[B] Resume: Lifecycle → WS reconnect + REST fetch → Repository → UI (< 2s)
[C] Selection: Lifecycle → REST fetch → Repository → UI (200-500ms)
[D] Fallback: Timer (45s) → REST fetch → Repository → UI (when WS down)
[E] First Open: didChangeDependencies → REST fetch + WS subscribe → UI (< 1s)
```

---

## 6. Timing Diagram: App Lifecycle Events

```
Time →  0s          5s          10s         15s         20s         25s

App Start
  │
  ├─ MapPage.initState()
  │    └─ Initialize VehicleDataRepository
  │         └─ WebSocket.connect() ──────────┐
  │                                           │
  ├─ MapPage.didChangeDependencies()         │
  │    └─ checkHealth()                      │ WebSocket
  │    └─ refreshAll() ───────────┐          │ Connecting...
  │                                │          │
  │                                │ REST     │
  │                                │ Fetch    │
  │                                ▼          ▼
  ├─ Markers rendered (cache) ──────────┐  Connected!
  │                                      │    │
  │  Fresh data arrives ◄────────────────┘    │
  │  Markers update                           │
  │                                            │
  │  Ping/Pong every 30s ◄────────────────────┤
  │  ├─ Ping (15s) ─────────────────────────► │
  │  ◄─ Pong (latency: 45ms)                  │
  │  ├─ Ping (45s) ─────────────────────────► │
  │  ◄─ Pong (latency: 50ms)                  │
  │                                            │
User minimizes app (10s mark)                 │
  │                                            │
  ├─ AppLifecycleState.paused                 │
  │    └─ suspend() ──────────────────────────►
  │                                        WebSocket closed
                                           Ping timer stopped
                                           Reconnect timer cancelled

... 20 seconds pass (app in background) ...

User returns to app (30s mark)
  │
  ├─ AppLifecycleState.resumed
  │    └─ _onAppResumed()
  │         ├─ forceReconnect() ─────────────┐
  │         │                                 │ WebSocket
  │         │                                 │ Connecting...
  │         │                                 ▼
  │         │                              Connected! (31s)
  │         │                                 │
  │         └─ refreshAll() ──────────┐       │
  │                                   │ REST  │
  │                                   │ Fetch │
  │                                   ▼       │
  │         Fresh data ◄──────────────┘       │
  │         Markers update (32s)              │
  │                                            │
  │         Periodic refresh timer started    │
  │         (every 45s if WS down)            │
  │                                            │
User selects marker (35s mark)                │
  │                                            │
  ├─ _onMarkerTap(id)                         │
  │    └─ refreshDevice(id) ──────┐           │
  │                                │ REST      │
  │                                │ Fetch     │
  │                                ▼           │
  │         Device data ◄──────────┘           │
  │         Detail panel update (35.3s)       │
  │                                            │
  │  Real-time updates ◄──────────────────────┤
  │  (WebSocket messages)                     │
  │  Position changes → markers move          │
  │                                            │
```

---

## 7. Error Recovery Flows

### A. Network Loss Recovery
```
WebSocket Connected
       │
       │ [Network drops]
       │
       ▼
WebSocket Error
       │
       └─► _scheduleReconnect(error)
                │
                ├─ Retry 1 (after 2s) ──► Failed ──┐
                ├─ Retry 2 (after 4s) ──► Failed ──┤
                ├─ Retry 3 (after 8s) ──► Failed ──┤
                ├─ Retry 4 (after 16s) ─► Failed ──┤
                ├─ Retry 5 (after 30s) ─► Failed ──┤
                │                                   │
                │ [Network restored]                │
                │                                   │
                ├─ Retry 6 (after 30s) ─► Success ◄┘
                │
                └─► Connected
                     │
                     └─► Repository fetches missed updates
```

### B. Stale Connection Recovery
```
WebSocket Connected (appears open)
       │
       │ Ping sent (30s timer) ──────────────┐
       │                                     │
       │ [No pong received after 5 minutes]  │
       │                                     │
       ▼                                     │
checkHealth() detects staleness             │
       │                                     │
       └─► forceReconnect()                  │
                │                            │
                └─► Close old socket         │
                │                            │
                └─► Connect new socket ◄─────┘
                │
                └─► Ping/pong resumes
```

### C. App Backgrounded Too Long
```
App Running → User minimizes (suspend WS)
       │
       │ [User leaves app for 1 hour]
       │
       ▼
User returns → AppLifecycleState.resumed
       │
       └─► _onAppResumed()
                │
                ├─► forceReconnect()
                │    │
                │    └─► Fresh WebSocket connection
                │
                └─► refreshAll()
                     │
                     └─► Fetch all positions from last hour
                          │
                          └─► Cache updated
                               │
                               └─► Markers show latest positions
```

---

## Legend

```
┌─────┐
│ Box │  Component or process
└─────┘

  │
  ▼     Data flow direction

─────►  Async operation (network call, timer)

◄─────  Data returned

[Text]  Event or condition

• Item  List item or feature
```

---

These diagrams show how the enhanced WebSocket system handles:
1. **App resume** - Automatic reconnection + fresh data
2. **Device selection** - Immediate server fetch
3. **Map open** - Health check + initial sync
4. **Network loss** - Exponential backoff retry
5. **Stale connection** - Ping/pong detection
6. **Long background** - Full state refresh

All flows converge to ensure markers always show fresh, real-time data without requiring logout/login! 🚀
