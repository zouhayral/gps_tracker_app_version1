# 🧭 Project Optimization Roadmap
*A detailed task list with goals and explanations for each optimization.*

---

## 🚀 Networking & Live Updates

- [x] Replace REST polling with WebSocket for live Traccar events — **Goal:** Real-time updates instead of periodic refreshes.
- [x] Implement exponential backoff + jitter on reconnect — **Goal:** Prevent reconnect overloads under poor networks.
- [x] Add HTTP caching (ETag / If-Modified-Since) — **Goal:** Reduce redundant network requests for static endpoints.
- [x] Tune Dio timeouts (connect = 2s, receive = 10s) — **Goal:** Fail fast and maintain responsive UX.
- [ ] Enable gzip compression (`Accept-Encoding: gzip`) — **Goal:** Reduce payload size and improve data efficiency.
- [x] Surface connection status provider and guard UI updates — **Goal:** Avoid UI flicker when offline.

---

## 🗺️ FMTC Init & Map Tile Reliability

- [x] Initialize FMTC before runApp — **Goal:** Prevent FMTC root unavailability errors.
- [x] Create tile store `main` on startup — **Goal:** Ensure persistent caching for map tiles.
- [x] Use HTTPS OSM tiles and proper user agent — **Goal:** Maintain security and API compliance.
- [x] Fallback to `NetworkTileProvider` when FMTC fails — **Goal:** Guarantee map always renders.
- [x] Add Cache Debug Page — **Goal:** Allow clearing caches for debugging and offline testing.

---

## 🗺️ Map Caching & Assets

- [x] Cache map tiles using `flutter_map_tile_caching` — **Goal:** Offline-ready map experience.
 - [x] Reuse prebuilt marker icons — **Goal:** Reduce redundant asset decoding for performance.
 - [x] Add vector icons for device statuses — **Goal:** Use scalable icons for better visuals.
 - [x] Limit image cache size — **Goal:** Prevent memory overuse on low-end devices.
 - [x] Precache common marker images — **Goal:** Reduce frame stutter when scrolling map.

---

## 🎯 UI Rebuild Optimization

- [x] Use `Riverpod.select()` — **Goal:** Minimize rebuilds by observing only changed fields.
- [x] Split device and position providers — **Goal:** Isolate updates and reduce UI work.
- [x] Smart cache via `ref.keepAlive()` — **Goal:** Persist data for smoother UX.
 - [x] Replace heavy rebuilds with `AnimatedSize` or `AnimatedSwitcher` — **Goal:** Improve visual transitions.

---

## 🗺️ Map Performance

- [x] Isolate per-marker rebuilds using granular providers — **Goal:** Optimize rendering for many markers.
- [x] Switch to FastMarkerLayer or clustering — **Goal:** Scale efficiently for large fleets.
- [x] Optimize device selection camera centering (<100ms) — **Goal:** Immediate map response to user selection.
- [x] Add enhanced marker visual feedback (scale, glow, color) — **Goal:** Clear visual indication of selected devices.

---

## 🧩 State Management (Riverpod)

- [ ] Convert global providers to finer-grained ones — **Goal:** Reduce coupling and rebuild scope.
- [ ] Use `AsyncValue.guard` — **Goal:** Simplify async error handling.
- [x] Keep previous data during refresh — **Goal:** Prevent flicker on updates.
- [x] Mark key providers as `keepAlive` — **Goal:** Maintain stability across tab switches.
- [x] Debounce search and zoom triggers — **Goal:** Prevent redundant computations.

---

## 🌐 Networking & Traccar Integration

- [x] Move from polling `/api/positions` → WebSocket — **Goal:** Real-time data streaming.
- [x] Add reconnect policy (backoff + jitter) — **Goal:** Smooth recovery from disconnects.
- [x] Add forced local TTL cache — **Goal:** Resilient API fallback when offline.
- [ ] Normalize timestamps to local — **Goal:** Prevent repeated conversions.
- [ ] Compress payloads where supported — **Goal:** Improve API efficiency.
- [ ] Add `X-Client-Version` header — **Goal:** Identify client versions in backend logs.

---

## 🗃️ Database (Drift/ObjectBox)

- [ ] Add indexes for faster lookups — **Goal:** Optimize queries.
- [ ] Enable WAL journal mode — **Goal:** Improve concurrency and write performance.
- [ ] Batch inserts for live streams — **Goal:** Reduce DB I/O cost.
- [ ] Add TTL cleanup for old positions — **Goal:** Keep DB size manageable.

---

## ⚙️ App Startup & Build Size

- [ ] Defer heavy initializations — **Goal:** Improve app startup speed.
- [ ] Enable R8 and resource shrinking — **Goal:** Minimize release APK size.
- [ ] Split Android build by ABI — **Goal:** Reduce install size.
- [ ] Remove unused fonts/locales — **Goal:** Optimize asset footprint.

---

## ⚠️ Error Handling & UX

- [x] Cache last good fix — **Goal:** Display position even when offline.
- [ ] Add unified offline banner — **Goal:** Improve feedback during connectivity loss.
- [ ] Throttle snackbars — **Goal:** Prevent UI spam during frequent errors.

---

## 🧪 CI, Profiling & Linting

- [x] Add strong analysis options — **Goal:** Maintain high code quality.
- [x] Centralize test configuration — **Goal:** Improve test stability.
- [ ] Set up GitHub Actions CI — **Goal:** Automate tests and lint checks.
- [ ] Profile frame time during map panning — **Goal:** Detect jank sources.

---

## 🔒 Security & Configuration

- [ ] Move API keys to `.env` — **Goal:** Protect secrets from version control.
- [ ] Add build flavors (dev/staging/prod) — **Goal:** Support multi-environment builds.
- [ ] Enable SSL pinning — **Goal:** Strengthen network security.

---

## 🧭 Router & Navigation

- [x] Refactor dashboard to use ShellRoute — **Goal:** Keep tab state persistent.
- [ ] Prevent full rebuild on tab switch — **Goal:** Optimize navigation performance.
- [ ] Add route guards for authentication — **Goal:** Secure access to private routes.

---

## 📋 Validation Steps

- [ ] Verify tile cache works offline.
- [ ] Confirm WebSocket reconnect stability.
- [ ] Check rebuild frequency via DevTools.
- [ ] Validate DB indexes via Drift Inspector.
- [ ] Confirm no frame jank >16ms under load.
