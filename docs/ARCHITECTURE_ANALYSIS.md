# Flutter GPS Tracker - Complete Architectural Analysis

**Generated:** October 20, 2025  
**Branch:** feat/notification-page  
**Purpose:** Guide notification system integration and future feature development

---

## Executive Summary

This is a **Feature-First + Repository Pattern Hybrid** architecture with clean separation of concerns:

- **State Management:** Riverpod 2.x (Providers, Notifiers, StreamProviders)
- **Data Layer:** Repository pattern + ObjectBox persistence + FMTC tile caching
- **UI Layer:** Feature modules with controller/view separation
- **Real-time:** WebSocket (Traccar) → Provider pipeline → UI reactivity
- **Performance:** Isolate-based clustering, marker caching, debounced rebuilds

**Strengths:**
✅ Clean feature boundaries  
✅ Reactive data flow with Riverpod  
✅ Excellent performance optimizations (isolates, caching, throttling)  
✅ Comprehensive documentation  

**Areas for Improvement:**
⚠️ Some mixed concerns (lib/map/ folder vs lib/features/map/)  
⚠️ Empty placeholder files (event_service.dart, event.dart model)  
⚠️ Notification system is stubbed but not implemented  

---

## 1. Folder Structure Analysis

### Current Organization

```
lib/
├── main.dart                      # Entry point: FMTC init, HTTP overrides, Riverpod
├── objectbox.g.dart              # Generated ObjectBox bindings
├── objectbox-model.json          # ObjectBox schema
│
├── app/                          # ❌ MIXED: app_root.dart here, app_router.dart missing
├── app.dart/                     # ❌ DUPLICATE: Empty or minimal, conflicts with app/
│
├── core/                         # ✅ GOOD: Shared infrastructure
│   ├── data/                     # Repository pattern (VehicleDataRepository)
│   ├── database/                 # ObjectBox DAOs + entities
│   ├── debug/                    # Rebuild profilers, diagnostics
│   ├── di/                       # Dependency injection (if used)
│   ├── diagnostics/              # Performance monitoring
│   ├── env/                      # Environment config
│   ├── logging/                  # Logging utilities
│   ├── map/                      # ⚠️ MIXED: Map-specific core (markers, motion, clustering)
│   ├── network/                  # HTTP clients, interceptors
│   ├── observers/                # Lifecycle observers
│   ├── providers/                # Core-level providers
│   ├── services/                 # Core services
│   ├── storage/                  # Storage utilities
│   ├── sync/                     # Sync orchestration
│   └── utils/                    # Helper functions
│
├── data/                         # ✅ Data layer (models + repositories)
│   ├── models/                   # Domain models (device, event, position, trip, user)
│   └── repositories/             # Data access abstractions
│
├── domain/                       # ✅ Clean Architecture domain layer
│   ├── entities/                 # Business entities
│   └── usecases/                 # Business logic
│
├── features/                     # ✅ EXCELLENT: Feature-first organization
│   ├── auth/
│   │   ├── controller/           # AuthNotifier, AuthState
│   │   └── presentation/         # Login/logout UI
│   ├── dashboard/
│   │   └── controller/           # DevicesNotifier (device list state)
│   ├── map/                      # ⭐ PRIMARY FEATURE
│   │   ├── clustering/           # Cluster engine, badge cache, spiderfy
│   │   ├── controller/           # FleetMapTelemetryController
│   │   ├── core/                 # Map-specific core logic
│   │   ├── data/                 # Position model, live/last-known providers
│   │   ├── providers/            # Map state providers, isolated notifiers
│   │   └── view/                 # MapPage, FlutterMapAdapter, overlays
│   ├── notifications/            # ⚠️ STUB: Only placeholder page
│   │   └── view/
│   │       └── notifications_page.dart  # Empty placeholder
│   ├── settings/
│   ├── telemetry/
│   ├── testing/
│   ├── trips/
│   └── widgets/                  # Shared feature widgets
│
├── map/                          # ⚠️ DUPLICATE: FMTC config, tile probes (should be in core/map/)
│   ├── fmtc_config.dart
│   ├── tile_http_overrides.dart
│   ├── tile_network_client.dart
│   └── tile_probe.dart
│
├── prefetch/                     # Prefetch orchestration
│
├── providers/                    # ✅ Top-level app-wide providers
│   ├── connectivity_provider.dart       # Network state management
│   ├── map_rebuild_provider.dart        # Map rebuild coordination
│   ├── multi_customer_providers.dart    # ⭐ Customer session + trips + notifications
│   └── prefetch_provider.dart           # Prefetch orchestration
│
├── services/                     # ✅ Service layer (network, persistence, business logic)
│   ├── auth_service.dart         # Authentication, session management
│   ├── customer/                 # ⭐ Multi-customer support (new)
│   │   ├── customer_credentials.dart    # Credentials state
│   │   ├── customer_device_positions.dart  # Real-time position map
│   │   ├── customer_manager.dart        # Login/logout orchestration
│   │   ├── customer_service.dart        # Barrel export
│   │   ├── customer_session.dart        # Session validation
│   │   └── customer_websocket.dart      # WebSocket adapter (typed messages)
│   ├── device_service.dart       # Device CRUD operations
│   ├── device_update_service.dart
│   ├── event_service.dart        # ❌ EMPTY: Placeholder file
│   ├── fmtc_initializer.dart     # FMTC initialization
│   ├── geofence_service.dart
│   ├── positions_service.dart    # Position API calls
│   ├── sync_service.dart
│   ├── traccar_connection_provider.dart
│   ├── traccar_socket_service.dart  # ⭐ WebSocket implementation
│   ├── trip_service.dart
│   ├── websocket_manager.dart
│   ├── websocket_manager_enhanced.dart
│   ├── websocket_service.dart
│   └── ws_connect_*.dart         # Platform-specific WebSocket connectors
│
├── theme/                        # App theming
├── utils/                        # App-level utilities
└── widgets/                      # Global reusable widgets
```

---

## 2. Architecture Style: **Hybrid (Feature-First + Repository + Clean)**

### Pattern Recognition

**Feature-First (Primary)**
- Features are self-contained modules under `lib/features/`
- Each feature has: `controller/`, `view/`, `data/`, `providers/`
- Example: `features/map/` contains all map-related code

**Repository Pattern**
- `VehicleDataRepository` centralizes data access
- Abstracts REST API + WebSocket + ObjectBox persistence
- Exposes per-device `ValueNotifier<VehicleDataSnapshot>`

**Clean Architecture Elements**
- `domain/` layer with entities and use cases
- `data/` layer with models and repositories
- Clear separation of concerns

**Riverpod State Management**
- Providers as dependency injection + state holders
- Hierarchical provider structure (session → websocket → positions)
- Auto-dispose for lifecycle management

---

## 3. State Management Patterns

### Riverpod Provider Types Used

| Provider Type | Usage | Examples |
|--------------|-------|----------|
| **Provider** | Singleton services, immutable state | `authServiceProvider`, `vehicleDataRepositoryProvider` |
| **StateProvider** | Mutable simple state | `customerCredentialsProvider` |
| **FutureProvider** | Async data loading | `customerSessionProvider`, `tripsProvider` |
| **StreamProvider** | Real-time data streams | `customerWebSocketProvider`, `positionsLiveProvider`, `notificationsProvider` |
| **NotifierProvider** | Complex stateful logic | `devicesNotifierProvider`, `webSocketManagerProvider` |
| **Family** | Parameterized providers | `vehiclePositionProvider(deviceId)`, `deviceByIdProvider(deviceId)` |

### Data Flow Patterns

**Pattern 1: WebSocket → Provider Pipeline → UI**
```
TraccarSocketService.connect()
  ↓ (raw WebSocket messages)
customerWebSocketProvider (StreamProvider)
  ↓ (typed messages: CustomerPositionsMessage, CustomerEventsMessage)
customerDevicePositionsProvider (StreamProvider)
  ↓ (Map<int, Position>)
UI: ref.watch(customerDevicePositionsProvider)
  ↓ (automatic rebuild on new data)
```

**Pattern 2: Repository + ValueNotifier**
```
VehicleDataRepository
  ↓ (maintains per-device notifiers)
_notifiers[deviceId]: ValueNotifier<VehicleDataSnapshot>
  ↓ (merges REST + WebSocket + cache)
UI: ValueListenableBuilder or ref.watch(positionByDeviceProvider(deviceId))
```

**Pattern 3: Isolate-Based Computation**
```
User zooms map → clusterProvider.notifier.computeClusters()
  ↓ (debounced 250ms)
if (markers > 800) → spawn isolate
  ↓ (SendPort/ReceivePort)
cluster_isolate.dart computes in background
  ↓ (returns ClusterResult)
UI rebuilds with clustered markers
```

### UI Update Origins

| Source | Mechanism | Performance Strategy |
|--------|-----------|---------------------|
| WebSocket | `ref.listen()` + `ref.watch()` | Debounced updates, throttled notifiers |
| Repository | `ValueListenable` + `notifyListeners()` | Per-device isolation, no cascade rebuilds |
| User Input | `ref.read().notifier.method()` | Immediate state update |
| Async API | `FutureProvider.future` | Loading/error states with AsyncValue |
| Timer/Periodic | `MarkerMotionController.globalTick` | 200ms tick, cubic easing interpolation |

---

## 4. Data Flow Architecture

### Complete Pipeline: WebSocket → UI

```
┌─────────────────────────────────────────────────────────────┐
│ 1. WebSocket Layer                                          │
├─────────────────────────────────────────────────────────────┤
│ TraccarSocketService                                         │
│  - Connects to /api/socket with JSESSIONID                  │
│  - Emits TraccarSocketMessage {type, payload, positions}    │
│  - Auto-reconnect with exponential backoff                  │
│  - Circuit breaker prevents retry storms                    │
└─────────────────────────────────────────────────────────────┘
                         ↓
┌─────────────────────────────────────────────────────────────┐
│ 2. Typed Message Adapter                                    │
├─────────────────────────────────────────────────────────────┤
│ customerWebSocketProvider (StreamProvider)                  │
│  - Wraps TraccarSocketService                               │
│  - Discriminates messages:                                  │
│    • CustomerConnectedMessage                               │
│    • CustomerPositionsMessage(List<Position>)               │
│    • CustomerEventsMessage(dynamic events)                  │
│    • CustomerDevicesMessage(dynamic devices)                │
│    • CustomerErrorMessage(String error)                     │
└─────────────────────────────────────────────────────────────┘
                         ↓
┌─────────────────────────────────────────────────────────────┐
│ 3. Domain-Specific Providers                                │
├─────────────────────────────────────────────────────────────┤
│ customerDevicePositionsProvider (StreamProvider)            │
│  - Maintains Map<int, Position>                             │
│  - Yields immutable map on each update                      │
│  - Triggers UI rebuild via ref.watch()                      │
│                                                              │
│ notificationsProvider (StreamProvider) [STUB]               │
│  - Listens to CustomerEventsMessage                         │
│  - Merges API notifications + live events                   │
│  - Yields List<Map<String, dynamic>>                        │
│                                                              │
│ liveNotificationEventsProvider (StreamProvider) [STUB]      │
│  - Streams individual events for toast notifications        │
└─────────────────────────────────────────────────────────────┘
                         ↓
┌─────────────────────────────────────────────────────────────┐
│ 4. Repository Layer (Optional Caching)                      │
├─────────────────────────────────────────────────────────────┤
│ VehicleDataRepository                                        │
│  - Listens to WebSocket via socketService.connect()        │
│  - Merges with REST API fallback                            │
│  - Persists to ObjectBox (EventsDao, TelemetryDao)          │
│  - Exposes per-device ValueNotifier<VehicleDataSnapshot>    │
│  - Debounces updates (250ms default)                        │
└─────────────────────────────────────────────────────────────┘
                         ↓
┌─────────────────────────────────────────────────────────────┐
│ 5. UI Layer                                                  │
├─────────────────────────────────────────────────────────────┤
│ MapPage (ConsumerStatefulWidget)                            │
│  - ref.watch(devicesNotifierProvider)                       │
│  - ref.listen(vehiclePositionProvider(deviceId), ...)       │
│  - Feeds MarkerMotionController for smooth animation        │
│  - Rebuilds only affected markers (not entire map)          │
│                                                              │
│ NotificationsPage (StatelessWidget) [PLACEHOLDER]           │
│  - TODO: ref.watch(notificationsProvider)                   │
│  - TODO: ref.listen(liveNotificationEventsProvider, ...)    │
└─────────────────────────────────────────────────────────────┘
```

### Async Caching: FMTC Tile System

```
User pans/zooms map
  ↓
FlutterMapAdapter requests tiles
  ↓
FMTC TileProvider checks cache
  ├─ HIT → return cached tile (instant)
  └─ MISS → download tile
       ↓
     Store in ObjectBox (tiles_osm or tiles_esri_sat)
       ↓
     Return to map
```

**Key Features:**
- Dual stores: `tiles_osm` (OpenStreetMap), `tiles_esri_sat` (Satellite)
- Offline mode: `hit-only` (no downloads when offline)
- Prefetch system: Profiles (Light, Commute, Heavy), rate-limited (2000 tiles/hour)
- Connectivity-aware: Auto-pauses prefetch when offline

### MarkerMotionController: Interpolation Engine

```
WebSocket position update → VehiclePositionProvider
  ↓
MapPage._setupPositionListenersInBuild()
  ↓
_motionController.updatePosition(deviceId, target, speed, course)
  ↓
Timer.periodic(200ms) → _onTick()
  ↓
Cubic easing interpolation (1200ms duration)
  ↓
Dead-reckoning extrapolation (speed ≥ 3 km/h, max 8s)
  ↓
globalTick.notifyListeners()
  ↓
_onMotionTick() → _scheduleMarkerUpdate()
  ↓
_processMarkersAsync() merges interpolated positions
  ↓
ValueListenableBuilder<List<Marker>> rebuilds markers only
```

**Performance:** 5 FPS animation, no full map rebuilds, background isolate for 800+ markers

---

## 5. Modularity Assessment

### Reusable Components

| Component | Location | Reusability | Dependencies |
|-----------|----------|-------------|--------------|
| **AuthService** | `services/auth_service.dart` | ⭐⭐⭐ High | Dio, FlutterSecureStorage |
| **VehicleDataRepository** | `core/data/vehicle_data_repository.dart` | ⭐⭐⭐ High | DeviceService, PositionsService, ObjectBox |
| **MarkerMotionController** | `core/map/marker_motion_controller.dart` | ⭐⭐⭐ High | latlong2, Flutter foundation |
| **TraccarSocketService** | `services/traccar_socket_service.dart` | ⭐⭐ Medium | AuthService, WebSocketChannel |
| **CustomerWebSocket** | `services/customer/customer_websocket.dart` | ⭐⭐ Medium | TraccarSocketService, CustomerSession |
| **Cluster System** | `features/map/clustering/` | ⭐⭐⭐ High | Standalone isolate logic |
| **FMTC Config** | `map/fmtc_config.dart` | ⭐⭐ Medium | flutter_map_tile_caching |

### Shared Modules

**Map Module** (`features/map/`)
- Used by: Dashboard (device list), Trips (route visualization), Geofences
- Exposes: FlutterMapAdapter, MarkerGenerator, ClusterEngine

**Vehicle Module** (implicit via VehicleDataRepository)
- Used by: Map, Dashboard, Telemetry, Trips
- Exposes: Device list, Position streams, Telemetry history

**Customer Module** (`services/customer/`)
- Used by: Multi-customer scenarios, Auth, WebSocket
- Exposes: Session validation, Credentials storage, Typed WebSocket messages

---

## 6. Integration Points for Notification System

### Current State

**Existing Infrastructure:**
✅ WebSocket message type: `CustomerEventsMessage`  
✅ ObjectBox entity: `EventEntity` with full schema  
✅ DAO: `EventsDao` with query methods  
✅ Provider stub: `notificationsProvider` in `multi_customer_providers.dart`  
✅ Provider stub: `liveNotificationEventsProvider`  
✅ UI placeholder: `NotificationsPage`  

**Missing Components:**
❌ Domain model: `lib/data/models/event.dart` is empty  
❌ Service layer: `lib/services/event_service.dart` is empty  
❌ Full implementation of notification providers  
❌ UI implementation of NotificationsPage  

### Recommended File Placement

```
lib/
├── data/
│   └── models/
│       └── event.dart                              # ✅ CREATE: Domain model
│           - class Event with fromJson/toJson
│           - fields: id, deviceId, type, timestamp, message, severity, etc.
│
├── services/
│   ├── event_service.dart                          # ✅ CREATE: Service layer
│   │   - fetchEvents(deviceId, from, to)
│   │   - markEventAsRead(eventId)
│   │   - clearAllEvents()
│   │   - Dio/HTTP client for REST API
│   │
│   └── customer/
│       └── (existing files unchanged)
│
├── features/
│   └── notifications/
│       ├── controller/                             # ✅ CREATE: Business logic
│       │   ├── notifications_notifier.dart         # StateNotifier for UI state
│       │   └── notifications_state.dart            # State classes
│       │
│       ├── data/                                   # ✅ CREATE: Feature-specific data
│       │   └── notifications_repository.dart       # Merges EventService + EventsDao
│       │
│       ├── providers/                              # ✅ CREATE: Feature providers
│       │   ├── notifications_provider.dart         # StreamProvider for real-time
│       │   └── event_filter_provider.dart          # Filter by type/device/date
│       │
│       └── view/                                   # ✅ UPDATE: UI implementation
│           ├── notifications_page.dart             # Full list view
│           ├── notification_card.dart              # Individual event card
│           ├── notification_filter_sheet.dart      # Filter bottom sheet
│           └── notification_toast.dart             # In-app toast overlay
│
├── providers/
│   └── multi_customer_providers.dart               # ✅ UPDATE: Complete implementation
│       - notificationsProvider: full implementation
│       - liveNotificationEventsProvider: full implementation
│
└── core/
    └── database/
        └── dao/
            └── events_dao.dart                      # ✅ ALREADY EXISTS: Use as-is
```

---

## 7. Recommended Architecture for Notifications

### Layer Structure

```
┌─────────────────────────────────────────────────────────────┐
│ UI Layer (features/notifications/view/)                     │
│  - NotificationsPage (ConsumerWidget)                       │
│  - NotificationCard (displays Event)                        │
│  - NotificationToast (overlay for live events)              │
└─────────────────────────────────────────────────────────────┘
                         ↑ ref.watch()
┌─────────────────────────────────────────────────────────────┐
│ Controller Layer (features/notifications/controller/)       │
│  - NotificationsNotifier extends StateNotifier              │
│    • State: NotificationsState (list, filters, loading)     │
│    • Methods: fetchEvents(), filterByType(), markAsRead()   │
└─────────────────────────────────────────────────────────────┘
                         ↑ calls
┌─────────────────────────────────────────────────────────────┐
│ Provider Layer (features/notifications/providers/)          │
│  - notificationsStreamProvider (real-time events)           │
│  - historicalNotificationsProvider (paginated list)         │
│  - eventCountProvider (badge count)                         │
└─────────────────────────────────────────────────────────────┘
                         ↑ uses
┌─────────────────────────────────────────────────────────────┐
│ Repository Layer (features/notifications/data/)             │
│  - NotificationsRepository                                  │
│    • Merges EventService (REST) + EventsDao (local)         │
│    • Listens to customerWebSocketProvider                   │
│    • Persists events to ObjectBox                           │
│    • Exposes Stream<List<Event>>                            │
└─────────────────────────────────────────────────────────────┘
                         ↑ uses
┌─────────────────────────────────────────────────────────────┐
│ Service Layer (services/)                                   │
│  - EventService (REST API calls)                            │
│  - EventsDao (ObjectBox persistence)                        │
│  - customerWebSocketProvider (live events)                  │
└─────────────────────────────────────────────────────────────┘
```

### Data Flow: Live Notification

```
1. WebSocket receives event
   TraccarSocketService → {"type": "events", "payload": [...]}

2. Typed message adapter
   customerWebSocketProvider → CustomerEventsMessage(events)

3. Repository listens and processes
   NotificationsRepository.listen() → Event.fromJson(event)

4. Persist to ObjectBox
   eventsDao.insert(EventEntity.fromEvent(event))

5. Stream update
   notificationsStreamProvider → yields new List<Event>

6. UI rebuilds
   ref.watch(notificationsStreamProvider) → NotificationCard

7. Optional: Show toast
   ref.listen(liveNotificationEventsProvider, (prev, next) {
     showNotificationToast(context, event);
   })
```

---

## 8. Current Strengths

### 1. **Excellent Performance Optimization**
- **Marker system:** Isolate-based clustering, LRU badge cache, differential updates
- **Map rendering:** Epoch-based rebuild controller, throttled notifiers, debounced panning
- **Tile caching:** FMTC with dual stores, prefetch profiles, offline mode
- **Interpolation:** MarkerMotionController with cubic easing, dead-reckoning

### 2. **Clean Reactive Architecture**
- Riverpod providers enable declarative UI updates
- WebSocket → Provider pipeline is well-structured
- Auto-dispose prevents memory leaks
- Family providers enable per-entity state

### 3. **Comprehensive Testing & Monitoring**
- Performance monitors: FpsMonitor, MarkerPerformanceMonitor, RebuildProfiler
- Telemetry HUD for cluster metrics
- Extensive unit tests (ObjectBox, providers, services)
- Debug overlays: rebuild counter, network status banner

### 4. **Strong Separation of Concerns**
- Features are self-contained modules
- Repository pattern abstracts data access
- Service layer handles business logic
- Clear distinction between domain models and entities

### 5. **Documentation**
- Comprehensive docs/ folder with architecture guides
- Code comments explain complex logic
- Prompt history preserved (e.g., PROMPT_4B_FMTC_ASYNC_PHASE2.md)

---

## 9. Potential Improvements

### Structural Issues

| Issue | Current State | Recommended Fix |
|-------|--------------|-----------------|
| **Duplicate folders** | `lib/app/` and `lib/app.dart/` coexist | Consolidate to `lib/app/` only |
| **Map split** | `lib/map/` (FMTC) vs `lib/core/map/` vs `lib/features/map/` | Move FMTC config to `lib/core/map/config/` |
| **Empty placeholders** | `event_service.dart`, `event.dart` are empty | Implement or remove |
| **Inconsistent naming** | `customer_device_positions.dart` vs `positions_live_provider.dart` | Standardize: `*_provider.dart` for providers |

### Code Organization

**Problem:** Notification system is stubbed but not functional  
**Solution:** Follow 7-layer structure (see Section 6)

**Problem:** Some providers mix concerns (e.g., `multi_customer_providers.dart` has trips + notifications + session)  
**Solution:** Split into separate files:
- `lib/providers/customer_session_provider.dart`
- `lib/providers/trips_provider.dart`
- Move notifications to `lib/features/notifications/providers/`

**Problem:** Repository uses `Map<int, ValueNotifier<VehicleDataSnapshot?>>` which is complex to test  
**Solution:** Consider extracting notifier factory or using Riverpod's `StateNotifier` pattern

### Async Isolation

**Problem:** Marker processing uses isolate only for 800+ markers  
**Solution:** Consider lowering threshold or using Isolate pool for all async operations

**Problem:** FMTC prefetch can cause main thread lag during store creation  
**Solution:** Move FMTC store initialization to isolate

---

## 10. Summary & Next Steps

### Architectural Overview

**Type:** Hybrid Feature-First + Repository + Clean Architecture  
**Maturity:** High (production-ready core, notifications need implementation)  
**Performance:** Excellent (isolates, caching, throttling, debouncing)  
**Modularity:** Good (reusable components, clear boundaries)  
**State Management:** Riverpod 2.x (declarative, reactive, testable)  

### Notification System Integration Plan

**Phase 1: Domain & Service Layer**
1. ✅ Create `lib/data/models/event.dart`
   - Define `Event` class with `fromJson`, `toJson`, `toEntity`, `fromEntity`
2. ✅ Implement `lib/services/event_service.dart`
   - Methods: `fetchEvents()`, `markAsRead()`, `clearAll()`
   - Use existing Dio client from `authServiceProvider`

**Phase 2: Repository**
3. ✅ Create `lib/features/notifications/data/notifications_repository.dart`
   - Merge EventService (REST) + EventsDao (ObjectBox) + WebSocket stream
   - Expose `Stream<List<Event>>`

**Phase 3: Providers**
4. ✅ Implement `lib/features/notifications/providers/notifications_provider.dart`
   - `notificationsStreamProvider`: Real-time stream
   - `historicalNotificationsProvider`: Paginated API calls
   - `eventCountProvider`: Unread badge count
5. ✅ Complete `lib/providers/multi_customer_providers.dart`
   - Finish `notificationsProvider` implementation
   - Finish `liveNotificationEventsProvider` implementation

**Phase 4: Controller**
6. ✅ Create `lib/features/notifications/controller/notifications_notifier.dart`
   - StateNotifier managing UI state (list, filters, loading, errors)
   - Methods: `loadMore()`, `filterByType()`, `refresh()`, `markAsRead()`

**Phase 5: UI**
7. ✅ Implement `lib/features/notifications/view/notifications_page.dart`
   - List view with pull-to-refresh
   - Filter bottom sheet (by type, device, date range)
   - Tap to see details or navigate to device on map
8. ✅ Create `lib/features/notifications/view/notification_toast.dart`
   - Overlay toast for live events
   - Use `ref.listen(liveNotificationEventsProvider, ...)`

**Phase 6: Integration**
9. ✅ Update `lib/app/app_router.dart` to add `/notifications` route
10. ✅ Add navigation from dashboard or map to notifications page
11. ✅ Add notification badge to app bar (unread count)

### Integration Points Summary

| Component | Path | Status | Priority |
|-----------|------|--------|----------|
| Event Model | `data/models/event.dart` | ❌ Empty | 🔴 High |
| Event Service | `services/event_service.dart` | ❌ Empty | 🔴 High |
| Notifications Repository | `features/notifications/data/notifications_repository.dart` | ❌ Missing | 🔴 High |
| Notifications Provider | `features/notifications/providers/notifications_provider.dart` | ❌ Missing | 🟡 Medium |
| Notifications Notifier | `features/notifications/controller/notifications_notifier.dart` | ❌ Missing | 🟡 Medium |
| Notifications Page | `features/notifications/view/notifications_page.dart` | ⚠️ Stub | 🔴 High |
| Multi-Customer Providers | `providers/multi_customer_providers.dart` | ⚠️ Partial | 🟡 Medium |
| EventsDao | `core/database/dao/events_dao.dart` | ✅ Complete | N/A |
| EventEntity | `core/database/entities/event_entity.dart` | ✅ Complete | N/A |
| WebSocket Events | `services/customer/customer_websocket.dart` | ✅ Complete | N/A |

---

## Appendix: Key Files Reference

### Core Infrastructure
- `lib/main.dart` - Entry point, FMTC init, HTTP overrides
- `lib/core/data/vehicle_data_repository.dart` - Centralized data access
- `lib/core/map/marker_motion_controller.dart` - Smooth marker animation
- `lib/core/database/objectbox_singleton.dart` - ObjectBox store manager

### State Management
- `lib/providers/connectivity_provider.dart` - Network state
- `lib/providers/multi_customer_providers.dart` - Customer session + trips + notifications
- `lib/features/dashboard/controller/devices_notifier.dart` - Device list state
- `lib/features/map/providers/map_state_providers.dart` - Map-specific state

### Services
- `lib/services/auth_service.dart` - Authentication + session
- `lib/services/traccar_socket_service.dart` - WebSocket client
- `lib/services/customer/customer_websocket.dart` - Typed WebSocket adapter
- `lib/services/positions_service.dart` - Position API calls
- `lib/services/device_service.dart` - Device API calls

### Features
- `lib/features/map/view/map_page.dart` - Main map UI (2000+ lines)
- `lib/features/map/clustering/` - Marker clustering system
- `lib/features/auth/controller/auth_notifier.dart` - Auth state management
- `lib/features/notifications/view/notifications_page.dart` - Placeholder (to be implemented)

### Documentation
- `docs/PROJECT_OVERVIEW_AI_BASE.md` - Core stack summary
- `docs/LIVE_MARKER_MOTION_FIX.md` - Motion controller explanation
- `docs/websocket_testing_guide.md` - WebSocket debugging guide

---

**End of Analysis**
