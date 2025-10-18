# Project Overview (AI Base)

This document is the single, authoritative overview of the Flutter + Traccar GPS tracking application. It replaces earlier module-level summaries and serves as the hub for future AI-assisted development and reasoning.

## Core Stack Summary

- Application
	- Flutter (multi-platform; primary targets: Android, iOS; secondary: Web/Desktop supported by flutter_map and current project layout)
	- State management: Riverpod (2.x)
	- Navigation/UI: Flutter Material
- Mapping
  - flutter_map 8.x as the map engine
  - flutter_map_tile_caching (FMTC) v10 for on-device tile caching
  - Dedicated HTTP/1.1 IOClient for tiles (custom TileNetworkClient)
  - Tile sources: OpenStreetMap (HOT) and Esri World Imagery (Satellite); hybrid overlay removed
  - Per-source FMTC stores (tiles_osm, tiles_esri_sat) with startup warmup
  - URL cache-busting on provider switch to avoid stale imagery
  - MapRebuildController: Epoch-based rebuild lifecycle management to prevent unnecessary full map reconstructions
- Markers and Performance
  - Modern marker system with custom painter/generator (modern_marker_* modules)
  - EnhancedMarkerCache for diffing and reuse, plus a ThrottledValueNotifier to minimize rebuilds
  - Adaptive marker clustering: zoom-aware, density-based grouping with accessibility support
  - Cluster engine: Grid-based O(n) algorithm with background isolate for > 800 markers
  - Visual cluster badges: Color-coded by size, WCAG AA compliant, semantic labels for screen readers
  - Interactive clusters: Tap to zoom-to-bounds or spiderfy (small clusters)
  - Optional background isolate for marker processing
  - Frame and rebuild diagnostics: performance monitors, rebuild tracker, and timing utilities
  - Isolated rebuild domains: map tiles, markers, and camera operate independently to avoid cascade rebuilds
- Prefetch System
  - Smart prefetch orchestrator with profile-based configuration (Light, Commute, Heavy)
  - Connectivity-aware pause/resume (auto-pauses when offline via ConnectivityCoordinator)
  - Fair-use rate limiting (2000 tiles/hour cap, random jitter, exponential backoff)
  - Per-source FMTC store targeting (OSM vs Esri caches isolated)
  - Throttled progress tracking (~4 updates/second) with non-blocking UI
  - Manual "Prefetch Current View" trigger with settings panel
- Data and Persistence
	- Repository pattern via VehicleDataRepository
	- ObjectBox for local persistence (DAOs: positions, telemetry, etc.)
	- Singleton ObjectBox Store manager prevents duplicate instance crashes
	- Last-known positions provider to merge storage with live updates
- Networking and Backend
	- Traccar-compatible WebSocket layer for live telemetry with circuit breaker (hostname validation prevents retry storms)
	- REST fallback for device and position data when WS is unavailable
	- Dio/HTTP usage for API calls where applicable
	- Network Resilience Layer: ConnectivityCoordinator unifies device network (connectivity_plus) and Traccar backend reachability
	- Debounced offline banner (4s show delay, 2-ping hide confirmation) prevents UI flicker
	- Automatic FMTC mode switching (online → normal, offline → hit-only) for instant cached tile access
	- Auto-triggers map rebuild on reconnect to refresh tiles and markers seamlessly
	- Defensive backend health check: parses HTML/plain text responses gracefully (prevents FormatException crashes)
- Testing and Tooling
	- Extensive unit/widget tests (ObjectBox-dependent tests skip in CI without native libs)
	- Lints via very_good_analysis

## Current Features

- Multi-layer basemap toggle between:
  - OpenStreetMap (HOT)
  - Esri World Imagery (Satellite)
- Robust tile loading with FMTC caching and a dedicated HTTP/1.1 client to prevent fetch instability
- Per-source FMTC stores to isolate caches and avoid cross-source collisions
- Runtime tile source switching with timestamped keys and URL cache-busting to force visual refresh
- Rebuild lifecycle management via MapRebuildController: prevents unnecessary full map reconstructions when only markers or camera change
- Network resilience with unified connectivity coordination: debounced offline banner, auto FMTC mode switching, seamless reconnection with map rebuild trigger
- Live device positions via Traccar-like WebSocket updates
- Last-known position fallback to ensure markers show even when offline
- Modern marker rendering with selection states, custom visuals, and efficient diffing
- Throttled marker updates to avoid UI jitters under high-frequency updates
- Camera fit and immediate move helpers for fast focus on selection (via persistent MapController, no widget rebuilds)
- Smart prefetch system with adaptive profiles (Light/Commute/Heavy) for offline tile preparation
- Connectivity-aware prefetch orchestration: auto-pauses when offline, resumes when online
- Fair-use compliant tile downloading: 2k/hour cap, random jitter (50-150ms), per-source rate limiting
- Prefetch settings panel with profile selector, progress tracking, and manual trigger
- Adaptive marker clustering with zoom-aware density thresholds (1-13 zoom range)
- Cluster computation: Debounced (250ms), background isolate for large datasets, < 16ms for 500 markers
- Accessibility-compliant cluster visuals: VoiceOver/TalkBack support, 4.5:1 contrast ratio, semantic labels
- Diagnostics for performance (rebuild tracking, frame timing, performance metrics)## Strengths Table
 - Badge caching for cluster markers to reduce paints and CPU load

| Area | What works well | Why it works |
|---|---|---|
| Tile Loading Reliability | Dedicated HTTP/1.1 client and compliant headers | Prevents unknownFetchException and adheres to OSM/CDN requirements |
| Visual Switching of Layers | Timestamped keys + URL cache-busting + rebuild epoch | Forces hard refresh, eliminating stale imagery after toggles |
| Cache Isolation | Per-source FMTC stores | Avoids cross-pollution between OSM and Satellite caches |
| Marker Pipeline | EnhancedMarkerCache + throttled updates | Minimizes rebuild cost and reduces UI flicker under load |
| Rebuild Isolation | MapRebuildController + persistent MapController | Camera moves and marker updates do NOT trigger full map reconstructions; only explicit tile source changes rebuild the widget tree |
| Offline Stability | ConnectivityCoordinator + debounced UI | No banner flicker during transient signal drops; cached tiles load instantly when offline; seamless auto-reconnection with map refresh |
| Smart Prefetch | Profile-based orchestrator + fair-use limits | Respects tile server policies; auto-pauses when offline; non-blocking UI with throttled progress; per-source store targeting |
| Adaptive Clustering | Grid-based O(n) algorithm + isolate support | Maintains 60 fps with 5000+ markers; zoom-aware density thresholds; WCAG AA accessible; overlay-only (no map rebuilds) |
| Runtime Stability | Singleton ObjectBox Store + WebSocket circuit breaker | Prevents duplicate Store crashes; stops retry storms on invalid hostname; lifecycle-aware wakelock wrapper (stub ready) |
| Fallback Resilience | Merge of live and last-known positions | Markers stay visible during transient network issues |
| Performance Instrumentation | Rebuild/Frame metrics and logging | Enables targeted tuning and regression detection |
| Test Coverage | Broad unit tests with graceful skips for native deps | Keeps core logic verified across modules |

## Weaknesses Table

| Issue / Limitation | Impact | Suggested Fix |
|---|---|---|
| Aggressive network/proxy caching can still surface old tiles in edge cases | Occasional stale imagery under certain networks | Keep per-source stores; retain timestamp cache-buster; optionally add short-lived version tag preference to rotate periodically |
| ObjectBox-native tests skip on CI without native libs | Reduced assurance for DAO paths in headless CI | Provide platform runners with objectbox_flutter_libs in integration tests or add a pure-Dart DAO mock suite |
| Prefetch manager disabled by default | Users don't benefit from preloaded tiles | Gradually enable per-zoom prefetch for common areas behind a setting with metrics gating |
| Clustering disabled by default | Users with large fleets see crowded maps | Enable clustering behind feature flag; add settings toggle; monitor FPS impact |
| Clustering isolate not fully implemented | Large datasets (800+) use sync path | Complete SendPort/ReceivePort messaging; serialize ClusterableMarker for isolate transfer |
| Spiderfy animation not implemented | Small cluster taps → placeholder action | Add radial layout algorithm with smooth expand/collapse animation |
| SafeWakelock not activated | Stub implementation ready but package not added | Add wakelock_plus dependency, uncomment API calls when use case defined |
| WebSocket using placeholder URL | Live telemetry disabled until configured | Update _wsUrl with production server address (37.60.238.215:8082) |
| Asset availability in tests (icons) | No-op renders in headless tests | Provide a minimal assets bundle for test runs or mock icon loader in tests |
| High-frequency WS updates could overwhelm UI on low-end devices | Potential jank at scale | Increase throttle for notifier in low-power mode; batch updates; backpressure strategy on repository side |
| FMTC store lifecycle | Store creation failures in constrained environments | Harden warmup with retries; expose UI hint if persistent; add diagnostics endpoint |

## Next Roadmap

1. ✅ **COMPLETED**: MapRebuildController implementation for isolated rebuild domains (Prompt 10A)
2. ✅ **COMPLETED**: Network Resilience Layer with unified connectivity coordination (Prompt 10 Pre-A)
3. ✅ **COMPLETED**: Smart Prefetch Profiles with adaptive orchestration and fair-use compliance (Prompt 10B)
4. ✅ **COMPLETED**: Backend Ping Hardening for defensive HTML/plain text response parsing (Prompt 10B Post-Fix)
5. ✅ **COMPLETED**: Adaptive Marker Clustering with zoom-aware density thresholds and WCAG AA accessibility (Prompt 10C)
6. ✅ **COMPLETED**: Runtime Stability Hotfix - SafeWakelock wrapper, ObjectBox singleton, WebSocket circuit breaker (Prompt 10D)
7. ✅ **COMPLETED**: Cluster Engine Finishing Pass – isolate compute, badge caching, spiderfy overlay, telemetry (Prompt 10E)
8. Activate SafeWakelock for prefetch/navigation scenarios (add wakelock_plus package).
9. Update WebSocket URL with production Traccar server (replace placeholder).
10. Offline-first mode: scheduled prefetch for areas of interest and clear UX around offline basemap coverage.
11. Diagnostics panel in-app: tile cache stats, WS status, connectivity health, last event time, and recent errors.
12. Repository backpressure and batching to smooth bursts of telemetry.
13. Integration test harness for map toggling and marker flows with a bundled test assets set.
14. Optional periodic tile cache versioning (soft bust) controlled via settings.
15. Expose FMTC hit-only mode when API becomes available for instant cached-only access.

## AI Usage Context

This file is the only authoritative context document for AI assistance on this project. When crafting changes or reasoning about architecture:

- Treat this document as the source of truth for stack components, active features, and known constraints.
- Prefer solutions that respect the current architecture: flutter_map 8.x, FMTC v10 with per-source stores, OSM/Esri basemaps, modern marker pipeline, Traccar-compatible backend.
- If a requirement appears to conflict with this overview, call it out and propose an update here first.
- Avoid relying on older or module-specific .md files; they are superseded by this document.

End of document.

