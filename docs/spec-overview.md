Map SDK
- We use flutter_map (see ADR-001-map-library.md). Mapbox is not used in this codebase.

Networking
- All HTTP traffic is via Dio; the app exposes a single dioProvider (see core/network/dio_client.dart and usages in services/*). Ensure docs and probes reference the same provider.

Persistence Layer
- Last-known positions are cached locally via a lightweight DAO (`lib/core/database/dao/positions_dao.dart`) backed by ObjectBox.
- A one-time migration is executed from the legacy Hive box on first run.
- On app start or provider build, the map pre-fills from this DAO before issuing REST calls, ensuring offline markers render within ~1s.

Testing
- Centralized test setup lives in `test/test_utils/test_config.dart`.
- Widget tests disable map tiles to avoid network I/O.
- DAO tests check for ObjectBox native libraries and skip gracefully if unavailable in the environment (e.g., certain CI runners).
# 📘 Spec - Overview (GPS Tracker Flutter App)

## Project Purpose
A cross-platform, real-time vehicle monitoring and fleet management app built with Flutter (Dart), using Riverpod/BLoC for state, Dio for networking, Drift for caching, and Mapbox for maps. Traccar (self-hosted) is the authoritative backend for tracking data, trips, geofences, events, and commands.

## Target Users
- Primary: Fleet managers, dispatchers, logistics operators.
- Secondary: Drivers and vehicle owners.

## Success Metrics
- Daily active tracked devices.
- Event-to-UI latency via WebSocket.
- Trip history retrieval latency.
- API uptime & request success rate.
- Crash-free sessions (%).

## Tech Stack
- UI: Flutter (Material 3), Poppins typography
- Architecture: Clean Architecture + Repository Pattern
- State: Riverpod (StateNotifier, AsyncValue) or BLoC
- Database: ObjectBox for local cache; Traccar for cloud; optional Supabase for profiles
- Networking: Dio + dio_cookie_manager, web_socket_channel
- Maps: flutter_map (see ADR-001)
- Routing: go_router
- Background/Sync: workmanager
- Security: flutter_secure_storage
- Utilities: json_serializable, freezed, build_runner, connectivity_plus, intl

## Theming
- Light theme background: #F5FFE2
- Primary/Online: #A6CD27
- Error/High priority: #FF383C
- Medium priority: #FF8D28
- Neutral text/icons: #49454F
- Hover/Pressed: #E2F998
- Trip details highlight: #213102