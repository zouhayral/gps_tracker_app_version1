# Big Picture Architecture – GPS Tracking & Notification System (Flutter + Firebase + SQLite)

Last updated: October 25, 2025

This document provides an end-to-end system view of the current GPS tracker app stack and how future geofencing integrates. It emphasizes real-time data handling, async performance, and marker memoization.

---

## 🧱 Section 1: High-Level System Overview

- Platform: Flutter mobile (Android/iOS), Material Design 3 UI
- Navigation: GoRouter
- State: Riverpod (providers, StreamProviders, Notifiers)
- Maps: Maps SDK via Flutter plugin (e.g., Google Maps). Marker caching + memoization
- Local Persistence: SQLite (offline cache, settings, recent events/devices)
- Backend: Firebase
  - Auth (Firebase Auth)
  - Firestore (device metadata, position snapshots, events)
  - Cloud Messaging (FCM) for push notifications
- Services (Device):
  - Location Service (foreground/background location; throttled streams)
  - Notification Service (local + FCM bridge)
  - Connectivity/Retry & Sync Service (backoff, batching)
- Repositories:
  - DeviceRepository (CRUD devices)
  - PositionRepository (live location streams + sync)
  - EventRepository (notifications/events persistence)
  - SettingsRepository (local settings, user prefs)
- Performance themes:
  - Async streaming with backpressure (debounce/throttle)
  - Marker memoization + bitmap cache
  - Batching writes to Firestore; offline-first cache in SQLite
  - Scoped rebuilds with Riverpod (granular providers)

---

## 🗺️ Section 2: Architecture Diagram (Mermaid)

```mermaid
flowchart LR
  subgraph Mobile_App[Flutter App]
    direction TB
    subgraph UI[UI Layer]
      M3[Material 3 Widgets]
      Router[GoRouter]
      MapView[Map View (Google Maps)]
    end

    subgraph State[State Layer – Riverpod]
      P_auth[(authProvider)]
      P_devices[(devicesProvider)]
      P_positions[(positionsStreamProvider)]
      P_events[(eventsProvider)]
      P_mapState[(mapStateProvider)]
      P_markerCache[(markerCacheProvider)]
    end

    subgraph Domain[Domain/Logic]
      Ctrl_auth[AuthController]
      Ctrl_devices[DeviceController]
      Ctrl_positions[PositionController]
      Ctrl_events[EventController]
      Use_cases[Use Cases]
    end

    subgraph Data[Data Layer]
      Repo_auth[AuthRepository]
      Repo_devices[DeviceRepository]
      Repo_positions[PositionRepository]
      Repo_events[EventRepository]
      Repo_settings[SettingsRepository]

      subgraph Local[Local Persistence]
        SQLite[(SQLite DB)]
        Cache[In-memory caches]
      end
    end

    subgraph Services[Platform/Integration Services]
      LocSvc[Location Service\n(fg/bg stream)]
      NotifSvc[Notification Service\n(local + FCM bridge)]
      ConnSvc[Connectivity & Sync]
      MapSvc[Map/Marker Service\n(memoization, bitmaps)]
    end
  end

  subgraph Firebase[Firebase Backend]
    Auth[(Firebase Auth)]
    FS[(Firestore)]
    FCM[(Cloud Messaging)]
  end

  subgraph Platform[Device/OS]
    GPS[(OS Location Provider)]
    BG[(BG Execution/WorkManager)]
    Net[(Network)]
  end

  %% Flows
  GPS --> LocSvc
  BG --> LocSvc
  Net --> ConnSvc

  LocSvc -->|Stream<Location>| Ctrl_positions
  Ctrl_positions --> Repo_positions
  Repo_positions <--> SQLite
  Repo_positions <-->|snapshots| FS

  Ctrl_devices --> Repo_devices
  Repo_devices <--> SQLite
  Repo_devices <-->|metadata| FS

  Ctrl_events --> Repo_events
  Repo_events <--> SQLite
  Repo_events <-->|events| FS

  P_positions --> P_mapState
  P_mapState --> P_markerCache
  P_markerCache --> MapSvc --> MapView

  P_auth --> Ctrl_auth --> Repo_auth --> Auth
  Repo_auth --> P_auth

  FS -->|server events| Ctrl_events
  Ctrl_events --> NotifSvc --> FCM
  FCM --> NotifSvc --> UI

  UI <-->|watch/select| State
  State <-->|invoke| Domain
  Domain <-->|call| Data
  Data <-->|bridge| Services
```

---

## 🔄 Section 3: Data Flow Explanation

1) Authentication
- User signs in (Firebase Auth). `authProvider` exposes session state.
- Guards in GoRouter read `authProvider` to control routes.

2) Device management (metadata)
- UI → `DeviceController` → `DeviceRepository`
- Repository writes to Firestore (`devices/{deviceId}`) and caches locally in SQLite for offline use.
- `devicesProvider` watches repository and invalidates on snapshot changes.

3) Real-time GPS tracking
- Platform GPS → Location Service emits throttled Stream<Location> (foreground/background).
- `PositionController` consumes stream, applies rate limiting and deduping, then calls `PositionRepository`.
- Repository:
  - Persists latest position locally (SQLite: positions table)
  - Batches Firestore writes (e.g., `positions/{deviceId}/points/{ts}`) or latest snapshot in `devices/{deviceId}`
  - Exposes Riverpod `positionsStreamProvider` combining:
    - Local cache for instant UI
    - Firestore snapshots for server-truth
- Map state listens to `positionsStreamProvider`, updates `mapStateProvider`.
- Marker cache memoizes bitmaps (deviceId + status + heading); only changed markers cause rebuild.

4) Notifications & events
- Server-side triggers (Cloud Functions or backend rules) create Firestore `events` documents and/or send FCMs to device topics.
- App receives FCM via Notification Service:
  - If foreground: show in-app toast and update `eventsProvider`.
  - If background/terminated: system tray, tap intent routes via GoRouter.
- `EventRepository` keeps local SQLite copy for offline history and filters (type/date/device).

5) Offline-first & sync
- All repositories read from SQLite first, then merge Firestore snapshots.
- Sync Service handles retries with exponential backoff when network returns.
- Write operations are enqueued locally if offline and flushed when online.

6) Performance strategies in the loop
- Debounce/throttle location stream per device (e.g., 300–1000ms, distance filter).
- Batch Firestore writes (arrayUnion or batched writes) within quota limits.
- Riverpod selective rebuilds: split providers (positions, devices, events, UI settings) to minimize widget rebuilds.
- Marker memoization and bitmap cache avoid repeated image work; keep stable MarkerIds.

---

## ⚙️ Section 4: Geofence Extension Plan

Goal: Add geofences with entry/exit monitoring, synced with Firebase, integrated with Riverpod and notifications.

A) Data model & storage
- Firestore:
  - `geofences/{userId}/rules/{geofenceId}` with fields:
    - type: circle | polygon
    - center (lat,lng), radius (for circle)
    - vertices (for polygon)
    - name, enabled, monitoredDevices: [deviceIds]
    - triggers: onEnter, onExit, dwellMs
    - notification: local | push | both
  - Optional server aggregation: `geofenceEvents/{userId}/{eventId}`
- SQLite mirrors the geofence rules for offline evaluation with versioning (updatedAt) and soft-delete.

B) Monitoring & evaluation
- Use platform geofencing APIs via a Flutter plugin (Android GeofencingClient; iOS Region Monitoring). Fallback to app-side evaluation if necessary:
  - Background task receives location updates; lightweight geofence evaluator checks point-in-circle/polygon.
  - Dwell logic with time windows to avoid flapping.
- Emit `GeofenceEvent(entry|exit|dwell)` to `EventRepository` and (optionally) Firestore.

C) Riverpod integration
- `geofencesProvider` (StreamProvider): Firestore + SQLite merged stream of rules.
- `geofenceMonitorProvider` (Notifier/Service): starts/stops platform monitoring based on rules and auth state.
- `geofenceEventsProvider` (StreamProvider): live events for UI and toasts.

D) Notifications
- Local: Show high-priority notification on entry/exit/dwell with deep link (device/geofence).
- Push: Publish to topic or per-device token via Cloud Functions if cross-device visibility is needed.

E) Sync & conflict resolution
- Last-write-wins with updatedAt; version counter to detect conflicts.
- Server enforces constraints (max radius/devices per user), and indexing on geofence queries.

F) UI additions
- Geofence Manager page: list, create, edit, enable/disable.
- Map overlay to draw polygons/circles.
- Filters in notifications page: by geofence, device, type.

---

## 🧩 Section 5: Recommended Improvements / Scalability Notes

Performance & UX
- Adopt distance and time filters on location stream; prefer OS-side filters to reduce wakeups.
- Keep marker IDs stable; update only changed markers. Precompute and cache rotated bitmaps by heading buckets.
- Partition providers: separate live positions, device metadata, and map camera state to reduce rebuild pressure.

Data & Firestore
- Use batched writes and server timestamps; limit per-second writes per device to stay within quotas.
- Consider `devices/{deviceId}/positions` subcollection for history and `devices/{deviceId}` for latest snapshot.
- Add composite indexes for queries used in lists (by userId, updatedAt, deviceId).
- Implement backpressure: queue writes locally and flush in bursts.

Offline & Sync
- Model a simple outbox table in SQLite for pending writes; ensure idempotent server apply using clientIds.
- On startup, replay outbox with retry and jitter; on auth change, clear or rebind queues.

Background & battery
- Respect platform limits; use foreground service on Android for continuous tracking; adaptive interval when screen off.
- Pause or coarsen updates when user is stationary to save battery.

Security & multi-tenant
- Firestore Security Rules: enforce per-user/device access; validate writes (schema, ranges).
- Use FCM topics per user and/or per device; rotate tokens on sign out.

Testing & Observability
- Add unit tests for geofence evaluation (point-in-polygon, dwell logic, edge cases).
- Integration tests covering location → repository → UI.
- Add lightweight telemetry: event counters, error rates, sync lag.

Scalability
- For large fleets, consider server-side aggregation (Cloud Functions) to fan-out notifications and compress writes.
- Consider partitioning collections by user/tenant; shard large write hotspots with randomized doc IDs.

---

### Tiny contract (for core real-time loop)
- Inputs: Stream<Location>, Firestore snapshots, user actions
- Outputs: UI state (markers, lists), local DB rows, server writes, notifications
- Error modes: offline, quota exceeded, background restrictions, auth expiry
- Success: UI remains responsive, markers smooth; no data loss; notifications timely

### Edge cases to handle
- App resumes after long offline period → outbox replay and conflict merge
- Background restrictions on iOS → reduced frequency, ensure compliance
- Rapid device motion → throttle + drop older frames; interpolate on UI
- Duplicated server events → idempotent insert with unique keys
- User switches account → clear caches, re-subscribe topics
```
