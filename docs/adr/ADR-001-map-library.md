# ADR-001: Map Library Selection

Date: 2025-10-08
Status: Accepted
Decision: Adopt `flutter_map` (OpenStreetMap-based) as the initial map rendering library.

## Context
The application requires a real-time device map, history polylines, potential geofences, clustering, theming (dark mode), and offline-friendly behavior. We evaluated `flutter_map`, `google_maps_flutter`, and Mapbox ecosystem alternatives.

## Options Considered
### 1. flutter_map (+ OSM tiles)
Pros:
- Pure Dart/Flutter rendering layer; highly extensible.
- Supports custom tile sources (including self-hosted / offline tile packs) easily.
- Rich plugin ecosystem (marker clustering, caching, vector tile experimentation via mapbox_vector_tile parsing, etc.).
- No API key required for basic OSM usage (just follow tile usage policy & set proper User-Agent).
- Simplified theming and custom painter overlays for polylines & heatmaps.
- Easier to intercept gestures & coordinate transforms for playback features.
Cons:
- No built-in Google or proprietary satellite imagery (requires 3rd-party providers, possibly with TOS constraints).
- Performance with extremely large marker counts (>5k) can require custom optimizations.
- Manual responsibility for respecting tile usage (rate limiting, attribution display).

### 2. google_maps_flutter
Pros:
- Native map SDK performance and gestures.
- Built-in vector map, traffic, satellite layers.
- Familiar UI for users.
Cons:
- API key management + potential billing.
- Limited deep customization (dynamic marker layering / custom shaders more constrained).
- Harder to do offline (no full offline tile packs integrated by default).
- Polylines & dynamic style adjustments more limited.

### 3. Mapbox (mapbox_gl / maplibre)
Pros:
- Vector tiles, style JSON theming (easy dark mode), high performance for many markers (symbol layer + data-driven styling).
- Offline packs supported (with MapLibre + custom tiles).
Cons:
- Additional native setup complexity & potential licensing/billing for Mapbox official SDK.
- mapbox_gl plugin maintenance churn historically; MapLibre alternatives still evolving.
- Slightly higher initial integration overhead.

## Comparison Summary
| Criterion | flutter_map | google_maps_flutter | mapbox_gl/maplibre |
|----------|-------------|---------------------|--------------------|
| Custom Overlays | Excellent | Moderate | Excellent |
| Offline Strategy | Straightforward (cache tiles) | Weak | Strong (with work) |
| Licensing/API Keys | None (OSM etiquette) | Requires key | Key (Mapbox) / none (MapLibre self-host) |
| Theming / Dark Mode | Manual (tile choice) | Limited | Excellent |
| Marker Clustering | Plugin | Limited | Native-ish via layers |
| Dev Velocity | High | High | Medium |
| Playback Polyline Control | High | Medium | High |
| Complexity to Integrate | Low | Low | Medium-High |

## Decision
Adopt `flutter_map` now to maximize speed and flexibility. Reassess if we: (a) need native satellite imagery; (b) exceed performance thresholds; or (c) require advanced vector styling not feasible with current approach.

## Consequences
- Need to implement tile attribution & optional rate limiting header/User-Agent.
- Must add dependency set: `flutter_map`, `latlong2`, possibly `cached_network_image` for marker assets, and later a clustering plugin.
- For dark mode: choose dark tile provider (e.g., Carto Dark, Stadia, or custom) or host styled tiles.
- Provide abstraction layer (`MapViewAdapter`) to keep a future switch manageable.

## Implementation Outline
1. Add dependencies to `pubspec.yaml`:
   - flutter_map
   - latlong2
2. Create `lib/features/map/view/map_page.dart` with a placeholder map using current device list (center fit to markers or fallback center).
3. Create `lib/features/map/core/map_adapter.dart` (interface) to decouple business logic.
4. Add attribution widget (opaque footer) with OSM notice.
5. Add simple marker builder using current device state.

## Migration / Future Switch Strategy
- Centralize mapping operations (add/remove markers, move camera, draw polylines) behind an adapter.
- In future, implement `GoogleMapAdapter` or `MapboxAdapter` abiding by same interface.
- Maintain domain models (Position, Device) independent of rendering library.

## Open Questions / Follow-ups
- Tile caching strategy & acceptable storage size limit.
- Potential need for offline tile preloading for poor connectivity scenarios.
- Evaluate performance with realistic device counts after basic implementation.

## Status Tracking
- [x] ADR written
- [x] Dependencies added
- [x] Adapter interface scaffolded
- [x] Placeholder map screen rendering
- [x] Attribution present

---
