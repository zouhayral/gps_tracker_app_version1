# 🚀 Flutter Project Structure (Optimized for Speed & Scalability)

## 🧱 1. Folder Structure

```
lib/
├── main.dart                                ## Entry point of the Flutter app (calls runApp)
├── app.dart                                 ## Root widget: handles routing, theme, and localization setup
│
├── core/                                    ## Core framework-agnostic logic used by all layers
│   ├── network/                             ## Handles API and WebSocket connections
│   │   ├── dio_client.dart                  ## Configures Dio instance, interceptors, and base options
│   │   ├── api_client.dart                  ## Abstraction for REST API calls (GET, POST, PUT, etc.)
│   │   ├── https_fallback_interceptor.dart  ## Ensures HTTPS fallback for insecure connections
│   │   └── websocket_client.dart            ## WebSocket connection manager for real-time data
│   │
│   ├── database/                            ## Local database layer using Drift (SQLite ORM)
│   │   ├── drift_database.dart              ## Central database connection setup
│   │   ├── dao/                             ## Data Access Objects – read/write database tables
│   │   │   ├── devices_dao.dart             ## CRUD operations for devices table
│   │   │   ├── positions_dao.dart           ## CRUD operations for position data (GPS points)
│   │   │   ├── trips_dao.dart               ## CRUD operations for trips and routes
│   │   │   └── events_dao.dart              ## CRUD operations for geofence or system events
│   │
│   ├── storage/                             ## Persistent local key-value storage
│   │   ├── storage_service.dart             ## Wrapper for SharedPreferences + SecureStorage
│   │   └── cache_manager.dart               ## In-memory cache for quick reads (session, device list)
│   │
│   ├── env/                                 ## Environment configuration
│   │   └── env.dart                         ## Holds environment variables and constants (e.g., API URL)
│   │
│   ├── utils/                               ## Generic utility helpers
│   │   ├── date_utils.dart                  ## Date/time parsing, formatting, timezone conversion
│   │   ├── network_utils.dart               ## Connectivity checks, request retry helpers
│   │   ├── json_utils.dart                  ## JSON serialization/deserialization helpers
│   │   └── string_utils.dart                ## String manipulation and formatting helpers
│   │
│   ├── logging/                             ## Centralized logging utilities
│   │   └── app_logger.dart                  ## Logger wrapper for error tracking and console logs
│   │
│   └── di/                                  ## Dependency Injection (DI) setup
│       └── locator.dart                     ## get_it configuration and service locator registration
│
├── data/                                    ## Data sources: API + Database layer
│   ├── models/                              ## Data models (serializable to/from JSON)
│   │   ├── user.dart                        ## User data model (id, name, email, etc.)
│   │   ├── device.dart                      ## Device entity representing tracked hardware
│   │   ├── position.dart                    ## Position data (lat/lng, speed, timestamp)
│   │   ├── trip.dart                        ## Trip metadata (distance, duration)
│   │   ├── event.dart                       ## Event model (geofence trigger, alert)
│   │   └── geofence.dart                    ## Geofence definition (id, radius, center)
│   │
│   ├── repositories/                        ## Bridge between Data and Domain layers
│   │   ├── auth_repository.dart             ## Handles login/logout and session persistence
│   │   ├── device_repository.dart           ## Fetches device data from API and cache
│   │   ├── trip_repository.dart             ## Fetches and stores trip history
│   │   ├── event_repository.dart            ## Manages event fetching and caching
│   │   └── geofence_repository.dart         ## Manages geofence creation, update, and retrieval
│
├── domain/                                  ## Pure business logic layer
│   ├── entities/                            ## Core domain objects independent of framework
│   │   └── (All core object definitions used by usecases)
│   │
│   ├── usecases/                            ## Application-specific business actions
│   │   ├── login_user.dart                  ## Authenticates user and returns session token
│   │   ├── get_devices.dart                 ## Fetches list of user devices
│   │   ├── get_trips.dart                   ## Retrieves trip summaries and details
│   │   ├── get_events.dart                  ## Loads events from API or cache
│   │   └── create_geofence.dart             ## Creates a new geofence for a user/device
│
├── features/                                ## User interface and state management (Flutter layer)
│   ├── auth/                                ## Authentication screens and controllers
│   │   ├── presentation/                    ## UI pages and widgets for authentication
│   │   │   ├── login_page.dart              ## Login screen with email/password fields
│   │   │   └── widgets/                     ## Auth-specific reusable UI components
│   │   └── controller/                      ## State management logic
│   │       ├── auth_notifier.dart           ## Handles login/logout via Riverpod or BLoC
│   │       └── auth_state.dart              ## Holds authentication state (loading, error, user)
│   │
│   ├── dashboard/                           ## Main app UI (maps, trips, notifications)
│   │   ├── maps_screen.dart                 ## Shows real-time device positions on a map
│   │   ├── trips_screen.dart                ## Displays trip history and analytics
│   │   ├── notifications_screen.dart        ## Lists device or system alerts
│   │   ├── settings_screen.dart             ## App and account settings
│   │   ├── geofences_screen.dart            ## Manage and visualize geofences
│   │   └── navigation/
│   │       └── bottom_nav.dart              ## Bottom navigation bar between dashboard sections
│   │
│   └── widgets/                             ## Reusable UI components shared across screens
│       ├── app_button.dart                  ## Styled button widget for consistency
│       ├── app_text_field.dart              ## Common input text field widget
│       ├── status_badge.dart                ## Badge widget for online/offline statuses
│       ├── offline_banner.dart              ## Banner that shows when network is disconnected
│       └── map_marker.dart                  ## Custom marker widget for map display
│
├── services/                                ## High-level orchestrators combining multiple repositories/usecases
│   ├── auth_service.dart                    ## Manages login sessions and token refresh logic
│   ├── device_service.dart                  ## Central API for device list, status, and commands
│   ├── trip_service.dart                    ## Aggregates trip data and summaries
│   ├── event_service.dart                   ## Unified interface for events (fetch, filter, group)
│   ├── geofence_service.dart                ## Handles geofence logic + sync
│   ├── websocket_service.dart               ## Real-time WebSocket handler for live updates
│   └── sync_service.dart                    ## Background synchronization and offline queue manager
│
└── theme/                                   ## UI theming and color definitions
    ├── app_theme.dart                       ## Light/dark theme setup using ThemeData
    └── app_colors.dart                      ## Centralized color palette constants


## 🚀 2. Architecture Overview

| Layer | Responsibility | Framework |
|-------|----------------|-----------|
| **Core** | Low-level infra (network, cache, env, logging, DI) | Dio, Drift, get_it |
| **Data** | Talking to APIs / DB, maps raw data to models | Dio, Drift |
| **Domain** | Pure business rules (use cases, entities) | Dart only |
| **Features** | Screens, ViewModels, and controllers | Flutter, Riverpod/BLoC |
| **Services** | High-level orchestration (Auth, Device, Sync) | Depends on Data + Domain |

---

## ⚡ 3. Performance Optimizations

- Persistent Dio + cookie jar (no rebuilds per request)
- In-memory cache for quick reads (recent login, last device list)
- Drift’s background sync for offline mode
- Riverpod’s `AsyncNotifier` for efficient state updates
- Debounced WebSocket streams to avoid UI thrash
- Lazy import of Mapbox screen to reduce startup time
- SecureStorage only for sensitive tokens; SharedPreferences for non-critical data

---

## 🧩 4. Tooling & Build Setup

- `.env` variables → `lib/core/env/env.dart`
- CI/CD → `.github/workflows/flutter-ci.yml`
- Lints → `analysis_options.yaml` (strict)
- Logging → `core/logging/app_logger.dart`
- Background sync → `services/sync_service.dart` (Workmanager)

---

## 🔐 5. Offline & Security

- Offline cache = Drift + SharedPreferences hybrid
- Sync queue for geofence create/update
- HTTPS enforced (fallback handled gracefully)
- Secure credentials storage via `flutter_secure_storage`

---

## 🧠 6. Development Flow

```
UI (feature) → Controller (Riverpod) → UseCase → Repository → ApiClient / Database
```

Example Login Flow:
```
LoginPage → AuthNotifier.login() → LoginUserUseCase → AuthRepository → DioClient (POST /api/session)
```

---

## 🧪 7. Ready for Expansion

Supports:
- Multi-user (Traccar + Supabase)
- Background jobs (sync, location)
- WebSocket live updates
- Offline/online transitions
- Modular unit tests

---

## ✅ 8. Summary

This structure is **optimized for performance, modularity, and scalability.**

✅ Clean separation of concerns  
✅ Test-friendly  
✅ Ready for CI/CD  
✅ Offline-first  
✅ Maintainable long-term