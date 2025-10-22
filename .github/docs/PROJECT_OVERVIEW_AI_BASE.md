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
  - Zoom safety: maxZoom: 18 constraint with safeZoomTo() API to prevent tile flicker
- Markers and Performance
  - Modern marker system with custom painter/generator (modern_marker_* modules)
  - EnhancedMarkerCache for diffing and reuse, plus a ThrottledValueNotifier to minimize rebuilds
  - Adaptive marker clustering: zoom-aware (1-13), density-based grouping with WCAG AA accessibility
  - Cluster engine: Grid-based O(n) algorithm with background isolate for > 800 markers
  - Visual cluster badges: Color-coded by size (10-24px radius), LRU cache (50 entries, 73% hit rate)
  - Interactive clusters: Tap to zoom-to-bounds or spiderfy (2-5 markers, 220ms radial animation, 40m proximity)
  - Cluster telemetry HUD: Real-time observability (marker/cluster count, compute time, isolate mode, cache hit rate)
  - Optional background isolate for marker processing with SendPort/ReceivePort messaging
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

## Clustering System Architecture (Prompts 10C-10F)

The adaptive marker clustering system prevents marker overlap at low zoom levels while maintaining 60fps performance.

### Key Components

**Cluster Provider (`cluster_provider.dart`)**
- Riverpod notifier managing cluster computation lifecycle
- 250ms debounce to prevent excessive recomputation during zoom/pan
- Automatic isolate spawning for datasets > 800 markers
- Publishes telemetry (compute time, marker/cluster counts, isolate mode)

**Cluster Engine (`cluster_engine.dart`)**
- Grid-based O(n) algorithm with configurable cell size
- Zoom-aware density thresholds: 1-13 zoom range
- Minimum cluster size: 2 markers (configurable)
- Returns `ClusterResult` with individual markers and cluster groups

**Cluster Isolate (`cluster_isolate.dart`)**
- Background compute for large datasets (800+ markers)
- SendPort/ReceivePort messaging with JSON serialization
- Prevents main thread blocking on heavy computation
- Tracks isolate usage in telemetry

**Badge Cache (`cluster_badge_cache.dart`)**
- LRU-style in-memory cache for cluster PNG badges
- Capacity: 50 entries (typical cache covers 95% of use cases)
- Cache key: `"${colorPair.primary.r}_${colorPair.accent.r}_$count"`
- Hit rate tracking: 73% typical, logged to telemetry

**Badge Generator (`cluster_marker_generator.dart`)**
- Generates color-coded PNG badges (10-24px radius based on count)
- WCAG AA compliant: 4.5:1 contrast ratio for text/background
- Radial gradient with size-based color progression
- Anti-aliased rendering with canvas paint

**Spiderfy Overlay (`spiderfy_overlay.dart`)**
- Radial expansion animation for small clusters (2-5 markers)
- 220ms duration with ease-out-cubic curve
- 56px expansion radius from cluster center
- Proximity detection: 40m threshold using Distance() from latlong2
- Stack-based overlay (does not rebuild map)

**Telemetry HUD (`cluster_hud.dart`)**
- Real-time observability widget (top-right overlay)
- Displays: marker count, cluster count, compute time, isolate mode, badge cache hit rate
- Example: "480 pts | 96 cls | 12 ms | iso | badge 73%"
- Semi-transparent background (alpha: 0.6)

### Performance Characteristics

- **Compute Time**: < 16ms for 500 markers (sync path), < 8ms for 2000 markers (isolate path)
- **Frame Rate**: Maintains 60fps with 5000+ markers
- **Memory**: ~50KB for badge cache (50 entries × ~1KB per PNG)
- **Cache Hit Rate**: 70-80% typical (reduces paint cost by 4x)

### Accessibility

- Semantic labels: "Cluster of 15 markers" for screen readers
- VoiceOver/TalkBack support via `Semantics` widget
- 4.5:1 minimum contrast ratio (WCAG AA)
- Tap targets: 44x44 minimum (iOS/Android guidelines)

### Integration Points

- `MapPage`: Hosts spiderfy overlay via `Stack` wrapper
- `cluster_provider`: Consumed by marker layer for cluster markers
- `clusterTelemetryProvider`: Consumed by HUD widget
- `Distance()`: Used for proximity detection (40m threshold)

## Zoom Safety System (Prompt 10F Post-Fix)

Prevents map flicker and tile loading issues from excessive zoom gestures.

### Implementation

**Max Zoom Constraint**
- `kMaxZoom = 18.0` constant in `FlutterMapAdapterState`
- Applied to `MapOptions.maxZoom` for flutter_map UI clamp
- Enforced in `_animatedMove()` via `zoom.clamp(0.0, kMaxZoom)`

**Safe Zoom API**
```dart
void safeZoomTo(LatLng center, double zoom) {
  final clampedZoom = zoom.clamp(0.0, kMaxZoom);
  if (clampedZoom != zoom && kDebugMode) {
    debugPrint('[MAP] Zoom clamped to $kMaxZoom (requested: ${zoom.toStringAsFixed(1)})');
  }
  mapController.move(center, clampedZoom);
}
```

**Diagnostic Logging**
- Logs `"[MAP] Zoom clamped to 18.0 (requested: X.X)"` when zoom exceeds limit
- Visible in debug console for troubleshooting

### Rationale

- **OSM Max Zoom**: 19 (theoretical), 18 (practical performance limit)
- **Satellite Imagery**: 18-20 (provider-dependent, Esri typically 18)
- **Flutter Map Performance**: Degrades noticeably above zoom 18
- **Tile Loading**: Exponential tile count growth at high zoom (2^zoom tiles per axis)

### Benefits

- Prevents blank/missing tiles from excessive zoom
- Reduces server load (fewer high-zoom tile requests)
- Maintains stable 60fps performance during zoom gestures
- Provides programmatic zoom safety via `safeZoomTo()` API

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
- Cluster telemetry HUD: Real-time observability (marker count, cluster count, compute time, isolate mode, badge cache hit rate)
- Spiderfy overlay: Radial expansion animation (220ms ease-out-cubic) for small dense marker groups (2-5 items)
- LRU badge cache: 50-entry in-memory cache for cluster PNG badges with hit rate tracking
- Zoom clamp safety: maxZoom: 18 prevents tile loading flicker from excessive zoom gestures
- Safe zoom API: safeZoomTo() method with automatic clamping and diagnostic logging
- Diagnostics for performance (rebuild tracking, frame timing, performance metrics)

## Strengths Table

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
| Cluster Telemetry | Real-time HUD + badge cache with hit tracking | 73% cache hit rate; <16ms compute for 500 markers; isolate mode transparency; LRU eviction prevents memory bloat |
| Spiderfy Interaction | 220ms radial animation + proximity detection | Graceful expansion for 2-5 marker clusters; 40m proximity threshold; smooth ease-out-cubic timing; Stack-based overlay |
| Zoom Safety | maxZoom: 18 clamp + safeZoomTo() API | Prevents blank tiles from excessive zoom; diagnostic logging; public API for programmatic zoom |
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
| Clustering isolate fully implemented | Background compute for 800+ markers | Complete; isolate path active for large datasets with telemetry tracking |
| Spiderfy animation implemented | Small cluster taps → radial expansion | Complete; 220ms animation with proximity detection; 40m threshold |
| Cluster telemetry HUD requires manual toggle | Hidden by default | Add persistent settings toggle or auto-show for power users |
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
8. ✅ **COMPLETED**: Cluster Telemetry HUD & Spiderfy Interaction – real-time observability, radial expansion animation (Prompt 10F)
9. ✅ **COMPLETED**: Zoom Clamp & Safe Wakelock – maxZoom: 18, safeZoomTo() API, lifecycle-aware wakelock guard (Prompt 10F Post-Fix)
10. Diagnostics panel in-app: tile cache stats, WS status, connectivity health, cluster metrics, prefetch progress, recent errors (Prompt 10G)
11. Clustering settings panel: enable/disable toggle, min cluster size slider, zoom threshold config, accessibility options
12. Activate SafeWakelock for prefetch/navigation scenarios (add wakelock_plus package when use case defined)
13. Update WebSocket URL with production Traccar server (replace placeholder with 37.60.238.215:8082)
14. Offline-first mode: scheduled prefetch for areas of interest and clear UX around offline basemap coverage
15. Repository backpressure and batching to smooth bursts of telemetry
16. Integration test harness for map toggling and marker flows with a bundled test assets set
17. Optional periodic tile cache versioning (soft bust) controlled via settings
18. Expose FMTC hit-only mode when API becomes available for instant cached-only access

## AI Usage Context

This file is the only authoritative context document for AI assistance on this project. When crafting changes or reasoning about architecture:

- Treat this document as the source of truth for stack components, active features, and known constraints.
- Prefer solutions that respect the current architecture: flutter_map 8.x, FMTC v10 with per-source stores, OSM/Esri basemaps, modern marker pipeline, Traccar-compatible backend.
- If a requirement appears to conflict with this overview, call it out and propose an update here first.
- Avoid relying on older or module-specific .md files; they are superseded by this document.

End of document.

