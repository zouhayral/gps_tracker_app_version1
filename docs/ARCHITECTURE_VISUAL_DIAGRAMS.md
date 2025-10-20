# Architecture Visual Diagrams

## 1. Overall System Architecture

```
┌─────────────────────────────────────────────────────────────────────────┐
│                         Flutter Application                              │
├─────────────────────────────────────────────────────────────────────────┤
│                                                                           │
│  ┌────────────────────────────────────────────────────────────────┐    │
│  │                     UI Layer (Features)                         │    │
│  │  ┌──────────┐  ┌──────────┐  ┌──────────┐  ┌──────────────┐  │    │
│  │  │   Map    │  │   Auth   │  │Dashboard │  │Notifications │  │    │
│  │  │  Page    │  │   Page   │  │   Page   │  │    Page      │  │    │
│  │  └────┬─────┘  └────┬─────┘  └────┬─────┘  └──────┬───────┘  │    │
│  └───────┼─────────────┼─────────────┼────────────────┼──────────┘    │
│          │             │             │                │                 │
│          │ ref.watch() │             │                │                 │
│          ▼             ▼             ▼                ▼                 │
│  ┌────────────────────────────────────────────────────────────────┐    │
│  │              Riverpod Providers (State Layer)                   │    │
│  │  ┌─────────────────┐  ┌─────────────────┐  ┌────────────────┐ │    │
│  │  │ Map State       │  │ Auth State      │  │ Notifications  │ │    │
│  │  │ Providers       │  │ Notifier        │  │ Provider       │ │    │
│  │  └────────┬────────┘  └────────┬────────┘  └────────┬───────┘ │    │
│  └───────────┼────────────────────┼────────────────────┼─────────┘    │
│              │                    │                    │                │
│              ▼                    ▼                    ▼                │
│  ┌────────────────────────────────────────────────────────────────┐    │
│  │                 Repository Layer                                │    │
│  │  ┌──────────────────┐  ┌──────────────┐  ┌──────────────────┐ │    │
│  │  │ VehicleData      │  │ Auth         │  │ Notifications    │ │    │
│  │  │ Repository       │  │ Service      │  │ Repository       │ │    │
│  │  └────────┬─────────┘  └──────┬───────┘  └────────┬─────────┘ │    │
│  └───────────┼────────────────────┼────────────────────┼─────────┘    │
│              │                    │                    │                │
│              ▼                    ▼                    ▼                │
│  ┌────────────────────────────────────────────────────────────────┐    │
│  │                    Service Layer                                │    │
│  │  ┌──────────┐  ┌──────────┐  ┌──────────┐  ┌──────────┐       │    │
│  │  │ Device   │  │Position  │  │  Event   │  │WebSocket │       │    │
│  │  │ Service  │  │ Service  │  │ Service  │  │ Service  │       │    │
│  │  └────┬─────┘  └────┬─────┘  └────┬─────┘  └────┬─────┘       │    │
│  └───────┼─────────────┼─────────────┼─────────────┼─────────────┘    │
│          │             │             │             │                    │
│          ▼             ▼             ▼             ▼                    │
│  ┌────────────────────────────────────────────────────────────────┐    │
│  │                Persistence & Network Layer                      │    │
│  │  ┌──────────────────────┐        ┌─────────────────────────┐   │    │
│  │  │   ObjectBox DAOs     │        │  Dio HTTP Client        │   │    │
│  │  │  ┌────────────────┐  │        │  ┌──────────────────┐   │   │    │
│  │  │  │ Positions DAO  │  │        │  │ REST API Calls   │   │   │    │
│  │  │  │ Events DAO     │  │        │  │ /api/devices     │   │   │    │
│  │  │  │ Telemetry DAO  │  │        │  │ /api/positions   │   │   │    │
│  │  │  └────────────────┘  │        │  │ /api/events      │   │   │    │
│  │  └──────────────────────┘        │  └──────────────────┘   │   │    │
│  │                                   └─────────────────────────┘   │    │
│  │  ┌──────────────────────┐        ┌─────────────────────────┐   │    │
│  │  │  FMTC Tile Cache     │        │ WebSocket Channel       │   │    │
│  │  │  ┌────────────────┐  │        │ ws://traccar/api/socket │   │    │
│  │  │  │ tiles_osm      │  │        └─────────────────────────┘   │    │
│  │  │  │ tiles_esri_sat │  │                                       │    │
│  │  │  └────────────────┘  │                                       │    │
│  │  └──────────────────────┘                                       │    │
│  └────────────────────────────────────────────────────────────────┘    │
│                                                                           │
└─────────────────────────────────────────────────────────────────────────┘
```

---

## 2. WebSocket Data Flow (Real-time Updates)

```
┌──────────────────────────────────────────────────────────────────────┐
│                  Traccar Server (Backend)                             │
│                  ws://your-server/api/socket                         │
└─────────────────────────────┬────────────────────────────────────────┘
                              │
                              │ WebSocket Connection
                              │ (with JSESSIONID cookie)
                              ▼
┌──────────────────────────────────────────────────────────────────────┐
│              TraccarSocketService (Raw WebSocket)                     │
│  - Auto-reconnect with exponential backoff                           │
│  - Circuit breaker (hostname validation)                             │
│  - Emits: TraccarSocketMessage {type, payload, positions}            │
└─────────────────────────────┬────────────────────────────────────────┘
                              │
                              │ Stream<TraccarSocketMessage>
                              ▼
┌──────────────────────────────────────────────────────────────────────┐
│         customerWebSocketProvider (StreamProvider)                    │
│  Discriminates messages into typed variants:                         │
│  ┌──────────────────────────────────────────────────────────────┐   │
│  │ • type='connected' → CustomerConnectedMessage()              │   │
│  │ • type='positions' → CustomerPositionsMessage(List<Position>)│   │
│  │ • type='events'    → CustomerEventsMessage(dynamic events)   │   │
│  │ • type='devices'   → CustomerDevicesMessage(dynamic devices) │   │
│  │ • type='error'     → CustomerErrorMessage(String error)      │   │
│  └──────────────────────────────────────────────────────────────┘   │
└─────────────────────────────┬────────────────────────────────────────┘
                              │
                              │ Branching to domain-specific providers
          ┌───────────────────┼───────────────────┐
          ▼                   ▼                   ▼
┌──────────────────┐  ┌──────────────────┐  ┌──────────────────┐
│ Positions        │  │ Events           │  │ Devices          │
│ Provider         │  │ Provider         │  │ Provider         │
├──────────────────┤  ├──────────────────┤  ├──────────────────┤
│ Maintains:       │  │ Maintains:       │  │ Maintains:       │
│ Map<int,Position>│  │ List<Event>      │  │ List<Device>     │
│                  │  │                  │  │                  │
│ Updates on:      │  │ Updates on:      │  │ Updates on:      │
│ CustomerPositions│  │ CustomerEvents   │  │ CustomerDevices  │
│ Message          │  │ Message          │  │ Message          │
└────────┬─────────┘  └────────┬─────────┘  └────────┬─────────┘
         │                     │                     │
         │                     │                     │
         ▼                     ▼                     ▼
┌──────────────────┐  ┌──────────────────┐  ┌──────────────────┐
│ Optional:        │  │ Optional:        │  │ Optional:        │
│ Repository Layer │  │ Repository Layer │  │ Repository Layer │
├──────────────────┤  ├──────────────────┤  ├──────────────────┤
│ • Merges with    │  │ • Persists to    │  │ • Caches to      │
│   REST API       │  │   EventsDao      │  │   SharedPrefs    │
│ • Caches to      │  │ • Merges API     │  │ • Merges API     │
│   ObjectBox      │  │   history        │  │   data           │
└────────┬─────────┘  └────────┬─────────┘  └────────┬─────────┘
         │                     │                     │
         │                     │                     │
         ▼                     ▼                     ▼
┌──────────────────┐  ┌──────────────────┐  ┌──────────────────┐
│ UI Layer         │  │ UI Layer         │  │ UI Layer         │
│ (MapPage)        │  │ (Notifications   │  │ (Dashboard)      │
│                  │  │  Page)           │  │                  │
│ ref.watch(       │  │ ref.watch(       │  │ ref.watch(       │
│  positions       │  │  notifications   │  │  devices         │
│  Provider)       │  │  Provider)       │  │  Provider)       │
│                  │  │                  │  │                  │
│ → Auto rebuild   │  │ → Auto rebuild   │  │ → Auto rebuild   │
│   markers        │  │   list           │  │   list           │
└──────────────────┘  └──────────────────┘  └──────────────────┘
```

---

## 3. Map Feature Architecture

```
┌─────────────────────────────────────────────────────────────────────┐
│                        Map Feature (lib/features/map/)              │
├─────────────────────────────────────────────────────────────────────┤
│                                                                       │
│  ┌─────────────────────────────────────────────────────────────┐   │
│  │                     View Layer                               │   │
│  │  ┌──────────────┐  ┌──────────────┐  ┌──────────────────┐  │   │
│  │  │   MapPage    │  │ FlutterMap   │  │  Debug Overlays  │  │   │
│  │  │ (main view)  │  │   Adapter    │  │  - Cluster HUD   │  │   │
│  │  │              │  │              │  │  - FPS Monitor   │  │   │
│  │  │ 2000+ lines  │  │ Wraps flutter│  │  - Rebuild Count │  │   │
│  │  │ ConsumerState│  │ _map widget  │  │                  │  │   │
│  │  └──────┬───────┘  └──────┬───────┘  └──────────────────┘  │   │
│  └─────────┼──────────────────┼──────────────────────────────┘   │
│            │                  │                                    │
│            ▼                  ▼                                    │
│  ┌─────────────────────────────────────────────────────────────┐   │
│  │               Controller Layer                               │   │
│  │  ┌──────────────────────────────────────────────────────┐   │   │
│  │  │ FleetMapTelemetryController (NotifierProvider)       │   │   │
│  │  │  - Manages device fetching                           │   │   │
│  │  │  - Coordinates telemetry updates                     │   │   │
│  │  │  - State: loading, error, data                       │   │   │
│  │  └──────────────────────────────────────────────────────┘   │   │
│  │                                                               │   │
│  │  ┌──────────────────────────────────────────────────────┐   │   │
│  │  │ MarkerMotionController (Stateful Object)             │   │   │
│  │  │  - Smooth interpolation (200ms tick, 1200ms duration)│   │   │
│  │  │  - Dead-reckoning extrapolation (speed-based)        │   │   │
│  │  │  - Per-device ValueNotifier<LatLng>                  │   │   │
│  │  │  - globalTick ValueNotifier for batch updates        │   │   │
│  │  └──────────────────────────────────────────────────────┘   │   │
│  └───────────────────────────────────────────────────────────┘   │
│                                                                     │
│  ┌─────────────────────────────────────────────────────────────┐   │
│  │                  Clustering System                           │   │
│  │  ┌───────────────────────────────────────────────────────┐  │   │
│  │  │ clusterProvider (NotifierProvider)                    │  │   │
│  │  │  - 250ms debounce on zoom/pan                         │  │   │
│  │  │  - Spawns isolate for 800+ markers                    │  │   │
│  │  │  - Publishes telemetry metrics                        │  │   │
│  │  └─────────────────────┬─────────────────────────────────┘  │   │
│  │                        │                                     │   │
│  │                        ▼                                     │   │
│  │  ┌───────────────────────────────────────────────────────┐  │   │
│  │  │ ClusterEngine (Pure Function)                         │  │   │
│  │  │  - Grid-based O(n) algorithm                          │  │   │
│  │  │  - Zoom-aware density thresholds (1-13)               │  │   │
│  │  │  - Returns: List<Marker> + List<Cluster>              │  │   │
│  │  └───────────────────────────────────────────────────────┘  │   │
│  │                                                               │   │
│  │  ┌───────────────────────────────────────────────────────┐  │   │
│  │  │ ClusterBadgeCache (LRU Cache)                         │  │   │
│  │  │  - 50 entry capacity                                  │  │   │
│  │  │  - PNG image caching                                  │  │   │
│  │  │  - Color-coded by count                               │  │   │
│  │  │  - 73% hit rate typical                               │  │   │
│  │  └───────────────────────────────────────────────────────┘  │   │
│  └─────────────────────────────────────────────────────────────┘   │
│                                                                     │
│  ┌─────────────────────────────────────────────────────────────┐   │
│  │                    Data Layer                                │   │
│  │  ┌──────────────────────────────────────────────────────┐   │   │
│  │  │ positionsLiveProvider (StreamProvider)               │   │   │
│  │  │  - Listens to WebSocket                              │   │   │
│  │  │  - Yields Map<int, Position>                         │   │   │
│  │  └──────────────────────────────────────────────────────┘   │   │
│  │                                                               │   │
│  │  ┌──────────────────────────────────────────────────────┐   │   │
│  │  │ positionsLastKnownProvider (FutureProvider)          │   │   │
│  │  │  - Merges ObjectBox + live data                      │   │   │
│  │  │  - Fallback for offline mode                         │   │   │
│  │  └──────────────────────────────────────────────────────┘   │   │
│  │                                                               │   │
│  │  ┌──────────────────────────────────────────────────────┐   │   │
│  │  │ vehiclePositionProvider.family(deviceId)             │   │   │
│  │  │  - Per-device position stream                        │   │   │
│  │  │  - Feeds motion controller                           │   │   │
│  │  └──────────────────────────────────────────────────────┘   │   │
│  └─────────────────────────────────────────────────────────────┘   │
│                                                                     │
│  ┌─────────────────────────────────────────────────────────────┐   │
│  │                Core Map Utilities                            │   │
│  │  ┌──────────────┐  ┌──────────────┐  ┌──────────────────┐  │   │
│  │  │ Marker Icon  │  │ Marker       │  │ Marker Performance│  │   │
│  │  │ Manager      │  │ Generator    │  │ Monitor           │  │   │
│  │  └──────────────┘  └──────────────┘  └──────────────────┘  │   │
│  │                                                               │   │
│  │  ┌──────────────┐  ┌──────────────┐  ┌──────────────────┐  │   │
│  │  │ Modern Marker│  │ Bitmap       │  │ Enhanced Marker   │  │   │
│  │  │ Cache        │  │ Descriptor   │  │ Cache             │  │   │
│  │  │              │  │ Cache        │  │                   │  │   │
│  │  └──────────────┘  └──────────────┘  └──────────────────┘  │   │
│  └─────────────────────────────────────────────────────────────┘   │
│                                                                     │
└─────────────────────────────────────────────────────────────────────┘
```

---

## 4. Notification System Architecture (To Be Implemented)

```
┌─────────────────────────────────────────────────────────────────────┐
│            Notification Feature (lib/features/notifications/)        │
├─────────────────────────────────────────────────────────────────────┤
│                                                                       │
│  ┌─────────────────────────────────────────────────────────────┐   │
│  │                     View Layer                               │   │
│  │  ┌──────────────────┐  ┌──────────────────┐                 │   │
│  │  │ Notifications    │  │ Notification     │                 │   │
│  │  │ Page             │  │ Toast Listener   │                 │   │
│  │  │                  │  │                  │                 │   │
│  │  │ - List view      │  │ - SnackBar       │                 │   │
│  │  │ - Pull refresh   │  │   overlay        │                 │   │
│  │  │ - Filter sheet   │  │ - ref.listen()   │                 │   │
│  │  └────────┬─────────┘  └────────┬─────────┘                 │   │
│  │           │                     │                            │   │
│  │           │ ref.watch()         │ ref.listen()               │   │
│  │           ▼                     ▼                            │   │
│  └─────────────────────────────────────────────────────────────┘   │
│                                                                     │
│  ┌─────────────────────────────────────────────────────────────┐   │
│  │                  Controller Layer                            │   │
│  │  ┌──────────────────────────────────────────────────────┐   │   │
│  │  │ NotificationsNotifier (StateNotifier)                │   │   │
│  │  │                                                       │   │   │
│  │  │ State: NotificationsState {                          │   │   │
│  │  │   events: List<Event>,                               │   │   │
│  │  │   isLoading: bool,                                   │   │   │
│  │  │   error: String?,                                    │   │   │
│  │  │   hasMore: bool                                      │   │   │
│  │  │ }                                                     │   │   │
│  │  │                                                       │   │   │
│  │  │ Methods:                                              │   │   │
│  │  │  - refresh()                                          │   │   │
│  │  │  - loadMore()                                         │   │   │
│  │  │  - filterByDevice(deviceId)                          │   │   │
│  │  │  - filterByType(type)                                │   │   │
│  │  │  - markAsRead(eventId)                               │   │   │
│  │  └──────────────────────────────────────────────────────┘   │   │
│  └─────────────────────────────────────────────────────────────┘   │
│                                                                     │
│  ┌─────────────────────────────────────────────────────────────┐   │
│  │                   Provider Layer                             │   │
│  │  ┌──────────────────────────────────────────────────────┐   │   │
│  │  │ notificationsStreamProvider (StreamProvider)         │   │   │
│  │  │  - Real-time event stream                            │   │   │
│  │  │  - Auto-updates from WebSocket + Repository          │   │   │
│  │  └────────────────────────┬─────────────────────────────┘   │   │
│  │                            │                                  │   │
│  │  ┌─────────────────────────┼────────────────────────────┐   │   │
│  │  │ filteredNotificationsProvider.family(filter)         │   │   │
│  │  │  - Applies device/type/unread filters                │   │   │
│  │  └──────────────────────────────────────────────────────┘   │   │
│  │                                                               │   │
│  │  ┌──────────────────────────────────────────────────────┐   │   │
│  │  │ unreadNotificationCountProvider (Provider)           │   │   │
│  │  │  - For badge count in app bar                        │   │   │
│  │  └──────────────────────────────────────────────────────┘   │   │
│  │                                                               │   │
│  │  ┌──────────────────────────────────────────────────────┐   │   │
│  │  │ liveNotificationEventProvider (StreamProvider)       │   │   │
│  │  │  - Single event stream for toast notifications       │   │   │
│  │  └──────────────────────────────────────────────────────┘   │   │
│  └─────────────────────────────────────────────────────────────┘   │
│                                                                     │
│  ┌─────────────────────────────────────────────────────────────┐   │
│  │                  Repository Layer                            │   │
│  │  ┌──────────────────────────────────────────────────────┐   │   │
│  │  │ NotificationsRepository                              │   │   │
│  │  │                                                       │   │   │
│  │  │ Responsibilities:                                     │   │   │
│  │  │  - Listen to customerWebSocketProvider               │   │   │
│  │  │  - Process CustomerEventsMessage                     │   │   │
│  │  │  - Persist to EventsDao (ObjectBox)                  │   │   │
│  │  │  - Merge with REST API (EventService)                │   │   │
│  │  │  - Expose Stream<List<Event>>                        │   │   │
│  │  │                                                       │   │   │
│  │  │ Data Flow:                                            │   │   │
│  │  │  WebSocket → EventEntity → ObjectBox                 │   │   │
│  │  │  REST API → Event → EventEntity → ObjectBox          │   │   │
│  │  │  ObjectBox → Event → Stream → UI                     │   │   │
│  │  └──────────────────────────────────────────────────────┘   │   │
│  └─────────────────────────────────────────────────────────────┘   │
│                                                                     │
│  ┌─────────────────────────────────────────────────────────────┐   │
│  │                   Service Layer                              │   │
│  │  ┌──────────────────────────────────────────────────────┐   │   │
│  │  │ EventService (NEW)                                   │   │   │
│  │  │  - fetchEvents(deviceId, from, to, type)             │   │   │
│  │  │  - markEventAsRead(eventId)                          │   │   │
│  │  │  - clearAllEvents()                                  │   │   │
│  │  │  - Uses Dio for REST API calls                       │   │   │
│  │  └──────────────────────────────────────────────────────┘   │   │
│  └─────────────────────────────────────────────────────────────┘   │
│                                                                     │
│  ┌─────────────────────────────────────────────────────────────┐   │
│  │              Persistence Layer (EXISTING)                    │   │
│  │  ┌──────────────────────────────────────────────────────┐   │   │
│  │  │ EventsDao (ObjectBox)                                │   │   │
│  │  │  - insert(EventEntity)                               │   │   │
│  │  │  - upsert(EventEntity)                               │   │   │
│  │  │  - getRecent(deviceId, type, limit)                  │   │   │
│  │  │  - getByDeviceAndType(deviceId, type)                │   │   │
│  │  │  - getUnreadCount()                                  │   │   │
│  │  │  - deleteOlderThan(timestamp)                        │   │   │
│  │  └──────────────────────────────────────────────────────┘   │   │
│  │                                                               │   │
│  │  ┌──────────────────────────────────────────────────────┐   │   │
│  │  │ EventEntity (ObjectBox Entity)                       │   │   │
│  │  │  - id, eventId, deviceId, eventType                  │   │   │
│  │  │  - eventTimeMs, positionId, geofenceId               │   │   │
│  │  │  - priority, severity, message                       │   │   │
│  │  │  - attributesJson                                    │   │   │
│  │  │  - @Index() on key fields                            │   │   │
│  │  └──────────────────────────────────────────────────────┘   │   │
│  └─────────────────────────────────────────────────────────────┘   │
│                                                                     │
└─────────────────────────────────────────────────────────────────────┘
```

---

## 5. Repository Pattern Detail

```
┌───────────────────────────────────────────────────────────────────┐
│                  VehicleDataRepository Pattern                     │
├───────────────────────────────────────────────────────────────────┤
│                                                                     │
│  Consumer requests data via:                                       │
│    ref.watch(vehicleDataRepositoryProvider)                        │
│                                                                     │
│                           │                                         │
│                           ▼                                         │
│  ┌────────────────────────────────────────────────────────────┐   │
│  │         VehicleDataRepository (Singleton)                   │   │
│  │                                                              │   │
│  │  Dependencies (injected via Riverpod):                      │   │
│  │    - VehicleDataCache (SharedPreferences)                   │   │
│  │    - DeviceService (REST API)                               │   │
│  │    - PositionsService (REST API)                            │   │
│  │    - TraccarSocketService (WebSocket)                       │   │
│  │    - TelemetryDao (ObjectBox)                               │   │
│  │                                                              │   │
│  │  Internal State:                                             │   │
│  │    - Map<int, ValueNotifier<VehicleDataSnapshot?>>          │   │
│  │      ↑ Per-device notifiers for reactive updates            │   │
│  │                                                              │   │
│  │    - Map<int, Timer> _debounceTimers                         │   │
│  │      ↑ Prevents update flooding (250ms debounce)            │   │
│  │                                                              │   │
│  │    - Map<int, DateTime> _lastFetchTime                       │   │
│  │      ↑ Memoization to avoid redundant API calls             │   │
│  │                                                              │   │
│  │  Methods:                                                    │   │
│  │    - getNotifier(deviceId) → ValueNotifier                   │   │
│  │    - refreshAll() → fetch devices + positions                │   │
│  │    - refreshDevice(deviceId) → fetch single device           │   │
│  │    - setOffline(bool) → guard REST calls when offline        │   │
│  └────────────────────────────────────────────────────────────┘   │
│                           │                                         │
│                           │ Data sources                            │
│                  ┌────────┼────────┐                                │
│                  │        │        │                                │
│                  ▼        ▼        ▼                                │
│         ┌─────────┐  ┌────────┐  ┌──────────┐                      │
│         │ REST    │  │WebSocket│ │ObjectBox │                      │
│         │ API     │  │Live     │ │Cache     │                      │
│         │         │  │Updates  │ │          │                      │
│         │/api/    │  │/api/    │ │TelemetryDao                      │
│         │devices  │  │socket   │ │PositionsDao                      │
│         │/api/    │  │         │ │          │                      │
│         │positions│  │         │ │          │                      │
│         └─────────┘  └────────┘  └──────────┘                      │
│                           │                                         │
│                           │ Merged data                             │
│                           ▼                                         │
│         ┌──────────────────────────────────────────┐               │
│         │    VehicleDataSnapshot (Value Object)    │               │
│         │                                           │               │
│         │  - device: Device                         │               │
│         │  - position: Position?                    │               │
│         │  - telemetry: Telemetry?                  │               │
│         │  - lastUpdate: DateTime                   │               │
│         │  - isStale: bool                          │               │
│         └──────────────────────────────────────────┘               │
│                           │                                         │
│                           │ Notifies listeners                      │
│                           ▼                                         │
│         ┌──────────────────────────────────────────┐               │
│         │  ValueNotifier<VehicleDataSnapshot?>     │               │
│         │    .notifyListeners()                     │               │
│         └──────────────────────────────────────────┘               │
│                           │                                         │
│                           │ UI subscribes                           │
│                           ▼                                         │
│         ┌──────────────────────────────────────────┐               │
│         │  MapPage / Dashboard / Widgets            │               │
│         │    - ValueListenableBuilder OR            │               │
│         │    - ref.watch(positionByDeviceProvider)  │               │
│         └──────────────────────────────────────────┘               │
│                                                                     │
│  Benefits:                                                          │
│    ✅ Single source of truth                                        │
│    ✅ Automatic cache invalidation                                  │
│    ✅ Debounced updates prevent UI flooding                         │
│    ✅ Offline-first with fallback strategies                        │
│    ✅ Per-device isolation (no cascade rebuilds)                    │
│    ✅ Testable (dependencies injected)                              │
│                                                                     │
└───────────────────────────────────────────────────────────────────┘
```

---

**End of Visual Diagrams**
