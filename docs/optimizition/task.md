# 🧠 Flutter App Optimization Micro Tasks

This document breaks down the optimization plan into small, actionable tasks suitable for tracking in GitHub Projects, ClickUp, or AI agents.

---

## 🚀 Top Quick Wins

### ✅ Networking & Live Updates
- [x] Replace REST polling with WebSocket for live Traccar events.
- [x] Implement exponential backoff + jitter on reconnect.
- [x] Add HTTP caching (ETag / If-Modified-Since) for static endpoints.
- [ ] Tune Dio timeouts: connect = 2s, receive = 10s.
- [ ] Enable gzip compression (`Accept-Encoding: gzip`).

### ✅ Map Caching & Assets
- [ ] Cache map tiles using `flutter_map_tile_caching` or `cached_network_image`.
- [ ] Reuse prebuilt marker icons (avoid repeated decode of `Image.asset`).
- [ ] Add vector icons (SVG or IconData) for device statuses.
- [ ] Limit image cache size (PaintingBinding.instance.imageCache.maximumSizeBytes).
- [ ] Precache images on startup for commonly used markers.

### ✅ UI Rebuilds
- [ ] Use `Riverpod.select()` to limit widget rebuilds.
- [ ] Split device provider and position provider.
- [ ] Use `ProviderScope.keepAlive` with cacheTime on heavy providers.
- [ ] Replace unnecessary rebuilds with `AnimatedSize` or `AnimatedSwitcher`.

---

## 🗺️ Map Performance

### ✅ Markers
- [ ] Switch to `FastMarkerLayer` or marker clustering for 100+ markers.
- [ ] Precreate marker widgets with `const` constructors.
- [ ] Wrap only info panel in `RepaintBoundary`.

### ✅ Camera & Bounds
- [ ] Throttle `fitToBounds` to max 1 call per 300ms.
- [ ] Avoid redundant fit calls during marker selection.
- [ ] Keep consistent padding constants for viewport fitting.

### ✅ Tiles
- [ ] Enable disk tile cache with expiry.
- [ ] Preload surrounding tiles (radius: 1–2 zoom levels).
- [ ] Limit `minZoom`/`maxZoom` to realistic levels for your map source.

### ✅ Gestures
- [ ] Debounce search input (200–300ms).
- [ ] Precompute lowercase names for device search.
- [ ] Prevent map panning from rebuilding the info panel.

---

## 🧩 State Management (Riverpod)

- [ ] Convert global providers to finer-grained ones (`deviceListProvider`, `positionsProvider`).
- [ ] Use `AsyncValue.guard` for safe async handling.
- [ ] Keep previous data during refresh (no flicker).
- [ ] Mark frequently accessed providers as `keepAlive`.
- [ ] Debounce frequent triggers (like search, pan, or zoom).

---

## 🌐 Networking & Traccar Integration

- [x] Move from polling `/api/positions` → WebSocket subscription.
- [x] Add reconnect policy with capped exponential backoff.
- [ ] Normalize timestamps to local once (avoid `.toLocal()` loops).
- [ ] Compress payloads where supported.
- [ ] Add versioned header: `X-Client-Version: x.y.z`.

---

## 🗃️ Database (Drift) & Caching

- [ ] Add index: `positions(deviceId, deviceTime DESC)`.
- [ ] Add index: `trips(deviceId, startTime)`.
- [ ] Enable WAL journal mode for faster concurrent writes.
- [ ] Batch inserts for live streams (`batch()`).
- [ ] Add TTL cleanup for old positions (e.g., keep last 7 days).
- [ ] Add in-memory LRU cache for last position per device.

---

## 🔍 Search & List Rendering

- [ ] Implement search debounce (250ms).
- [ ] Precompute and cache `searchKey = name.toLowerCase()`.
- [ ] Use `ListView.builder` with fixed `itemExtent`.
- [ ] Avoid unnecessary `RichText` if no highlights are needed.

---

## 📊 Info Panel (Bottom Sheet)

- [ ] Render content lazily based on snap height.
- [ ] Replace full rebuilds with `AnimatedSize`.
- [ ] Disable unnecessary shadows and gradients.
- [ ] Use const constructors and static styles for repeated widgets.

---

## 🧱 Widget Build Hygiene

- [ ] Add `const` to all constructors possible.
- [ ] Hoist shared `TextStyle` / `BoxDecoration` to static finals.
- [ ] Assign `keys` to list items and animated children.
- [ ] Coalesce rapid state updates via `postFrameCallback`.

---

## 🖼️ Image & Asset Optimization

- [ ] Convert static icons to SVGs or IconFonts.
- [ ] Use precache for marker icons.
- [ ] Set global image cache size limit.
- [ ] Enable lazy loading where possible.

---

## ⚙️ App Startup & Build Size

- [ ] Defer heavy initializations until after first frame.
- [ ] Enable R8 + resource shrinking.
- [ ] Split Android build by ABI.
- [ ] Remove unused fonts and locales.
- [ ] Subset fonts to reduce asset size.

---

## ⚠️ Error Handling & UX

- [ ] Add unified offline banner (already partially present).
- [ ] Differentiate between “no data” vs “offline”.
- [ ] Cache last good fix for better user experience.
- [ ] Throttle snackbars or toasts to avoid spam.

---

## 🧪 CI, Profiling & Linting

- [ ] Add `analysis_options.yaml` with strong lints (use `very_good_analysis`).
- [ ] Set up GitHub Actions to run `dart analyze` and `flutter test`.
- [ ] Profile frame time during live map panning.
- [ ] Track memory over 5 min continuous updates.
- [ ] Measure CPU usage spikes during bursts of position updates.

---

## 🔒 Security & Configuration

- [ ] Move API URLs and keys to `.env` or `env.dart`.
- [ ] Add build flavors: `dev`, `staging`, `prod`.
- [ ] Validate HTTPS and optionally enable SSL pinning.
- [ ] Exclude sensitive config from version control.

---

## 🧭 Router & Navigation

- [ ] Refactor dashboard to use a `ShellRoute` or persistent `BottomNavShell`.
- [ ] Prevent full rebuild on tab switch (IndexedStack).
- [ ] Add route guards for authenticated sessions.

---

## 🧰 Concrete Implementation Tasks

- [ ] Add tile caching + FastMarkerLayer.
- [ ] Implement WebSocket event streaming.
- [ ] Add Drift migration scripts for indexes.
- [ ] Refactor Riverpod providers (map, device list, positions).
- [ ] Integrate BottomNavShell + persistent tab state.
- [ ] Add `probe_history.dart` CLI to measure batch sizes.
- [ ] Add profiling entrypoint in debug builds.

---

## 📋 Validation Steps (Post-Implementation)

- [ ] Verify tile cache works offline.
- [ ] Confirm WebSocket reconnects gracefully.
- [ ] Check map rebuild frequency via Flutter DevTools.
- [ ] Validate DB indexes via Drift Inspector.
- [ ] Measure memory/CPU after 10 minutes of tracking.
- [ ] Confirm no layout jank > 16ms per frame.

---

_Last updated: 2025-10-09_
