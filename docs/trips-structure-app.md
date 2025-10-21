# Project Structure & Architecture Blueprint (Trips-ready)

Date: 2025-10-22

This document describes the current architecture (Notifications, Maps, Diagnostics, Data Layer, UI), codifies shared patterns, and proposes a reusable blueprint for adding the Trips module in a consistent, performant way.

## 1) Project overview

Design philosophy
- Async-first, cache-aware, reactive UI (Riverpod)
- Prefer background work (compute()/isolates) for heavy operations
- Resilient data flows (WebSocket + REST backfill, replay anchors, dedup)
- Developer visibility via diagnostics overlay and automated perf tests

Core systems (textual diagram)
- AppRoot (MaterialApp + Providers)
  - Diagnostics overlay (kDebugMode): DevDiagnostics + RebuildTracker
- Data sources
  - WebSocket (customer events)
  - REST (Traccar API) for backfill, details
- Repositories (single source of truth per domain)
  - NotificationsRepository (events stream, dedup, enrichment, persistence)
  - VehicleDataRepository (WS lifecycle, per-device backfill, recovery stream)
  - Map/Marker processing (isolate compute + UI adapter)
- Providers (Riverpod)
  - Repository providers
  - Stream/derived providers (filtered/paged/search)
- UI modules
  - Notifications (pages, tiles, banners)
  - Maps (marker layers, controls)
  - Diagnostics (overlay, toggles)

## 2) Data flow summary

WebSocket → Repository → Provider → UI
1. WebSocket emits raw event(s)
2. NotificationsRepository parses, dedups, enriches (device names, severity/priority), persists to ObjectBox, updates replay anchor
3. Emits updated list via `watchEvents()` → `notificationsStreamProvider`
4. UI rebuilds selectively (.select) or per-item

Traccar REST → Repository → Provider → UI
1. Repository uses EventService to fetch (per-device backfill, safe window)
2. Persist to ObjectBox, update in-memory cache, emit list

Persistent replay anchor & dedup
- Anchor stored in SharedPreferences; advanced during live updates and backfill
- In-memory dedup Set<String> with bounded persistence (pruned, periodic)

## 3) Module blueprints

### Notifications module
Files (examples)
- `lib/repositories/notifications_repository.dart`
- `lib/providers/notification_providers.dart`
- `lib/features/notifications/view/notifications_page.dart`
- `lib/features/notifications/view/notification_tile.dart`

Responsibilities
- Subscribe to WS and Vehicle repo backfill stream
- Parse/normalize timestamps; dedup by id; enrich with device names
- Persist events (ObjectBox) and emit via broadcast stream
- Maintain replay anchor in SharedPreferences

Performance/UX notes
- ListView.builder with stable keys (ValueKey)
- Tile-level `.select()` on `isRead` via `notificationByIdProvider`
- Debounced search (250ms) and heavy-filtering offloaded via `compute()` for large lists
- Pagination (page=50) with lazy load near bottom; non-blocking UI on stream load

### Maps module
Files (examples)
- `lib/features/map/view/flutter_map_adapter.dart`
- `lib/core/map/marker_processing_isolate.dart`
- `lib/core/diagnostics/rebuild_tracker.dart`

Responsibilities
- Construct efficient marker layers and clustering
- Offload clustering/aggregation to an isolate when heavy
- Minimize rebuilds via narrow rebuild scopes and memoization

Performance/UX notes
- Track cluster compute timings via DevDiagnostics
- Rebuild scoping to avoid entire map rebuilds
- Camera movement throttling; tile cache via FMTC with IO client

### Trips module (new)
Goal
- Replay historical trips (paths), show metrics (distance/time), and surface events along the route

Proposed structure
- Repository: `lib/repositories/trip_repository.dart`
  - Contracts: fetch trips (by device + time), fetch trip summary, cache
  - Data sources: REST (Traccar reports), possibly local cache
  - Emits streams or exposes fetch APIs + cached snapshots
- Providers: `lib/providers/trip_providers.dart`
  - `tripRepositoryProvider`
  - `tripsByDeviceProvider(deviceId, range)` (Future/Stream)
  - `tripPlaybackProvider(tripId)` for controlling playback state
- UI: `lib/ui/trips/`
  - `trips_page.dart` (list + search/date filters)
  - `trip_details_page.dart` (summary + map polyline)
  - `trip_playback_controls.dart` (play/pause/scrub)

Performance/UX notes
- Polyline/segment computation in isolate for long trips
- Use `.select()` for playback state and item readouts
- Pagination for long history
- Share map adapter logic (polyline layer + markers) with Maps module

### Diagnostics module
Files
- `lib/core/diagnostics/dev_diagnostics.dart`
- `lib/features/debug/dev_diagnostics_overlay.dart`
- `lib/features/debug/dev_diagnostics_controller.dart`

Responsibilities
- Expose metrics: WS reconnects, backfill requests/applied, markers/sec, FPS, dedupSkipped, ping latency, cluster compute, filter compute
- Debug-only toggle & overlay rendering (ValueNotifiers)

Integration pattern
- Repositories/managers call DevDiagnostics hooks on critical paths
- Overlay consumes ValueNotifiers directly (no extra rebuild churn)

## 4) Shared utilities

Models (present/example)
- `lib/data/models/event.dart`
- Future: `lib/data/models/trip.dart`, `lib/data/models/vehicle.dart` (if not already)

Base repository class (proposal)
- `lib/core/base_repository.dart`
  - Common lifecycle: init, dispose, logging helper
  - Optional: `BaseCacheMixin` for cached list snapshots and broadcast stream wiring

Helper mixins (proposal)
- `CacheMixin<T>`: cached list, emit snapshot, guarded emit
- `DebounceMixin`: simple debouncer for rapid-fire UI inputs
- `ComputeHelper`: wrapper to run compute with typed payloads and error handling

Unified DT utils (proposal)
- `DateUtilsX.normalizeToLocal`, `truncateToDay`, `safeParseServerTime`

Logging
- `Logger`/`debugPrint` wrapper with domain tags, and rate-limited spam control

## 5) Optimization guidelines

- Rebuild minimization
  - Prefer `.select()` to watch only fields needed by a widget
  - Stable keys on list items (`ValueKey(id)`) to preserve caches
- Input debounce
  - Debounce user input (search) to 200–300ms
- Heavy work off main thread
  - Use `compute()` or isolates for filtering/clustering/polyline computation
- Async initialization strategy
  - Never block UI on cold starts; render with last known snapshot and update
- Diagnostics under kDebugMode
  - Keep release builds clean; low overhead
- Pagination & lazy load
  - Page size ~50–100; load more when near bottom

## 6) Folder & naming convention

Target scheme
```
lib/
 ├─ core/
 │   ├─ base_repository.dart              # optional shared base
 │   ├─ diagnostics/                      # DevDiagnostics, RebuildTracker
 │   ├─ map/                              # isolates/adapters for map
 │   ├─ utils/                            # date, logging, compute helpers
 │   └─ database/                         # DAOs/entities
 ├─ data/
 │   └─ models/                           # event.dart, trip.dart, vehicle.dart
 ├─ repositories/
 │   ├─ notifications_repository.dart
 │   ├─ trip_repository.dart              # new
 │   └─ vehicle_data_repository.dart
 ├─ providers/
 │   ├─ notification_providers.dart
 │   ├─ trip_providers.dart               # new
 │   └─ map_providers.dart                # if needed
 ├─ features/ (or ui/)
 │   ├─ notifications/                    # pages + widgets
 │   ├─ maps/
 │   ├─ trips/                            # new (pages + widgets)
 │   └─ debug/                            # overlay, toggles
 └─ main.dart
```
Conventions
- File names: `snake_case.dart`
- Repositories: `XRepository`, providers: `x_providers.dart`, pages: `XPage`
- Keep domain-specific UI under `features/<domain>/`

## 7) How to add the Trips module (step-by-step)

1) Models
- Add `lib/data/models/trip.dart` with id, deviceId, startTime, endTime, distance, polyline/points, attributes

2) Repository
- Add `lib/repositories/trip_repository.dart` with methods:
  - `Future<List<Trip>> fetchTrips({required int deviceId, required DateTime from, required DateTime to})`
  - `Future<TripDetails> fetchTripDetails(String tripId)` (summary + points)
  - Optional cache snapshot + broadcast stream for live updates
- Use REST endpoints for reports; cache recent results in ObjectBox (optional)

3) Providers
- `tripRepositoryProvider` (singleton)
- `tripsByDeviceProvider((deviceId, range))` (Future/Stream, debounced inputs)
- `tripPlaybackProvider(tripId)` (StateNotifier for play/pause/scrub)

4) UI
- `ui/trips/trips_page.dart`
  - Debounced date/device filters; `ListView.builder` with stable keys
  - Pagination for long ranges
- `ui/trips/trip_details_page.dart`
  - Map polyline using shared map adapter (polyline layer builder)
  - Events overlay along the route (reuse NotificationTile visuals when relevant)
- `ui/trips/trip_playback_controls.dart`
  - Hook into `tripPlaybackProvider` for reactive playback state

5) Performance & diagnostics
- Offload polyline simplification/segmentation to isolate for long trips
- Record compute timings via `DevDiagnostics.recordClusterCompute/recordFilterCompute`
- Add perf tests (avg FPS while playback, compute time thresholds)

## 8) Future extensions

- Analytics & summaries
  - Daily/weekly distance, average speed, idling time
- Push notifications for trip boundaries
  - Start/end-of-trip local notifications (server-driven where available)
- Background sync
  - Periodic prefetch of yesterday’s trips + cache warm-up
- Auto-reporting
  - Persist perf metrics snapshots (CI and on-device dev builds) to detect regressions

## References to current code
- Notifications repo: `lib/repositories/notifications_repository.dart`
- Providers: `lib/providers/notification_providers.dart`
- UI: `lib/features/notifications/view/notifications_page.dart`, `notification_tile.dart`
- Diagnostics: `lib/core/diagnostics/dev_diagnostics.dart`, `lib/features/debug/dev_diagnostics_overlay.dart`
- Map clustering: `lib/core/map/marker_processing_isolate.dart`, `lib/features/map/view/flutter_map_adapter.dart`
- App entry: `lib/main.dart`

---
This blueprint standardizes module patterns and performance practices, ensuring that adding Trips (and other features) remains consistent, fast, and maintainable.
